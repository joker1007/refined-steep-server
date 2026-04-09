# rbs_inline: enabled
# frozen_string_literal: true

module Refined
  module Steep
    module Server
      class SteepState
        attr_reader :project #: ::Steep::Project
        attr_reader :type_check_service #: ::Steep::Services::TypeCheckService
        attr_reader :assignment #: ::Steep::Services::PathAssignment
        attr_reader :mutex #: Mutex

        # @rbs steepfile_path: Pathname
        # @rbs return: void
        def initialize(steepfile_path:)
          @mutex = Mutex.new
          @project = load_project(steepfile_path)
          @type_check_service = ::Steep::Services::TypeCheckService.new(project: @project)
          @assignment = ::Steep::Services::PathAssignment.all
          @buffered_changes = {} #: Hash[Pathname, Array[::Steep::Services::ContentChange]]
        end

        # @rbs path: Pathname
        # @rbs changes: Array[::Steep::Services::ContentChange]
        # @rbs return: void
        def push_changes(path, changes)
          @mutex.synchronize do
            existing = @buffered_changes[path]
            unless existing
              existing = [] #: Array[::Steep::Services::ContentChange]
              @buffered_changes[path] = existing
            end
            existing.concat(changes)
          end
        end

        # @rbs return: Hash[Pathname, Array[::Steep::Services::ContentChange]]
        def flush_changes
          @mutex.synchronize do
            copy = @buffered_changes.dup
            @buffered_changes.clear
            copy
          end
        end

        # @rbs return: void
        def apply_changes
          changes = flush_changes
          type_check_service.update(changes: changes) unless changes.empty?
        end

        # @rbs path: Pathname
        # @rbs return: ::Steep::Project::Target?
        def target_for_path(path)
          project.target_for_inline_source_path(path) ||
            project.target_for_source_path(path) ||
            project.target_for_signature_path(path)
        end

        # @rbs target_name: Symbol
        # @rbs return: ::Steep::Services::SignatureService?
        def signature_service_for(target_name)
          type_check_service.signature_services[target_name]
        end

        private

        # @rbs steepfile_path: Pathname
        # @rbs return: ::Steep::Project
        def load_project(steepfile_path)
          path = steepfile_path.expand_path
          ::Steep::Project.new(steepfile_path: path).tap do |project|
            ::Steep::Project::DSL.parse(project, path.read, filename: path.to_s)
          end
        end
      end
    end
  end
end
