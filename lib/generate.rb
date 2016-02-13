require 'bosh/template/renderer'
require 'json'

# Generate has methods for manipulating streams and generating configuration
# files using those streams.
module Generate
  # Proces the given template using a provided spec and output filename
  #
  # @param bosh_spec          [Hash]   The input data as a hash
  # @param input_file_path    [String] The input filepath for the template
  # @param output_file_path   [String] The output filepath
  def self.generate(bosh_spec, input_file_path, output_file_path, &_block)
    # Make sure we're getting all the parameters we need
    raise NoDataProvided if bosh_spec.nil?
    raise NoInputFileProvided if input_file_path.nil?
    raise NoOutputFileProvided if output_file_path.nil?

    # Read the erb template
    begin
      perms = File.stat(input_file_path).mode
      erb_template = ERB.new(File.read(input_file_path))
      erb_template.filename = input_file_path
    rescue Errno::ENOENT
      raise "failed to read template file: #{template}"
    end

    # Create a BOSH evaluation context
    evaluation_context = Bosh::Template::EvaluationContext.new(bosh_spec)
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
      raise "failed to open output file #{output}: #{e}"
    ensure
      out_file.close unless out_file.nil?
    end
  end
end
