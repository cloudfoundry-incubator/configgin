require 'kubeclient'
require 'uri'
require_relative 'exceptions'

# KubeLinkSpecs provides the information required to generate BOSH links by
# pretending to be a hash.
class KubeLinkSpecs
  # ANNOTATION_AZ is the Kube annotation for the (availability) zone
  ANNOTATION_AZ = 'failure-domain.beta.kubernetes.io/zone'.freeze

  def initialize(spec, namespace, kube_client, kube_client_stateful_set)
    @links = {}
    @client = kube_client
    @client_stateful_set = kube_client_stateful_set
    @namespace = namespace
    @spec = spec || {}
  end

  def this_name
    @spec['job']['name']
  end

  # pod_index returns a number for the given pod name. The number is expected to
  # be unique across all pods for the role.
  def pod_index(name)
    index = name.rpartition('-').last
    return index.to_i if /^\d+$/ =~ index
    # The pod name is something like role-abcxyz
    # Derive the index from the randomness that went into the suffix.
    # chars are the characters kubernetes might use to generate names
    # Copied from https://github.com/kubernetes/kubernetes/blob/52a6ad0acb26/staging/src/k8s.io/client-go/pkg/util/rand/rand.go#L73
    chars = 'bcdfghjklmnpqrstvwxz0123456789'
    index.chars.map { |c| chars.index(c) }.reduce(0) { |v, c| v * chars.length + c }
  end

  def _get_pods_for_role(role_name)
    @client.get_pods(namespace: @namespace, label_selector: "skiff-role-name=#{role_name}")
  end

  def get_pods_for_role(role_name, wait_for_ip, job)
    loop do
      # The 30.times loop exists to print out status messages
      30.times do
        1.times do
          pods = _get_pods_for_role(role_name)
          if wait_for_ip
            # Wait until all pods have IP addresses and properties
            break unless pods.all? { |pod| pod.status.podIP }
            break unless pods.all? { |pod| pod.metadata.annotations["skiff-exported-properties-#{job}"] }
          else
            # We just need one pod with exported properties
            pods.select! { |pod| pod.status.podIP }
            pods.select! { |pod| pod.metadata.annotations["skiff-exported-properties-#{job}"] }
          end
          return pods unless pods.empty?
        end
        sleep 1
      end
      $stdout.puts "Waiting for pods for role #{role_name} and provider job #{job} (at #{Time.now})..."
    end
  end

  def get_exported_properties(pod, job)
    exported_properties = pod.metadata.annotations["skiff-exported-properties-#{job}"]
    exported_properties.nil? ? {} : JSON.parse(exported_properties)
  end

  def get_pod_instance_info(pod, job, pods_per_image)
    index = pod_index(pod.metadata.name)
    {
      'name' => pod.metadata.name,
      'index' => index,
      'id' => pod.metadata.name,
      'az' => pod.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
      'address' => pod.status.podIP,
      'properties' => get_exported_properties(pod, job),
      'bootstrap' => pods_per_image[pod.metadata.uid] < 2
    }
  end

  # Return the number of pods for each image
  def get_pods_per_image(pods)
    result = {}
    sets = Hash.new(0)
    keys = {}
    pods.each do |pod|
      key = pod.status.containerStatuses.map(&:imageID).sort.join("\n")
      sets[key] += 1
      keys[pod.metadata.uid] = key
    end
    pods.each do |pod|
      result[pod.metadata.uid] = sets[keys[pod.metadata.uid]]
    end
    result
  end

  def get_svc_instance_info(role_name, job)
    svc = @client.get_service(role_name, @namespace)
    pod = get_pods_for_role(role_name, false, job).first
    {
      'name' => svc.metadata.name,
      'index' => 0, # Completely made up index; there is only ever one service
      'id' => svc.metadata.name,
      'az' => pod.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
      'address' => svc.spec.clusterIP,
      'properties' => get_exported_properties(pod, job),
      'bootstrap' => true
    }
  end

  def get_statefulset_instance_info(role_name, job)
    ss = @client_stateful_set.get_stateful_set(role_name, @namespace)
    pod = get_pods_for_role(role_name, false, job).first

    Array.new(ss.spec.replicas) do |i|
      {
        'name' => ss.metadata.name,
        'index' => i,
        'id' => ss.metadata.name,
        'az' => pod.metadata.annotations['failure-domain.beta.kubernetes.io/zone'] || 'az0',
        'address' => "#{ss.metadata.name}-#{i}.#{ss.spec.serviceName}",
        'properties' => get_exported_properties(pod, job),
        'bootstrap' => i.zero?
      }
    end
  end

  def service?(role_name)
    @client.get_service(role_name, @namespace)
    true
  rescue KubeException
    false
  end

  def [](key)
    return @links[key] if @links.key? key

    # Resolve the role we're looking for
    provider = @spec['consumes'][key]
    unless provider
      $stderr.puts "No link provider found for #{key}"
      return @links[key] = nil
    end

    if provider['role'] == this_name
      $stderr.puts "Resolving link #{key} via self provider #{provider}"
      pods = get_pods_for_role(provider['role'], true, provider['job'])
      pods_per_image = get_pods_per_image(pods)
      instances = pods.map { |p| get_pod_instance_info(p, provider['job'], pods_per_image) }
    elsif service? provider['role']
      # Getting pods for a different service; since we have kube services, we don't handle it in configgin
      $stderr.puts "Resolving link #{key} via service #{provider}"
      instances = [get_svc_instance_info(provider['role'], provider['job'])]
    else
      # If there's no service associated, check the statefulset instead
      $stderr.puts "Resolving link #{key} via statefulset #{provider}"
      instances = get_statefulset_instance_info(provider['role'], provider['job'])
    end

    @links[key] = {
      'address' => "#{provider['role']}.#{ENV['KUBERNETES_NAMESPACE']}.svc.#{ENV['KUBERNETES_CLUSTER_DOMAIN']}",
      'instance_group' => '',
      'default_network' => '',
      'deployment_name' => @namespace,
      'domain' => "#{ENV['KUBERNETES_NAMESPACE']}.svc.#{ENV['KUBERNETES_CLUSTER_DOMAIN']}",
      'root_domain' => "#{ENV['KUBERNETES_NAMESPACE']}.svc.#{ENV['KUBERNETES_CLUSTER_DOMAIN']}",
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
