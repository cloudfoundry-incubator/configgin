require 'spec_helper'
require 'optparse'
require 'cli'
require 'exceptions'

describe Cli do
  it 'should create an option parser' do
    expect(Cli.make_option_parser({})).to be_an(OptionParser)
  end

  context 'with a full config' do
    let(:config) {
      { input: '/tmp/in.file', output: '/tmp/out.file',
        base: '/tmp/base.json', templates: '/tmp/templates.tml' }
    }

    it 'should accept correct arrangements of arguments' do
      expect {
        Cli.check_opts(config)
      }.not_to raise_error
    end

    it 'should fail if input is missing' do
      config.delete(:input)
      expect {
        Cli.check_opts(config)
      }.to raise_error(ArgMissingError, 'input')
    end

    it 'should fail if output is missing' do
      config.delete(:output)
      expect {
        Cli.check_opts(config)
      }.to raise_error(ArgMissingError, 'output')
    end

    it 'should fail if base is missing' do
      config.delete(:base)
      expect {
        Cli.check_opts(config)
      }.to raise_error(ArgMissingError, 'base')
    end

    it 'should fail if templates is missing' do
      config.delete(:templates)
      expect {
        Cli.check_opts(config)
      }.to raise_error(ArgMissingError, 'templates')
    end
  end
end
