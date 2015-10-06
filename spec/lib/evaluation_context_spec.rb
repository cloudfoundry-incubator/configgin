require 'spec_helper'
require 'evaluation_context'

describe EvaluationContext do
  it "should look up values that exist in context first without kato or mappings" do
    properties = {'properties' => {'fake' => {'mapping' => 5}}}
    context = EvaluationContext.new(properties, nil)
    prop = context.p('fake.mapping')
    expect(prop).to eq(5)
  end

  context "with a fake mappings.yml file" do
    before do
      expect(YAML).to receive(:load_file).and_return({
        EvaluationContext::SECTION_STATIC_VALUES => {'fake.static' => 'fake'},
        EvaluationContext::SECTION_MAPPINGS => {'fake.mapping' => 'kato/fake'}
      })
    end

    it "should look up default mapped values" do
      properties = {"properties" => {}}
      context = EvaluationContext.new(properties, nil)
      prop = nil
      expect {
        prop = context.p('fake.static')
      }.not_to raise_error

      expect(prop).to eq('fake')
    end

    it "should look up values from kato" do
      configurator = KatoConfigurator.new()
      expect(configurator).to receive(:get).with('kato', 'fake').and_return('something')

      properties = {'properties' => {}}
      context = EvaluationContext.new(properties, configurator)
      prop = nil
      expect {
        prop = context.p('fake.mapping')
      }.not_to raise_error

      expect(prop).to eq('something')
    end
  end

  it "should fail with MappingConflictError when a key is in both static_values and mappings" do
    evcontext = EvaluationContext.new({'properties' => {}}, nil)
    expect(YAML).to receive(:load_file).and_return({
      EvaluationContext::SECTION_STATIC_VALUES => {"cc.bulk_api_user" => 5},
      EvaluationContext::SECTION_MAPPINGS => {"cc.bulk_api_user" => 5}
    })

    expect {
      evcontext.p("cc.bulk_api_user")
    }.to raise_error(MappingConflictError, "cc.bulk_api_user in both static_values and mappings in config")
  end
end
