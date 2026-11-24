# frozen_string_literal: true

require "minitest/autorun"
require "ripper"
require "yaml"
require_relative "../lib/plastic/graph/migration/store_migration"

# A rule about the files of this repository: only lib/plastic/layout.yml and its reader name a core file of an
# intent folder or a path inside resources/. Any other code asks Plastic::Layout. A string literal that is exactly
# such a name is refused, and so is a path built around one: the part after an interpolation, such as
# "#{intent.dir}/graph.json", a glob, such as "store/*/spec.md", and a quoted path inside SQL. A sentence that mentions
# a file name stays allowed. The data steps of the migrations are left alone: each states the layout of its own
# version and never changes (ruling of 24 November 2026).
class LayoutNamesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LAYOUT = YAML.safe_load_file(File.join(ROOT, "lib/plastic/layout.yml"))
  OLD_NAMES = %w[savepoint.md plan.md checklist.md revisions.md graph.md handoff.md].freeze
  NAMES = (LAYOUT.fetch("files").values.map { |entry| entry.fetch("name") } + OLD_NAMES).freeze
  RESOURCES = LAYOUT.fetch("resources")
  # A path part `resources` followed by one of its folders, such as resources/tmp/ or store/*/resources/output/.
  RESOURCE_PATH = %r{(?:\A|/)#{RESOURCES.fetch("name")}/(?:#{RESOURCES.fetch("folders").values.map { |entry| entry.fetch("path").split("/")[1] }.uniq.join("|")})(?:/|\z)}
  QUOTED = /'([^'\s]+)'/
  OWNERS = [File.join(ROOT, "lib/plastic/layout.rb"), File.join(ROOT, "lib/plastic/layout/")].freeze
  DATA_STEPS = Plastic::Graph::StoreMigration::DATA_STEPS.values.map { |step| Object.const_source_location(step.name).first }.uniq.freeze

  # The string parts of Ruby `source` that name a core file or a resources path: the whole literal, one word of a %w
  # list, or the path inside one.
  def self.naming(source) = Ripper.lex(source).flat_map { |(_position, kind, text)| (kind == :on_tstring_content) ? named_parts(text) : [] }

  def self.named?(text) = NAMES.include?(text) || text.start_with?("resources/")

  # The whole of `text` when it names a file, or else each path in it that names one: `text` itself when it holds no
  # space, and each quoted word when it does.
  def self.named_parts(text)
    return [text] if named?(text)

    (text.match?(/\s/) ? text.scan(QUOTED).flatten : [text]).select { |part| path_named?(part) }
  end

  def self.path_named?(part) = part.include?("/") && (part.split("/").any? { |piece| NAMES.include?(piece) } || part.match?(RESOURCE_PATH))

  def self.sources = Dir[File.join(ROOT, "lib/**/*.rb")].reject { |path| OWNERS.any? { |owner| path.start_with?(owner) } || DATA_STEPS.include?(path) }.sort

  def test_the_scan_reads_files_from_the_disk
    refute_empty self.class.sources
  end

  def test_the_scan_leaves_the_data_steps_of_the_migrations_alone
    refute_empty DATA_STEPS
    assert_empty DATA_STEPS & self.class.sources
  end

  def test_the_detector_catches_a_file_name_and_a_resources_path
    assert_equal ["spec.md", "resources/tmp/"], self.class.naming(%(a = "spec.md"\nb = 'resources/tmp/'\n))
  end

  def test_the_detector_catches_a_name_after_an_interpolation
    assert_equal ["/graph.json"], self.class.naming("path = \"\#{intent.dir}/graph.json\"")
  end

  def test_the_detector_catches_a_glob
    assert_equal ["store/*/spec.md"], self.class.naming('Dir["store/*/spec.md"]')
  end

  def test_the_detector_catches_a_quoted_path_inside_sql
    sql = %(SQL = "SELECT path FROM printed WHERE path GLOB 'store/*/resources/output/reports/*'")

    assert_equal ["store/*/resources/output/reports/*"], self.class.naming(sql)
  end

  def test_the_detector_leaves_a_sentence_alone
    assert_empty self.class.naming(%(say "Write the done criteria in spec.md and run plastic store sync up."))
  end

  def test_the_detector_leaves_a_sentence_that_names_a_resources_folder_alone
    assert_empty self.class.naming(%(say "move the file to resources/tmp/ instead of deleting it"))
  end

  def test_the_detector_leaves_a_ruby_folder_named_resources_alone
    assert_empty self.class.naming(%(require_relative "../../knowledge/resources/row_moves"))
  end

  def test_no_code_outside_the_layout_names_a_core_file_or_a_resources_folder
    found = self.class.sources.to_h { |path| [path.delete_prefix("#{ROOT}/"), self.class.naming(File.read(path))] }.reject { |_path, names| names.empty? }

    assert_empty found, "ask Plastic::Layout instead of naming these files: #{found}"
  end
end
