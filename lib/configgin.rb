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

  # Set the exported properties and their digests, and return the digests.
  def patch_job_metadata(jobs)
    digests = {}
    jobs.each do |name, job|
      digest = property_digest(job.exported_properties)
      kube_client.patch_pod(
        @self_name,
        {
          metadata: {
            annotations: {
              :"skiff-exported-properties-#{name}" => job.exported_properties.to_json,
              :"skiff-exported-digest-#{name}" => digest
            }
          }
        },
        kube_namespace
      )
      digests[name] = digest
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
    expected_annotations.each_pair do |instance_group_name, digests|
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
    pod = kube_client.get_pod(@self_name, kube_namespace)
    pod['metadata']['labels']['app.kubernetes.io/component']
  end
end
