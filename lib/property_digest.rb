require 'digest/sha1'
require 'json'

# Given a properties (a JSON-serializable Hash), generate a digest that will be
# consistent across runs even if the enumeration order of hashes changes.
def property_digest(properties)
  normalize_object = lambda do |obj|
    case obj
    when Hash
      {}.tap { |result| obj.sort.each { |k, v| result[k] = normalize_object.call(v) } }
    when Enumerable
      obj.map(&normalize_object)
    else
      obj
    end
  end
  "sha1:#{Digest::SHA1.hexdigest(normalize_object.call(properties).to_json)}"
end
