require 'bosh/template/renderer'
require 'evaluation_context'
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
  # @param input    [String] The input filepath (or nil for stdin)
  # @param block    [Block]  The block to pass the streams to (out_stream, in_stream)
  def self.generate(data: nil, output: nil, input: nil, &_block)
    in_file = STDIN
    out_file = STDOUT

    if !data.nil?
      in_file = StringIO.new(data)
    elsif !input.nil?
      begin
        in_file = File.open(input, 'r')
      rescue Errno::ENOENT => e
        in_file = nil
        STDERR.puts("failed to open input file #{input}: #{e}")
        return
      end
    end

    unless output.nil?
      begin
        out_file = File.open(output, 'w')
      rescue Errno::ENOENT, Errno::EACCES => e
        out_file = nil
        STDERR.puts("failed to open output file #{output}: #{e}")
        return
      end
    end

    yield out_file, in_file
  ensure
    in_file.close if !in_file.nil? && !input.nil?
    out_file.close if !out_file.nil? && !output.nil?
  end

  # Render the given template using input filename and output filename
  # if given, defaulting to STDIN and STDOUT respectively if not given.
  #
  # @param output       [IO]     The output stream
  # @param input        [IO]     The input stream
  # @param template     [String] The template filepath
  # @param config_store [Object] A configuration store (anything that responds to get(key)
  def self.render(out_file, in_file, template, config_store)
    data = in_file.read
    spec = JSON.parse(data)
    evaluation_context = EvaluationContext.new(spec, config_store)

    begin
      template = ERB.new(File.read(template))
    rescue Errno::ENOENT
      STDERR.puts("failed to read template file: #{template}")
      return
    end

    output = template.result(evaluation_context.get_binding)

    out_file.write(output)
  end
end
