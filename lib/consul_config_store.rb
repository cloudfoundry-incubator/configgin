require 'diplomat'

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

    Diplomat::configure do |config|
      config.url = consul_address
    end
  end

  # Get a key value from the consul store
  # Config key value resolution is described below
  #
  # TODO: Library-ize this resolving, fissile outputs like this:
  # Default sets
  # The default values from the job specs, per job: /<prefix>/spec/<job-name>/<key-path>/
  # Opinions retrieved from generated manifest files: /<prefix>/opinions/<key-path>/
  # User sets
  # Global properties store:  /<prefix>/user/<key-path>
  # Per-role container store: /<prefix>/role/<role-name>/<key-path>
  #
  # @param key [String] The config key (dot separated eg: cc.port)
  # @return    [String] The value (or nil) of the key in the consul config
  def get(key)
    key.gsub!(/\./, '/')

    # Most specific to least specific (in accordance with the stuff above)
    lookup_order = %W(
      /#{@prefix}/role/#{@role}/#{key}
      /#{@prefix}/user/#{key}
      /#{@prefix}/opinions/#{key}
      /#{@prefix}/spec/#{@job}/#{key}
    )

    value = nil
    lookup_order.each { |key_lookup|
      begin
        value = Diplomat::Kv.get(key_lookup)
        break
      rescue Diplomat::KeyNotFound
        value = nil
        next
      end
    }

    return value
  end
end
