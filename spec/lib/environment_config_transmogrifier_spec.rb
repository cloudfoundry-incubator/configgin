require 'spec_helper'
require 'environment_config_transmogrifier'

describe EnvironmentConfigTransmogrifier do
  context 'with a config_transmogrifier' do
    before do
      @base_config = {
        "job" => {
          "templates" => []
        },
        "properties" => {
          "non_hash_key" => 0,
          "parent_key" => {
            "child_key" => {
            }
          }
        },
        "networks" => {
          "default" => {}
        }
      }
    end

    it 'should error on overriding non hash values' do
      # Arrange
      environment_templates = {
        "properties.non_hash_key.error" => "((TEST_ENV_VAR))"
      }
      ct = EnvironmentConfigTransmogrifier.new(@base_config, environment_templates)

      # Act
      # Assert
      expect { ct.transmogrify }.to raise_exception NonHashValueOverride
    end

    it 'should inject a configuration value' do
      # Arrange
      environment_templates = {
        "properties.parent_key.child_key.grandchild_key" => "foo"
      }
      ct = EnvironmentConfigTransmogrifier.new(@base_config, environment_templates)

      # Act
      new_config = ct.transmogrify

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq ('foo')
    end

    it 'should process mustache templates' do
      # Arrange
      environment_templates = {
        "properties.parent_key.child_key.grandchild_key" => "((MY_FOO_VAR))"
      }
      ct = EnvironmentConfigTransmogrifier.new(@base_config, environment_templates)
      ENV['MY_FOO_VAR'] = 'bar'

      # Act
      new_config = ct.transmogrify

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq ('bar')
    end
  end
end
