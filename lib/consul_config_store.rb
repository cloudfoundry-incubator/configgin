require 'diplomat'
require 'yaml'

# ConsulConfigStore uses consul to look up values.
class ConsulConfigStore
  # Initialize a new consul config store using address
  #
  # @param consul_address [String] The address to the consul agent/server
  # @param prefix         [String] The prefix of the key sets.
  # @param job            [String] Job name
  # @param role           [String] Role name
  def initialize(consul_address, prefix, job, role)
    @prefix = prefix
    @job = job
    @role = role

    Diplomat.configure do |config|
      config.url = consul_address
    end
  end

  # Build the configuration hash using specific lookup rules
  #
  # @return       [Hash]   The giant hash from consul
  def build()
    lookup_order = %W(
      /#{@prefix}/spec/#{@job}/
      /#{@prefix}/opinions/
      /#{@prefix}/user/
      /#{@prefix}/role/#{@role}/
    )

    hash = {}
    lookup_order.each do |lookup|
      hash.merge!(config_for_prefix(lookup))
    end

    ConsulConfigStore.recursively_expand_hash(hash)
  end

  # Get the key value pairs for a key prefix from consul.
  #
  # @return [Hash] The key values turned into a hash.
  def config_for_prefix(prefix)
    begin
      kvpairs = Diplomat::Kv.get(prefix, { recurse: true })
    rescue Diplomat::KeyNotFound
      return {}
    end

    hash = {}
    kvpairs.each do |kvp|
      key_replace = prefix[1, prefix.length]
      key = kvp[:key].gsub(/^#{key_replace}/, '')
      hash[key] = YAML.load(kvp[:value])
    end

    hash
  end

  def self.recursively_expand_hash(hash)
    new_hash = {}
    hash.each_pair do |k, v|
      key_parts = k.split('/').reject { |s| s.empty? }
      len = key_parts.length
      i = 1

      key_parts.inject(new_hash) do |h, key|
        unless h.is_a?(Hash)
          prev_key = key_parts[0..i-2].join('/')
          this_key = key_parts[0..i-1].join('/')
          prev_val = hash[prev_key].nil? ? "nil" : hash[prev_key].to_s
          fail StandardError, "#{prev_key} is a value: #{prev_val}, but also has a sub-key: #{this_key} => #{v}"
        end

        val = nil
        if i == len
          h[key] = v
        elsif !h.has_key?(key)
          h[key] = {}
        end

        i += 1
        h[key]
      end
    end

    new_hash
  end
end
