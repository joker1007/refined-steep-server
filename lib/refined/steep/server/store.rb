# rbs_inline: enabled
# frozen_string_literal: true

module Refined
  module Steep
    module Server
      class Store
        class DocumentEntry
          attr_reader :uri #: String
          attr_reader :content #: String
          attr_reader :version #: Integer

          # @rbs uri: String
          # @rbs content: String
          # @rbs version: Integer
          # @rbs return: void
          def initialize(uri:, content:, version:)
            @uri = uri
            @content = content
            @version = version
          end
        end

        # @rbs @steep_state: SteepState
        # @rbs @documents: Hash[String, DocumentEntry]

        # @rbs steep_state: SteepState
        # @rbs return: void
        def initialize(steep_state)
          @steep_state = steep_state
          @documents = {}
        end

        # @rbs uri: String
        # @rbs text: String
        # @rbs version: Integer
        # @rbs return: void
        def open(uri:, text:, version:)
          @documents[uri] = DocumentEntry.new(uri: uri, content: text, version: version)

          path = uri_to_relative_path(uri)
          return unless path

          @steep_state.push_changes(path, [
            ::Steep::Services::ContentChange.new(text: text),
          ])
        end

        # @rbs uri: String
        # @rbs content_changes: Array[Hash[Symbol, untyped]]
        # @rbs version: Integer
        # @rbs return: void
        def change(uri:, content_changes:, version:)
          entry = @documents[uri]
          return unless entry

          changes = content_changes.map do |change|
            range = change[:range]
            ::Steep::Services::ContentChange.new(
              range: range && [
                ::Steep::Services::ContentChange::Position.new(
                  line: range[:start][:line] + 1,
                  column: range[:start][:character],
                ),
                ::Steep::Services::ContentChange::Position.new(
                  line: range[:end][:line] + 1,
                  column: range[:end][:character],
                ),
              ],
              text: change[:text],
            )
          end

          # Update the stored content with the last full text
          last_change = content_changes.last
          if last_change && !last_change[:range]
            @documents[uri] = DocumentEntry.new(uri: uri, content: last_change[:text], version: version)
          else
            @documents[uri] = DocumentEntry.new(uri: uri, content: entry.content, version: version)
          end

          path = uri_to_relative_path(uri)
          return unless path

          @steep_state.push_changes(path, changes)
        end

        # @rbs uri: String
        # @rbs return: void
        def close(uri:)
          @documents.delete(uri)
        end

        # @rbs uri: String
        # @rbs return: DocumentEntry?
        def get(uri)
          @documents[uri]
        end

        private

        # @rbs uri: String
        # @rbs return: Pathname?
        def uri_to_relative_path(uri)
          path = ::Steep::PathHelper.to_pathname(uri)
          return unless path

          @steep_state.project.relative_path(path)
        end
      end
    end
  end
end
