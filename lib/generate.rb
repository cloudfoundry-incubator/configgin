require 'bosh/template/renderer'
#require 'evaluation_context'
#require 'kato_configurator'
require 'json'

module Generate
  # Generate the given template using input filename and output filename
  # if given, defaulting to STDIN and STDOUT respectively if not given.
  # If given the context parameter, input is overridden by the contents of
  # the string.
  #
  # @param template [String] The template filepath
  # @param context  [String] The input as a string (overrides input param)
  # @param input    [String] The input filepath (or nil for stdin)
  # @param output   [String] The output filepath (or nil for stdout)
  # @return [Bool] success?
  def self.generate(template, context: nil, input: nil, output: nil)
    in_file = STDIN
    out_file = STDOUT

    if !context.nil?
      in_file = StringIO.new(context)
    elsif !input.nil?
      begin
        in_file = File.open(input, "r")
      rescue Errno::ENOENT => e
        in_file = nil
        STDERR.puts("failed to open input file #{input}: #{e}")
        return false
      end
    end

    unless output.nil?
      begin
        out_file = File.open(output, "w")
      rescue Errno::ENOENT, Errno::EACCES => e
        out_file = nil
        STDERR.puts("failed to open output file #{output}: #{e}")
        return false
      end
    end

    Generate::render out_file, in_file, template
    return true
  ensure
    in_file.close if !in_file.nil? && !input.nil?
    out_file.close if !out_file.nil? && !output.nil?
  end

  # Render the given template using input filename and output filename
  # if given, defaulting to STDIN and STDOUT respectively if not given.
  #
  # @param output   [IO]     The output stream
  # @param input    [IO]     The input stream
  # @param template [String] The template filepath
  def self.render(out_file, in_file, template, configurator = nil)
    context = in_file.read

    spec = JSON.parse(context)
    evaluation_context = EvaluationContext.new(spec, configurator)

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
