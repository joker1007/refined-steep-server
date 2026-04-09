# frozen_string_literal: true

RSpec.describe Refined::Steep::Server::MessageReader do
  it "reads JSON-RPC messages from IO" do
    json = '{"method":"initialize","params":{}}'
    raw = "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    io = StringIO.new(raw)

    reader = Refined::Steep::Server::MessageReader.new(io)
    messages = []
    reader.each_message { |msg| messages << msg }

    expect(messages.size).to eq(1)
    expect(messages[0][:method]).to eq("initialize")
  end

  it "reads multiple messages" do
    messages_data = [
      { method: "initialize", params: {} },
      { method: "initialized", params: {} },
    ]

    raw = messages_data.map do |data|
      json = JSON.generate(data)
      "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end.join

    io = StringIO.new(raw)
    reader = Refined::Steep::Server::MessageReader.new(io)
    messages = []
    reader.each_message { |msg| messages << msg }

    expect(messages.size).to eq(2)
    expect(messages[0][:method]).to eq("initialize")
    expect(messages[1][:method]).to eq("initialized")
  end
end

RSpec.describe Refined::Steep::Server::MessageWriter do
  it "writes JSON-RPC messages to IO" do
    io = StringIO.new
    writer = Refined::Steep::Server::MessageWriter.new(io)

    writer.write({ id: 1, result: nil })

    output = io.string
    expect(output).to match(/Content-Length: \d+\r\n\r\n/)
    json_part = output.sub(/Content-Length: \d+\r\n\r\n/, "")
    parsed = JSON.parse(json_part, symbolize_names: true)
    expect(parsed[:jsonrpc]).to eq("2.0")
    expect(parsed[:id]).to eq(1)
    expect(parsed[:result]).to be_nil
  end
end
