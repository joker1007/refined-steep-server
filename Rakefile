# frozen_string_literal: true

require "bundler/gem_tasks"

namespace :rbs do
  desc "Generate RBS files from rbs-inline annotations"
  task :inline do
    sh "bundle exec rbs-inline --output=sig/generated lib"
  end
end

task default: %i[]
