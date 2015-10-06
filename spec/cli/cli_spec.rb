require 'spec_helper'
require 'optparse'
require 'cli'
require 'exceptions'

describe Cli do
  it "should create an option parser" do
    expect(Cli::make_option_parser({})).to be_a(OptionParser)
  end

  it "should check options to make sure they're valid" do
    expect {
      Cli::check_opts({input: "input", data: "data"})
    }.to raise_error(ArgConflictError)
  end

  it "should accept correct arrangements of arguments" do
    expect {
      Cli::check_opts({consul: "consul", data: "data", template: "template"})
    }.not_to raise_error
  end

  it "should fail if template is missing" do
    expect {
      Cli::check_opts({consul: "consul", data: "something"})
    }.to raise_error(ArgMissingError, "template")
  end

  it "should fail if consul is missing" do
    expect {
      Cli::check_opts({data: "something", template: "template"})
    }.to raise_error(ArgMissingError, "consul")
  end

  it "should fail if input AND data is missing" do
    expect {
      Cli::check_opts({template: "template"})
    }.to raise_error(ArgMissingError, "input or data")
  end
end
