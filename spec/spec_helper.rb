require 'bundler/setup'
Bundler.setup(:default, :test)

class MockKubeClient
  def _get_single(type, name, namespace = nil)
    items = (@state[type] || []).dup
    items.select! { |i| i.metadata.name == name }
    items.select! { |i| i.metadata.namespace == namespace } unless namespace.nil?
    items.first
  end

  def _patch_single(type, name, patch, namespace = nil)
    object = _get_single(type, name, namespace)
    raise %(Could not find #{type} "#{namespace}/#{name}" to patch) unless object

    patch_object = lambda do |child_obj, child_patch|
      child_patch.each_pair do |k, v|
        child_obj[k] = v.is_a?(Hash) ? patch_object.call(child_obj[k] || OpenStruct.new, v) : v
      end
      child_obj
    end
    patch_object.call object, patch
  end

  def _delete_single(type, name, namespace = nil)
    (@state[type] ||= []).delete_if do |resource|
      name == resource.metadata.name && (namespace.nil? || namespace == resource.metadata.namespace)
    end
  end

  def _create_single(type, resource)
    (@state[type] ||= []).push(resource)
  end

  def _get_multiple(type, filters = {})
    items = (@state[type] || []).dup
    items.select! { |i| i.metadata.namespace == filters[:namespace] } unless filters[:namespace].nil?
    unless filters[:label_selector].nil?
      label, value = filters[:label_selector].split('=', 2)
      items.select! { |i| i.metadata.labels[label] == value }
    end
    items
  end

  def method_missing(name, *args)
    if name.to_s.start_with? 'get_'
      type = name.to_s.sub(/^get_/, '').sub(/s$/, '')
      return _get_multiple(type, *args) if name.to_s.end_with? 's'

      return _get_single(type, *args)
    elsif name.to_s.start_with? 'patch_'
      type = name.to_s.sub(/^patch_/, '').sub(/s$/, '')
      raise "Don't know how to patch multiple #{type}s: #{name}" if name.to_s.end_with? 's'

      return _patch_single(type, *args)
    elsif name.to_s.start_with? 'delete_'
      type = name.to_s.sub(/^delete_/, '').sub(/s$/, '')
      raise "Don't know how to delete multiple #{type}s: #{name}" if name.to_s.end_with? 's'

      return _delete_single(type, *args)
    elsif name.to_s.start_with? 'create_'
      type = name.to_s.sub(/^create_/, '').sub(/s$/, '')
      raise "Don't know how to create multiple #{type}s: #{name}" if name.to_s.end_with? 's'

      return _create_single(type, *args)
    end
    super
  end

  def respond_to_missing?(method_name, include_private = false)
    return true if /^(?:get|patch|delete|create)_/ =~ method_name.to_s

    super
  end

  def initialize(file_name)
    @state = convert_to_openstruct(YAML.load_file(file_name))
  end
end

# convert_to_openstruct takes an object and recursively converts any
# encountered hashes to an OpenStruct
def convert_to_openstruct(obj)
  case obj
  when Hash, OpenStruct
    OpenStruct.new(Hash[obj.map { |k, v| [k, convert_to_openstruct(v)] }])
  when Array
    obj.map { |v| convert_to_openstruct(v) }
  else
    obj
  end
end

def trap_error(example)
  # Eat stderr and only print it if something goes wrong
  orig_stderr = $stderr
  $stderr = StringIO.new('', 'w')
  begin
    result = example.run
  ensure
    orig_stderr.write $stderr.string if result.is_a?(Exception)
    $stderr = orig_stderr
  end
  result
end

def fixture(relpath)
  File.join(File.dirname(__FILE__), 'lib/fixtures', relpath)
end
