require 'spec_helper'
require 'job'
require 'ostruct'
require 'stringio'
require 'tempfile'
require 'yaml'

def fixture(relpath)
  File.join(File.dirname(__FILE__), 'fixtures', relpath)
end

class MockKubeClient
  def _get_single(type, name, namespace = nil)
    items = (@state[type] || []).dup
    items.select! { |i| i.metadata.name == name }
    items.select! { |i| i.metadata.namespace == namespace } unless namespace.nil?
    items.first
  end

  def _get_multiple(type, filters = {})
    items = (@state[type] || []).dup
    items.select! { |i| i.metadata.namespace == filters[:namespace] } unless filters[:namespace].nil?
    unless filters[:label_selector].nil?
      label, value = filters[:label_selector].split('=', 2)
      items.select! { |i| i.metadata.labels[label] == value }
    end
    items
  end

  def method_missing(name, *args)
    if name.to_s.start_with? 'get_'
      type = name.to_s.sub(/^get_/, '').sub(/s$/, '')
      return _get_multiple(type, *args) if name.to_s.end_with? 's'
      return _get_single(type, *args)
    end
    super
  end

  def respond_to_missing?(method_name, include_private = false)
    return true if method_name.to_s.start_with? 'get_'
    super
  end

  # _convert_ostruct takes an object and recursively converts any
  # encountered hashes to an ostruct
  def _convert_ostruct(obj)
    return OpenStruct.new(Hash[obj.map { |k, v| [k, _convert_ostruct(v)] }]).freeze if obj.is_a?(Hash)
    return obj.map { |v| _convert_ostruct(v) }.freeze if obj.is_a?(Array)
    obj
  end

  def initialize(file_name)
    @state = _convert_ostruct(YAML.load_file(file_name))
  end
end

describe Job do
  context 'with some file paths and an eval context' do
    template_filename = fixture('fake.yml.erb')
    restricted_template_filename = fixture('0600.yml.erb')
    bosh_spec = JSON.parse(File.read(fixture('fake.json')))
    expect_output = File.read(fixture('fake.yml'))

    let(:client) { MockKubeClient.new(fixture('state.yml')) }
    subject(:job) { Job.new(bosh_spec, 'namespace', client) }

    before do
      allow(ENV).to receive(:[]).and_wrap_original do |env, name|
        case name
        when 'KUBE_SERVICE_DOMAIN_SUFFIX' then 'domain'
        else env.call(name)
        end
      end
    end

    around(:each) do |example|
      # Eat stderr and only print it if something goes wrong
      orig_stderr = $stderr
      $stderr = StringIO.new('', 'w')
      begin
        result = example.run
      ensure
        orig_stderr.write $stderr.string if result.is_a?(Exception)
        $stderr = orig_stderr
      end
      result
    end

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
