require 'spec_helper'
require 'bosh_deployment_manifest'
require 'bosh_deployment_manifest_config_transmogrifier'

describe BoshDeploymentManifestConfigTransmogrifier do
  context 'with a bosh deployment manifest' do
    let(:base_config) {
      {
        'job' => {
          'templates' => []
        },
        'properties' => {
          'zookeeper' => {
            'foo' => 'baz'
          }
        }
      }
    }

    it 'updates the config with values from the bosh manifest' do
      manifest = BoshDeploymentManifest.new(
        File.expand_path('fixtures/bosh-deployment-manifest.yml', __dir__)
      )

      # 'server' is the instance group that is being tested
      new_config = BoshDeploymentManifestConfigTransmogrifier.transmogrify(base_config, 'server', manifest)
      expect(new_config['properties']['zookeeper']['foo']).to eq('bar')
    end
  end
end
