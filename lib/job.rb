require 'bosh/template/renderer'
require 'json'
require_relative 'kube_link_generator'

# Job describes a single BOSH job
class Job
  def initialize(spec, namespace, client, client_stateful_set)
    @spec = spec
    @namespace = namespace
    @client = client
    links = @spec['links'] = KubeLinkSpecs.new(@spec, @namespace, @client, client_stateful_set)

    # Figure out whether _this_ should bootstrap
    pods = @client.get_pods(namespace: @namespace, label_selector: "app.kubernetes.io/component=#{self_role}")
    pods_per_image = links.get_pods_per_image(pods)
    @spec['bootstrap'] = pods_per_image[self_pod.metadata.uid] < 2
  end

  attr_reader :spec

  def exported_properties
    return @exported_propertes if @exported_properties
    exported_properties = {}
    spec['exported_properties'].each do |prop|
      src = spec['properties']
      dst = exported_properties
      keys = prop.split('.')
      leaf = keys.pop
      keys.each do |key|
        dst[key] ||= {}
        dst = dst[key]
        src = src.fetch(key, {})
      end
      dst[leaf] = src[leaf]
    end
    @exported_properties = exported_properties
  end

  def self_pod
    @self_pod ||= @client.get_pod(ENV['HOSTNAME'], @namespace)
  end

  def self_role
    self_pod['metadata']['labels']['app.kubernetes.io/component']
  end

  # Process the given template using a provided spec and output filename
  #
  # @param input_file_path    [String] The input filepath for the template
  # @param output_file_path   [String] The output filepath
  # @param dns_encoder        [KubeDNSEncoder] BOSH DNS encoder
  def generate(input_file_path, output_file_path, dns_encoder)
    # Make sure we're getting all the parameters we need
    raise NoDataProvided if spec.nil?
    raise NoInputFileProvided if input_file_path.nil?
    raise NoOutputFileProvided if output_file_path.nil?

    # Read the erb template
    begin
      perms = File.stat(input_file_path).mode
      erb_template = ERB.new(File.read(input_file_path), nil, '-')
      erb_template.filename = input_file_path
    rescue Errno::ENOENT
      raise "failed to read template file #{input_file_path}"
    end

    # Create a BOSH evaluation context
    evaluation_context = Bosh::Template::EvaluationContext.new(spec, dns_encoder)
    # Process the Template
    output = erb_template.result(evaluation_context.get_binding)

    begin
      # Open the output file
      output_dir = File.dirname(output_file_path)
      FileUtils.mkdir_p(output_dir)
      out_file = File.open(output_file_path, 'w')
      # Write results to the output file
      out_file.write(output)
      # Set the appropriate permissions on the output file
      out_file.chmod(perms)
    rescue Errno::ENOENT, Errno::EACCES => e
      out_file = nil
      raise "failed to open output file #{output_file_path}: #{e}"
    ensure
      out_file.close unless out_file.nil?
    end
  end
end
