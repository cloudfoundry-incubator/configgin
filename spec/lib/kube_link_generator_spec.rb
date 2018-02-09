require 'spec_helper'
require 'kube_link_generator'

describe KubeLinkSpecs do
  context 'with some file paths and an eval context' do
    bosh_spec = JSON.parse(File.read(fixture('fake.json')))

    let(:namespace) { 'namespace' }
    let(:client) { MockKubeClient.new(fixture('state-multi.yml')) }
    let(:client_stateful_set) { MockKubeClient.new(fixture('stateful-set.yml')) }
    subject(:specs) { KubeLinkSpecs.new(bosh_spec, namespace, client, client_stateful_set) }

    before do
      allow(ENV).to receive(:[]).and_wrap_original do |env, name|
        case name
        when 'KUBE_SERVICE_DOMAIN_SUFFIX' then 'domain'
        else env.call(name)
        end
      end
    end

    around(:each) { |ex| trap_error(ex) }

    context :get_statefulset_instance_info do
      it 'should return the expected information' do
        instances = specs.get_statefulset_instance_info('dummy', 'dummy')
        expect(instances.length).to be 3
        expect(instances[0]['bootstrap']).to be true
        expect(instances[1]['bootstrap']).to be false
        expect(instances[2]['bootstrap']).to be false
        expect(instances[0]['index']).to be 0
        expect(instances[1]['index']).to be 1
        expect(instances[2]['index']).to be 2
        expect(instances[0]['address']).to eq 'dummy-0.dummy-set'
        expect(instances[1]['address']).to eq 'dummy-1.dummy-set'
        expect(instances[2]['address']).to eq 'dummy-2.dummy-set'
      end
    end

    context :get_pod_instance_info do
      it 'should return the expected information' do
        job = 'dummy'
        pods = specs._get_pods_for_role(job)
        pod = pods.find { |p| p.metadata.name.start_with? 'bootstrap-pod' }
        expect(pod).to_not be_nil
        pods_per_image = specs.get_pods_per_image(pods)
        expect(specs.get_pod_instance_info(pod, job, pods_per_image)).to include(
          'address'    => '1.2.3.4',
          'az'         => 'az0',
          'bootstrap'  => true,
          'id'         => 'bootstrap-pod-3',
          'index'      => 3,
          'name'       => 'bootstrap-pod-3',
          'properties' => {}
        )
      end
      it 'should not be bootstrap with multiple pods of the same images' do
        job = 'dummy'
        pods = specs._get_pods_for_role(job)
        pod = pods.find { |p| p.metadata.name.start_with? 'ready-pod-0' }
        expect(pod).to_not be_nil
        pods_per_image = specs.get_pods_per_image(pods)
        instance_info = specs.get_pod_instance_info(pod, job, pods_per_image)
        expect(instance_info['bootstrap']).not_to be_truthy
      end
    end

    context :get_pods_per_image do
      it 'should return the expected counts' do
        job = 'dummy'
        pods = specs._get_pods_for_role(job)
        pods_per_image = specs.get_pods_per_image(pods)
        expect(pods_per_image).to eq(
          '893dd4a8-2067-44d3-aae7-1389f6a1789a' => 2,
          'fed899c8-0140-48fd-ac88-772368bde1f9' => 2,
          '9091e7e7-ec89-453b-b5ca-352a47772fe9' => 1
        )
      end
    end
  end
end
