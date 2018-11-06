require 'spec_helper'
require 'bosh_deployment_manifest'

describe BoshDeploymentManifest do
  it 'parses the properties' do
    manifest = described_class.new(File.expand_path('fixtures/bosh-deployment-manifest.yml', __dir__))
    expected_properties = {
      'foo' => 'bar',
      'a.b.c' => 1,
      'number' => 2
    }

    expect(manifest.properties_for_instance_group('server')).to eq(expected_properties)
  end

  it 'memoizes instance group properties' do
    manifest = described_class.new(File.expand_path('fixtures/bosh-deployment-manifest.yml', __dir__))
    properties = manifest.properties_for_instance_group('server')

    expect(manifest).to_not receive(:inject_properties)
    memoized_properties = manifest.properties_for_instance_group('server')
    expect(memoized_properties).to eq(properties)
  end
end
