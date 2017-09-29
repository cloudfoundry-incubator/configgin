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

  def this_name
    @spec['job']['name']
  end

  def pod_index(name)
    index = name.rpartition('-').last
    return index.to_i if /^\d+$/ =~ index
    chars = 'bcdfghjklmnpqrstvwxz0123456789'
    index.chars.map { |c| chars.index(c) }.reduce(0) { |v, c| v * chars.length + c }
  end

  def get_pods_for_role(role_name, wait_for_ip)
    loop do
      sleep 1
      pods = @client.get_pods(namespace: @namespace, label_selector: "skiff-role-name=#{role_name}")
      if wait_for_ip
        # Wait until all pods have IP addresses and properties
        next unless pods.all? { |pod| pod.status.podIP }
        next unless pods.all? { |pod| pod.metadata.annotations['skiff-exported-properties'] }
      else
        # We just need one pod with exported properties
        pods.select! { |pod| pod.status.podIP }
        pods.select! { |pod| pod.metadata.annotations['skiff-exported-properties'] }
      end
      return pods unless pods.empty?
    end
  end

  def get_pod_instance_info(pod, job)
    index = pod_index(pod.metadata.name)
    properties = JSON.parse(pod.metadata.annotations['skiff-exported-properties'])
    {
      'name' => pod.metadata.name,
      'index' => index,
      'id' => pod.metadata.name,
      'az' => pod.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
      'address' => pod.status.podIP,
      'properties' => properties.fetch(job, {}),
      'bootstrap' => index.zero?
    }
  end

  def get_svc_instance_info(role_name, job)
    svc = @client.get_service(role_name, @namespace)
    pod = get_pods_for_role(role_name, false).first
    properties = JSON.parse(pod.metadata.annotations['skiff-exported-properties'])
    {
      'name' => svc.metadata.name,
      'index' => 0,
      'id' => svc.metadata.name,
      'az' => pod.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
      'address' => svc.spec.clusterIP,
      'properties' => properties.fetch(job, {}),
      'bootstrap' => true
    }
  end

  def [](key)
    return @links[key] if @links.key? key

    # Resolve the role we're looking for
    provider = @spec['consumes'][key]
    unless provider
      STDERR.puts "No link provider found for #{key}"
      @links[key] = nil
      return @links[key]
    end

    if provider['role'] == this_name
      STDERR.puts "Resolving link #{key} via self provider #{provider}"
      instances = get_pods_for_role(provider['role'], true).map {|p| get_pod_instance_info(p, provider['job'])}
    else
      # Getting pods for a different service; since we have kube services, we don't handle it in configgin
      STDERR.puts "Resolving link #{key} via service #{provider}"
      instances = [get_svc_instance_info(provider['role'], provider['job'])]
    end

    @links[key] = {
      'address' => "#{key}.#{ENV['KUBE_SERVICE_DOMAIN_SUFFIX']}",
      'instance_group' => '',
      'default_network' => '',
      'deployment_name' => @namespace,
      'domain' => ENV['KUBE_SERVICE_DOMAIN_SUFFIX'],
      'root_domain' => ENV['KUBE_SERVICE_DOMAIN_SUFFIX'],
      'instances' => instances,
      'properties' => instances.first['properties']
    }
  end
end

# KubeDNSEncoder is a BOSH DNS encoder object. It is unclear at this point what it does.
class KubeDNSEncoder
  def initialize(link_specs)
    @link_specs = link_specs
  end
end
