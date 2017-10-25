require 'spec_helper'
require 'environment_config_transmogrifier'
require 'exceptions'

describe EnvironmentConfigTransmogrifier do
  context 'with a config_transmogrifier' do
    before do
      @base_config = {
        'job' => {
          'templates' => []
        },
        'properties' => {
          'nil_value' => nil,
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
      environment_templates = {
        'properties.non_hash_key.error' => '((TEST_ENV_VAR))'
      }
      expect(ENV).to receive(:to_hash).and_return('TEST_ENV_VAR' => 'false')

      expect {
        EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)
      }.to(raise_exception(NonHashValueOverride,
                           "Refusing to override non-hash value 0 with false: 'non_hash_key.error' - " \
                           "Complete key: 'properties.non_hash_key.error'"))
    end

    it 'should allow overriding nil values' do
      environment_templates = {
        'properties.nil_value' => '((TEST_ENV_VAR))'
      }
      expect(ENV).to receive(:to_hash).and_return('TEST_ENV_VAR' => 'hello')

      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      expect(new_config['properties']['nil_value']).to eq 'hello'
    end

    it 'should inject bootstrap without index' do
      # Arrange
      environment_templates = {}

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['bootstrap']).to be true
    end

    it 'should inject bootstrap for index of primary component' do
      # Arrange
      environment_templates = {
        'index' => 0
      }

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['bootstrap']).to be true
    end

    it 'should inject bootstrap for index of non-primary component' do
      # Arrange
      environment_templates = {
        'index' => 1
      }

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['bootstrap']).to be false
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
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => 'bar')

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq 'bar'
    end

    it 'should error on triple-paren' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => 'f(((MY_FOO_VAR)))'
      }
      # Act
      # Assert
      expect {
        EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)
      }.to(raise_exception(LoadYamlFromMustacheError,
                           /Could not load config key.*Illegal content in tag/))
    end

    it 'should not show values on error' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => 'f(((MY_FOO_VAR))); CLASSIFIED SECRET'
      }
      # Act
      # Assert
      expect {
        begin
          EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)
        rescue LoadYamlFromMustacheError => e
          expect(e.message).not_to match(/CLASSIFIED SECRET/)
          raise
        end
      }.to(raise_exception(LoadYamlFromMustacheError,
                           /Could not load config key 'properties.parent_key.child_key.grandchild_key'/))
    end

    it 'should support changing templates inline' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => '((={{ }}=))f({{MY_FOO_VAR}})'
      }
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => 'bar')
      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)
      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq 'f(bar)'
    end

    it 'should not handle quoted references as verbatim strings' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => 'f(("("))((MY_FOO_VAR))((")"))'
      }
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => 'bar')
      # Act
      # Assert
      expect { EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates) }
        .to raise_exception(LoadYamlFromMustacheError) do |e|
          prefix = "Could not load config key 'properties.parent_key.child_key.grandchild_key'"
          expect(e.message).to start_with prefix
          expect(e.message).to include 'Illegal content in tag'
        end
    end

    it 'should process mustache templates with new lines are kept' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => '((MY_FOO_VAR))'
      }
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => "bar\nfoo")

      # Act
      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      # Assert
      expect(new_config['properties']['parent_key']['child_key']['grandchild_key']).to eq "bar\nfoo"
    end

    it 'should keep value type' do
      # Arrange
      environment_templates = {
        'properties.parent_key.child_key.grandchild_key' => '((MY_FOO_VAR))'
      }
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => '0')

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
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => '0')

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
      expect(ENV).to receive(:to_hash).and_return('MY_FOO_VAR' => 'bar')

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
      allow(EnvironmentConfigTransmogrifier).to receive(:extendReplace) {}
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
      allow(EnvironmentConfigTransmogrifier).to receive(:extendReplace) {}
      environment_templates = {}

      # Act
      EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates,
                                                   secrets: nil)
      # Asserts
      expect(EnvironmentConfigTransmogrifier).to receive(:extendReplace).exactly(0).times
    end

    it 'should recursively resolve subtitutions' do
      expect(ENV).to receive(:to_hash).and_return('FOO' => '((BAR))', 'BAR' => 'bbb')

      environment_templates = {
        'properties.key' => 'aaa((FOO))ccc'
      }

      new_config = EnvironmentConfigTransmogrifier.transmogrify(@base_config, environment_templates)

      expect(new_config['properties']['key']).to eq 'aaabbbccc'
    end
  end
end
