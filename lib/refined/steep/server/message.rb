# rbs_inline: enabled
# frozen_string_literal: true

module Refined
  module Steep
    module Server
      Interface = LanguageServer::Protocol::Interface
      Constant = LanguageServer::Protocol::Constant
      Transport = LanguageServer::Protocol::Transport

      class Message
        attr_reader :method #: String
        attr_reader :params #: untyped

        # @rbs method: String
        # @rbs params: untyped
        # @rbs return: void
        def initialize(method:, params:)
          @method = method
          @params = params
        end

        # @rbs return: Hash[Symbol, untyped]
        def to_hash
          raise NotImplementedError
        end
      end

      class Notification < Message
        class << self
          # @rbs message: String
          # @rbs type: Integer
          # @rbs return: Notification
          def window_show_message(message, type: Constant::MessageType::INFO)
            new(
              method: "window/showMessage",
              params: Interface::ShowMessageParams.new(type: type, message: message),
            )
          end

          # @rbs message: String
          # @rbs type: Integer
          # @rbs return: Notification
          def window_log_message(message, type: Constant::MessageType::LOG)
            new(
              method: "window/logMessage",
              params: Interface::LogMessageParams.new(type: type, message: message),
            )
          end

          # @rbs uri: String
          # @rbs diagnostics: Array[untyped]
          # @rbs version: Integer?
          # @rbs return: Notification
          def publish_diagnostics(uri, diagnostics, version: nil)
            new(
              method: "textDocument/publishDiagnostics",
              params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: diagnostics, version: version),
            )
          end
        end

        # @rbs return: Hash[Symbol, untyped]
        def to_hash
          hash = { method: @method } #: Hash[Symbol, untyped]

          if @params
            hash[:params] = @params.to_hash
          end

          hash
        end
      end

      class Request < Message
        # @rbs id: Integer | String
        # @rbs method: String
        # @rbs params: untyped
        # @rbs return: void
        def initialize(id:, method:, params:)
          @id = id #: Integer | String
          super(method: method, params: params)
        end

        # @rbs return: Hash[Symbol, untyped]
        def to_hash
          hash = { id: @id, method: @method } #: Hash[Symbol, untyped]

          if @params
            hash[:params] = @params.to_hash
          end

          hash
        end
      end

      class ErrorResponse
        attr_reader :message #: String
        attr_reader :code #: Integer

        # @rbs id: Integer
        # @rbs code: Integer
        # @rbs message: String
        # @rbs data: Hash[Symbol, untyped]?
        # @rbs return: void
        def initialize(id:, code:, message:, data: nil)
          @id = id #: Integer
          @code = code
          @message = message
          @data = data #: Hash[Symbol, untyped]?
        end

        # @rbs return: Hash[Symbol, untyped]
        def to_hash
          {
            id: @id,
            error: {
              code: @code,
              message: @message,
              data: @data,
            },
          }
        end
      end

      class Result
        attr_reader :response #: untyped
        attr_reader :id #: Integer

        # @rbs id: Integer
        # @rbs response: untyped
        # @rbs return: void
        def initialize(id:, response:)
          @id = id
          @response = response
        end

        # @rbs return: Hash[Symbol, untyped]
        def to_hash
          { id: @id, result: @response }
        end
      end
    end
  end
end
