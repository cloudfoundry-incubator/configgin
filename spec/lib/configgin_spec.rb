require 'spec_helper'
require 'configgin'

describe Configgin do
  let(:options) {
    {
      jobs: File.expand_path('fixtures/nats-job-config.json', __dir__),
      env2conf: File.expand_path('fixtures/nats-env2conf.yml', __dir__)
    }
  }
  subject {
    described_class.new(options)
  }

  before(:each) {
    allow(subject).to receive(:set_job_metadata)
    allow(subject).to receive(:render_job_templates)
    allow(subject).to receive(:kube_namespace).and_return('the-namespace')
    allow(subject).to receive(:kube_token).and_return('abcdefg')
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/var/vcap/jobs-src/loggregator_agent/config_spec.json')
      .and_return(File.read(File.expand_path('fixtures/nats-loggregator-config-spec.json', __dir__)))
  }

  describe '#run' do
    it 'reads the namespace' do
      expect(Job).to receive(:new).with(anything, "the-namespace", any_args)
      subject.run
    end

    it 'uses default values' do
      expect(Job).to receive(:new) do |bosh_spec, *_|
        expect(bosh_spec['properties']['loggregator']['tls']['agent']['cert']). to eq('')
      end
      subject.run
    end

    context 'with ENV variables' do
      before(:each) {
        stub_const('ENV', 'LOGGREGATOR_AGENT_CERT' => 'FOO')
      }
      it 'considers ENV variables in templates' do
        expect(Job).to receive(:new) do |bosh_spec, *_|
          expect(bosh_spec['properties']['loggregator']['tls']['agent']['cert']). to eq('FOO')
        end

        subject.run
      end
    end

    context 'with a bosh deployment manifest' do
      subject {
        described_class.new(options.merge(bosh_deployment_manifest: File.expand_path('fixtures/nats-manifest.yml', __dir__)))
      }

      it 'considers values from the bosh manifest' do
        stub_const('ENV', 'HOSTNAME' => 'nats-server')
        expect(Job).to receive(:new) do |bosh_spec, *_|
          expect(bosh_spec['properties']['loggregator']['tls']['agent']['cert']). to eq('BAR')
        end

        subject.run
      end
    end
  end
end
