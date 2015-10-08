require 'optparse'
require 'generate'
require 'exceptions'

# Cli is a helper module for dealing with command line flags
module Cli
  # Check options for any errors
  #
  # @param options [Hash] The options to check
  def self.check_opts(options)
    if !options[:input].nil? && !options[:data].nil?
      fail ArgConflictError, '--input and --data are mutually exclusive arguments'
    end

    if options[:input].nil? && options[:data].nil?
      fail ArgMissingError, 'input or data'
    end

    [:template, :consul, :prefix, :job, :role].each do |key|
      if options[key].nil? || options[key].empty?
        fail ArgMissingError, key.to_s
      end
    end
  end

  # Make an option parser bound to the hash passed in.
  #
  # @param options [Hash]   The hash that the options will be bound to on parse!
  # @return        [Object] The option parser that can be used.
  def self.make_option_parser(options)
    OptionParser.new do |opts|
      opts.banner = 'Usage: configgin [options] <template>'

      opts.on('-d', '--data data', 'Input from command line') do |d|
        options[:data] = d
      end
      opts.on('-i', '--input file', 'Input from file') do |i|
        options[:input] = i
      end
      opts.on('-o', '--output file', 'Output to file') do |o|
        options[:output] = o
      end
      opts.on('-c', '--consul address', 'Address to consul agent') do |c|
        options[:consul] = c
      end
      opts.on('-p', '--prefix name', 'Consul config key prefix') do |p|
        options[:prefix] = p
      end
      opts.on('-j', '--job name', 'Job name') do |j|
        options[:job] = j
      end
      opts.on('-r', '--role name', 'Role name') do |r|
        options[:role] = r
      end
    end
  end
end
