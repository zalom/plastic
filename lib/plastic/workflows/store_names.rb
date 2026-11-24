# frozen_string_literal: true

require "shellwords"
require_relative "../errors"
require_relative "../scope"

module Plastic
  module Workflows
    # The stores a call reads when it takes --stores: each a registered project or global, in the order named, or the
    # call's own store when it names none. A command for a store other than the call's own carries --project.
    module StoreNames
      # Refuses --stores together with --project: the stores are named once.
      def refuse_project(context)
        raise Usage, "--stores names the stores; --project does not apply" if context.stores && context.scope.requested?
      end

      def store_slugs(context)
        stores = context.stores
        stores ? named(context, stores) : [context.scope.slug]
      end

      def named(context, stores)
        names = stores.split(",").map(&:strip).uniq
        raise Usage, "name at least one store after --stores" if names.empty?

        names.each { |name| refuse_unregistered(context.scope, name) }
      end

      def refuse_unregistered(scope, name)
        projects = scope.projects
        return if name == Scope::GLOBAL || projects.key?(name)

        raise Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}"
      end

      # The command as the call's own store runs it: with --project when `slug` is another store.
      def in_store(scope, command, slug)
        return command if slug == scope.slug || command.include?("--project")

        "#{command} --project #{Shellwords.escape(slug)}"
      end
    end
  end
end
