# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Intent 308 subtraction and contract pins. end-intent's exit 2 and exit 6 retired, the
# scaffold-intent per-file verbs retired, no live reference to the removed 1.x gate in
# the skills tree, and the two contracts the review asked to pin (the end-intent header
# and the OutcomeGuard comment). Literal names below carry a removal note on their line so
# test/gates_removed_test.rb's own scan reads them as notes, not live references.
class Backfill308Test < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  REMOVAL_NOTE = /removed in 2\.0|retired in 2\.0/.freeze
  SCAN_ROOTS = %w[scripts skills docs/internals.md docs/architecture.md docs/reference AGENTS.md].freeze
  REMOVED_NAMES = [
    "scaffold_spec", # removed in 2.0 (intent 308)
    "scaffold_checklist", # removed in 2.0 (intent 308)
    "scaffold_outcome", # removed in 2.0 (intent 308)
    "extract_acceptance_criteria", # removed in 2.0 (intent 308)
    "refuse_without_force", # removed in 2.0 (intent 308)
    "Bridge.check_gate", # removed in 2.0 (intent 307/308)
    "scaffold-intent spec", # removed in 2.0 (intent 308)
    "scaffold-intent outcome", # removed in 2.0 (intent 308)
    "scaffold-intent checklist", # removed in 2.0 (intent 308)
  ].freeze

  def files_under(root)
    path = File.join(REPO, root)
    return [path] if File.file?(path)

    Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) && f !~ %r{/(node_modules|\.git)/} }
  end

  def test_no_live_reference_to_a_removed_name_outside_the_removal_notes
    hits = []
    SCAN_ROOTS.flat_map { |r| files_under(r) }.each do |file|
      File.foreach(file).with_index(1) do |line, no|
        next if line.match?(REMOVAL_NOTE)

        name = REMOVED_NAMES.find { |n| line.include?(n) }
        hits << "#{file.sub("#{REPO}/", "")}:#{no}: #{name}" if name
      end
    rescue ArgumentError
      next # binary file
    end
    assert_empty hits, "live references to removed names:\n#{hits.join("\n")}"
  end

  def test_end_intent_no_longer_exits_2_or_6_and_says_so_in_its_header
    script = File.read(File.join(REPO, "scripts", "end-intent"))
    refute_match(/^\s+exit [26]\b/, script, "end-intent must not exit 2 or 6 anywhere")
    assert_match(/^#   2  retired in 2\.0 \(intent 308\)/, script)
    assert_match(/^#   6  retired in 2\.0 \(intent 308\)/, script)
    refute_match(/run_structure_gate/, script)
    assert_match(/def run_backfill\(/, script)
    assert_match(/def run_structure_check\(/, script)
  end

  def test_outcome_guard_comment_names_its_two_callers_and_no_block
    lib = File.read(File.join(REPO, "scripts", "lib", "outcome_guard.rb"))
    assert_match(/post-backfill self-check/, lib)
    assert_match(/nothing blocks on it/, lib)
    refute_match(/exit-2 path/, lib)
  end

  def test_skills_no_longer_describe_the_write_time_gate
    skill = File.read(File.join(REPO, "skills", "intent-ending", "SKILL.md"))
    refute_match(/write-time hook/, skill)
    refute_match(/exit 6/, skill.gsub(/.*retired in 2\.0.*\n/, ""))
    assert_match(/backfill/i, skill)
  end
end
