require 'spec_helper'
require 'generate'
require 'stringio'
require 'tempfile'

describe Generate do
  context "with some file paths" do
    template_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.yml.erb')
    input_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.json')
    expect_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.yml')
    expect_output = File.read(expect_filename)

    it "should generate the templates from filenames" do
      begin
        file = Tempfile.new('config_gen_output.txt')
        file.close()

        Generate::generate(output: file.path, input: input_filename) do |output, input|
          Generate::render(output, input, template_filename, nil)
        end

        output = YAML.load_file(file.path)
        expect(output).to eq(YAML.load(expect_output))
      ensure
        file.unlink unless file.nil?
      end
    end

    it "should render the templates with data" do
      # output into string io and compare with expect_filename
      output_buffer = StringIO.new()
      File.open(input_filename) do |input_file|
        Generate::render(output_buffer, input_file, template_filename, nil)
      end

      expect(output_buffer.string).to eq(expect_output)
    end
  end
end
