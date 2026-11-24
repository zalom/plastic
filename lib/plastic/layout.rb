# frozen_string_literal: true

require "yaml"
require_relative "layout/entries"
require_relative "layout/problems"

module Plastic
  # The layout of an intent folder, read from layout.yml. Every command that works in an intent folder takes
  # its file names, folder paths, states and old names from here, and no other file of the kernel names a
  # core file or a resources folder. StoreLayout, a different class, says where the stores sit in the home.
  module Layout
    PATH = File.join(__dir__, "layout.yml")
    KINDS_READ = %w[document legacy_rows lines].freeze

    # The layout as parsed: a frozen Hash read once.
    def self.data = (@data ||= YAML.safe_load_file(PATH).freeze)

    # A list of what is wrong with the layout file, empty when it is sound.
    def self.problems = Problems.new(data).to_a

    def self.version = data.fetch("version")

    def self.states = data.fetch("states")

    def self.folder = data.fetch("folder")

    def self.slug_words = folder.fetch("slug_words")

    # The name of an intent folder: its id, two dashes and its slug.
    def self.folder_name(id, slug) = "#{id}--#{slug}"

    # The folder name as a template, such as {id}--{slug}.
    def self.folder_template = folder.fetch("name")

    # The core files, in the order the layout lists them.
    def self.files = data.fetch("files").map { |role, entry| CoreFile.from(role.to_sym, entry) }

    def self.file(role) = files.find { |entry| entry.role == role.to_sym } || raise(KeyError, "the layout has no #{role} file")

    # The name of the core file of `role`; with no role, the name of this module, as every module answers.
    def self.name(role = nil) = role ? file(role).name : super()

    def self.core_names = files.map(&:name)

    # Whether `rel` is a core file of an intent folder.
    def self.core?(rel) = core_names.include?(rel)

    # The core files that an intent in `state` must hold, in layout order.
    def self.required_in(state) = files.select { |entry| entry.required_in?(state) }

    def self.resources_root = data.fetch("resources").fetch("name")

    def self.resource_folders = data.fetch("resources").fetch("folders").map { |role, entry| ResourceFolder.new(role: role.to_sym, path: entry.fetch("path"), purpose: entry.fetch("purpose"), sync: entry.fetch("sync")) }

    # The path of a resources folder by its role: reports, files, references or tmp.
    def self.resource(role) = resource_folders.find { |entry| entry.role == role.to_sym }.path

    def self.resource_paths = resource_folders.map(&:path)

    # The folders whose files a sync reads by type: the reports and the files.
    def self.output_folders = resource_folders.select { |entry| entry.sync.then { |sync| %w[recorded by_type].include?(sync) } }.map(&:path)

    # Whether `rel` is a path inside one of the four resources folders.
    def self.sorted?(rel) = resource_paths.any? { |path| rel.start_with?(path) }

    def self.scratch = Regexp.new(data.fetch("resources").fetch("scratch"))

    def self.tmp_types = data.fetch("resources").fetch("tmp_types")

    def self.legacy = data.fetch("legacy").map { |entry| LegacyEntry.from(entry) }

    # The legacy entry that names `rel`, a path inside the intent folder, or nil.
    def self.legacy_for(rel) = legacy.find { |entry| entry.match?(rel) }

    # Whether a sync up reads `rel` as an older layout's file: the old intent file, the plan, the checklist,
    # the action files and an old savepoint.md.
    def self.legacy_read?(rel) = KINDS_READ.include?(legacy_sync(rel))

    # The sync word of the legacy entry that names `rel`, or nil.
    def self.legacy_sync(rel) = legacy_for(rel)&.sync

    # Whether a sync up reads `rel` into rows or documents: a core file or an older layout's file it still reads.
    def self.read?(rel) = core?(rel) || legacy_read?(rel)

    # The folder that holds the output folders, with a closing slash.
    def self.output_root = "#{File.dirname(resource(:files).chomp("/"))}/"

    # Whether `rel` is machine state a sync never reads and a sort never moves.
    def self.machine?(rel) = legacy_for(rel)&.sync == "skip" || File.basename(rel).match?(Regexp.new(data.fetch("machine").fetch("swept")))

    # Machine state of a store folder that no record holds: skipped when a sync lists the files.
    def self.skipped = Regexp.new(data.fetch("machine").fetch("skipped"))

    # Where the repair of the legacy entry that names `rel` moves or renames it, or nil.
    def self.destination(rel) = legacy_for(rel)&.destination(rel)

    def self.store_root_allowed = Entries.root_allowed(data.fetch("store_root").fetch("allowed"))

    def self.store_root_legacy = Entries.root_legacy(data.fetch("store_root").fetch("legacy"))

    # What the folder store/ of a store folder may hold beside its intent folders.
    def self.store_folder_allowed = Entries.root_allowed(data.fetch("store_folder").fetch("allowed"))

    # The leftovers of the folder store/ that a repair removes.
    def self.store_folder_legacy = Entries.root_legacy(data.fetch("store_folder").fetch("legacy"))

    # The reason an `amended` work log line gives for a kind of change: rename, move, remove, revision or link.
    def self.amendment_reason(kind) = data.fetch("amendments").fetch(kind.to_s)
  end
end
