require 'spec_helper'
require 'generate'
require 'stringio'
require 'tempfile'

describe Generate do
  context 'with some file paths' do
    template_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.yml.erb')
    know_filename_template_filename = File.join(File.dirname(__FILE__), 'fixtures', 'know_filename.erb')
    restricted_template_filename = File.join(File.dirname(__FILE__), 'fixtures', '0600.yml.erb')
    input_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.json')
    expect_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.yml')
    expect_output = File.read(expect_filename)

    it 'should generate the templates from filenames' do
      begin
        file = Tempfile.new('configgin_output.txt')
        file.close

        Generate.generate(output: file.path, input: input_filename) do |output, input|
          Generate.render(output, input, template_filename, nil)
        end

        output = YAML.load_file(file.path)
        expect(output).to eq(YAML.load(expect_output))
      ensure
        file.unlink unless file.nil?
      end
    end

    it 'should preserve template permissions' do
      begin
        file = Tempfile.new('configgin_output.txt')
        file.close

        File.chmod(0600, restricted_template_filename)

        Generate.generate(output: file.path, input: input_filename) do |output, input|
          Generate.render(output, input, restricted_template_filename, nil)
        end

        expect(format('%o', File.stat(file.path).mode)).to eq('100600')
      ensure
        file.unlink unless file.nil?
      end
    end

    it 'should render the templates with data' do
      # output into string io and compare with expect_filename
      output_buffer = StringIO.new
      File.open(input_filename) do |input_file|
        Generate.render(output_buffer, input_file, template_filename, nil)
      end

      expect(output_buffer.string).to eq(expect_output)
    end

    it 'should know template filename' do
      # output into string io and compare with expect_filename
      output_buffer = StringIO.new
      File.open(input_filename) do |input_file|
        Generate.render(output_buffer, input_file, know_filename_template_filename, nil)
      end

      expect(output_buffer.string).to eq(know_filename_template_filename + "\n")
    end

    it 'should create directories for output paths' do
      Dir.mktmpdir('configgin_mkdir_p_test') do |dir|
        output_file = File.join(dir, 'adirectory', 'test.yml')
        Generate.generate(output: output_file, input: input_filename) do |output, input|
          Generate.render(output, input, template_filename, nil)
        end

        output = YAML.load_file(output_file)
        expect(output).to eq(YAML.load(expect_output))

        expect(Dir.exist?(File.dirname(output_file))).to be true
      end
    end
  end
end
