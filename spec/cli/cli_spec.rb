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
      Cli::check_opts({input: "something", data: "something"})
    }.to raise_error(ArgConflictError)
  end

  it "should let good options through" do
    expect {
      Cli::check_opts({data: "something", template: "something"})
    }.not_to raise_error
  end

  it "should fail if template is missing" do
    expect {
      Cli::check_opts({data: "something"})
    }.to raise_error(ArgMissingError, "template")
  end

  it "should fail if template is missing" do
    expect {
      Cli::check_opts({data: "something"})
    }.to raise_error(ArgMissingError, "template")
  end
end
