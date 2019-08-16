# frozen_string_literal: true

require 'command_class'

module Provisioning

  # Err = Errors::Authentication
  # # Possible Errors Raised:
  # # AuthenticatorNotFound, InvalidCredentials

  Provision = CommandClass.new(
    dependencies: {
      audit_event:            ::Authentication::AuditEvent.new
    },
    inputs:       %i(provision_input provisioners)
  ) do

    def call
      provisioner.provision(@provision_input)
    end

    private

    def provisioner
      @provisioner ||= @provisioners[@provision_input.provisioner_name]
    end
  end
end
