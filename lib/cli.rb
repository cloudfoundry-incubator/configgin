require 'optparse'
require 'exceptions'

# Cli is a helper module for dealing with command line flags
module Cli
  # Check options for any errors
  #
  # @param options [Hash] The options to check
  def self.check_opts(options)
    [:jobs, :env2conf].each do |key|
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

      # Job definition file
      opts.on('-j', '--jobs file', 'Job definitions') do |j|
        options[:jobs] = j
      end

      # Environment to configuration templates file
      opts.on('-e', '--env2conf file',
              'Environment to configuration templates YAML') do |e|
        options[:env2conf] = e
      end
    end
  end
end
