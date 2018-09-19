require 'bundler/setup'
Bundler.setup(:default, :test)

class MockKubeClient
  def _get_single(type, name, namespace = nil)
    items = (@state[type] || []).dup
    items.select! { |i| i.metadata.name == name }
    items.select! { |i| i.metadata.namespace == namespace } unless namespace.nil?
    items.first
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
    end
    super
  end

  def respond_to_missing?(method_name, include_private = false)
    return true if method_name.to_s.start_with? 'get_'
    super
  end

  # _convert_ostruct takes an object and recursively converts any
  # encountered hashes to an ostruct
  def _convert_ostruct(obj)
    return OpenStruct.new(Hash[obj.map { |k, v| [k, _convert_ostruct(v)] }]).freeze if obj.is_a?(Hash)
    return obj.map { |v| _convert_ostruct(v) }.freeze if obj.is_a?(Array)
    obj
  end

  def initialize(file_name)
    @state = _convert_ostruct(YAML.load_file(file_name))
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
