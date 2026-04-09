# frozen_string_literal: true

RSpec.describe Refined::Steep::Server::LspServer do
  let(:fixtures_dir) { Pathname(File.expand_path("../../../fixtures", __dir__)) }
  let(:steepfile_path) { fixtures_dir / "Steepfile" }
  let(:lib_dir) { fixtures_dir / "lib" }
  let(:sig_dir) { fixtures_dir / "sig" }

  before do
    FileUtils.mkdir_p(lib_dir)
    FileUtils.mkdir_p(sig_dir)
    steepfile_path.write(<<~RUBY)
      target :lib do
        check "lib"
        signature "sig"
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(fixtures_dir)
  end

  def encode_message(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def create_server(messages)
    raw = messages.map { |m| encode_message(m) }.join
    reader = StringIO.new(raw)
    writer = StringIO.new

    server = described_class.new(reader: reader, writer: writer)
    [server, writer]
  end

  def parse_responses(writer)
    output = writer.string
    responses = []
    scanner = StringIO.new(output)
    while (headers = scanner.gets("\r\n\r\n"))
      content_length = headers[/Content-Length: (\d+)/i, 1]&.to_i
      next unless content_length

      raw = scanner.read(content_length)
      next unless raw

      responses << JSON.parse(raw, symbolize_names: true)
    end
    responses
  end

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
      messages = [
        {
          id: 1,
          method: "initialize",
          params: { rootUri: "file://#{fixtures_dir}", capabilities: {} },
        },
        { method: "initialized", params: {} },
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
      ]

      server, = create_server(messages)
      server.start
      sleep 0.2

      # After close, document should be removed
      expect(server.store&.get(uri)).to be_nil
    end
  end

  describe "textDocument/didChange" do
    it "applies changes through store" do
      uri = "file://#{lib_dir}/test.rb"
      messages = [
        {
          id: 1,
          method: "initialize",
          params: { rootUri: "file://#{fixtures_dir}", capabilities: {} },
        },
        { method: "initialized", params: {} },
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
      ]

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
end
