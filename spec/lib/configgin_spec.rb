require 'base64'
require 'spec_helper'
require 'configgin'
require 'property_digest'

describe Configgin do
  let(:options) {
    {
      jobs: fixture('nats-job-config.json'),
      env2conf: fixture('nats-env2conf.yml'),
      bosh_deployment_manifest: nil,
      self_name: 'pod-0'
    }
  }
  let(:client) {
    MockKubeClient.new(fixture('state.yml'))
  }
  subject {
    described_class.new(options)
  }

  before(:each) {
    allow(subject).to receive(:render_job_templates)
    allow(subject).to receive(:kube_namespace).and_return('the-namespace')
    allow(subject).to receive(:kube_token).and_return('abcdefg')
    allow(subject).to receive(:kube_client).and_return(client)
    allow(subject).to receive(:kube_client_stateful_set).and_return(client)
    allow(subject).to receive(:instance_group).and_return('instance-group')
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/var/vcap/jobs-src/loggregator_agent/config_spec.json')
                                 .and_return(File.read(fixture('nats-loggregator-config-spec.json')))
  }

  describe '#run' do
    it 'reads the namespace' do
      expect(Job).to receive(:new).with(hash_including(namespace: 'the-namespace')).and_call_original
      subject.run
    end

    it 'uses default values' do
      expect(Job).to receive(:new).and_wrap_original do |original, arguments|
        expect(arguments[:spec]['properties']['loggregator']['tls']['agent']['cert']).to eq('')
        original.call(arguments)
      end
      subject.run
    end

    context 'with ENV variables' do
      before(:each) {
        stub_const('ENV', 'LOGGREGATOR_AGENT_CERT' => 'FOO')
      }
      it 'considers ENV variables in templates' do
        expect(Job).to receive(:new).and_wrap_original do |original, arguments|
          expect(arguments[:spec]['properties']['loggregator']['tls']['agent']['cert']). to eq('FOO')
          original.call(arguments)
        end

        subject.run
      end
    end

    context 'with a bosh deployment manifest' do
      subject {
        described_class.new(options.merge(bosh_deployment_manifest: File.expand_path('fixtures/nats-manifest.yml', __dir__)))
      }

      it 'considers values from the bosh manifest' do
        expect(subject).to receive(:instance_group).and_return('nats-server')
        expect(Job).to receive(:new).and_wrap_original do |original, arguments|
          expect(arguments[:spec]['properties']['tls']['agent']['cert']). to eq('BAR')
          original.call(arguments)
        end

        subject.run
      end
    end

    describe "#export_job_properties" do
      before(:each) {
        stub_const('ENV',
                   # exported properties secret is only created for the main instance group container
                   'KUBERNETES_CONTAINER_NAME' => 'instance-group',
                   'CONFIGGIN_VERSION_TAG' => '1.2.3')
      }
      it 'writes initial digest values to secret' do
        # Tag does not exist in secret, so create both exported properties setting *and* initial
        # digest values. Do *not* create any annotation on the statefulset.
        subject.run
        secret = client.get_secret('instance-group', 'the-namespace')
        expect(secret).not_to be_nil
        exported_properties = Base64.decode64(secret.data['skiff-exported-properties-loggregator_agent'])
        initial_digest = Base64.decode64(secret.data['skiff-initial-digest-loggregator_agent'])
        expect(initial_digest).to eq property_digest(JSON.parse(exported_properties))

        statefulset = client.get_stateful_set('debugger', 'the-namespace')
        expect(statefulset).not_to be_nil
        expect(statefulset.spec.template.metadata.annotations['skiff-in-props-instance-group-loggregator_agent']).to be_nil
      end

      it 'patches the affected statefulset' do
        # Create secret with tag value, so initial_digest should *not* be written to the secret,
        # but affected statefulsets should be annotated with the expected digest value.
        secret = Kubeclient::Resource.new
        secret.metadata = {
          name: 'instance-group',
          namespace: 'the-namespace',
        }
        secret.data = { ENV['CONFIGGIN_VERSION_TAG'] => "" }
        client.create_secret(secret)

        subject.run
        secret = client.get_secret('instance-group', 'the-namespace')
        expect(secret).not_to be_nil
        expect(secret.data['skiff-initial-digest-loggregator_agent']).to be_nil
        exported_properties = Base64.decode64(secret.data['skiff-exported-properties-loggregator_agent'])

        statefulset = client.get_stateful_set('debugger', 'the-namespace')
        expect(statefulset).not_to be_nil
        expected_digest = statefulset.spec.template.metadata.annotations['skiff-in-props-instance-group-loggregator_agent']
        expect(expected_digest).to eq property_digest(JSON.parse(exported_properties))
      end
    end
  end

  describe '#expected_annotations' do
    let(:job_configs) { JSON.parse(File.read(fixture('nats-job-config.json'))) }
    let(:job_digests) { { 'loggregator_agent' => '123' } }
    it 'should return the correct expected annotations' do
      result = subject.expected_annotations(job_configs, job_digests)
      expect(result).to eq(
        'debugger' => {
          'skiff-in-props-instance-group-loggregator_agent' => '123'
        }
      )
    end
    it 'should do nothing with older job configs' do
      patched_spec = JSON.parse(File.read(fixture('nats-loggregator-config-spec.json')))
      patched_spec.delete 'consumed_by'
      allow(File).to receive(:read).with('/var/vcap/jobs-src/loggregator_agent/config_spec.json')
                                   .and_return(patched_spec.to_json)
      expect do
        subject.expected_annotations(job_configs, job_digests)
      end.not_to raise_error
    end
  end
end
