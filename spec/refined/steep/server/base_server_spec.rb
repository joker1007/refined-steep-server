# frozen_string_literal: true

RSpec.describe Refined::Steep::Server::BaseServer do
  def build_message(method:, id: nil, params: {})
    msg = { method: method, params: params }
    msg[:id] = id if id
    msg
  end

  def encode_message(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def create_server(messages)
    raw = messages.map { |m| encode_message(m) }.join
    reader = StringIO.new(raw)
    writer = StringIO.new

    server = TestServer.new(reader: reader, writer: writer)
    [server, writer]
  end

  # Concrete subclass for testing
  before do
    stub_const("TestServer", Class.new(Refined::Steep::Server::BaseServer) do
      attr_reader :processed_messages

      def initialize(**options)
        @processed_messages = []
        super
      end

      def process_message(message)
        @processed_messages << message
      end

      private

      def shutdown
        # no-op
      end
    end)
  end

  describe "#start" do
    it "processes initialize message synchronously" do
      messages = [build_message(method: "initialize", id: 1, params: { capabilities: {} })]
      server, = create_server(messages)

      server.start

      expect(server.processed_messages.size).to eq(1)
      expect(server.processed_messages[0][:method]).to eq("initialize")
    end

    it "processes initialized notification synchronously" do
      messages = [build_message(method: "initialized")]
      server, = create_server(messages)

      server.start

      expect(server.processed_messages.size).to eq(1)
      expect(server.processed_messages[0][:method]).to eq("initialized")
    end

    it "queues other messages for worker thread" do
      messages = [build_message(method: "textDocument/hover", id: 1)]
      server, = create_server(messages)

      server.start
      # Give the worker thread time to process
      sleep 0.1

      expect(server.processed_messages.size).to eq(1)
      expect(server.processed_messages[0][:method]).to eq("textDocument/hover")
    end

    it "handles shutdown and exit sequence" do
      messages = [
        build_message(method: "shutdown", id: 1),
        build_message(method: "exit"),
      ]
      server, writer = create_server(messages)

      expect { server.start }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end

      # Verify shutdown response was written
      output = writer.string
      expect(output).to include('"id":1')
      expect(output).to include('"result":null')
    end
  end

  describe "#send_message" do
    it "sends result message through outgoing queue" do
      messages = [
        build_message(method: "initialize", id: 1, params: { capabilities: {} }),
      ]
      server, writer = create_server(messages)

      # Override process_message to send a result
      allow(server).to receive(:process_message) do |msg|
        server.send(:send_message, Refined::Steep::Server::Result.new(id: msg[:id], response: { capabilities: {} }))
      end

      server.start
      sleep 0.1

      output = writer.string
      expect(output).to include('"capabilities"')
    end
  end
end
