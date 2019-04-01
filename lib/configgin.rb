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

  def initialize(options)
    @job_configs = JSON.parse(File.read(options[:jobs]))
    @templates = YAML.load_file(options[:env2conf])
    @bosh_deployment_manifest = options[:bosh_deployment_manifest]
  end

  def run
    jobs = generate_jobs(@job_configs, @templates)
    job_digests = set_job_metadata(jobs)
    render_job_templates(jobs, @job_configs)
    restart_affected_pods(@job_configs, job_digests)
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

      jobs[job] = Job.new(bosh_spec, kube_namespace, kube_client, kube_client_stateful_set)
    end
    jobs
  end

  # Set the exported properties and their digests, and return the digests
  def set_job_metadata(jobs)
    digests = Hash.new
    jobs.each do |name, job|
      digest = property_digest(job.exported_properties)
      kube_client.patch_pod(
        ENV['HOSTNAME'],
        { metadata: {
          annotations: {
            :"skiff-exported-properties-#{name}" => job.exported_properties.to_json,
            :"skiff-exported-digest-#{name}" => digest,
          }
        } },
        kube_namespace
      )
      digests[name] = digest
    end
    puts "Got digests #{digests.inspect}"
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

  # Some pods might have depended onthe properties exported by this pod; locate
  # them and cause them to restart as appropriate.
  def restart_affected_pods(job_configs, job_digests)
    fail "No digest" if job_digests.nil?
    instance_groups_to_examine = Hash.new { |h, k| h[k] = Hash.new }
    job_configs.each do |job, job_config|
      base_config = JSON.parse(File.read(job_config['base']))
      base_config['consumed_by'].each_pair do |provider_name, consumer_jobs|
        consumer_jobs.each do |consumer_job|
          digest_key = "skiff-imported-properties-#{instance_group}-#{provider_name}"
          instance_groups_to_examine[consumer_job['role']][digest_key] = job_digests[provider_name]
        end
      end
    end

    instance_groups_to_examine.each_pair do |instance_group_name, digests|
      begin
        kube_client_stateful_set.patch_stateful_set(
          instance_group_name,
          { spec: { template: { metadata: { annotations: digests } } } },
          kube_namespace
        )
        puts "Patched StatefulSet #{instance_group_name} for new exported digests"
      rescue KubeException => e
        begin
          response = begin
            JSON.parse(e.response || '') || {}
          rescue JSON::ParseError
            {}
          end
          if response['reason'] == 'NotFound'
            # The StatefulSet can be missing if we're configured to not have an optional instance group
            puts "Skipping patch of non-existant StatefulSet #{instance_group_name}"
            next
          end
          puts "Error patching #{instance_group_name}: #{response.to_json}"
          raise
        end
      end
    end
  end

  def kube_namespace
    @kube_namespace ||= File.read("#{SVC_ACC_PATH}/namespace")
  end

  def kube_token
    @kube_token ||= File.read("#{SVC_ACC_PATH}/token")
  end

  private

  def kube_client
    @kube_client ||= Kubeclient::Client.new(
      URI::HTTPS.build(
        host: ENV['KUBERNETES_SERVICE_HOST'],
        port: ENV['KUBERNETES_SERVICE_PORT_HTTPS']
      ),
      'v1',
      ssl_options: {
        ca_file: "#{SVC_ACC_PATH}/ca.crt",
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      },
      auth_options: {
        bearer_token: kube_token
      }
    )
  end

  def kube_client_stateful_set
    @kube_client_stateful_set ||= Kubeclient::Client.new(
      URI::HTTPS.build(
        host: ENV['KUBERNETES_SERVICE_HOST'],
        port: ENV['KUBERNETES_SERVICE_PORT_HTTPS'],
        path: '/apis/apps'
      ),
      'v1',
      ssl_options: {
        ca_file: "#{SVC_ACC_PATH}/ca.crt",
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      },
      auth_options: {
        bearer_token: kube_token
      }
    )
  end

  def instance_group
    pod = kube_client.get_pod(ENV['HOSTNAME'], kube_namespace)
    pod['metadata']['labels']['app.kubernetes.io/component']
  end
end
