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
  # Intent 363 emptied PLASTIC.md of doctrine. It is now a one-page pointer at the
  # `plastic` command line (ruling D43), so the content pins that used to live here
  # were deleted rather than rewritten. The doctrine they guarded now lives in the
  # docs/help chapters `plastic help TOPIC` prints (intent 372, family 4). The
  # tutorial and conventions skills' own routing SKILL.md files carried no doctrine
  # of their own (family 4 disposition: "dropped"), so they left no chapter behind.

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
  # skills/intent-continuing/references/boarding-matrix.md dropped from this list by intent
  # 372 (family 2): intent-continuing moved into `plastic continue`, a command; its file
  # is gone.
  PROSE_FILES_MUST_NOT_SAY_DONE = %w[
    templates/agents.md
    docs/help/completion-and-done.md
    docs/help/locks-and-worktrees.md
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

# Row 5.2 - both tutorial tracks walk create, graph, runner step, end -
# never the old consolidate-the-spec / plan.md-and-checklist ceremony.
def test_tutorial_tracks_walk_the_runner_loop
  track1 = read("docs/help/track-1-guided.md")
  track2 = read("docs/help/track-2-auto.md")

  [track1, track2].each do |content|
    assert_match(/graph\.md/, content, "must name graph.md")
  end

  assert_match(/runner\s+step/i, track1, "track 1 must walk runner step")
  refute_match(/Consolidate the spec/i, track1,
               "track 1 must not walk the retired consolidate-the-spec station")
  refute_match(/###\s*\d+\.\s*Done\b/, track1,
               "track 1 must not name a station \"Done\"")
  assert_match(/###\s*\d+\.\s*End\b/, track1, "track 1 must name an End station")

  refute_match(/Auto owns How \(the plan, the checklist, the action files\)/, track2,
               "track 2 must not describe Auto's How as plan/checklist/action files any more")
end

# Row 5.3 - the retired "Done" alias names no state or stage anywhere in the
# shipped skills/templates tree or PLASTIC.md, outside a backtick-quoted
# literal ledger token. scripts/ is out (doctor.rb messages are pinned by
# test/doctor_done_signals_test.rb).
def test_done_alias_absent_from_whole_shipped_tree
  targets = Dir.glob(File.join(REPO, "skills", "**", "*")).select { |f| File.file?(f) } +
            Dir.glob(File.join(REPO, "templates", "**", "*")).select { |f| File.file?(f) } +
            [File.join(REPO, "PLASTIC.md")]

  offenders = []
  targets.each do |path|
    content = File.read(path)
    stripped = content.gsub(/`[^`]*`/, "")
    offenders << path.sub("#{REPO}/", "") if stripped.match?(/\bDone\b/)
  end

  assert_empty offenders.uniq,
               "these files still name the retired \"Done\" state/stage outside backticks: " \
               "#{offenders.uniq.join(", ")}"
end
end
