require 'spec_helper'
require 'job'
require 'ostruct'
require 'stringio'
require 'tempfile'
require 'yaml'

describe Job do
  context 'with some file paths and an eval context' do
    template_filename = fixture('fake.yml.erb')
    restricted_template_filename = fixture('0600.yml.erb')
    bosh_spec = JSON.parse(File.read(fixture('fake.json')))
    expect_output = File.read(fixture('fake.yml'))

    let(:client) { MockKubeClient.new(fixture('state.yml')) }
    subject(:job) { Job.new(spec: bosh_spec, namespace: 'the-namespace', client: client, client_stateful_set: client, self_name: 'pod-0') }

    before do
      allow(ENV).to receive(:[]).and_wrap_original do |env, name|
        case name
        when 'HOSTNAME' then 'pod-0'
        when 'KUBERNETES_CLUSTER_DOMAIN' then 'domain'
        when 'KUBERNETES_NAMESPACE' then 'namespace'
        else env.call(name)
        end
      end
    end

    around(:each) { |ex| trap_error(ex) }

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
          expect(format('%<mode>o', mode: File.stat(file.path).mode)).to eq('100600')
        ensure
          file&.unlink
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
        file&.unlink
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

  context 'when resolving bootstrapness' do
    bosh_spec = JSON.parse(File.read(fixture('fake.json')))

    let(:namespace) { 'namespace' }
    let(:client) { MockKubeClient.new(fixture('state-multi.yml')) }

    around(:each) { |ex| trap_error(ex) }

    it 'should bootstrap when pod is alone' do
      job = Job.new(spec: bosh_spec, namespace: namespace, client: client, client_stateful_set: client, self_name: 'unrelated-pod-0')
      expect(job.spec['bootstrap']).to be_truthy
    end

    it 'should not break bootstrapping a pod in pending status' do
      job = Job.new(spec: bosh_spec, namespace: namespace, client: client, client_stateful_set: client, self_name: 'pending-pod-0')
      expect(job.spec['containerStatuses']).to be_falsey
    end

    it 'should bootstrap when only pod with this image' do
      job = Job.new(spec: bosh_spec, namespace: namespace, client: client, client_stateful_set: client, self_name: 'bootstrap-pod-3')
      expect(job.spec['bootstrap']).to be_truthy
    end

    it 'shoud not upgrade when multiple pods with same image' do
      job = Job.new(spec: bosh_spec, namespace: namespace, client: client, client_stateful_set: client, self_name: 'ready-pod-0')
      expect(job.spec['bootstrap']).to be_falsy
    end
  end
end
