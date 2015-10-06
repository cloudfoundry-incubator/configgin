require 'optparse'
require 'generate'
require 'exceptions'

module Cli
  # Check options for any errors
  #
  # @param options [Hash] The options to check
  def self.check_opts(options)
    if !options[:input].nil? && !options[:context].nil?
      raise ArgConflictError, '--input and --context are mutually exclusive arguments'
    end

    if options[:template].nil? || options[:template].empty?
      raise ArgMissingError, 'template'
    end

    if options[:consul].nil? || options[:consul].empty?
      raise ArgMissingError, 'consul'
    end
  end

  # Make an option parser bound to the hash passed in.
  # 
  # @param options [Hash] The hash that the options will be bound to on parse!
  def self.make_option_parser(options)
    return OptionParser.new do |opts|
      opts.banner = "Usage: config-gen [options] <template>"

      opts.on("-d", "--data data", "Input from command line") { |d|
        options[:data] = d
      }
      opts.on("-i", "--input file", "Input from file") { |i|
        options[:input] = i
      }
      opts.on("-o", "--output file", "Output to file") { |o|
        options[:output] = o
      }
      opts.on("-c", "--consul", "Address to consul agent") { |c|
        options[:consul] = c
      }
    end
  end
end
