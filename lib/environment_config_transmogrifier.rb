require 'yaml'
require 'mustache'

# EnvironmentConfigTransmogrifier uses environment variables to generate config values
# for specific keys.
class EnvironmentConfigTransmogrifier
  # Initialize a new EnvironmentConfigTransmogrifier using a base configuration
  # and a set of environment templates
  #
  # @param base_config            [Hash] Hash containing base configuration.
  # @param environment_templates  [Hash] Hash containing configuration templates.
  def initialize(base_config, environment_templates)
    @base_config = base_config
    @environment_templates = environment_templates
  end

  # Processes the mustache templates and injects new keys into the configuration
  #
  # @return [Hash] Hash containing the updated configuration
  def transmogrify
    # build input hash for mustache
    input_hash = {}
    ENV.each_pair do |var, value|
      input_hash[var] = value
    end

    # we may need to process the input hash:
    # deal with service discovery env vars, secrets, etc.

    # iterate through templates
    @environment_templates.each do |key, template|
      # generate value from template
      value = Mustache.render("{{=(( ))=}}#{template}", input_hash)
      # inject value in huge json
      inject_value(@base_config, key, value)
    end

    return @base_config
  end

  def get(key)
  end

  private

  def inject_value(hash, key, value)
    # split key by '.'
    key_grams = key.split('.')

    # if there's more than one gram, keep going
    if key_grams.size > 1
      # initialize a hash if we're going deeper
      # than what's currently available
      hash[key_grams[0]] = {} unless hash.has_key?(key_grams[0])
      # error out if we're trying to override
      # an existing value that's not a hash
      if !hash[key_grams[0]].is_a?(Hash)
        raise NonHashValueOverride, 'Refusing to override non-hash value.'
      end
      # keep going deeper
      inject_value(hash[key_grams[0]], key_grams.drop(1).join('.'), value)
    else
      # else, we can set the value
      hash[key] = value
    end
  end
end
