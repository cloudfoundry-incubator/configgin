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
    export_job_properties(jobs)
    render_job_templates(jobs, @job_configs)
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

  def render_job_templates(jobs, job_configs)
    jobs.each do |job_name, job|
      dns_encoder = KubeDNSEncoder.new(job.spec['links'])

      job_configs[job_name]['files'].each do |infile, outfile|
        job.generate(infile, outfile, dns_encoder)
      end
    end
  end

  # Write exported properties to secret and update annotations on importing stateful sets.
  def export_job_properties(jobs)
    # Co-located containers don't get to export properties.
    return unless instance_group == ENV["KUBERNETES_CONTAINER_NAME"]
    # Jobs (errands) don't export properties.
    return unless self_pod['metadata']['ownerReferences'][0]['kind'] == "StatefulSet"

    sts = kube_client_stateful_set.get_stateful_set(instance_group, kube_namespace)

    # Make sure the secret attached to the stateful set exists.
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
    begin
      kube_client.create_secret(secret)
    rescue
    end
    secret = kube_client.get_secret(instance_group, kube_namespace)
    secret.data ||= {}

    # version tag changes whenever the chart version or the secrets generation changes
    version_tag = ENV["CONFIGGIN_VERSION_TAG"]
    new_tag = !secret.data[version_tag]
    secret.data = {version_tag => ""} if new_tag # make sure old properties are deleted during upgrade

    digests = {}
    jobs.each do |name, job|
      secret.data["skiff-exported-properties-#{name}"] = Base64.encode64(job.exported_properties.to_json)
      digests[name] = property_digest(job.exported_properties)

      # Record initial digest values whenever the tag changes, in which case the pod startup
      # order is already controlled by the "CONFIGGIN_IMPORT_#{role}" references to the new
      # tags in the corresponding secrets. There is no annotation when importing this set of
      # initial values because the helm chart doesn't include any annotations, and we don't
      # want to trigger a pod restart by adding them.
      encoded_digest = Base64.encode64(digests[name])
      if new_tag
        secret.data["skiff-initial-digest-#{name}"] = encoded_digest
      end
      if secret.data["skiff-initial-digest-#{name}"] == encoded_digest
        digests[name] = nil
      end
    end
    kube_client.update_secret(secret)

    # Some pods might depend on the properties exported by this pod; add annotations
    # to the template spec of the stateful sets so that the pods will be restarted if
    # the exported values have changed from the initial values.
    expected_annotations(@job_configs, digests).each_pair do |instance_group_name, digests|
      # Avoid restarting our own pod
      next if instance_group_name == instance_group

      begin
        sts = kube_client_stateful_set.get_stateful_set(instance_group_name, kube_namespace)
      rescue KubeException => e
        begin
          begin
            response = JSON.parse(e.response || '')
          rescue JSON::ParseError
            response = {}
          end
          if response['reason'] == 'NotFound'
            # The StatefulSet can be missing if we're configured to not have an optional instance group.
            warn "Skipping patch of non-existant StatefulSet #{instance_group_name}"
            next
          end
          warn "Error fetching stateful set #{instance_group_name}: #{response.to_json}"
          raise
        end
      end

      # Update annotations to match digests for current property values. The stateful set will
      # only restarts pods when the checksum of the pod spec changes, so no-op "updates" are ok.
      annotations = {}
      sts.spec.template.metadata.annotations.each_pair do |key, value|
        annotations[key] = value
      end
      digests.each_pair do |key, value|
        annotations[key] = value
      end

      kube_client_stateful_set.merge_patch_stateful_set(
        instance_group_name,
        { spec: { template: { metadata: { annotations: annotations } } } },
        kube_namespace
      )
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

  def self_pod
    @pod ||= kube_client.get_pod(@self_name, kube_namespace)
  end

  def instance_group
    self_pod['metadata']['labels']['app.kubernetes.io/component']
  end
end
