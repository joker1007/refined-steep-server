# rbs_inline: enabled
# frozen_string_literal: true

module Refined
  module Steep
    module Server
      class LspServer < BaseServer
        LSP = LanguageServer::Protocol

        attr_reader :steep_state #: SteepState?
        attr_reader :store #: Store?

        # @rbs reader: IO?
        # @rbs writer: IO?
        # @rbs return: void
        def initialize(reader: nil, writer: nil)
          @steep_state = nil
          @store = nil
          @last_signature_help_line = nil #: Integer?
          @last_signature_help_result = nil #: untyped
          super(reader: reader, writer: writer)
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def process_message(message)
          case message[:method]
          when "initialize"
            handle_initialize(message)
          when "initialized"
            handle_initialized(message)
          when "textDocument/didOpen"
            handle_did_open(message)
          when "textDocument/didChange"
            handle_did_change(message)
          when "textDocument/didClose"
            handle_did_close(message)
          when "textDocument/hover"
            handle_hover(message)
          when "textDocument/completion"
            handle_completion(message)
          when "textDocument/signatureHelp"
            handle_signature_help(message)
          when "textDocument/definition"
            handle_goto(message, :definition)
          when "textDocument/implementation"
            handle_goto(message, :implementation)
          when "textDocument/typeDefinition"
            handle_goto(message, :type_definition)
          when "workspace/symbol"
            handle_workspace_symbol(message)
          when "$/cancelRequest"
            handle_cancel_request(message)
          end
        rescue => e
          $stderr.puts "Error processing #{message[:method]}: #{e.message}"
          $stderr.puts e.backtrace&.first(10)&.join("\n")

          if message[:id]
            send_message(ErrorResponse.new(
              id: message[:id],
              code: Constant::ErrorCodes::INTERNAL_ERROR,
              message: e.message || "Internal error",
            ))
          end
        end

        private

        # @rbs return: void
        def shutdown
          # no-op
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_initialize(message)
          root_uri = message.dig(:params, :rootUri)
          root_path = message.dig(:params, :rootPath)

          workspace_path = if root_uri
            ::Steep::PathHelper.to_pathname(root_uri)
          elsif root_path
            Pathname(root_path)
          else
            Pathname.pwd
          end

          steepfile_path = find_steepfile(workspace_path)

          if steepfile_path
            state = SteepState.new(steepfile_path: steepfile_path)
            @steep_state = state
            @store = Store.new(state)
          end

          send_message(Result.new(
            id: message[:id],
            response: Interface::InitializeResult.new(
              capabilities: Interface::ServerCapabilities.new(
                text_document_sync: Interface::TextDocumentSyncOptions.new(
                  change: Constant::TextDocumentSyncKind::INCREMENTAL,
                  open_close: true,
                ),
                hover_provider: true,
                completion_provider: Interface::CompletionOptions.new(
                  trigger_characters: [".", "@", ":"],
                ),
                signature_help_provider: Interface::SignatureHelpOptions.new(
                  trigger_characters: ["("],
                ),
                workspace_symbol_provider: true,
                definition_provider: true,
                implementation_provider: true,
                type_definition_provider: true,
              ),
              server_info: {
                name: "refined-steep-server",
                version: VERSION,
              },
            ),
          ))
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_initialized(message)
          return unless @steep_state

          load_project_files
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_did_open(message)
          store = @store
          return unless store

          params = message[:params]
          uri = params[:textDocument][:uri]
          text = params[:textDocument][:text]
          version = params[:textDocument][:version]

          store.open(uri: uri, text: text, version: version)
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_did_change(message)
          store = @store
          return unless store

          params = message[:params]
          uri = params[:textDocument][:uri]
          version = params[:textDocument][:version]
          content_changes = params[:contentChanges]

          store.change(uri: uri, content_changes: content_changes, version: version)
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_did_close(message)
          store = @store
          return unless store

          uri = message[:params][:textDocument][:uri]
          store.close(uri: uri)
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_hover(message)
          state = @steep_state
          unless state
            send_empty_response(message[:id])
            return
          end

          state.apply_changes

          params = message[:params]
          path = uri_to_relative_path(state, params[:textDocument][:uri])
          unless path
            send_empty_response(message[:id])
            return
          end

          line = params[:position][:line] + 1
          column = params[:position][:character]

          content = ::Steep::Services::HoverProvider.content_for(
            service: state.type_check_service,
            path: path,
            line: line,
            column: column,
          )

          if content
            lsp_range = content.location.as_lsp_range
            range = Interface::Range.new(
              start: Interface::Position.new(
                line: lsp_range[:start][:line],
                character: lsp_range[:start][:character],
              ),
              end: Interface::Position.new(
                line: lsp_range[:end][:line],
                character: lsp_range[:end][:character],
              ),
            )

            hover = Interface::Hover.new(
              contents: Interface::MarkupContent.new(
                kind: "markdown",
                value: ::Steep::LSPFormatter.format_hover_content(content).to_s,
              ),
              range: range,
            )

            send_message(Result.new(id: message[:id], response: hover))
          else
            send_empty_response(message[:id])
          end
        rescue ::Steep::Typing::UnknownNodeError
          send_empty_response(message[:id])
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_completion(message)
          state = @steep_state
          unless state
            send_empty_response(message[:id])
            return
          end

          state.apply_changes

          params = message[:params]
          path = uri_to_relative_path(state, params[:textDocument][:uri])
          unless path
            send_empty_response(message[:id])
            return
          end

          line = params[:position][:line] + 1
          column = params[:position][:character]
          trigger = params.dig(:context, :triggerCharacter)

          items = complete_items(state, path, line, column, trigger)

          send_message(Result.new(
            id: message[:id],
            response: Interface::CompletionList.new(
              is_incomplete: false,
              items: items || [],
            ),
          ))
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_signature_help(message)
          state = @steep_state
          unless state
            send_empty_response(message[:id])
            return
          end

          state.apply_changes

          params = message[:params]
          path = uri_to_relative_path(state, params[:textDocument][:uri])
          unless path
            send_empty_response(message[:id])
            return
          end

          line = params[:position][:line] + 1
          column = params[:position][:character]

          result = compute_signature_help(state, path, line, column)
          send_message(Result.new(id: message[:id], response: result))
        end

        # @rbs message: lsp_message
        # @rbs kind: Symbol
        # @rbs return: void
        def handle_goto(message, kind)
          state = @steep_state
          unless state
            send_empty_response(message[:id])
            return
          end

          state.apply_changes

          params = message[:params]
          uri = params[:textDocument][:uri]
          path = ::Steep::PathHelper.to_pathname(uri)
          unless path
            send_empty_response(message[:id])
            return
          end

          line = params[:position][:line] + 1
          column = params[:position][:character]

          goto_service = ::Steep::Services::GotoService.new(
            type_check: state.type_check_service,
            assignment: state.assignment,
          )

          locations = case kind
          when :definition
            goto_service.definition(path: path, line: line, column: column)
          when :implementation
            goto_service.implementation(path: path, line: line, column: column)
          when :type_definition
            goto_service.type_definition(path: path, line: line, column: column)
          else
            [] #: Array[untyped]
          end

          result = locations.map do |loc|
            loc_path = case loc
            when RBS::Location
              Pathname(loc.buffer.name)
            else
              Pathname(loc.source_buffer.name)
            end

            loc_path = state.project.absolute_path(loc_path)

            {
              uri: ::Steep::PathHelper.to_uri(loc_path).to_s,
              range: loc.as_lsp_range,
            }
          end

          send_message(Result.new(id: message[:id], response: result))
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_workspace_symbol(message)
          state = @steep_state
          unless state
            send_message(Result.new(id: message[:id], response: []))
            return
          end

          query = message[:params][:query] || ""

          provider = ::Steep::Index::SignatureSymbolProvider.new(
            project: state.project,
            assignment: state.assignment,
          )
          state.project.targets.each do |target|
            index = state.type_check_service.signature_services.fetch(target.name).latest_rbs_index
            provider.indexes[target] = index
          end

          symbols = provider.query_symbol(query)

          result = symbols.map do |symbol|
            Interface::SymbolInformation.new(
              name: symbol.name,
              kind: symbol.kind,
              location: symbol.location.yield_self do |location|
                path = Pathname(location.buffer.name)
                {
                  uri: ::Steep::PathHelper.to_uri(state.project.absolute_path(path)),
                  range: {
                    start: { line: location.start_line - 1, character: location.start_column },
                    end: { line: location.end_line - 1, character: location.end_column },
                  },
                }
              end,
              container_name: symbol.container_name,
            )
          end

          send_message(Result.new(id: message[:id], response: result))
        end

        # @rbs message: lsp_message
        # @rbs return: void
        def handle_cancel_request(message)
          id = message[:params][:id]
          @cancelled_requests << id if id
        end

        # @rbs return: void
        def load_project_files
          state = @steep_state
          return unless state

          loader = ::Steep::Services::FileLoader.new(base_dir: state.project.base_dir)

          state.project.targets.each do |target|
            loader.each_path_in_target(target) do |path|
              absolute_path = state.project.absolute_path(path)
              next unless absolute_path.file?

              content = absolute_path.read
              state.push_changes(path, [
                ::Steep::Services::ContentChange.new(text: content),
              ])
            end
          end

          state.apply_changes
          publish_diagnostics
        end

        # @rbs return: void
        def publish_diagnostics
          state = @steep_state
          return unless state

          formatter = ::Steep::Diagnostic::LSPFormatter.new(state.project.targets.first&.code_diagnostics_config || {})

          state.project.targets.each do |target|
            state.type_check_service.source_files.each_value do |file|
              next unless target.possible_source_file?(file.path)

              diagnostics = file.diagnostics || []
              lsp_diagnostics = diagnostics.filter_map do |diag|
                formatter.format(diag)
              end

              absolute_path = state.project.absolute_path(file.path)
              uri = ::Steep::PathHelper.to_uri(absolute_path).to_s

              send_message(Notification.publish_diagnostics(uri, lsp_diagnostics))
            end
          end
        end

        # @rbs state: SteepState
        # @rbs path: Pathname
        # @rbs line: Integer
        # @rbs column: Integer
        # @rbs trigger: String?
        # @rbs return: Array[untyped]?
        def complete_items(state, path, line, column, trigger)
          case
          when target = state.project.target_for_inline_source_path(path) || state.project.target_for_source_path(path)
            file = state.type_check_service.source_files[path] or return nil
            subtyping = state.type_check_service.signature_services.fetch(target.name).current_subtyping or return nil

            provider = ::Steep::Services::CompletionProvider::Ruby.new(
              source_text: file.content,
              path: path,
              subtyping: subtyping,
            )

            if (prefix_size, items = provider.run_at_comment(line: line, column: column))
              items.map { |item| format_completion_item(item) }
            else
              items = begin
                provider.run(line: line, column: column)
              rescue Parser::SyntaxError
                [] #: Array[untyped]
              end
              items.map { |item| format_completion_item(item) }
            end
          when target = state.project.target_for_signature_path(path)
            sig_service = state.type_check_service.signature_services[target.name] or return nil
            completion = ::Steep::Services::CompletionProvider::RBS.new(path, sig_service)
            prefix_size, type_names = completion.run(line, column)

            type_names.map do |absolute_name, relative_name|
              format_rbs_completion_item(sig_service, absolute_name, relative_name.to_s, prefix_size, line, column)
            end
          end
        end

        # @rbs item: untyped
        # @rbs return: untyped
        def format_completion_item(item)
          range = Interface::Range.new(
            start: Interface::Position.new(line: item.range.start.line - 1, character: item.range.start.column),
            end: Interface::Position.new(line: item.range.end.line - 1, character: item.range.end.column),
          )

          case item
          when ::Steep::Services::CompletionProvider::LocalVariableItem
            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: Constant::CompletionItemKind::VARIABLE,
              label_details: Interface::CompletionItemLabelDetails.new(description: item.type.to_s),
              insert_text: item.identifier.to_s,
              sort_text: item.identifier.to_s,
            )
          when ::Steep::Services::CompletionProvider::ConstantItem
            kind = (item.class? || item.module?) ? Constant::CompletionItemKind::CLASS : Constant::CompletionItemKind::CONSTANT

            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: kind,
              text_edit: Interface::TextEdit.new(range: range, new_text: item.identifier.to_s),
            )
          when ::Steep::Services::CompletionProvider::SimpleMethodNameItem
            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: Constant::CompletionItemKind::FUNCTION,
              label_details: Interface::CompletionItemLabelDetails.new(description: item.method_name.relative.to_s),
              insert_text: item.identifier.to_s,
            )
          when ::Steep::Services::CompletionProvider::ComplexMethodNameItem
            method_names = item.method_names.map(&:relative).uniq
            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: Constant::CompletionItemKind::FUNCTION,
              label_details: Interface::CompletionItemLabelDetails.new(description: method_names.join(", ")),
              insert_text: item.identifier.to_s,
            )
          when ::Steep::Services::CompletionProvider::GeneratedMethodNameItem
            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: Constant::CompletionItemKind::FUNCTION,
              label_details: Interface::CompletionItemLabelDetails.new(description: "(Generated)"),
              insert_text: item.identifier.to_s,
            )
          when ::Steep::Services::CompletionProvider::InstanceVariableItem
            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: Constant::CompletionItemKind::FIELD,
              label_details: Interface::CompletionItemLabelDetails.new(description: item.type.to_s),
              text_edit: Interface::TextEdit.new(range: range, new_text: item.identifier.to_s),
            )
          when ::Steep::Services::CompletionProvider::KeywordArgumentItem
            Interface::CompletionItem.new(
              label: item.identifier.to_s,
              kind: Constant::CompletionItemKind::FIELD,
              label_details: Interface::CompletionItemLabelDetails.new(description: "Keyword argument"),
              text_edit: Interface::TextEdit.new(range: range, new_text: item.identifier.to_s),
            )
          when ::Steep::Services::CompletionProvider::TypeNameItem
            kind = case
            when item.absolute_type_name.class? then Constant::CompletionItemKind::CLASS
            when item.absolute_type_name.interface? then Constant::CompletionItemKind::INTERFACE
            when item.absolute_type_name.alias? then Constant::CompletionItemKind::FIELD
            end

            Interface::CompletionItem.new(
              label: item.relative_type_name.to_s,
              kind: kind,
              text_edit: Interface::TextEdit.new(range: range, new_text: item.relative_type_name.to_s),
            )
          when ::Steep::Services::CompletionProvider::TextItem
            Interface::CompletionItem.new(
              label: item.label,
              kind: Constant::CompletionItemKind::SNIPPET,
              insert_text_format: Constant::InsertTextFormat::SNIPPET,
              text_edit: Interface::TextEdit.new(range: range, new_text: item.text),
            )
          else
            Interface::CompletionItem.new(
              label: item.to_s,
              kind: Constant::CompletionItemKind::TEXT,
            )
          end
        end

        # @rbs sig_service: untyped
        # @rbs absolute_name: untyped
        # @rbs complete_text: String
        # @rbs prefix_size: Integer
        # @rbs line: Integer
        # @rbs column: Integer
        # @rbs return: untyped
        def format_rbs_completion_item(sig_service, absolute_name, complete_text, prefix_size, line, column)
          range = Interface::Range.new(
            start: Interface::Position.new(line: line - 1, character: column - prefix_size),
            end: Interface::Position.new(line: line - 1, character: column),
          )

          Interface::CompletionItem.new(
            label: complete_text,
            text_edit: Interface::TextEdit.new(range: range, new_text: complete_text),
            kind: Constant::CompletionItemKind::CLASS,
          )
        end

        # @rbs state: SteepState
        # @rbs path: Pathname
        # @rbs line: Integer
        # @rbs column: Integer
        # @rbs return: untyped
        def compute_signature_help(state, path, line, column)
          target = state.project.target_for_inline_source_path(path) || state.project.target_for_source_path(path)
          return unless target

          file = state.type_check_service.source_files[path]
          return unless file

          subtyping = state.type_check_service.signature_services.fetch(target.name).current_subtyping
          return unless subtyping

          source = ::Steep::Source.parse(file.content, path: file.path, factory: subtyping.factory)
            .without_unrelated_defs(line: line, column: column)

          provider = ::Steep::Services::SignatureHelpProvider.new(source: source, subtyping: subtyping)

          if (items, index = provider.run(line: line, column: column))
            signatures = items.map do |item|
              params = item.parameters or raise
              Interface::SignatureInformation.new(
                label: item.method_type.to_s,
                parameters: params.map { |param| Interface::ParameterInformation.new(label: param) },
                active_parameter: item.active_parameter,
                documentation: item.comment&.yield_self do |comment|
                  Interface::MarkupContent.new(
                    kind: Constant::MarkupKind::MARKDOWN,
                    value: comment.string.gsub(/<!--(?~-->)-->/, ""),
                  )
                end,
              )
            end

            @last_signature_help_line = line
            @last_signature_help_result = Interface::SignatureHelp.new(
              signatures: signatures,
              active_signature: index,
            )
          end
        rescue Parser::SyntaxError
          @last_signature_help_result if @last_signature_help_line == line
        end

        # @rbs state: SteepState
        # @rbs uri: String
        # @rbs return: Pathname?
        def uri_to_relative_path(state, uri)
          path = ::Steep::PathHelper.to_pathname(uri)
          return unless path

          state.project.relative_path(path)
        end

        # @rbs workspace_path: Pathname?
        # @rbs return: Pathname?
        def find_steepfile(workspace_path)
          return unless workspace_path

          dir = workspace_path.expand_path
          loop do
            steepfile = dir / "Steepfile"
            return steepfile if steepfile.file?

            parent = dir.parent
            return nil if parent == dir

            dir = parent
          end
        end
      end
    end
  end
end
