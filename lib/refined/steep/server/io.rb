# rbs_inline: enabled
# frozen_string_literal: true

require "json"

module Refined
  module Steep
    module Server
      class MessageReader
        # @rbs @io: IO

        # @rbs io: IO
        # @rbs return: void
        def initialize(io)
          @io = io
        end

        # @rbs &block: (Hash[Symbol, untyped]) -> void
        # @rbs return: void
        def each_message(&block)
          while (headers = @io.gets("\r\n\r\n"))
            content_length = headers[/Content-Length: (\d+)/i, 1]&.to_i
            next unless content_length

            raw_message = @io.read(content_length)
            next unless raw_message

            block.call(JSON.parse(raw_message, symbolize_names: true))
          end
        end
      end

      class MessageWriter
        # @rbs @io: IO

        # @rbs io: IO
        # @rbs return: void
        def initialize(io)
          @io = io
        end

        # @rbs message: Hash[Symbol, untyped]
        # @rbs return: void
        def write(message)
          message[:jsonrpc] = "2.0"
          json_message = message.to_json

          @io.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
          @io.flush
        end
      end
    end
  end
end
