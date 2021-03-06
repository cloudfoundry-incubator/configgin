require 'yaml'
require 'mustache'
require 'shellwords'
require 'tmpdir'

require_relative 'base_transmogrifier'

# EnvironmentConfigTransmogrifier uses environment variables to generate config values
# for specific keys.
class EnvironmentConfigTransmogrifier < BaseTransmogrifier
  @@memoize_mustache = {}

  # NoEscapeMustache does not escape these characters: & \ " < > '
  class NoEscapeMustache < Mustache
    # Disabling this cop because this is the function we need to override
    # rubocop:disable MethodName
    def escapeHTML(str)
      str
    end
    # rubocop:enable MethodName
  end

  # Processes the mustache templates and injects new keys into the configuration
  #
  # @return [Hash] Hash containing the updated configuration
  def self.transmogrify(base_config, environment_templates, secrets: nil)
    # build input hash for mustache
    input_hash = ENV.to_hash

    # load secrets
    extend_replace(input_hash, secrets) if secrets && File.directory?(secrets)

    # remove empty values
    input_hash.reject! { |_, v| v.nil? || v.empty? }

    # iterate through templates
    environment_templates.each do |key, value|
      # generate value from template

      # we need to process the template at least once, even if it doesn't
      # actually contain a mustache template, to get value types correctly;
      # by default, all values are strings, because they come from the environment
      # we need to unmarshall them using YAML.load
      loop do
        value = process_mustache_template(value, input_hash, key)
        break unless value.respond_to?(:include?) && value.include?('((')
      end

      # inject value in huge json
      inject_value(base_config, key.split('.'), value, key)
    end

    base_config
  end

  def self.process_mustache_template(value, input_hash, key)
    val = @@memoize_mustache.fetch(value, {})[input_hash]
    return val if val

    delimiter = '{{=(( ))=}}'
    begin
      mustache_value = NoEscapeMustache.render("#{delimiter}#{value}", input_hash)
      # replace new lines with double new lines for proper new-line YAML parsing
      mustache_value = mustache_value.to_s.gsub("\n", "\n\n")
      @@memoize_mustache[value] ||= {}
      @@memoize_mustache[value][input_hash] = YAML.safe_load(mustache_value)
    rescue StandardError => e
      msg = mustache_message_from_error(e)
      raise LoadYamlFromMustacheError, "Could not load config key '#{key}': #{msg}"
    end
  end

  def self.mustache_message_from_error(error)
    lines = error.message.split(/\n/)
    return 'No reason for failure given by mustache library' if lines.empty?
    return lines.first if lines.size < 4

    caret_line = lines[3]
    caret_pos = caret_line.index('^')
    return lines[0] + '.' unless caret_pos

    delimiter = '{{=(( ))=}}'
    actual_line = lines[2]
    leading_junk = actual_line.lstrip.start_with?(delimiter) ? actual_line.index(delimiter) : 0
    lines[0] + ": Error at or near position #{caret_pos - leading_junk} of template value."
  end

  def self.extend_replace(hash, path)
    # This code assumes that 'path' points to a directory of files.
    # The name of each file is the key into the hash, and the contents
    # of the file are the value to enter, as-is. The order of the
    # files in the directory does not matter.
    Dir.glob(File.join(path, '*')).each do |file|
      key   = File.basename(file)
      value = File.read(file)

      # Write the collected information to the hash. This will
      # overwrite, i.e. replace an existing value for that name. This
      # means that the values found in 'path' have priority over the
      # values already in the 'hash'. This is what we want for
      # '/etc/secrets'
      hash[key.upcase.tr('-', '_')] = value
    end
  end
end
