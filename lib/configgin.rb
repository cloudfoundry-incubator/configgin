require 'base64'
require 'json'

require_relative 'cli'
require_relative 'job'
require_relative 'environment_config_transmogrifier'
require_relative 'bosh_deployment_manifest_config_transmogrifier'
require_relative 'kube_link_generator'
require_relative 'bosh_deployment_manifest'
require_relative 'property_digest'

# Configgin is the main class which puts all the pieces together and configures
# the container according to the options.
class Configgin
  # SVC_ACC_PATH is the location of the service account secrets
  SVC_ACC_PATH = '/var/run/secrets/kubernetes.io/serviceaccount'.freeze

  def initialize(jobs:, env2conf:, bosh_deployment_manifest:, self_name: ENV['HOSTNAME'])
    @job_configs = JSON.parse(File.read(jobs))
    @templates = YAML.load_file(env2conf)
    @bosh_deployment_manifest = bosh_deployment_manifest
    @self_name = self_name
  end

  def run
    jobs = generate_jobs(@job_configs, @templates)
    job_digests = patch_job_metadata(jobs)
    render_job_templates(jobs, @job_configs)
    restart_affected_pods expected_annotations(@job_configs, job_digests)
    # enable_affected_containers
  end

  def generate_jobs(job_configs, templates)
    jobs = {}
    job_configs.each do |job, job_config|
      base_config = JSON.parse(File.read(job_config['base']))

      begin
        bosh_spec = EnvironmentConfigTransmogrifier.transmogrify(base_config, templates, secrets: '/etc/secrets')

        if @bosh_deployment_manifest
          manifest = BoshDeploymentManifest.new(@bosh_deployment_manifest)
          bosh_spec = BoshDeploymentManifestConfigTransmogrifier.transmogrify(bosh_spec, instance_group, manifest)
        end
      rescue NonHashValueOverride => e
        STDERR.puts e.to_s
        STDERR.puts "Error generating #{job}: #{outfile} from #{infile}"
        exit 1
      end

      jobs[job] = Job.new(
        spec: bosh_spec,
        namespace: kube_namespace,
        client: kube_client,
        client_stateful_set: kube_client_stateful_set,
        self_name: @self_name
      )
    end
    jobs
  end

  def enable_affected_containers
    return unless instance_group == ENV["KUBERNETES_CONTAINER_NAME"]

    version_tag = ENV["CONFIGGIN_VERSION_TAG"]
    return unless version_tag

    begin
      secret = kube_client.get_secret(instance_group, kube_namespace)
      secret.data[version_tag] = ""
      kube_client.update_secret(secret)
    rescue KubeException => e
      STDERR.puts e
      sts = kube_client_stateful_set.get_stateful_set(instance_group, kube_namespace)
      secret = Kubeclient::Resource.new
      secret.metadata = {
        name: sts.metadata.name,
        namespace: kube_namespace,
        ownerReferences:  [
          {
            apiVersion: sts.apiVersion,
            blockOwnerDeletion: false,
            controller: false,
            kind: sts.kind,
            name: sts.metadata.name,
            uid: sts.metadata.uid,
          }
        ]
      }
      secret.data = {version_tag => ""}
      kube_client.create_secret(secret)
    end
  end

  # Set the exported properties and their digests, and return the digests.
  def patch_job_metadata(jobs)
    pod = kube_client.get_pod(@self_name, kube_namespace)

    secret = Kubeclient::Resource.new
    secret.metadata = {}
    # Prefixing with pod.metadata.name is purely for human convenience/debugging.
    secret.metadata.name = "#{pod.metadata.name}-#{pod.metadata.uid}"
    secret.metadata.namespace = kube_namespace

    # Make sure the secret gets removed when the pod is deleted.
    secret.metadata.ownerReferences = [
      {
        apiVersion: pod.apiVersion,
        blockOwnerDeletion: false,
        controller: false,
        kind: pod.kind,
        name: pod.metadata.name,
        uid: pod.metadata.uid,
      }
    ]

    secret.data = {}
    digests = {}
    jobs.each do |name, job|
      digests[name] = property_digest(job.exported_properties)
      secret.data["skiff-exported-properties-#{name}"] = Base64.encode64(job.exported_properties.to_json)
      secret.data["skiff-exported-digest-#{name}"] = Base64.encode64(digests[name])
    end

    # Only the main container gets to export properties; colocated sidecars don't.
    if instance_group == ENV["KUBERNETES_CONTAINER_NAME"]
      begin
        kube_client.delete_secret(secret.metadata.name, kube_namespace)
      rescue
      end
      kube_client.create_secret(secret)
    end

    digests
  end

  def render_job_templates(jobs, job_configs)
    jobs.each do |job_name, job|
      dns_encoder = KubeDNSEncoder.new(job.spec['links'])

      job_configs[job_name]['files'].each do |infile, outfile|
        job.generate(infile, outfile, dns_encoder)
      end
    end
  end

  # Some pods might have depended on the properties exported by this pod; given
  # the annotations expected on the pods (keyed by the instance group name),
  # patch the StatefulSets such that they will be restarted.
  def restart_affected_pods(expected_annotations)
    return unless instance_group == ENV["KUBERNETES_CONTAINER_NAME"]

    secret = nil
    version_tag = ENV["CONFIGGIN_VERSION_TAG"]
    if version_tag
      begin
        secret = kube_client.get_secret(instance_group, kube_namespace)
      rescue
      end
    end

    if !version_tag || (secret && secret.data[version_tag])
      expected_annotations.each_pair do |instance_group_name, digests|
        # Avoid restarting our own pod
        next if instance_group_name == instance_group

        begin
          kube_client_stateful_set.patch_stateful_set(
            instance_group_name,
            { spec: { template: { metadata: { annotations: digests } } } },
            kube_namespace
          )
          warn "Patched StatefulSet #{instance_group_name} for new exported digests"
        rescue KubeException => e
          begin
            begin
              response = JSON.parse(e.response || '')
            rescue JSON::ParseError
              response = {}
            end
            if response['reason'] == 'NotFound'
              # The StatefulSet can be missing if we're configured to not have an
              # optional instance group.
              warn "Skipping patch of non-existant StatefulSet #{instance_group_name}"
              next
            end
            warn "Error patching #{instance_group_name}: #{response.to_json}"
            raise
          end
        end
      end
    end

    return unless version_tag

    if secret
      secret.data[version_tag] = ""
      kube_client.update_secret(secret)
    else
      sts = kube_client_stateful_set.get_stateful_set(instance_group, kube_namespace)
      secret = Kubeclient::Resource.new
      secret.metadata = {
        name: sts.metadata.name,
        namespace: kube_namespace,
        ownerReferences:  [
          {
            apiVersion: sts.apiVersion,
            blockOwnerDeletion: false,
            controller: false,
            kind: sts.kind,
            name: sts.metadata.name,
            uid: sts.metadata.uid,
          }
        ]
      }
      secret.data = {version_tag => ""}
      kube_client.create_secret(secret)
    end

  end

  # Given the active jobs, and a hash of the expected annotations for each,
  # return the annotations we expect to be on each pod based on what properties
  # each job imports.
  def expected_annotations(job_configs, job_digests)
    instance_groups_to_examine = Hash.new { |h, k| h[k] = {} }
    job_configs.each_pair do |job_name, job_config|
      base_config = JSON.parse(File.read(job_config['base']))
      base_config.fetch('consumed_by', {}).values.each do |consumer_jobs|
        consumer_jobs.each do |consumer_job|
          digest_key = "skiff-in-props-#{instance_group}-#{job_name}"
          instance_groups_to_examine[consumer_job['role']][digest_key] = job_digests[job_name]
        end
      end
    end
    instance_groups_to_examine
  end

  def kube_namespace
    @kube_namespace ||= File.read("#{SVC_ACC_PATH}/namespace")
  end

  def kube_token
    @kube_token ||= File.read("#{SVC_ACC_PATH}/token")
  end

  private

  def create_kube_client(path: nil, version: 'v1')
    Kubeclient::Client.new(
      URI::HTTPS.build(
        host: ENV['KUBERNETES_SERVICE_HOST'],
        port: ENV['KUBERNETES_SERVICE_PORT_HTTPS'],
        path: path
      ),
      version,
      ssl_options: {
        ca_file: "#{SVC_ACC_PATH}/ca.crt",
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      },
      auth_options: {
        bearer_token: kube_token
      }
    )
  end

  def kube_client
    @kube_client ||= create_kube_client
  end

  def kube_client_stateful_set
    @kube_client_stateful_set ||= create_kube_client(path: '/apis/apps')
  end

  def instance_group
    @pod ||= kube_client.get_pod(@self_name, kube_namespace)
    @pod['metadata']['labels']['app.kubernetes.io/component']
  end
end
