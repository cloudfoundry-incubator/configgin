require 'spec_helper'
require 'consul_config_store'

describe ConsulConfigStore do
  before do
    expect(Diplomat).to receive(:configure)

    @address = 'address'
    @prefix = 'prefix'
    @job = 'cloud_controller_ng'
    @role = 'cc_role'
    @config_store = ConsulConfigStore.new(@address, @prefix, @job, @role)
  end

  it "should get values from consul" do
    expect(Diplomat::Kv).to receive(:get).with('/prefix/role/cc_role/cc/port')

    @config_store.get('cc.port')
  end

  it "should use fallbacks to find the correct defaults" do
    expect(Diplomat::Kv).to receive(:get)
      .with('/prefix/role/cc_role/cc/port')
      .and_raise(Diplomat::KeyNotFound)
      .ordered
    expect(Diplomat::Kv).to receive(:get)
      .with('/prefix/user/cc/port')
      .and_raise(Diplomat::KeyNotFound)
      .ordered
    expect(Diplomat::Kv).to receive(:get)
      .with('/prefix/opinions/cc/port')
      .and_raise(Diplomat::KeyNotFound)
      .ordered
    expect(Diplomat::Kv).to receive(:get)
      .with('/prefix/spec/cloud_controller_ng/cc/port')
      .and_raise(Diplomat::KeyNotFound)
      .ordered

    expect(@config_store.get('cc.port')).to be_nil
  end
end
