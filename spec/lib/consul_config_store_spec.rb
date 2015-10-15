require 'spec_helper'
require 'consul_config_store'

describe ConsulConfigStore do
  context 'with a config_store' do
    before do
      expect(Diplomat).to receive(:configure)

      @address = 'address'
      @prefix = 'prefix'
      @job = 'cloud_controller_ng'
      @role = 'cc_role'
      @config_store = ConsulConfigStore.new(@address, @prefix, @job, @role)
    end

    it 'should ignore hashes that have no key found' do
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/spec/cloud_controller_ng/', { recurse: true })
        .and_return([
          { key: 'prefix/spec/cloud_controller_ng/cc/k1', value: '1' },
          { key: 'prefix/spec/cloud_controller_ng/cc/k2', value: '1' },
          { key: 'prefix/spec/cloud_controller_ng/cc/k3', value: '1' },
          { key: 'prefix/spec/cloud_controller_ng/cc/k4', value: '1' },
         ])
        .ordered
      expect(Diplomat::Kv).to receive(:get)
        .and_raise(Diplomat::KeyNotFound)
        .ordered
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/user/', { recurse: true })
        .and_raise(Diplomat::KeyNotFound)
        .ordered
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/role/cc_role/', { recurse: true })
        .and_raise(Diplomat::KeyNotFound)
        .ordered

      hash = @config_store.build

      expect(hash['cc']['k1']).to eq(1)
      expect(hash['cc']['k2']).to eq(1)
      expect(hash['cc']['k3']).to eq(1)
      expect(hash['cc']['k4']).to eq(1)
    end

    it 'should create an overridden set of hashes, getting the final value correct' do
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/spec/cloud_controller_ng/', { recurse: true })
        .and_return([
          { key: 'prefix/spec/cloud_controller_ng/cc/k1', value: '1' },
          { key: 'prefix/spec/cloud_controller_ng/cc/k2', value: '1' },
          { key: 'prefix/spec/cloud_controller_ng/cc/k3', value: '1' },
          { key: 'prefix/spec/cloud_controller_ng/cc/k4', value: '1' },
         ])
        .ordered
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/opinions/', { recurse: true })
        .and_return([
          { key: 'prefix/opinions/cc/k1', value: '2' },
          { key: 'prefix/opinions/cc/k2', value: '2' },
          { key: 'prefix/opinions/cc/k3', value: '2' },
        ])
        .ordered
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/user/', { recurse: true })
        .and_return([
          { key: 'prefix/user/cc/k1', value: '3' },
          { key: 'prefix/user/cc/k2', value: '3' },
        ])
        .ordered
      expect(Diplomat::Kv).to receive(:get)
        .with('/prefix/role/cc_role/', { recurse: true })
        .and_return([
          { key: 'prefix/role/cc_role/cc/k1', value: '4' },
        ])
        .ordered

      hash = @config_store.build

      expect(hash['cc']['k1']).to eq(4)
      expect(hash['cc']['k2']).to eq(3)
      expect(hash['cc']['k3']).to eq(2)
      expect(hash['cc']['k4']).to eq(1)
    end

    it 'should fetch collections of hashes' do
      prefix = '/hcf/spec/cloud_controller_ng'
      expect(Diplomat::Kv).to receive(:get)
        .with(prefix, { recurse: true })
        .and_return([
          { key: 'my/key/name', value: 'value' },
          { key: 'my/key/name2', value: 'value2' },
         ])

      hash = @config_store.config_for_prefix(prefix)

      expect(hash).to be_a(Hash)
      expect(hash['my/key/name']).to eq("value")
    end

    it 'should yaml decode when fetching' do
      prefix = '/hcf/spec/cloud_controller_ng'
      expect(Diplomat::Kv).to receive(:get)
        .with(prefix, { recurse: true })
        .and_return([
          { key: 'my/key/name', value: '5' },
         ])

      hash = @config_store.config_for_prefix(prefix)

      expect(hash).to be_a(Hash)
      expect(hash['my/key/name']).to be_a(Integer)
      expect(hash['my/key/name']).to eq(5)
    end
  end

  it 'should recursively expand a hash' do
    hash = ConsulConfigStore.recursively_expand_hash({
      'my/key/name' => 'value',
      'my/key2' => 'value2',
    })

    expect(hash).to be_a(Hash)
    expect(hash['my']).to be_a(Hash)
    expect(hash['my']['key']).to be_a(Hash)
    expect(hash['my']['key']['name']).to eq('value')

    expect(hash['my']).to be_a(Hash)
    expect(hash['my']['key2']).to eq('value2')
  end

  it 'should recursively expand a hash' do
    hash = ConsulConfigStore.recursively_expand_hash({
      'my/key/name' => 'value',
      'my/key2' => 'value2',
    })

    expect(hash).to be_a(Hash)
    expect(hash['my']).to be_a(Hash)
    expect(hash['my']['key']).to be_a(Hash)
    expect(hash['my']['key']['name']).to eq('value')

    expect(hash['my']).to be_a(Hash)
    expect(hash['my']['key2']).to eq('value2')
  end

  it 'hash expansion should have a nice error when nil objects have sub-keys' do
  end

  it 'it should overwrite values with hashes if they have keys under them' do
    weird_data = { 'my/key' => 10, 'my/key/name' => 5 }

    hash = ConsulConfigStore.recursively_expand_hash(weird_data)
    expect(hash['my']).to be_a(Hash)
    expect(hash['my']['key']).to be_a(Hash)
    expect(hash['my']['key']['name']).to eq(5)
  end

  it 'it should not ruin data that exists if keys are not in order' do
    weird_data = { 'my/key/name' => 5, 'my/key' => 10 }

    hash = ConsulConfigStore.recursively_expand_hash(weird_data)
    expect(hash['my']).to be_a(Hash)
    expect(hash['my']['key']).to be_a(Hash)
    expect(hash['my']['key']['name']).to eq(5)
  end
end
