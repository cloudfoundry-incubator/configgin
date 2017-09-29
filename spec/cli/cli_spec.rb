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
      { jobs: '/tmp/in.file', env2conf: '/tmp/templates.tml' }
    }

    it 'should accept correct arrangements of arguments' do
      expect {
        Cli.check_opts(config)
      }.not_to raise_error
    end

    it 'should fail if jobs is missing' do
      config.delete(:jobs)
      expect {
        Cli.check_opts(config)
      }.to raise_error(ArgMissingError, 'jobs')
    end

    it 'should fail if templates is missing' do
      config.delete(:env2conf)
      expect {
        Cli.check_opts(config)
      }.to raise_error(ArgMissingError, 'env2conf')
    end

    it 'should exit when checking version' do
      opts = {}
      expect(Cli).to receive(:puts).with(Configgin::VERSION)
      expect {
        Cli.make_option_parser(opts).parse!(%w[--version --jobs /dev/null])
      }.to raise_error(SystemExit)
      expect(opts).to be_empty
    end
  end
end
