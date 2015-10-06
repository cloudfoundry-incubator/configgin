require 'bosh/template/evaluation_context'
require 'kato/config'
require 'yaml'

# EvaluationContext looks up values in a hybrid bosh-template way but also
# using a fallback Configurator (an example of which is KatoConfigurator)
# Uses the mappings described in config/mappings.yml to map bosh template
# names to kato config names.
class EvaluationContext < Bosh::Template::EvaluationContext
  SECTION_STATIC_VALUES = 'static_values'.freeze
  SECTION_MAPPINGS      = 'mappings'.freeze

  # Create a new evaluation context with the context and a config resolver
  #
  # @param context      [String] The context with which to look up values
  #                              before defaulting to the configurator.
  # @param configurator [Object] Anything that responds to .get(component, key)
  #                              for retrieving config values.
  def initialize(context, configurator)
    super(context)
    @configurator = configurator
  end

  # Look up 'name' property in the collection
  #
  # @param collection [Hash]   The collection to look up against
  # @param name       [String] Dot-separated property name
  def lookup_property(collection, name)
    keys = name.split(".")
    ref = collection

    # Check in the context data to see if it's present and return it if it is
    keys.each do |key|
      ref = ref[key]
      break if ref.nil?
    end
    return ref unless ref.nil?

    ref = config[SECTION_STATIC_VALUES][name]

    mapping = config[SECTION_MAPPINGS][name]
    unless mapping.nil?
      unless ref.nil?
        raise MappingConflictError, "#{name} in both static_values and mappings in config"
      end

      component, key = mapping.split('/', 2)
      ref = @configurator.get(component, key)
    end

    return ref
  end

  # Loads the mappings.yml configuration file.
  def config
    @config ||= YAML.load_file(File.join(File.dirname(__FILE__), '..', 'config', 'mappings.yml'))
  end
end
