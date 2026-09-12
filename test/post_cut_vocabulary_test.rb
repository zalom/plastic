# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Intent 341 (G8 ceremony cut), node n4: the shipped templates, doctor messages, and
# tutorial speak the same post-cut vocabulary the lifecycle skills already do (n1, n6).
# The cycle is What -> Why -> How -> Exec; completion is the End tail (delivered or
# abandoned), never a fifth stage called "Done". Plan review is optional, never a
# required step. A graph intent (D1, no ceremonies) is judged on graph.md and nodes/,
# never dinged for a missing spec.md/plan.md/checklist.md.
class PostCutVocabularyTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  def read(rel) = File.read(File.join(REPO, rel))

  # Row 4.1
  def test_plastic_md_template_names_runner_loop
    content = read("scripts/lib/installer_core.rb")
    body = content[/CODEX_AGENTS_MD_BODY = <<~MD\.freeze\n(.*?)\n\s*MD\n/m, 1]
    refute_nil body, "CODEX_AGENTS_MD_BODY heredoc not found in installer_core.rb"

    assert_match(/\bdirect\b/i, body, "the template should name the direct mode")
    assert_match(/\bthinking\b/i, body, "the template should name the thinking mode")
    assert_match(/\bauto\b/i, body, "the template should name the auto mode")
    assert_match(/runner/i, body, "the template should point at the runner loop")
    assert_match(/\bstep\b/i, body, "the template should name the runner's step verb")

    refute_match(/moved through What.*Why.*How.*Exec/mi, body,
                 "the template should not teach the five-stage ladder any more")
  end

  # Row 4.2 - templates, skills, and doctor MESSAGES never call the terminal state "Done"
  # (parser code that reads real `Done delivered|abandoned` ledger lines stays untouched:
  # scripts/lib/savepoint.rb, scripts/lib/index_projection.rb, scripts/append-ledger).
  PROSE_FILES_MUST_NOT_SAY_DONE = %w[
    templates/agents.md
    skills/conventions/references/completion-and-done.md
    skills/conventions/references/locks-and-worktrees.md
    skills/intent-continuing/references/boarding-matrix.md
    skills/auto/SKILL.md
    skills/auto/references/human-report-contract.md
  ].freeze

  def test_done_alias_absent_from_shipped_tree
    PROSE_FILES_MUST_NOT_SAY_DONE.each do |rel|
      content = read(rel)
      refute_match(/\bDone\b/, content, "#{rel} still names the retired \"Done\" alias")
    end

    # The savepoint_operational and backfilled_complete "Done delivered|abandoned"/"Done
    # echo" message text is pinned verbatim by test/doctor_done_signals_test.rb (outside
    # n4's files), which must keep working: those two message families are left as they
    # are. Only the instances a pinned test does not depend on are cut here.
    doctor = read("scripts/doctor.rb")
    [
      /last Done line says/,
      /manual Done-bookend repair/,
    ].each do |pattern|
      refute_match(pattern, doctor, "scripts/doctor.rb still shows a \"Done\" message: #{pattern.inspect}")
    end
  end

  # Row 4.3 - the plan review is optional everywhere it is named, never required.
  PLAN_REVIEW_FILES = %w[
    skills/auto/SKILL.md
    skills/auto/references/agent-architecture.md
  ].freeze

  def test_plan_review_not_required_anywhere
    combined = PLAN_REVIEW_FILES.map { |rel| read(rel) }.join("\n---\n")
    sentences = combined.split(/(?<=[.:])\s+/)
    plan_review_sentences = sentences.select { |s| s =~ /plan review/i }

    refute_empty plan_review_sentences, "no sentence names the plan review"
    assert(plan_review_sentences.any? { |s| s =~ /optional/i },
           "no sentence naming the plan review calls it optional:\n#{plan_review_sentences.join("\n")}")

    refute_match(/plan review(er)? is required/i, combined)
    refute_match(/must dispatch the plan review/i, combined)
    refute_match(/is a required step/i, combined)

    # The pinned literal other tests depend on must survive the reword.
    assert_includes read("skills/auto/SKILL.md"), "plan-reviewer-prompt.md"
  end

  # Row 4.5 - the tutorial's auto track names the same four stations the runner loop
  # actually walks: create the intent, write graph.md, drive it with runner step, end.
  def test_tutorial_walks_the_runner_loop
    content = read("skills/tutorial/SKILL.md")
    auto_bullet = content[/\d+\.\s*\*\*Auto\*\*:(.*?)(?=\n\d+\.|\n\n)/m, 1]
    refute_nil auto_bullet, "no Auto bullet found in skills/tutorial/SKILL.md"

    assert_match(/create/i, auto_bullet)
    assert_match(/graph/i, auto_bullet)
    assert_match(/runner\s*step/i, auto_bullet)
    assert_match(/\bend\b/i, auto_bullet)
  end
end
