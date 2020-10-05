# frozen_string_literal: true

require 'command_class'
require 'uri'
require 'websocket'
require 'rubygems/package'

require 'active_support/time'
require 'websocket-client-simple'

module Authentication
  module AuthnK8s

    KubeExec ||= CommandClass.new(
      dependencies: {
        env:    ENV,
        logger: Rails.logger
      },
      inputs:       %i(k8s_object_lookup pod_namespace pod_name container cmds body stdin)
    ) do

      extend Forwardable
      def_delegators :@k8s_object_lookup, :kube_client

      DEFAULT_KUBE_EXEC_COMMAND_TIMEOUT = 5

      def call
        @message_log    = MessageLog.new
        @channel_closed = false

        url       = server_url(@cmds, @stdin)
        headers   = kube_client.headers.clone
        ws_client = WebSocket::Client::Simple.connect(url, headers: headers)

        add_websocket_event_handlers(ws_client, @body, @stdin)

        wait_for_close_message

        unless @channel_closed
          raise Errors::Authentication::AuthnK8s::CommandTimedOut.new(
            timeout,
            @container,
            @pod_name
          )
        end

        # TODO: raise an `WebsocketServerFailure` here in the case of ws :error

        @message_log.messages
      end

      def on_open(ws_client, body, stdin)
        hs       = ws_client.handshake
        hs_error = hs.error

        if hs_error
          ws_client.emit(:error, "Websocket handshake error: #{hs_error.inspect}")
        else
          @logger.debug(
            LogMessages::Authentication::AuthnK8s::PodChannelOpen.new(@pod_name)
          )

          if stdin
            data = WebSocketMessage.channel_byte('stdin') + body
            ws_client.send(data)

            # We close the socket and don't wait for the cert to be fully injected
            # so that we can finish handling the request quickly and don't leave the
            # Conjur server hanging. If an error occurred it will be written to
            # the client container logs.
            ws_client.send(nil, type: :close)
          end
        end
      end

      def on_message(msg, ws_client)
        wsmsg = WebSocketMessage.new(msg)

        msg_type = wsmsg.type
        msg_data = wsmsg.data

        if msg_type == :binary
          @logger.debug(
            LogMessages::Authentication::AuthnK8s::PodChannelData.new(
              @pod_name,
              wsmsg.channel_name,
              msg_data
            )
          )
          @message_log.save_message(wsmsg)
        elsif msg_type == :close
          @logger.debug(
            LogMessages::Authentication::AuthnK8s::PodMessageData.new(
              @pod_name,
              "close",
              msg_data
            )
          )
          ws_client.close
        end
      end

      def on_close
        @channel_closed = true
        @logger.debug(
          LogMessages::Authentication::AuthnK8s::PodChannelClosed.new(@pod_name)
        )
      end

      def on_error(err)
        @channel_closed = true

        error_info = err.inspect
        @logger.debug(
          LogMessages::Authentication::AuthnK8s::PodError.new(@pod_name, error_info)
        )
        @message_log.save_error_string(error_info)
      end

      private

      def add_websocket_event_handlers(ws_client, body, stdin)
        # We need to set this so the handlers will call this class's methods.
        # If we use 'self' inside the curly brackets it will be try to use methods
        # of the class WebSocket::Client::Simple::Client
        kube = self

        ws_client.on(:open) { kube.on_open(ws_client, body, stdin) }
        ws_client.on(:message) { |msg| kube.on_message(msg, ws_client) }
        ws_client.on(:close) { kube.on_close }
        ws_client.on(:error) { |err| kube.on_error(err) }
      end

      def wait_for_close_message
        (timeout / 0.1).to_i.times do
          break if @channel_closed
          sleep 0.1
        end
      end

      def query_string(cmds, stdin)
        stdin_part = stdin ? ['stdin=true'] : []
        cmds_part  = cmds.map { |cmd| "command=#{CGI.escape(cmd)}" }
        (base_query_string_parts + stdin_part + cmds_part).join("&")
      end

      def base_query_string_parts
        %W(container=#{CGI.escape(@container)} stderr=true stdout=true)
      end

      def server_url(cmds, stdin)
        api_uri  = kube_client.api_endpoint
        base_url = "wss://#{api_uri.host}:#{api_uri.port}"
        path     = "/api/v1/namespaces/#{@pod_namespace}/pods/#{@pod_name}/exec"
        query    = query_string(cmds, stdin)
        "#{base_url}#{path}?#{query}"
      end

      def timeout
        return @timeout if @timeout

        kube_timeout = @env["KUBE_EXEC_COMMAND_TIMEOUT"]
        not_provided = kube_timeout.to_s.strip.empty?
        default      = DEFAULT_KUBE_EXEC_COMMAND_TIMEOUT
        # If the value of KUBE_EXEC_COMMAND_TIMEOUT is not an integer it will be zero
        @timeout = not_provided ? default : kube_timeout.to_i
      end
    end

    class KubeExec
      # This delegates to all the work to the call method created automatically
      # by CommandClass
      #
      # This is needed because we need these methods to exist on the class,
      # but that class contains only a metaprogramming generated `call()`.
      def execute(k8s_object_lookup:, pod_namespace:, pod_name:, cmds:, container: 'authenticator', body: "", stdin: false)
        call(
          k8s_object_lookup: k8s_object_lookup,
          pod_namespace:     pod_namespace,
          pod_name:          pod_name,
          container:         container,
          cmds:              cmds,
          body:              body,
          stdin:             stdin
        )
      end
    end
  end
end
