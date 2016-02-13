require 'spec_helper'
require 'environment_config_transmogrifier'

describe EnvironmentConfigTransmogrifier do
  context 'with a config_transmogrifier' do
    before do
      @base_config = {
        'job' => {
          'templates' => []
        },
        'properties' => {
          'non_hash_key' => 0,
          'parent_key' => {
            'child_key' => {
            }
          }
        },
        'networks' => {
          'default' => {}
        }
      }
    end

    it 'should error on overriding non hash values' do
      # Arrange
      environment_templates = {
        'properties.non_hash_key.error' => '((TEST_ENV_VAR))'
      }

      # Act
      # Assert
      expect {
        EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)
      }.to(raise_exception(NonHashValueOverride))
    end

    it 'should inject a configuration value' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => 'foo'
      }

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq 'foo'
    end

    it 'should process mustache templates' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => '((MY_FOO_VAR))'
      }
      ENV['MY_FOO_VAR'] = 'bar'

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq 'bar'
    end

    it 'should keep value type' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => '((MY_FOO_VAR))'
      }
      ENV['MY_FOO_VAR'] = '0'

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq 0
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).not_to eq '0'
    end

    it 'should keep specific value type' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => "'((MY_FOO_VAR))'"
      }
      ENV['MY_FOO_VAR'] = '0'

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).not_to eq 0
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq '0'
    end
  end
end
