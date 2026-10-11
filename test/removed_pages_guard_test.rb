# frozen_string_literal: true

require "minitest/autorun"

class RemovedPagesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SUBJECTS = %w[README.md AGENTS.md CONTRIBUTING.md INSTALL.md SECURITY.md PLASTIC.md docs/**/*.md agents/*.md scripts/**/*.rb bin/**/*.rb hooks/*].freeze
  REMOVED = {
    "docs/internals.md" => /(?<![\w-])internals\.md/,
    "docs/help/human-report-contract.md" => /human-report-contract/,
    "docs/help/maintenance-and-revisions.md" => /maintenance-and-revisions/,
    "docs/guide/getting-started/migrate-command.md" => /migrate-command/,
    "docs/skill-authoring.md" => /skill-authoring/,
    "docs/adr/index.md" => %r{\(adr/|docs/adr\b}
  }.freeze

  def subjects = Dir.glob(SUBJECTS, base: ROOT).select { |path| File.file?(File.join(ROOT, path)) }.sort

  def removed_names(text) = REMOVED.select { |_, name| text.match?(name) }.keys

  def offenses
    subjects.to_h { |path| [path, removed_names(File.read(File.join(ROOT, path)))] }.reject { |_, names| names.empty? }
  end

  def test_the_subjects_are_read_from_the_disk
    assert_includes subjects, "docs/contributing/ARCHITECTURE.md"
    assert_includes subjects, "scripts/lib/plastic.rb"
  end

  def test_every_removed_page_is_gone
    assert_empty(REMOVED.keys.select { |page| File.exist?(File.join(ROOT, page)) })
  end

  def test_no_subject_names_a_removed_page
    assert_empty offenses
  end

  def test_the_detector_catches_a_link_to_a_removed_page
    assert_equal ["docs/internals.md"], removed_names("See [internals](internals.md) for depth.")
  end

  def test_the_detector_leaves_a_current_page_alone
    assert_empty removed_names("See [the architecture](docs/contributing/ARCHITECTURE.md).")
  end
end
