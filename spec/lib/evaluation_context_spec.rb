require 'spec_helper'
require 'evaluation_context'
require 'diplomat'

describe EvaluationContext do
  it "should override the parameters it's given" do
    config_store = double('ConsulConfigStore')
    expect(config_store).to receive(:build).and_return(
      'cc' => { 'addr' => 'hello', 'ovwr' => 'hello' }
    )

    data = { 'properties' => { 'cc' => { 'port' => 5, 'ovwr' => 5 } } }
    ec = EvaluationContext.new(data, config_store)

    expect(ec.properties.cc.port).to eq(5)
    expect(ec.p('cc.port')).to eq(5)

    expect(ec.properties.cc.addr).to eq('hello')
    expect(ec.p('cc.addr')).to eq('hello')

    expect(ec.properties.cc.ovwr).to eq(5)
    expect(ec.p('cc.ovwr')).to eq(5)
  end
end
