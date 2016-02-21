require 'yaml'
require 'mustache'
require 'shellwords'

# EnvironmentConfigTransmogrifier uses environment variables to generate config values
# for specific keys.
module EnvironmentConfigTransmogrifier
  # NoEscapeMustache does not escape these characters: & \ " < > '
  class NoEscapeMustache < Mustache
    # Disabling this cop because this is the function we need to override
    # rubocop:disable MethodName
    def escapeHTML(str)
      str
    end
  end

  # Processes the mustache templates and injects new keys into the configuration
  #
  # @return [Hash] Hash containing the updated configuration
  def self.transmogrify(base_config, environment_templates)
    # build input hash for mustache
    input_hash = ENV.to_hash

    # we may need to process the input hash:
    # deal with service discovery env vars, secrets, etc.

    # iterate through templates
    environment_templates.each do |key, template|
      # generate value from template
      begin
        value = YAML.load(NoEscapeMustache.render("{{=(( ))=}}#{template}", input_hash))
      rescue => e
        raise LoadYamlFromMustacheError "Could not load config key '#{key}': #{e.message}"
      end
      # inject value in huge json
      inject_value(base_config, key.split('.'), value)
    end

    base_config
  end

  def self.inject_value(hash, key_grams, value)
    # if we only have 1 gram, we can set the value
    if key_grams.size == 1
      hash[key_grams[0]] = value
      return
    end

    # if there's more than one gram, keep going

    # initialize a hash if we're going deeper
    # than what's currently available
    hash[key_grams[0]] = {} unless hash.key?(key_grams[0])
    # error out if we're trying to override
    # an existing value that's not a hash
    unless hash[key_grams[0]].is_a?(Hash)
      raise NonHashValueOverride, 'Refusing to override non-hash value.'
    end
    # keep going deeper
    inject_value(hash[key_grams[0]], key_grams.drop(1), value)
  end
end
