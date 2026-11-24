# frozen_string_literal: true

require "json"
require_relative "../layout"
require_relative "../store_layout"
require_relative "shell_writes"

module Plastic
  module Hooks
    # Whether the guard refuses one tool call of an agent, and why. The call is refused when it writes a file of a
    # store that is not in the resources folder of an open intent, or an intent record in the project tree. The paths
    # come from the file tools, from a patch, or from the write forms of a shell command.
    class GuardVerdict
      FILE_TOOLS = %w[Write Edit MultiEdit NotebookEdit].freeze
      FILE_KEYS = %i[file_path notebook_path path].freeze
      PATCH = /^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$/
      CLOSED = %w[done abandoned].freeze
      SAID = {
        record: "%{path} is an intent record in the project tree; intents live in the store, and plastic intent new makes one.",
        store: "%{path} belongs to the store, and only Plastic commands write it.",
        folder: "%{path} is in a folder that no intent owns; plastic intent new makes an intent folder.",
        closed: "%{path} belongs to a closed intent: intent %{id} is %{status}, and it keeps its files.",
        core: "%{path} is in an intent folder, and %{writer}.",
        open: "Only the resources/ folder of an open intent is open to the agent."
      }.freeze

      def initialize(home:, cwd:, user_home: Dir.home)
        @home = home
        @cwd = cwd
        @user_home = user_home
        @intents = {}
      end

      # The paths one tool call writes: the file of a file tool, the files of a patch, or the write forms of a shell
      # command.
      def self.paths(tool, input)
        return input.values_at(*FILE_KEYS).compact.map(&:to_s) if FILE_TOOLS.include?(tool)

        text = Array(input[:command] || input[:input] || input[:patch]).join(" ")
        text.include?("*** Begin Patch") ? text.scan(PATCH).flatten.map(&:strip) : ShellWrites.paths(text)
      end

      # Who writes the file at `rel` inside an intent folder, in words.
      def self.writer(rel)
        named = Layout.files.find { |entry| entry.name == rel }&.writer
        return "only Plastic commands write files there" unless named

        (named == "rows") ? "Plastic prints it from the database rows" : "only #{named} writes it"
      end

      # The reason the call is refused, or nil when it passes.
      def reason(tool, input)
        paths = self.class.paths(tool, Hash(input).transform_keys(&:to_sym))
        found = paths.filter_map { |path| absolute(path) }.lazy.filter_map { |full| refusal(full) }.first
        found && "Plastic: #{found} #{SAID.fetch(:open)}"
      end

      private

      def absolute(word)
        expanded = word.sub(%r{\A(?:~|\$HOME|\$\{HOME\})(?=/|\z)}, @user_home).sub(%r{\A\$\{?PLASTIC_HOME\}?(?=/|\z)}, @home)
        File.expand_path(expanded, @cwd)
      rescue ArgumentError
        nil
      end

      def refusal(path)
        return said(:record, path:) if Layout.project_records.any? { |folder| path.include?("/#{folder}") }

        root = store_root(path)
        root && store_refusal(root, path)
      end

      # The store folder that holds `path`, or nil.
      def store_root(path)
        base = StoreLayout.projects_root(@home)
        return File.join(base, path.delete_prefix("#{base}/").split("/").first) if path.start_with?("#{base}/")

        global = StoreLayout.global_root(@home)
        global if path.start_with?(File.join(global, "store", ""))
      end

      def store_refusal(root, path)
        parts = path.delete_prefix("#{root}/").split("/")
        return said(:store, path:) unless parts.first == "store" && parts.size > 2

        intent_refusal(intents(root)[parts[1]], parts.drop(2), path)
      end

      def intent_refusal(intent, inside, path)
        return said(:folder, path:) unless intent

        status = intent["status"]
        return said(:closed, path:, id: intent["intent_id"], status:) if CLOSED.include?(status)

        said(:core, path:, writer: self.class.writer(inside.join("/"))) unless inside.first == Layout.resources_root && inside.size > 1
      end

      # The intents of the store at `root` by folder name, read from store/index.json once.
      def intents(root)
        @intents[root] ||= JSON.parse(File.read(File.join(root, "store", "index.json"))).fetch("intents", [])
          .to_h { |row| [Layout.folder_name(row["intent_id"], row["slug"]), row] }
      rescue SystemCallError, JSON::ParserError
        @intents[root] = {}
      end

      def said(key, **values) = format(SAID.fetch(key), **values)
    end
  end
end
