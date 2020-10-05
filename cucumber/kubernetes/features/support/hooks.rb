Before('@skip') do
  skip_this_scenario
end

Before('@k8s_skip') do
  skip_this_scenario if ENV['PLATFORM'] == 'kubernetes'
end

Before do
  # Erase the certificates and keys from each container.
  kube_client.get_pods(namespace: namespace).select{|p| p.metadata.namespace == namespace}.each do |pod|
    next unless (ready_status = pod.status.conditions.find { |c| c.type == "Ready" })
    next unless ready_status.status == "True"
    next unless pod.metadata.name =~ /inventory\-/

    pod.spec.containers.each do |container|
      next unless container.name == "authenticator"

      Authentication::AuthnK8s::ExecuteCommandInContainer.new.call(
        k8s_object_lookup: Authentication::AuthnK8s::K8sObjectLookup.new,
        pod_namespace: pod.metadata.namespace,
        pod_name: pod.metadata.name,
        container: container.name,
        cmds: %w(rm -rf /etc/conjur/ssl/*),
        body: "",
        stdin: false
      )
    end
  end
end

After('@ssl_dir_perm') do
  # TODO: get this dynamically?
  object_id = "app=inventory-pod"
  container_name = "authenticator"

  puts "setting ssl dir pem 1"
  find_matching_pod(object_id)

  @pod.spec.containers.each do |container|
    next unless container.name == container_name

    puts "setting ssl dir pem 2"

    Authentication::AuthnK8s::ExecuteCommandInContainer.new.call(
      k8s_object_lookup: Authentication::AuthnK8s::K8sObjectLookup.new,
      pod_namespace: @pod.metadata.namespace,
      pod_name: @pod.metadata.name,
      container: container_name,
      cmds: %w(chmod 777 /etc/conjur/ssl),
      body: "",
      stdin: false
    )

    puts "setting ssl dir pem 3"

  end
end

