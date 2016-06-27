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
      }.to(raise_exception(NonHashValueOverride,
                           "Refusing to override non-hash value: 'non_hash_key.error' - " \
                           "Complete key: 'properties.non_hash_key.error'"))
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

    it 'should read secrets directory and use them over ENV' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => '((MY_FOO_VAR))'
      }
      ENV['MY_FOO_VAR'] = 'bar'

      Dir.mktmpdir do |secrets|
        f = File.new(File.join(secrets, 'MY_FOO_VAR'), 'w')
        f.write('BIG')
        f.close

        # Act
        new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates,
                                                                  secrets: secrets)

        # Assert
        expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq 'BIG'
      end
    end

    it 'should ignore a secrets file' do
      # Arrange
      allow(EnvironmentConfigTransmogrifier).to receive (:extendReplace) {}
      environment_templates = {}

      Dir.mktmpdir do |tmp|
        secrets = File.join(tmp, 'MY_FOO_VAR')
        f = File.new(secrets, 'w')
        f.write('BIG')
        f.close

        # Act
        EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates,
                                                     secrets: secrets)
        # Asserts
        expect(EnvironmentConfigTransmogrifier).to receive(:extendReplace).exactly(0).times
      end
    end

    it 'should ignore a nil secrets' do
      # Arrange
      allow(EnvironmentConfigTransmogrifier).to receive (:extendReplace) {}
      environment_templates = {}

      # Act
      EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates,
                                                   secrets: nil)
      # Asserts
      expect(EnvironmentConfigTransmogrifier).to receive(:extendReplace).exactly(0).times
    end
  end
end
