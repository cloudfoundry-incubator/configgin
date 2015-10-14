require 'spec_helper'
require 'evaluation_context'

describe EvaluationContext do
  it 'should look up values that exist in data first without consul' do
    properties = { 'properties' => { 'fake' => { 'value' => 5 } } }
    context = EvaluationContext.new(properties, nil)
    prop = context.p('fake.value')
    expect(prop).to eq(5)
  end

  it 'should look up values in config_store when it can\'t find it in data' do
    properties = { 'properties' => { 'fake' => { 'value' => 5 } } }
    config_store = double('config_store')
    expect_value = 5
    expect(config_store).to receive(:get)
      .with('fake.othervalue')
      .and_return(expect_value)

    context = EvaluationContext.new(properties, config_store)
    prop = context.p('fake.othervalue')
    expect(prop).to eq(expect_value)
  end

  it 'should look up values that exist in properties' do
    properties = { 'properties' => { 'fake' => { 'value' => 5 } } }
    context = EvaluationContext.new(properties, nil)
    prop = context.properties.fake.value
    expect(prop).to eq(5)
  end

  it 'should look up values in consul that don''t exist in properties' do
    properties = { 'properties' => { 'fake' => { 'value' => 5 } } }
    config_store = double('config_store')
    expect_value = 5

    keys = %w(cc configuration)
    keys.inject('') do |key, next_key|
      next_key = key.length == 0 ? next_key : "#{key}.#{next_key}"
      expect(config_store).to receive(:get)
        .with(next_key)
        .and_return(nil)
        .ordered
      next_key
    end

    expect(config_store).to receive(:get)
      .with('cc.configuration.port')
      .and_return(expect_value)
      .ordered

    context = EvaluationContext.new(properties, config_store)
    prop = context.properties.cc.configuration.port
    expect(prop).to eq(expect_value)
  end

  it 'should look up values in consul that half exist in properties' do
    old_value = 20
    expect_value = 5
    properties = { 'properties' => { 'cc' => { 'port' => old_value } } }
    config_store = double('config_store')

    expect(config_store).to receive(:get)
      .with('cc.configuration')
      .and_return(nil)
      .ordered
    expect(config_store).to receive(:get)
      .with('cc.configuration.port')
      .and_return(expect_value)
      .ordered

    context = EvaluationContext.new(properties, config_store)

    prop = context.properties.cc.configuration.port
    expect(prop).to eq(expect_value)

    prop = context.properties.cc.port
    expect(prop).to eq(old_value)
  end
end
