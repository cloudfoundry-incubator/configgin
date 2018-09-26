# BaseTransmogrifier holds shared code for the transmogrifier classes
class BaseTransmogrifier
  def self.inject_value(hash, key_grams, value, original_key)
    # if we only have 1 gram, we can set the value
    if key_grams.size == 1
      # If the new value is nil, and the old value was a hash, it's because
      # somebody didn't provide a full default value; ignore it.
      unless value.nil? && hash[key_grams[0]].is_a?(Hash)
        hash[key_grams[0]] = value
      end
      return
    end

    # if there's more than one gram, keep going

    # Initialize a hash if we're going deeper than what's currently available;
    # sometimes we want to override when the old value is nil (i.e. no default)
    # but the new value is a hash.
    hash[key_grams[0]] = {} if hash[key_grams[0]].nil?
    # error out if we're trying to override
    # an existing value that's not a hash
    unless hash[key_grams[0]].is_a?(Hash)
      raise NonHashValueOverride, \
            "Refusing to override non-hash value #{hash[key_grams[0]].inspect} " \
            "with #{value.inspect}: '#{key_grams.join('.')}'" \
            " - Complete key: '#{original_key}'"
    end
    # keep going deeper
    inject_value(hash[key_grams[0]], key_grams.drop(1), value, original_key)
  end
end
