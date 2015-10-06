require 'spec_helper'
require 'evaluation_context'

describe EvaluationContext do
  it "should look up values that exist in data first without consul" do
    properties = {'properties' => {'fake' => {'value' => 5}}}
    context = EvaluationContext.new(properties, nil)
    prop = context.p('fake.value')
    expect(prop).to eq(5)
  end

  it "should look up values in config_store when it can't find it in data" do
    properties = {'properties' => {'fake' => {'value' => 5}}}
    config_store = double("config_store")
    expect_value = 5
    expect(config_store).to receive(:get)
      .with('fake', 'othervalue')
      .and_return(expect_value)

    context = EvaluationContext.new(properties, config_store)
    prop = context.p('fake.othervalue')
    expect(prop).to eq(expect_value)
  end
end
