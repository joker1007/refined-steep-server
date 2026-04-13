# refined-steep-server

[![CI](https://github.com/joker1007/refined-steep-server/actions/workflows/ci.yml/badge.svg)](https://github.com/joker1007/refined-steep-server/actions/workflows/ci.yml)

Most of this project is written by Claude Code.

A language server for Ruby type checking that uses [Steep](https://github.com/soutaro/steep) as a library. It provides the same type checking features as Steep's built-in language server, reimplemented with a single-process multi-threaded architecture inspired by [ruby-lsp](https://github.com/Shopify/ruby-lsp). Designed with Neovim compatibility in mind.

## Motivation

Steep ships with a built-in language server based on a multi-process architecture (master + interaction worker + type-check workers). While powerful, this design can be complex to manage and debug. It also type-checks the entire project on startup, which can cause significant delays in large codebases.

refined-steep-server takes a different approach: it runs everything in a single process with multiple threads, directly calling Steep's internal services as a library. Instead of type-checking all files on startup, it only type-checks files as they are opened or modified. This results in a simpler, faster-starting server that is easier to integrate with editors like Neovim.

## Features

### Supported LSP Methods

| Method | Description |
|--------|-------------|
| `textDocument/hover` | Show type information at cursor |
| `textDocument/completion` | Code completion (triggers: `.`, `@`, `:`) |
| `textDocument/signatureHelp` | Method signature help (trigger: `(`) |
| `textDocument/definition` | Go to definition |
| `textDocument/implementation` | Find implementations |
| `textDocument/typeDefinition` | Go to type definition |
| `workspace/symbol` | Workspace-wide symbol search |
| `textDocument/publishDiagnostics` | Type error diagnostics |

### Additional Features

- Incremental text document synchronization
- Type checking runs on file open and file save (not on every keystroke)
- WorkDoneProgress notifications for type checking progress
- Steepfile auto-discovery (searches parent directories)
- Configurable logging with `--log-level` and `--log-file` options

## Architecture

```
Client (editor)
  |
  v
[Main Thread] reads stdin --> incoming_queue
  |
  v
[Worker Thread] pops from incoming_queue --> process_message --> Steep services
  |
  v
[Writer Thread] pops from outgoing_queue --> writes JSON-RPC to stdout
```

Steep's services (`TypeCheckService`, `HoverProvider`, `CompletionProvider`, `GotoService`, `SignatureHelpProvider`) are called directly as library APIs, with `PathAssignment.all` handling all files in a single process.

## Requirements

- Ruby >= 3.2.0
- Steep ~> 1.10
- A `Steepfile` in your project

## Installation

```bash
gem install refined-steep-server
```

Or add to your Gemfile:

```ruby
gem "refined-steep-server"
```

## Usage

### Basic

```bash
refined-steep-server
```

The server communicates over stdin/stdout using the LSP protocol. Point your editor's LSP client to this executable.

### With Debug Logging

```bash
refined-steep-server --log-level debug
```

### With Log File

```bash
refined-steep-server --log-level debug --log-file /tmp/refined-steep.log
```

### Neovim Configuration (0.12+)

Neovim 0.12+ has built-in LSP support via `vim.lsp.config()` and `vim.lsp.enable()`. No plugins required.

```lua
vim.lsp.config("refined_steep", {
  cmd = { "refined-steep-server" },
  filetypes = { "ruby" },
  root_markers = { "Steepfile" },
})

vim.lsp.enable("refined_steep")
```

## Development

After checking out the repo, run `bin/setup` to install dependencies.

### Commands

```bash
# Run tests
bundle exec rspec

# Generate RBS from inline annotations
bundle exec rbs-inline --output=sig/generated lib

# Run type checker
bundle exec steep check

# Recommended workflow after changes:
bundle exec rbs-inline --output=sig/generated lib && bundle exec steep check && bundle exec rspec
```

### Project Structure

```
lib/refined/steep/server/
  base_server.rb    # Abstract server with 3-thread model (reader/worker/writer)
  lsp_server.rb     # Concrete LSP server with request routing and handlers
  steep_state.rb    # Bridge to Steep: Project, TypeCheckService, change buffer
  store.rb          # Document state management
  message.rb        # LSP message types (Result, Error, Notification, Request)
  io.rb             # JSON-RPC MessageReader/MessageWriter
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joker1007/refined-steep-server.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
