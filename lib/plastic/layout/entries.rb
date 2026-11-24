# frozen_string_literal: true

module Plastic
  module Layout
    # A heading of a core file, with the older names a reader still accepts.
    Heading = Data.define(:name, :aliases) do
      def names = [name, *aliases]

      # A pattern for a Markdown heading line of any level that carries one of the names.
      def pattern = /\A#+\s*(?:#{names.map { |word| Regexp.escape(word) }.join("|")})\s*\z/i
    end

    # A core file of an intent folder: what it is for, the states that require it and who writes it.
    CoreFile = Data.define(:role, :name, :purpose, :required, :writer, :front_matter, :headings) do
      def self.from(role, data)
        new(role:, name: data.fetch("name"), purpose: data.fetch("purpose"), required: data.fetch("required"),
          writer: data.fetch("writer"), front_matter: data.fetch("front_matter", []),
          headings: data.fetch("headings", []).map { |heading| Layout::Entries.heading(heading) })
      end

      def required_in?(state) = required.include?(state)
    end

    # A folder under resources/, with what a sync does with its files.
    ResourceFolder = Data.define(:role, :path, :purpose, :sync)

    # A file or folder of an older layout: how a sync treats it, what a repair does with it and where it goes.
    LegacyEntry = Data.define(:name, :match, :sync, :repair, :to, :why) do
      def self.from(data)
        new(name: data.fetch("name"), match: data.fetch("match"), sync: data.fetch("sync"), repair: data.fetch("repair"),
          to: data["to"], why: data.fetch("why"))
      end

      def match?(rel) = match.any? { |glob| File.fnmatch?(glob, rel, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB) }

      # Where `rel` goes on a repair that moves it: the target folder or file, with the rest of the path kept.
      def destination(rel)
        return unless repair == "move"

        to.end_with?("/") ? "#{to}#{rel.delete_prefix(folder_prefix)}" : to
      end

      private

      def folder_prefix = name.end_with?("/") ? name : ""
    end

    # An entry of the store root: a name and what it is for, or the repair of an old one.
    RootEntry = Data.define(:name, :purpose, :repair, :why)

    module Entries
      def self.heading(data)
        data.is_a?(Hash) ? Heading.new(name: data.fetch("name"), aliases: data.fetch("aliases", [])) : Heading.new(name: data, aliases: [])
      end

      def self.root_allowed(list) = list.map { |data| RootEntry.new(name: data.fetch("name"), purpose: data.fetch("purpose"), repair: nil, why: nil) }

      def self.root_legacy(list) = list.map { |data| RootEntry.new(name: data.fetch("name"), purpose: nil, repair: data.fetch("repair"), why: data.fetch("why")) }
    end
  end
end
