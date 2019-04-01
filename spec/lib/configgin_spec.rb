require 'spec_helper'
require 'configgin'

describe Configgin do
  let(:options) {
    {
      jobs: fixture('nats-job-config.json'),
      env2conf: fixture('nats-env2conf.yml'),
      bosh_deployment_manifest: nil,
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
    allow(subject).to receive(:instance_group).and_return('instance-group')
    allow(subject).to receive(:restart_affected_pods) # and skip the call
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/var/vcap/jobs-src/loggregator_agent/config_spec.json')
      .and_return(File.read(fixture('nats-loggregator-config-spec.json')))
  }

  describe '#run' do
    it 'reads the namespace' do
      expect(Job).to receive(:new).and_wrap_original do |original, arguments|
        expect(arguments[:namespace]).to eq('the-namespace')
        original.call(arguments.merge(self_name: 'pod-0'))
      end
      subject.run
    end

    it 'uses default values' do
      expect(Job).to receive(:new).and_wrap_original do |original, arguments|
        expect(arguments[:spec]['properties']['loggregator']['tls']['agent']['cert']).to eq('')
        original.call(arguments.merge(self_name: 'pod-0'))
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
          original.call(arguments.merge(self_name: 'pod-0'))
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
          original.call(arguments.merge(self_name: 'pod-0'))
        end

        subject.run
      end
    end
  end
end
