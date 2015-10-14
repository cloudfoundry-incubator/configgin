require 'bosh/template/evaluation_context'
require 'ostruct_config_store'
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
    @config_store = config_store # super(data) needs this to be set before it runs
    super(data)
  end

  # Look up 'name' property in the collection
  # Overrides Bosh::Template::EvaluationContext.lookup_property
  # (from include Bosh::Template::PropertyHelper)
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

  # openstruct is a helper that calls make_open_struct
  # cannot be removed because inside initialize() super(data) calls this.
  def openstruct(object)
    EvaluationContext.make_open_struct(object, @config_store)
  end

  # Creates a nested OpenStructConfigStore representation of the hash.
  # Overrides Bosh::Template::EvaluationContext.openstruct
  #
  # @param object       [Object] A hash, array or something else.
  # @param config_store [Object] Config store to create OpenStructConfigStore's with
  # @return             [OpenStructConfigStore] An object that behaves like OpenStruct.
  def self.make_open_struct(object, config_store)
    case object
    when Hash
      mapped = object.inject({}) { |h, (k, v)|
        h[k] = make_open_struct(v, config_store)
        h
      }
      OpenStructConfigStore.new(mapped, config_store: config_store)
    when Array
      object.map { |item| make_open_struct(item, config_store) }
    else
      object
    end
  end
end
