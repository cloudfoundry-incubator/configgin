require 'spec_helper'
require 'job'
require 'stringio'
require 'tempfile'

describe Job do
  context 'with some file paths and an eval context' do
    template_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.yml.erb')
    restricted_template_filename = File.join(File.dirname(__FILE__), 'fixtures', '0600.yml.erb')
    bosh_spec = File.join(File.dirname(__FILE__), 'fixtures', 'fake.json')
    expect_filename = File.join(File.dirname(__FILE__), 'fixtures', 'fake.yml')
    expect_output = File.read(expect_filename)

    subject(:job) { Job.new(JSON.parse(File.read(bosh_spec)), 'namespace', nil) }

    it 'should preserve template permissions' do
      Dir.mktmpdir('configgin_mkdir_p_test') do |dir|
        begin
          # Arrange
          file = Tempfile.new('configgin_output.txt')
          file.close
          restricted_file_duplicate = File.join(dir, 'test.chmod')
          FileUtils.cp(restricted_template_filename, restricted_file_duplicate)
          File.chmod(0o600, restricted_file_duplicate)

          # Act
          job.generate(restricted_file_duplicate, file.path, nil)

          # Assert
          expect(format('%o', File.stat(file.path).mode)).to eq('100600')
        ensure
          file.unlink unless file.nil?
        end
      end
    end

    it 'should render the templates with data' do
      begin
        # Arrange
        file = Tempfile.new('configgin_output.txt')
        file.close

        # Act
        job.generate(template_filename, file.path, nil)

        # Assert (compare with expect_filename)
        expect(File.read(file)).to eq(expect_output)
      ensure
        file.unlink unless file.nil?
      end
    end

    it 'should create directories for output paths' do
      # Arrange
      Dir.mktmpdir('configgin_mkdir_p_test') do |dir|
        output_file = File.join(dir, 'adirectory', 'test.yml')

        # Act
        job.generate(template_filename, output_file, nil)

        # Assert (compare with expect_filename)
        output = YAML.load_file(output_file)
        expect(output).to eq(YAML.safe_load(expect_output))

        expect(Dir.exist?(File.dirname(output_file))).to be true
      end
    end

    it 'should list exported properties' do
      expect(job.exported_properties).to eq(
        'nats' => { 'machines' => ['localhost', '127.0.0.1'] },
        'stuff' => { 'one' => 1, 'two' => [2] }
      )
    end
  end
end
