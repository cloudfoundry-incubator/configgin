require 'kato_configurator'

describe KatoConfigurator do
  context "with some blank properties and a KatoConfigurator" do
    properties = {"properties" => {}}
    configurator = KatoConfigurator.new()

    it "it should retrieve node lists as a special case" do
      expect(Kato::Cluster::Manager)
        .to receive(:node_ids_for_process)
        .with('gnatsd')
        .and_return(["127.0.0.1"])

      context = EvaluationContext.new(properties, configurator)
      # Maps to nodes/gnatsd
      expect(context.p("nats.machines")).to eq(["127.0.0.1"])
    end

    it "should append http:// to the cluster/endpoint value as a special case" do
      expect(Kato::Config)
        .to receive(:get)
        .with('cluster', 'endpoint')
        .and_return("127.0.0.1")

      context = EvaluationContext.new(properties, configurator)
      # Maps to cluster/endpoint
      expect(context.p("cc.srv_api_uri")).to eq("http://127.0.0.1")
    end

    it "it should look up values" do
      expect(Kato::Config)
        .to receive(:get)
        .with('cloud_controller_ng', 'uaa/url')
        .and_return("http://fun")

      context = EvaluationContext.new(properties, configurator)
      # Maps to "cloud_controller_ng/uaa/url
      expect(context.p("uaa.url")).to eq("http://fun")
    end
  end
end
