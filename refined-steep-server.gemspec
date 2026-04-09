# frozen_string_literal: true

require_relative "lib/refined/steep/server/version"

Gem::Specification.new do |spec|
  spec.name = "refined-steep-server"
  spec.version = Refined::Steep::Server::VERSION
  spec.authors = ["joker1007"]
  spec.email = ["kakyoin.hierophant@gmail.com"]

  spec.summary = "A language server using Steep as a library with ruby-lsp architecture"
  spec.description = "Language server implementation that provides Steep-equivalent type checking features using ruby-lsp's single-process multi-threaded architecture"
  spec.homepage = "https://github.com/joker1007/refined-steep-server"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/joker1007/refined-steep-server"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "steep", "~> 1.10"
  spec.add_dependency "language_server-protocol", "~> 3.17"
end
