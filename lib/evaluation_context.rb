require 'bosh/template/evaluation_context'
require 'yaml'

# EvaluationContext looks up values in a hybrid bosh-template way but also
# using a fallback config_store (an example of which is ConsulConfigStore)
class EvaluationContext < Bosh::Template::EvaluationContext
  # Create a new evaluation context with the data and a config store to resolve
  # values missing from the config.
  #
  # @param data         [String] The data with which to look up values
  #                              before defaulting to the config_store.
  # @param config_store [Object] Anything that responds to .get(key)
  #                              for retrieving config values.
  def initialize(data, config_store)
    super(data)
    @config_store = config_store
  end

  # Look up 'name' property in the collection
  #
  # @param collection [Hash]   The collection to look up against
  # @param key        [String] Dot-separated property key name.
  def lookup_property(collection, key)
    keys = key.split('.')
    ref = collection

    # Check in the data data to see if it's present and return it if it is
    keys.each do |fragment|
      ref = ref[fragment]
      break if ref.nil?
    end

    return ref unless ref.nil?

    @config_store.get(key)
  end
end
