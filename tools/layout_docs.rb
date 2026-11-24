# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)).uniq!
require "plastic/layout"

# Builds the intent folder section of PLASTIC.md and the page docs/help/intent-folder.md from lib/plastic/layout.yml.
module LayoutDocs
  ROOT = File.expand_path("..", __dir__)
  START = "<!-- layout:start -->"
  FINISH = "<!-- layout:end -->"
  PAGE = File.join(ROOT, "docs/help/intent-folder.md")
  PLASTIC = File.join(ROOT, "PLASTIC.md")

  def self.names(files) = files.map { |entry| "`#{entry.name}`" }.join(", ")

  def self.code(list) = list.map { |item| "`#{item}`" }.join(", ")

  # The short section of PLASTIC.md.
  def self.section
    printed, written = Plastic::Layout.files.partition { |entry| entry.writer == "rows" }
    folders = Plastic::Layout.resource_folders.map { |folder| "`#{folder.path.delete_prefix("resources/").chomp("/")}`" }.join(", ")
    <<~TEXT.chomp
      #{START}
      Intent folder `store/#{Plastic::Layout.folder_template}/`: #{names(written)}, printed #{names(printed)}, and `#{Plastic::Layout.resources_root}/` (#{folders}).
      Sync up names any other file: `plastic help intent-folder`.
      #{FINISH}
    TEXT
  end

  def self.states(entry) = entry.required.empty? ? "never" : entry.required.join(", ")

  def self.headings(entry) = entry.headings.map { |heading| ([heading.name] + heading.aliases.map { |name| "#{name} (old)" }).join(" / ") }.join(", ")

  def self.core_rows
    Plastic::Layout.files.map do |entry|
      "| `#{entry.name}` | #{entry.purpose} | #{states(entry)} | #{entry.writer} |"
    end
  end

  def self.shape_lines
    Plastic::Layout.files.filter_map do |entry|
      parts = []
      parts << "front matter #{code(entry.front_matter)}" unless entry.front_matter.empty?
      parts << "headings #{headings(entry)}" unless entry.headings.empty?
      "- `#{entry.name}`: #{parts.join("; ")}." unless parts.empty?
    end
  end

  def self.resource_rows
    Plastic::Layout.resource_folders.map { |folder| "| `#{folder.path}` | #{folder.purpose} | #{folder.sync.tr("_", " ")} |" }
  end

  def self.legacy_rows
    Plastic::Layout.legacy.map { |entry| "| `#{entry.name}` | #{entry.sync.tr("_", " ")} | #{repair(entry)} | #{entry.why} |" }
  end

  def self.repair(entry) = entry.to ? "#{entry.repair} to `#{entry.to}`" : entry.repair

  def self.root_rows
    allowed = Plastic::Layout.store_root_allowed.map { |entry| "| `#{entry.name}` | allowed | #{entry.purpose} |" }
    allowed + Plastic::Layout.store_root_legacy.map { |entry| "| `#{entry.name}` | #{entry.repair} | #{entry.why} |" }
  end

  def self.store_folder_rows
    allowed = Plastic::Layout.store_folder_allowed.map { |entry| "| `store/#{entry.name}` | allowed | #{entry.purpose} |" }
    allowed + Plastic::Layout.store_folder_legacy.map { |entry| "| `store/#{entry.name}` | #{entry.repair.tr("_", " ")} | #{entry.why} |" }
  end

  def self.amendment_rows = Plastic::Layout.data.fetch("amendments").map { |kind, reason| "| #{kind} | #{reason} |" }

  # The page docs/help/intent-folder.md.
  def self.page = [intro, files_part, store_part, amendments_part].join("\n")

  def self.intro
    <<~TEXT
      # The intent folder

      This page is generated from `lib/plastic/layout.yml` by `ruby bin/layout-docs`. Change the layout file, not this page.

      A folder is named `#{Plastic::Layout.folder_template}` and made by `plastic intent new`. The slug takes up to #{Plastic::Layout.slug_words} words of the title and never changes. #{Plastic::Layout.folder.fetch("purpose")}

      An intent is in one of these states: #{Plastic::Layout.states.join(", ")}. An intent that is future, open, in progress or parked is open.

    TEXT
  end

  def self.files_part
    <<~TEXT
      ## Files

      | File | Purpose | Required in | Writer |
      | --- | --- | --- | --- |
      #{core_rows.join("\n")}

      Plastic prints a file whose writer is rows from the database rows, and the named commands write each other file. The agent writes no core file by hand.

      ## Shape of each file

      #{shape_lines.join("\n")}

      ## Resources

      #{Plastic::Layout.data.fetch("resources").fetch("purpose")}

      | Folder | Purpose | Sync |
      | --- | --- | --- |
      #{resource_rows.join("\n")}

      ## Files of an older layout

      `plastic store sync up` reads or skips each of these by the sync column, and any file that is neither here nor above is named as a stray. The repair column says what a repair of an older folder does.

      | Name | Sync | Repair | Why |
      | --- | --- | --- | --- |
      #{legacy_rows.join("\n")}

    TEXT
  end

  def self.store_part
    <<~TEXT
      ## The store folder

      #{Plastic::Layout.data.fetch("store_root").fetch("purpose")}

      | Name | Status | Purpose or repair |
      | --- | --- | --- |
      #{root_rows.join("\n")}

      #{Plastic::Layout.data.fetch("store_folder").fetch("purpose")}

      | Name | Status | Purpose or repair |
      | --- | --- | --- |
      #{store_folder_rows.join("\n")}
    TEXT
  end

  def self.amendments_part
    <<~TEXT
      ## Amendments

      `plastic intent repair` changes only the structure of a done or abandoned intent, never its work. Each change writes one `amended` line in the intent's work.log with the reason for its kind.

      | Change | Reason |
      | --- | --- |
      #{amendment_rows.join("\n")}
    TEXT
  end

  # PLASTIC.md with its section replaced, or with the section added after the first paragraph that names resources.
  def self.plastic_text(text = File.read(PLASTIC))
    return text.sub(/#{Regexp.escape(START)}.*?#{Regexp.escape(FINISH)}/m) { section } if text.include?(START)

    text.sub("and whether the result is a finding or code.\n") { |line| "#{line}\n#{section}\n" }
  end

  def self.build
    File.write(PAGE, page)
    File.write(PLASTIC, plastic_text)
  end
end
