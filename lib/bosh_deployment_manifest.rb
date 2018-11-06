require 'yaml'

# BoshDeploymentManifest is used to parse BOSH manifests
class BoshDeploymentManifest
  def initialize(path)
    @manifest = YAML.load_file(path)
  end

  def properties_for_instance_group(instance_group_name)
    return @properties[instance_group_name] if @properties && @properties[instance_group_name]

    instance_group = @manifest['instance_groups'].find { |group| group['name'] == instance_group_name }
    return [] unless instance_group

    properties = {}
    instance_group['jobs'].each do |job|
      next unless job.key?('properties')

      job['properties'].each do |key, value|
        inject_properties(properties, job, key, value)
      end
    end

    @properties ||= {}
    @properties[instance_group_name] = properties
  end

  private

  def inject_properties(properties, job, key, value)
    case value
    when Hash
      value.each do |sub_key, sub_value|
        inject_properties(properties, job, "#{key}.#{sub_key}", sub_value)
      end
    else
      properties[key] = value
    end
  end
end
