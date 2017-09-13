require 'kubeclient'
require 'uri'
require_relative 'exceptions'

# KubeLinkSpecs provides the information required to generate BOSH links by
# pretending to be a hash.
class KubeLinkSpecs
  # ANNOTATION_AZ is the Kube annotation for the (availability) zone
  ANNOTATION_AZ = 'failure-domain.beta.kubernetes.io/zone'.freeze

  def initialize(spec, namespace, kube_client)
    @links = {}
    @client = kube_client
    @namespace = namespace
    @spec = spec || {}
  end

  def this_name()
    @spec['job']['name']
  end

  def pod_index(name)
    index = name.rpartition('-').last
    return index.to_i if /^\d+$/ =~ index
    chars = 'bcdfghjklmnpqrstvwxz0123456789'
    index.chars.map { |c| chars.index(c) }.reduce(0) { |v, c| v * chars.length + c }
  end

  def [](key)
    return @links[key] if @links.key? key

    # Resolve the role we're looking for
    provider = @spec['consumes'][key]
    unless provider
      puts "No link provider found for #{key}"
      @links[key] = nil
      return @links[key]
    end

    @links[key] = {
      'address' => "#{key}.#{ENV['KUBE_SERVICE_DOMAIN_SUFFIX']}",
      'properties' => {},
      'instance_group' => '',
      'default_network' => '',
      'deployment_name' => @namespace,
      'domain' => ENV['KUBE_SERVICE_DOMAIN_SUFFIX'],
      'root_domain' => ENV['KUBE_SERVICE_DOMAIN_SUFFIX']
    }
    if provider['role'] == this_name
      STDERR.puts "Resolving link #{key} via self provider #{provider}"
      pods = loop do
        pods = @client.get_pods(namespace: @namespace, label_selector: "skiff-role-name=#{this_name}")
        # Wait until we have at least one pod (the one this is running on), and they all have IP addresses
        break pods unless pods.empty? || !pods.select { |pod| pod.status.podIP.nil? }.empty?
        sleep 1
      end
      @links[key]['instances'] = pods.map do |pod|
        unless pod.metadata.annotations['skiff-exported-properties']
          until pod.metadata.annotations['skiff-exported-properties']
            sleep 1
            pod = @client.get_pod(pod.metadata.name, @namespace)
          end
        end
        index = pod_index(pod.metadata.name)
        properties = JSON.parse(pod.metadata.annotations['skiff-exported-properties'] || '{}')
        {
          'name' => pod.metadata.name,
          'index' => index,
          'id' => pod.metadata.name,
          'az' => pod.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
          'address' => pod.status.podIP,
          'properties' => properties.fetch(provider['job'], {}),
          'bootstrap' => index.zero?
        }
      end
    else
      STDERR.puts "Resolving link #{key} via service #{provider}"
      # Getting pods for a different service; since we have kube services, we don't handle it in configgin
      svc = @client.get_service(provider['role'], @namespace)
      pods = loop do
        pods = @client.get_pods(namespace: @namespace, label_selector: "skiff-role-name=#{provider['role']}")
        pods.reject! { |pod| pod.status.podIP.nil? }
        pods.select! { |pod| pods.first.metadata.annotations['skiff-exported-properties'] }
        break pods unless pods.empty?
        sleep 1
      end
      properties = JSON.parse(pods.first.metadata.annotations['skiff-exported-properties'] || '{}')
      @links[key]['instances'] = [
        'name' => svc.metadata.name,
        'index' => 0,
        'id' => svc.metadata.name,
        'az' => pods.first.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
        'address' => svc.spec.clusterIP,
        'properties' => properties.fetch(provider['job'], {}),
        'bootstrap' => true
      ]
    end
    @links[key]['properties'] = @links[key]['instances'].first['properties']
    @links[key]
  end
end

# KubeDNSEncoder is a BOSH DNS encoder object. It is unclear at this point what it does.
class KubeDNSEncoder
  def initialize(link_specs)
    @link_specs = link_specs
  end
end
