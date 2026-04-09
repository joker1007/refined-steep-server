# frozen_string_literal: true

RSpec.describe Refined::Steep::Server::SteepState do
  include_context "steep_fixture"

  describe "#initialize" do
    it "loads the project from Steepfile" do
      state = described_class.new(steepfile_path: steepfile_path)
      expect(state.project).to be_a(::Steep::Project)
      expect(state.project.targets.size).to eq(1)
      expect(state.project.targets[0].name).to eq(:lib)
    end

    it "creates a TypeCheckService" do
      state = described_class.new(steepfile_path: steepfile_path)
      expect(state.type_check_service).to be_a(::Steep::Services::TypeCheckService)
    end
  end

  describe "#push_changes and #flush_changes" do
    it "buffers and flushes changes" do
      state = described_class.new(steepfile_path: steepfile_path)
      path = Pathname("lib/test.rb")
      change = ::Steep::Services::ContentChange.new(text: "class Foo; end")

      state.push_changes(path, [change])
      flushed = state.flush_changes

      expect(flushed.keys).to eq([path])
      expect(flushed[path].size).to eq(1)
      expect(flushed[path][0].text).to eq("class Foo; end")
    end

    it "clears buffer after flush" do
      state = described_class.new(steepfile_path: steepfile_path)
      path = Pathname("lib/test.rb")
      change = ::Steep::Services::ContentChange.new(text: "class Foo; end")

      state.push_changes(path, [change])
      state.flush_changes
      flushed = state.flush_changes

      expect(flushed).to be_empty
    end
  end
end
