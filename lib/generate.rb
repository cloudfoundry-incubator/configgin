require 'bosh/template/renderer'
require 'json'

# Generate has methods for manipulating streams and generating configuration
# files using those streams.
module Generate
  # Generate the given template using input filename and output filename
  # if given, defaulting to STDIN and STDOUT respectively if not given.
  # If given the data parameter, input is overridden by the contents of
  # the string.
  #
  # @param data     [String] The input as a string (overrides input param)
  # @param output   [String] The output filepath (or nil for stdout)
  # @param block    [Block]  The block to pass the streams to (out_stream, in_stream)
  def self.generate(data: nil, output: nil, &_block)
    out_file = STDOUT

    if !data.nil?
      in_file = StringIO.new(data)
    else
      raise NoDataProvided
    end

    unless output.nil?
      begin
        output_dir = File.dirname(output)
        FileUtils.mkdir_p(output_dir)
        out_file = File.open(output, 'w')
      rescue Errno::ENOENT, Errno::EACCES => e
        out_file = nil
        STDERR.puts("failed to open output file #{output}: #{e}")
        return
      end
    end

    yield out_file, in_file
  ensure
    out_file.close if !out_file.nil? && !output.nil?
  end

  # Render the given template using input filename and output filename
  # if given, defaulting to STDIN and STDOUT respectively if not given.
  #
  # @param output       [IO]     The output stream
  # @param input        [IO]     The input stream
  # @param template     [String] The template filepath
  def self.render(out_file, in_file, template)
    data = in_file.read
    spec = JSON.parse(data)
    evaluation_context = Bosh::Template::EvaluationContext.new(spec)

    begin
      perms = File.stat(template).mode
      erb_template = ERB.new(File.read(template))
      erb_template.filename = template
    rescue Errno::ENOENT
      STDERR.puts("failed to read template file: #{template}")
      return
    end

    output = erb_template.result(evaluation_context.get_binding)

    out_file.write(output)

    out_file.chmod(perms) if out_file.is_a?(File)
  end
end
