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
        when 'KUBERNETES_CLUSTER_DOMAIN' then 'domain'
        when 'KUBERNETES_NAMESPACE' then 'namespace'
        else env.call(name)
        end
      end

      # Make the tests run faster
      stub_const('KubeLinkSpecs::SLEEP_DURATION', 0)
    end

    around(:each) { |ex| trap_error(ex) }
=begin
    context :get_pods_for_role do
      it 'should get the expected pods' do
        pods = specs.get_pods_for_role('dummy', 'dummy')
        expect(pods.length).to be 3
        expect(pods[0].metadata.name).to eq('ready-pod-0')
        expect(pods[1].metadata.name).to eq('ready-pod-too-0')
        expect(pods[2].metadata.name).to eq('bootstrap-pod-3')
      end

      it 'should find pods from before jobs in properties' do
        client = MockKubeClient.new(fixture('state-jobless-properties.yml'))
        allow(specs).to receive(:client) { client }
        pods = specs.get_pods_for_role('dummy', 'dummy')
        expect(pods.length).to be 2
        expect(pods[0].metadata.name).to eq('old-pod-0')
        expect(specs.get_exported_properties('dummy-role', pods[0], 'dummy')).to include('prop' => 'b')
        expect(pods[1].metadata.name).to eq('new-pod-0')
        expect(specs.get_exported_properties('dummy-role', pods[1], 'dummy')).to include('prop' => 'c')
      end

      # Build a client with the given answers (sequentially)
      # The block will be called with the current index, total count, and the unmodified pods
      def build_answers
        max = 10
        answers = Array.new(max) do |i|
          client = MockKubeClient.new(fixture('state-jobless-properties.yml'))
          pods = client.get_pods(namespace: namespace, label_selector: 'app.kubernetes.io/component=dummy')
          yield i, max, pods
        end

        client = MockKubeClient.new(fixture('state-jobless-properties.yml'))
        allow(specs).to receive(:client) { client }
        allow(client).to receive(:get_pods) do
          expect(answers).not_to be_empty
          answers.shift
        end

        answers
      end

      it 'should wait for pods to be ready' do
        # Build canned answers where the pods are not ready
        answers = build_answers do |index, max, pods|
          if index + 1 < max
            pods.map! do |pod|
              # Drop the podIP
              status = OpenStruct.new(pod.status.to_h.merge(podIP: nil)).freeze
              OpenStruct.new(pod.to_h.merge(status: status)).freeze
            end
          end
          pods
        end

        pods = specs.get_pods_for_role('dummy', 'dummy')
        expect(pods).not_to be_empty
        expect(answers).to be_empty
        expect(pods.length).to eq 2
        expect(pods[0].metadata.name).to eq('old-pod-0')
        expect(pods[1].metadata.name).to eq('new-pod-0')
      end

      it 'should wait for all pods to be ready' do
        # Build canned answers where the pods are not ready
        answers = build_answers do |index, max, pods|
          if index + 1 < max
            pods.map! do |pod|
              next pod if index.even? && pod.metadata.name.start_with?('old')
              next pod if index.odd?  && pod.metadata.name.start_with?('new')

              # Drop the podIP
              status = OpenStruct.new(pod.status.to_h.merge(podIP: nil)).freeze
              OpenStruct.new(pod.to_h.merge(status: status)).freeze
            end
          end
          pods
        end

        pods = specs.get_pods_for_role('dummy', 'dummy', wait_for_all: true)
        expect(pods).not_to be_empty
        expect(answers).to be_empty
        expect(pods.length).to eq 2
        expect(pods[0].metadata.name).to eq('old-pod-0')
        expect(pods[1].metadata.name).to eq('new-pod-0')
      end

      it 'should accept the old pod as ready' do
        answers = build_answers do |_, _, pods|
          pods.map! do |pod|
            next pod if pod.metadata.name == 'old-pod-0'

            # Drop the podIP
            status = OpenStruct.new(pod.status.to_h.merge(podIP: nil)).freeze
            OpenStruct.new(pod.to_h.merge(status: status)).freeze
          end
        end

        pods = specs.get_pods_for_role('dummy', 'dummy')
        expect(pods).not_to be_empty
        expect(answers).not_to be_empty # should have only needed the first one
        expect(pods.length).to eq 1
        expect(pods[0].metadata.name).to eq('old-pod-0')
      end

      it 'should accept the new pod as ready' do
        answers = build_answers do |_, _, pods|
          pods.map! do |pod|
            next pod if pod.metadata.name.start_with? 'new'

            # Drop the podIP
            status = OpenStruct.new(pod.status.to_h.merge(podIP: nil)).freeze
            OpenStruct.new(pod.to_h.merge(status: status)).freeze
          end
        end

        pods = specs.get_pods_for_role('dummy', 'dummy')
        expect(pods).not_to be_empty
        expect(answers).not_to be_empty # should have only needed the first one
        expect(pods.length).to eq 1
        expect(pods[0].metadata.name).to eq('new-pod-0')
      end
    end

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
        role = 'dummy-role'
        job = 'dummy'
        sts_image = "docker.io/image-one\ndocker.io/image-two"
        pods = specs._get_pods_for_role(job, sts_image)
        pod = pods.find { |p| p.metadata.name.start_with? 'bootstrap-pod' }
        expect(pod).to_not be_nil
        pods_per_image = specs.get_pods_per_image(pods)
        expect(specs.get_pod_instance_info(role, pod, job, pods_per_image)).to include(
          'address'    => 'bootstrap-pod-3.provider-role.namespace.svc.domain',
          'az'         => 'az0',
          'bootstrap'  => true,
          'id'         => 'bootstrap-pod-3',
          'index'      => 3,
          'name'       => 'bootstrap-pod-3',
          'properties' => {}
        )
      end
      it 'should not be bootstrap with multiple pods of the same images' do
        role = 'dummy-role'
        job = 'dummy'
        sts_image = "docker.io/image-one\ndocker.io/image-two"
        pods = specs._get_pods_for_role(job, sts_image)
        pod = pods.find { |p| p.metadata.name.start_with? 'ready-pod-0' }
        expect(pod).to_not be_nil
        pods_per_image = specs.get_pods_per_image(pods)
        instance_info = specs.get_pod_instance_info(role, pod, job, pods_per_image)
        expect(instance_info['bootstrap']).not_to be_truthy
      end
    end

    context :get_pods_per_image do
      it 'should return the expected counts' do
        job = 'dummy'
        sts_image = "docker.io/image-one\ndocker.io/image-two"
        pods = specs._get_pods_for_role(job, sts_image)
        pods_per_image = specs.get_pods_per_image(pods)
        expect(pods_per_image).to eq(
          '893dd4a8-2067-44d3-aae7-1389f6a1789a' => 2,
          'fed899c8-0140-48fd-ac88-772368bde1f9' => 2,
          '9091e7e7-ec89-453b-b5ca-352a47772fe9' => 1
        )
      end
    end
=end
  end
end
