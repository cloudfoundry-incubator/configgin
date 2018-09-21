require 'spec_helper'
require 'bosh_deployment_manifest'

describe BoshDeploymentManifest do
  it 'parses the properties' do
    manifest = described_class.new(File.expand_path('fixtures/bosh-deployment-manifest.yml', __dir__))
    expected_properties = {
      'zookeeper.foo' => 'bar',
      'zookeeper.a.b.c' => 1,
      'status.number' => 2
    }

    expect(manifest.properties_for_instance_group('server')).to eq(expected_properties)
  end
end
