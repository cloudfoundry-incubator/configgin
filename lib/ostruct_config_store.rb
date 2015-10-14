require 'ostruct'

# OpenStructConfigStore behaves like open struct except for if it can't find
# a value in itself, it will ask the config_store.
class OpenStructConfigStore < OpenStruct
  # KvFinder recursively uses itself and the config_store to get values out
  # of the config_store that are evaluated like so: kvfinder1.kvfinder2 and so on.
  class KvFinder
    def initialize(key, config_store)
      @key = key
      @config_store = config_store
    end

    def method_missing(name, *_args)
      @key << name.to_s
      val = @config_store.get(@key.join('.'))
      return val unless val.nil?

      self
    end
  end

  @@key = []

  def initialize(hash = nil, config_store: nil)
    @config_store = config_store
    super(hash)
  end

  def method_missing(name, *args)
    @@key.push(name.to_s)

    val = super(name, *args)
    unless val.nil?
      @@key = [] unless val.instance_of?(OpenStructConfigStore)
      return val
    end

    val = @config_store.get(@@key.join('.'))
    return val unless val.nil?

    finder = KvFinder.new(@@key.dup, @config_store)
    @@key = []
    finder
  end

  def new_ostruct_member(name)
    name.to_sym
  end
end
