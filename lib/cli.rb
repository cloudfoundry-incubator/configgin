require 'optparse'
require 'generate'
require 'exceptions'

# Cli is a helper module for dealing with command line flags
module Cli
  # Check options for any errors
  #
  # @param options [Hash] The options to check
  def self.check_opts(options)
    [:input, :output, :base, :env2conf].each do |key|
      if options[key].nil? || options[key].empty?
        raise ArgMissingError, key.to_s
      end
    end
  end

  # Make an option parser bound to the hash passed in.
  #
  # @param options [Hash]   The hash that the options will be bound to on parse!
  # @return        [Object] The option parser that can be used.
  def self.make_option_parser(options)
    OptionParser.new do |opts|
      opts.banner = 'Usage: configgin [options]'

      # Input template file
      opts.on('-i', '--input-erb file', 'Input erb template') do |i|
        options[:input] = i
      end

      # Output file
      opts.on('-o', '--output file', 'Output to file') do |o|
        options[:output] = o
      end

      # Base config JSON file
      opts.on('-b', '--base file', 'Base configuration JSON') do |b|
        options[:base] = b
      end

      # Environment to configuration templates file
      opts.on('-e', '--env2conf file', 'Environment to configuration templates YAML') do |e|
        options[:env2conf] = e
      end
    end
  end
end
