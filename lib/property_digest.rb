require 'digest/sha1'
require 'json'

# Given a properties (a JSON-serializable Hash), generate a digest that will be
# consistent across runs even if the enumeration order of hashes changes.
def property_digest(properties)
    def normalize_object(obj)
        case obj
        when Hash
            Hash.new.tap { |result| obj.sort.each { |k, v| result[k] = normalize_object(v) } }
        when Enumerable
            obj.map { |v| normalize_object(v) }
        else
            obj
        end
    end
    json = normalize_object(properties).to_json
    "sha1:#{Digest::SHA1.hexdigest(json)}"
end
