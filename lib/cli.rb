require 'optparse'
require 'generate'
require 'exceptions'

module Cli
  # Check options for any errors
  #
  # @param options [Hash] The options to check
  def self.check_opts(options)
    if !options[:input].nil? && !options[:data].nil?
      raise ArgConflictError, '--input and --data are mutually exclusive arguments'
    end

    if options[:input].nil? && options[:data].nil?
      raise ArgMissingError, 'input or data'
    end

    [:template, :consul, :job, :role].each { |key|
      if options[key].nil? || options[key].empty?
        raise ArgMissingError, key.to_s
      end
    }
  end

  # Make an option parser bound to the hash passed in.
  # 
  # @param options [Hash] The hash that the options will be bound to on parse!
  def self.make_option_parser(options)
    return OptionParser.new do |opts|
      opts.banner = "Usage: configgin [options] <template>"

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
      opts.on("-p", "--prefix", "Consul config key prefix") { |p|
        options[:prefix] = p
      }
      opts.on('-j', '--job', 'Job name') { |j|
        options[:job] = j
      }
      opts.on('-r', '--role', 'Role name') { |r|
        options[:role] = r
      }
    end
  end
end
