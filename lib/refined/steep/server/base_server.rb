# rbs_inline: enabled
# frozen_string_literal: true

module Refined
  module Steep
    module Server
      # @rbs!
      #   type lsp_message = Hash[Symbol, untyped]

      class BaseServer
        # @rbs reader: IO?
        # @rbs writer: IO?
        # @rbs return: void
        def initialize(reader: nil, writer: nil)
          @reader = MessageReader.new(reader || $stdin) #: MessageReader
          @writer = MessageWriter.new(writer || $stdout) #: MessageWriter
          @mutex = Mutex.new #: Mutex
          @incoming_queue = Thread::Queue.new #: Thread::Queue
          @outgoing_queue = Thread::Queue.new #: Thread::Queue
          @cancelled_requests = [] #: Array[Integer]
          @current_request_id = 1 #: Integer

          @worker = start_worker_thread #: Thread
          @outgoing_dispatcher = start_outgoing_thread #: Thread

          Thread.main.priority = 1
        end

        # @rbs return: void
        def start
          @reader.each_message do |message|
            method = message[:method]

            case method
            when "initialize", "initialized", "$/cancelRequest"
              process_message(message)
            when "shutdown"
              @mutex.synchronize do
                send_log_message("Shutting down refined-steep-server...")
                shutdown
                run_shutdown
                @writer.write(Result.new(id: message[:id], response: nil).to_hash)
              end
            when "exit"
              exit(@incoming_queue.closed? ? 0 : 1)
            else
              @incoming_queue << message
            end
          end
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def process_message(message)
          raise NotImplementedError
        end

        # @rbs return: void
        def run_shutdown
          @incoming_queue.clear
          @outgoing_queue.clear
          @incoming_queue.close
          @outgoing_queue.close
          @cancelled_requests.clear

          @worker.terminate
          @outgoing_dispatcher.terminate
        end

        private

        # @rbs return: void
        def shutdown
          raise NotImplementedError
        end

        # @rbs return: Thread
        def start_worker_thread
          Thread.new do
            while (message = @incoming_queue.pop)
              handle_incoming_message(message)
            end
          end
        end

        # @rbs return: Thread
        def start_outgoing_thread
          Thread.new do
            while (message = @outgoing_queue.pop)
              @mutex.synchronize { @writer.write(message.to_hash) }
            end
          end
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_incoming_message(message)
          id = message[:id]

          @mutex.synchronize do
            if id && @cancelled_requests.delete(id)
              send_message(ErrorResponse.new(
                id: id,
                code: Constant::ErrorCodes::REQUEST_CANCELLED,
                message: "Request #{id} was cancelled",
              ))
              return
            end
          end

          process_message(message)
          @cancelled_requests.delete(id)
        end

        # @rbs message: Result | ErrorResponse | Notification | Request
        # @rbs return: void
        def send_message(message)
          return if @outgoing_queue.closed?

          @outgoing_queue << message
          @current_request_id += 1 if message.is_a?(Request)
        end

        # @rbs id: Integer
        # @rbs return: void
        def send_empty_response(id)
          send_message(Result.new(id: id, response: nil))
        end

        # @rbs message: String
        # @rbs type: Integer
        # @rbs return: void
        def send_log_message(message, type: Constant::MessageType::LOG)
          send_message(Notification.window_log_message(message, type: type))
        end
      end
    end
  end
end
