# frozen_string_literal: true

RSpec.describe Refined::Steep::Server do
  describe Refined::Steep::Server::Result do
    it "serializes to hash with id and result" do
      result = Refined::Steep::Server::Result.new(id: 1, response: { key: "value" })
      expect(result.to_hash).to eq({ id: 1, result: { key: "value" } })
    end

    it "serializes nil response" do
      result = Refined::Steep::Server::Result.new(id: 2, response: nil)
      expect(result.to_hash).to eq({ id: 2, result: nil })
    end
  end

  describe Refined::Steep::Server::ErrorResponse do
    it "serializes to hash with error structure" do
      error = Refined::Steep::Server::ErrorResponse.new(
        id: 1,
        code: -32600,
        message: "Invalid Request",
      )
      expect(error.to_hash).to eq({
        id: 1,
        error: {
          code: -32600,
          message: "Invalid Request",
          data: nil,
        },
      })
    end

    it "includes data when provided" do
      error = Refined::Steep::Server::ErrorResponse.new(
        id: 1,
        code: -32600,
        message: "Invalid Request",
        data: { detail: "something" },
      )
      expect(error.to_hash[:error][:data]).to eq({ detail: "something" })
    end
  end

  describe Refined::Steep::Server::Notification do
    it "serializes to hash with method and params" do
      notification = Refined::Steep::Server::Notification.window_log_message("hello")
      hash = notification.to_hash
      expect(hash[:method]).to eq("window/logMessage")
      expect(hash[:params]).to include(:type, :message)
    end

    it "creates publish_diagnostics notification" do
      notification = Refined::Steep::Server::Notification.publish_diagnostics(
        "file:///test.rb",
        [],
      )
      hash = notification.to_hash
      expect(hash[:method]).to eq("textDocument/publishDiagnostics")
      expect(hash[:params][:uri]).to eq("file:///test.rb")
    end
  end

  describe Refined::Steep::Server::Request do
    it "serializes to hash with id, method, and params" do
      params = LanguageServer::Protocol::Interface::ShowMessageParams.new(
        type: 1,
        message: "test",
      )
      request = Refined::Steep::Server::Request.new(
        id: 5,
        method: "window/showMessage",
        params: params,
      )
      hash = request.to_hash
      expect(hash[:id]).to eq(5)
      expect(hash[:method]).to eq("window/showMessage")
      expect(hash[:params]).to include(:type, :message)
    end
  end
end
