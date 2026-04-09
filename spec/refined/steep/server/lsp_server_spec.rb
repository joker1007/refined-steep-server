# frozen_string_literal: true

RSpec.describe Refined::Steep::Server::LspServer do
  include_context "lsp_helpers"

  describe "initialize request" do
    it "returns server capabilities" do
      messages = [
        {
          id: 1,
          method: "initialize",
          params: {
            rootUri: "file://#{fixtures_dir}",
            capabilities: {},
          },
        },
      ]

      server, writer = create_server(messages)
      server.start
      sleep 0.1

      responses = parse_responses(writer)
      init_response = responses.find { |r| r[:id] == 1 }

      expect(init_response).not_to be_nil
      result = init_response[:result]
      capabilities = result[:capabilities]

      expect(capabilities[:hoverProvider]).to be true
      expect(capabilities[:definitionProvider]).to be true
      expect(capabilities[:implementationProvider]).to be true
      expect(capabilities[:typeDefinitionProvider]).to be true
      expect(capabilities[:workspaceSymbolProvider]).to be true
      expect(capabilities[:completionProvider]).to include(:triggerCharacters)
      expect(capabilities[:signatureHelpProvider]).to include(:triggerCharacters)
      expect(capabilities[:textDocumentSync][:openClose]).to be true
      expect(result[:serverInfo][:name]).to eq("refined-steep-server")
    end
  end

  describe "textDocument/didOpen and didClose" do
    it "tracks document lifecycle" do
      uri = "file://#{lib_dir}/test.rb"
      messages = init_messages([
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: { uri: uri, languageId: "ruby", version: 1, text: "class Foo; end" },
          },
        },
        {
          method: "textDocument/didClose",
          params: { textDocument: { uri: uri } },
        },
      ])

      server, = create_server(messages)
      server.start
      sleep 0.2

      expect(server.store&.get(uri)).to be_nil
    end
  end

  describe "textDocument/didChange" do
    it "applies changes through store" do
      uri = "file://#{lib_dir}/test.rb"
      messages = init_messages([
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: { uri: uri, languageId: "ruby", version: 1, text: "class Foo; end" },
          },
        },
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: uri, version: 2 },
            contentChanges: [{ text: "class Bar; end" }],
          },
        },
      ])

      server, = create_server(messages)
      server.start
      sleep 0.2

      entry = server.store&.get(uri)
      expect(entry).not_to be_nil
      expect(entry.content).to eq("class Bar; end")
      expect(entry.version).to eq(2)
    end
  end

  describe "shutdown and exit" do
    it "shuts down cleanly" do
      messages = [
        {
          id: 1,
          method: "initialize",
          params: { rootUri: "file://#{fixtures_dir}", capabilities: {} },
        },
        { id: 2, method: "shutdown", params: {} },
        { method: "exit" },
      ]

      server, writer = create_server(messages)

      expect { server.start }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end

      responses = parse_responses(writer)
      shutdown_response = responses.find { |r| r[:id] == 2 }
      expect(shutdown_response).not_to be_nil
      expect(shutdown_response[:result]).to be_nil
    end
  end

  describe "Steepfile discovery" do
    it "finds Steepfile from rootUri" do
      messages = [
        {
          id: 1,
          method: "initialize",
          params: { rootUri: "file://#{fixtures_dir}", capabilities: {} },
        },
      ]

      server, = create_server(messages)
      server.start
      sleep 0.1

      expect(server.steep_state).not_to be_nil
      expect(server.steep_state.project.targets.size).to eq(1)
    end
  end

  context "with typed project" do
    let(:source_code) do
      <<~RUBY
        class Greeter
          attr_reader :name

          def initialize(name)
            @name = name
          end

          def greet
            "Hello, " + name
          end
        end
      RUBY
    end

    let(:rbs_content) do
      <<~RBS
        class Greeter
          attr_reader name: String

          def initialize: (String name) -> void
          def greet: () -> String
        end
      RBS
    end

    before do
      (lib_dir / "greeter.rb").write(source_code)
      (sig_dir / "greeter.rbs").write(rbs_content)
    end

    def open_and_request(id:, method:, uri:, text:, request_params:)
      init_messages([
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: { uri: uri, languageId: "ruby", version: 1, text: text },
          },
        },
        { id: id, method: method, params: request_params },
      ])
    end

    describe "textDocument/completion" do
      it "returns completion items for method calls" do
        uri = "file://#{lib_dir}/greeter.rb"
        completion_source = source_code.sub("\"Hello, \" + name", "self.")

        messages = open_and_request(
          id: 10,
          method: "textDocument/completion",
          uri: uri,
          text: completion_source,
          request_params: {
            textDocument: { uri: uri },
            position: { line: 8, character: 9 },
            context: { triggerKind: 2, triggerCharacter: "." },
          },
        )

        server, writer = create_server(messages)
        server.start
        sleep 1.0

        responses = parse_responses(writer)
        completion_response = responses.find { |r| r[:id] == 10 }

        expect(completion_response).not_to be_nil
        expect(completion_response[:error]).to be_nil

        result = completion_response[:result]
        expect(result).to include(:items)

        labels = result[:items].map { |item| item[:label] }
        expect(labels).to include("name")
        expect(labels).to include("greet")
      end

      it "returns empty completion list when no completions available" do
        uri = "file://#{lib_dir}/greeter.rb"

        messages = open_and_request(
          id: 10,
          method: "textDocument/completion",
          uri: uri,
          text: source_code,
          request_params: {
            textDocument: { uri: uri },
            position: { line: 0, character: 0 },
            context: { triggerKind: 1 },
          },
        )

        server, writer = create_server(messages)
        server.start
        sleep 1.0

        responses = parse_responses(writer)
        completion_response = responses.find { |r| r[:id] == 10 }

        expect(completion_response).not_to be_nil
        expect(completion_response[:error]).to be_nil

        result = completion_response[:result]
        expect(result).to include(:items)
        expect(result[:items]).to be_an(Array)
      end

      it "returns completion response without error for unknown file" do
        unknown_uri = "file://#{lib_dir}/unknown.rb"

        messages = init_messages([
          {
            id: 10,
            method: "textDocument/completion",
            params: {
              textDocument: { uri: unknown_uri },
              position: { line: 0, character: 0 },
              context: { triggerKind: 1 },
            },
          },
        ])

        server, writer = create_server(messages)
        server.start
        sleep 0.5

        responses = parse_responses(writer)
        completion_response = responses.find { |r| r[:id] == 10 }

        expect(completion_response).not_to be_nil
        if completion_response[:result]
          expect(completion_response[:result][:items]).to be_an(Array)
        else
          expect(completion_response[:result]).to be_nil
        end
      end
    end

    describe "textDocument/hover" do
      it "returns hover information for typed expressions" do
        uri = "file://#{lib_dir}/greeter.rb"

        messages = open_and_request(
          id: 10,
          method: "textDocument/hover",
          uri: uri,
          text: source_code,
          request_params: {
            textDocument: { uri: uri },
            position: { line: 3, character: 10 },
          },
        )

        server, writer = create_server(messages)
        server.start
        sleep 1.0

        responses = parse_responses(writer)
        hover_response = responses.find { |r| r[:id] == 10 }

        expect(hover_response).not_to be_nil
        expect(hover_response[:error]).to be_nil
      end
    end
  end
end
