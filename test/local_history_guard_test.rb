# frozen_string_literal: true

require "json"
require "minitest/autorun"

class LocalHistoryGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHIPPED = (JSON.parse(File.read(File.join(ROOT, "package.json"))).fetch("files") + ["README.md"]).freeze
  TEXT = /\.(?:md|rb|yml|yaml|json|sh|txt|css|html)\z|\A[^.]+\z/
  HISTORY = Regexp.union(
    /\bintents? \d{1,3}[a-z]?\d*\b/i,
    /\b(?:in|since|before|until) v?\d+\.\d+\b(?![.\d-])/,
    /\brul(?:ed|ing)\b[^.\n]{0,20}\b20\d\d-\d\d-\d\d\b/i,
    /\((?:owner ruling |ruling |decision )?D\d+r?\b|\b(?:ruling|decision) D\d+r?\b/,
    %r{/Users/[a-z]|/home/[a-z]+/}
  )
  FENCE = /^\s*```/

  def self.subjects
    SHIPPED.flat_map { |entry| File.directory?(File.join(ROOT, entry)) ? Dir[File.join(ROOT, entry, "**", "*")] : [File.join(ROOT, entry)] }
      .select { |path| File.file?(path) && File.basename(path).match?(TEXT) }
  end

  def history(text)
    fenced = false
    text.each_line.with_index(1).filter_map do |line, number|
      fenced = !fenced if line.match?(FENCE)
      "#{number}: #{line.strip}" if !fenced && line.match?(HISTORY)
    end
  end

  def test_the_subjects_are_read_from_the_disk
    paths = self.class.subjects

    refute_empty paths
    assert(paths.any? { |path| path.end_with?("agents/plastic-enforcer.md") })
    assert(paths.any? { |path| path.end_with?("scripts/lib/installer_core.rb") })
  end

  def test_no_shipped_file_carries_local_history
    found = self.class.subjects.to_h { |path| [path.delete_prefix("#{ROOT}/"), history(File.read(path))] }.reject { |_, lines| lines.empty? }

    assert_empty found
  end

  def test_the_detector_catches_an_intent_number
    refute_empty history("there is no stage agent (removed in\n2.0, intent 304): record")
  end

  def test_the_detector_catches_version_history
    refute_empty history("Nothing blocks a write in 2.0; the lock")
  end

  def test_the_detector_catches_a_ruling_date
    refute_empty history("Every verb prints the same Markdown (owner ruling 2026-08-31).")
  end

  def test_the_detector_catches_a_decision_id
    refute_empty history("one carrier that works everywhere (decision D1). The report")
  end

  def test_the_detector_catches_a_home_path
    refute_empty history("read /Users/someone/.plastic/stores")
  end

  def test_the_detector_leaves_a_version_string_alone
    assert_empty history("semver_compare(target, \"2.0.0-alpha.28\") >= 0")
  end

  def test_the_detector_leaves_a_fenced_example_alone
    assert_empty history("```bash\nplastic graph show 12   # The work graph of intent 12\n```\n")
  end

  def test_the_detector_leaves_a_ruling_placeholder_alone
    assert_empty history("- D1 <first ruling, as the owner gave it>")
  end

  def test_the_detector_leaves_the_ruling_command_alone
    assert_empty history("Write an owner ruling, with --supersedes to replace an older one")
  end
end
