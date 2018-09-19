require_relative 'base_transmogrifier'

# BoshDeploymentManifestConfigTransmogrifier extracts property values from a bosh
# manifest and updates the config accordingly.
class BoshDeploymentManifestConfigTransmogrifier < BaseTransmogrifier
  def self.transmogrify(base_config, instance_group, bosh_deployment_manifest)
    bosh_deployment_manifest.properties_for_instance_group(instance_group).each do |key, value|
      full_key = 'properties.' + key
      inject_value(base_config, full_key.split('.'), value, full_key)
    end
    base_config
  end
end
