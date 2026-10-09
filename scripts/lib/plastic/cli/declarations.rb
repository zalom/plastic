# frozen_string_literal: true

require_relative "../invalid"
require_relative "command/argument"
require_relative "command/option"

module Plastic
  class CLI
    # The words a command's class body declares itself with: what the tool
    # takes, what it works on, and which graphs it reads and writes.
    module Declarations
      GRAPHS = %i[work knowledge retrieval references].freeze
      PRINTS = %i[intent roadmap index].freeze
      OPTION_DEFAULTS = { repeatable: false, required: false }.freeze

      # The arguments that name the thing a call works on, such as the
      # intent id and the node id. A tool that writes keeps one open routine
      # run per subject (see RoutineRun).
      def subject(*names)
        @subject = names if names.any?
        @subject
      end

      # The intent a call works on, as its subject and its first argument.
      def intent_subject
        subject :intent_id
        argument :intent_id, label: "ID", text: "the intent"
      end

      # One node of an intent, as its subject and its first two arguments.
      def node_subject
        intent_subject
        subject :intent_id, :id
        argument :id, label: "NODE", text: "the node"
      end

      # One word the tool takes, as `argument :id, label: "ID", text: "the intent"`.
      # Add `rest: true` to take every word left, `optional: true` to allow none.
      def argument(name, **shape) = arguments << Command::Argument.new(name:, rest: false, optional: false, **shape)

      # One switch the tool takes, as `option :dir, switch: "--dir DIR", text: "where"`,
      # with `default:` for its value when the call leaves it out.
      def option(name, **shape)
        options << Command::Option.new(name:, **OPTION_DEFAULTS.merge(default: shape[:repeatable] ? [] : nil, **shape))
      end

      # Which graphs the tool reads or writes. Every read goes through the
      # retrieval graph; `reads :work` names the records it reads.
      def reads(*graphs) = graphs_for(:@reads, graphs)

      def writes(*graphs) = graphs_for(:@writes, graphs)

      # Which files the tool prints after it writes: `prints :intent` for the
      # intent it worked on, `:roadmap` for the roadmap, `:index` for store/index.json.
      def prints(*kinds)
        unknown = kinds - PRINTS
        raise Invalid, "#{name}: unknown print #{unknown.join(", ")}" if unknown.any?

        (@prints ||= []).concat(kinds)
      end

      # Marks a tool that opens no graph, so it runs in a home with no store.
      def graphless = (@graphless = true)

      def graphless? = @graphless == true

      def arguments = (@arguments ||= [])

      def options = (@options ||= [])

      # The names of every argument and option.
      def declared_names = (arguments + options).map(&:name)

      # The first words TABLE gives this class. A class that runs under
      # several names, such as Group, is told its words by CLI.call.
      def tool_name(table = TABLE)
        table.find { |_name, (klass, _summary)| klass == name.delete_prefix("Plastic::") }&.first
      end

      def usage_line(tool = tool_name) = ["plastic", tool, *(arguments + options).map(&:usage)].join(" ")

      private

      def graphs_for(variable, graphs)
        unknown = graphs - GRAPHS
        raise Invalid, "#{name}: unknown graph #{unknown.join(", ")}" if unknown.any?

        list = instance_variable_get(variable) || instance_variable_set(variable, [])
        list.concat(graphs)
      end
    end
  end
end
