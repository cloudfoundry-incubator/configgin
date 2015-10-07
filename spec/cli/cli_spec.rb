require 'spec_helper'
require 'optparse'
require 'cli'
require 'exceptions'

describe Cli do
  it "should create an option parser" do
    expect(Cli::make_option_parser({})).to be_an(OptionParser)
  end

  it "it should prevent input and data from both being specified" do
    expect {
      Cli::check_opts({input: "input", data: "data"})
    }.to raise_error(ArgConflictError)
  end

  context "with a full config" do
    let(:config) {
      {consul: "consul", data: "data", template: "template", job: "job", role: "role", prefix: "prefix"}
    }

    it "should accept correct arrangements of arguments" do
      expect {
        Cli::check_opts(config)
      }.not_to raise_error
    end

    it "should fail if input AND data is missing" do
      config.delete(:input)
      config.delete(:data)
      expect {
        Cli::check_opts(config)
      }.to raise_error(ArgMissingError, "input or data")
    end

    it "should fail if template is missing" do
      config.delete(:template)
      expect {
        Cli::check_opts(config)
      }.to raise_error(ArgMissingError, "template")
    end

    it "should fail if consul is missing" do
      config.delete(:consul)
      expect {
        Cli::check_opts(config)
      }.to raise_error(ArgMissingError, 'consul')
    end

    it "should fail if job is prefix" do
      config.delete(:prefix)
      expect {
        Cli::check_opts(config)
      }.to raise_error(ArgMissingError, 'prefix')
    end

    it "should fail if job is missing" do
      config.delete(:job)
      expect {
        Cli::check_opts(config)
      }.to raise_error(ArgMissingError, 'job')
    end

    it "should fail if role is missing" do
      config.delete(:role)
      expect {
        Cli::check_opts(config)
      }.to raise_error(ArgMissingError, 'role')
    end
  end
end
