# frozen_string_literal: true

module Loader
  module Handlers
    # extends the policy loader to provision variable secret values. This occurs
    # after the initial policy load, when the database resources exist.
    module Provision

      # handing_provisioning records each of the resources found that include
      # the `provision/provisioner` annotation so that we can provision secret
      # values after the database resources have been created
      def handle_provisioning id
        pending_provisions << id
      end

      def provision_values
        pending_provisions.each do |id|
          resource = Resource[id]
          
          provisioner = resource.annotation('provision/provisioner')
          parameter = resource.annotation('provision/context/parameter')
          value = @context[parameter.to_sym]

          Secret.create resource_id: id, value: value
          resource.enforce_secrets_version_limit
        end
      end
  
      def pending_provisions
        @pending_provisions ||= []
      end
    end
  end
end
