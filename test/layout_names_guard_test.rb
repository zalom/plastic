# frozen_string_literal: true

require "minitest/autorun"
require "ripper"
require "yaml"

# A rule about the files of this repository: only lib/plastic/layout.yml and its reader name a core file of an
# intent folder or a path inside resources/. Any other code asks Plastic::Layout. A string literal that is exactly
# such a name is refused; a sentence that mentions a file name stays allowed.
class LayoutNamesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LAYOUT = YAML.safe_load_file(File.join(ROOT, "lib/plastic/layout.yml"))
  OLD_NAMES = %w[savepoint.md plan.md checklist.md revisions.md graph.md handoff.md].freeze
  NAMES = (LAYOUT.fetch("files").values.map { |entry| entry.fetch("name") } + OLD_NAMES).freeze
  OWNERS = [File.join(ROOT, "lib/plastic/layout.rb"), File.join(ROOT, "lib/plastic/layout/")].freeze

  # The string parts of Ruby `source` that name a core file or a resources path: the whole literal, or one word of a %w list.
  def self.naming(source) = Ripper.lex(source).filter_map { |(_position, kind, text)| text if kind == :on_tstring_content && named?(text) }

  def self.named?(text) = NAMES.include?(text) || text.start_with?("resources/")

  def self.sources = Dir[File.join(ROOT, "lib/**/*.rb")].reject { |path| OWNERS.any? { |owner| path.start_with?(owner) } }.sort

  def test_the_scan_reads_files_from_the_disk
    refute_empty self.class.sources
  end

  def test_the_detector_catches_a_file_name_and_a_resources_path
    assert_equal ["spec.md", "resources/tmp/"], self.class.naming(%(a = "spec.md"\nb = 'resources/tmp/'\n))
  end

  def test_the_detector_leaves_a_sentence_alone
    assert_empty self.class.naming(%(say "Write the done criteria in spec.md and run plastic sync up."))
  end

  def test_no_code_outside_the_layout_names_a_core_file_or_a_resources_folder
    found = self.class.sources.to_h { |path| [path.delete_prefix("#{ROOT}/"), self.class.naming(File.read(path))] }.reject { |_path, names| names.empty? }

    assert_empty found, "ask Plastic::Layout instead of naming these files: #{found}"
  end
end
