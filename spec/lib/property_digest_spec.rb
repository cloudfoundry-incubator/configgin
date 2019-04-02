require 'spec_helper'
require 'property_digest'

describe :property_digest do
  def compare_digest(object, json)
    expect(property_digest(object)).to eq "sha1:#{Digest::SHA1.hexdigest(json)}"
  end
  it 'should digest a number' do
    compare_digest 1, '1'
  end
  it 'should digest a string' do
    compare_digest 'foo', '"foo"'
  end
  it 'should digest an array' do
    compare_digest %w[foo bar], '["foo","bar"]'
  end
  it 'should digest a hash' do
    compare_digest ({ a: 1, b: 2 }), '{"a":1,"b":2}'
  end
  it 'should sort a hash before digesting' do
    compare_digest ({ b: 1, a: 2 }), '{"a":2,"b":1}'
  end
  it 'should sort hashes nested in arrays' do
    compare_digest [b: 1, a: 2], '[{"a":2,"b":1}]'
  end
  it 'should sort hashes nested in hashes' do
    compare_digest ({ c: { b: 1, a: 2 } }), '{"c":{"a":2,"b":1}}'
  end
end
