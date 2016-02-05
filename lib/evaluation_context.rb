require 'bosh/template/evaluation_context'
require 'deep_merge'
require 'shellwords'

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
    hash = config_store.build
    data['properties'] = hash.deep_merge!(data['properties'])
    super(data)
  end
end
