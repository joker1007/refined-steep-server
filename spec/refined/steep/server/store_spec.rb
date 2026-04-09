# frozen_string_literal: true

RSpec.describe Refined::Steep::Server::Store do
  let(:steepfile_path) { Pathname(File.expand_path("../../../fixtures/Steepfile", __dir__)) }
  let(:base_dir) { steepfile_path.parent }

  before do
    FileUtils.mkdir_p(base_dir / "lib")
    FileUtils.mkdir_p(base_dir / "sig")
    steepfile_path.write(<<~RUBY)
      target :lib do
        check "lib"
        signature "sig"
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(base_dir)
  end

  let(:steep_state) { Refined::Steep::Server::SteepState.new(steepfile_path: steepfile_path) }
  let(:store) { described_class.new(steep_state) }

  describe "#open" do
    it "stores the document" do
      uri = "file://#{base_dir}/lib/test.rb"
      store.open(uri: uri, text: "class Foo; end", version: 1)

      entry = store.get(uri)
      expect(entry).not_to be_nil
      expect(entry.content).to eq("class Foo; end")
      expect(entry.version).to eq(1)
    end

    it "pushes changes to steep_state" do
      uri = "file://#{base_dir}/lib/test.rb"
      store.open(uri: uri, text: "class Foo; end", version: 1)

      changes = steep_state.flush_changes
      expect(changes).not_to be_empty
    end
  end

  describe "#change" do
    it "pushes incremental changes to steep_state" do
      uri = "file://#{base_dir}/lib/test.rb"
      store.open(uri: uri, text: "class Foo; end", version: 1)
      steep_state.flush_changes # clear initial open

      store.change(
        uri: uri,
        content_changes: [
          {
            range: {
              start: { line: 0, character: 6 },
              end: { line: 0, character: 9 },
            },
            text: "Bar",
          },
        ],
        version: 2,
      )

      changes = steep_state.flush_changes
      expect(changes).not_to be_empty
      path = changes.keys.first
      expect(changes[path].first.text).to eq("Bar")
      expect(changes[path].first.range).not_to be_nil
    end

    it "pushes full text changes to steep_state" do
      uri = "file://#{base_dir}/lib/test.rb"
      store.open(uri: uri, text: "class Foo; end", version: 1)
      steep_state.flush_changes

      store.change(
        uri: uri,
        content_changes: [{ text: "class Bar; end" }],
        version: 2,
      )

      entry = store.get(uri)
      expect(entry.content).to eq("class Bar; end")
      expect(entry.version).to eq(2)
    end
  end

  describe "#close" do
    it "removes the document" do
      uri = "file://#{base_dir}/lib/test.rb"
      store.open(uri: uri, text: "class Foo; end", version: 1)
      store.close(uri: uri)

      expect(store.get(uri)).to be_nil
    end
  end
end
