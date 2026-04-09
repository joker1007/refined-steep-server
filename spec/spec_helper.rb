# frozen_string_literal: true

require "refined/steep/server"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
end

RSpec.shared_context "steep_fixture" do
  let(:fixtures_dir) { Pathname(File.expand_path("../fixtures", __dir__)) }
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
end

RSpec.shared_context "lsp_helpers" do
  include_context "steep_fixture"

  let(:logger) { Refined::Steep::Server::BaseServer.create_default_logger(level: Logger::WARN, io: StringIO.new) }

  def encode_message(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def create_server(messages)
    raw = messages.map { |m| encode_message(m) }.join
    reader = StringIO.new(raw)
    writer = StringIO.new

    server = Refined::Steep::Server::LspServer.new(reader: reader, writer: writer, logger: logger)
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

  def init_messages(extras = [])
    [
      {
        id: 1,
        method: "initialize",
        params: { rootUri: "file://#{fixtures_dir}", capabilities: {} },
      },
      { method: "initialized", params: {} },
      *extras,
    ]
  end
end
