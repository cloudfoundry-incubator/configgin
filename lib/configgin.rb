require_relative 'cli'
require_relative 'job'
require_relative 'environment_config_transmogrifier'
require_relative 'bosh_deployment_manifest_config_transmogrifier'
require_relative 'kube_link_generator'
require_relative 'bosh_deployment_manifest'

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
    set_job_metadata(jobs)
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
          bosh_spec = BoshDeploymentManifestConfigTransmogrifier.transmogrify(bosh_spec, ENV['HOSTNAME'], manifest)
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

  def set_job_metadata(jobs)
    jobs.each do |name, job|
      kube_client.patch_pod(
        ENV['HOSTNAME'],
        { metadata: { annotations: { :"skiff-exported-properties-#{name}" => job.exported_properties.to_json } } },
        kube_namespace
      )
    end
  end

  def render_job_templates(jobs, job_configs)
    jobs.each do |job_name, job|
      dns_encoder = KubeDNSEncoder.new(job.spec['links'])

      job_configs[job_name]['files'].each do |infile, outfile|
        job.generate(infile, outfile, dns_encoder)
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
      'v1beta1',
      ssl_options: {
        ca_file: "#{SVC_ACC_PATH}/ca.crt",
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      },
      auth_options: {
        bearer_token: kube_token
      }
    )
  end
end
