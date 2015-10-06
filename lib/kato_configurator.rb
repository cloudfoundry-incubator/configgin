# KatoConfigurator uses Kato::Config to look up various values
# and special cases a few different names/values.
class KatoConfigurator
  # get a configuration value
  #
  # @param component [String] The component name of the hash to fetch
  # @param name      [String] The / separated key value to fetch.
  def get(component, name)
    case
    when component == "nodes"
      return Kato::Cluster::Manager.node_ids_for_process(name)
    when component == "cluster" && name == "endpoint"
      return "http://#{Kato::Config.get(component, name)}"
    when component == "dea_ng" && name == "resources/memory_mb"
      value = Kato::Config.get(component, name)
      if value == "auto"
        value = 1024
      end
      value
    else
      return Kato::Config::get(component, name)
    end
  end
end
