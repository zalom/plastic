# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Doctrine305Test (intent 305): the core doctrine block and the docs around it
# describe the 2.0 model (two modes plus auto, the record, the day ledger, the
# session pointer) and none of the gates intent 302 removed. Static and
# hermetic: it reads the repo tree and asserts on prose; it writes nothing.
#
# The byte, line, and token ceilings on PLASTIC.md live in
# test/plastic_core_budget_test.rb (tightened in the same change, the intent
# 223 rule); this file pins content, not size.
class Doctrine305Test < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PLASTIC_MD = File.join(ROOT, "PLASTIC.md")
  ADAPTERS = File.join(ROOT, "docs", "reference", "harness-adapters.md")
  GUIDES = File.join(ROOT, "docs", "guides")
  OLD_GUIDE = "what-the-gates-are-telling-you"
  NEW_GUIDE = File.join(GUIDES, "reading-the-ledgers.md")
  CHAPTERS = %w[locks-and-worktrees.md maintenance-and-revisions.md].map do |name|
    File.join(ROOT, "skills", "conventions", "references", name)
  end
  EXECUTING = File.join(ROOT, "skills", "intent-executing", "SKILL.md")
  PICK_MODE = File.join(GUIDES, "pick-your-mode.md")

  REMOVAL_NOTE = /removed in 2\.0|retired in 2\.0|left with the gates|no longer|not yet/i.freeze
  RETIRED_HOOK_NAMES = %w[
    lock-gate code-gate links-gate create-gate bash-gate gate-check savepoint-pre edit-gates
  ].freeze

  def read(path)
    File.read(path)
  end

  def normalized(path)
    read(path).gsub(/\s+/, " ")
  end

  def relative(path)
    path.sub("#{ROOT}/", "")
  end

  # --- PLASTIC.md ------------------------------------------------------------

  def test_plastic_md_has_no_gates_or_tiers_heading
    body = read(PLASTIC_MD)
    refute_match(/^## .*Transition Gates/, body, "the Transition Gates section must be gone")
    refute_match(/^## .*Tiers/, body, "the Tiers section must be gone")
  end

  def test_plastic_md_never_mentions_a_gate
    hits = read(PLASTIC_MD).lines.each_with_index.select { |l, _| l.match?(/\bgates?\b/i) }
    assert_empty hits.map { |l, i| "#{i + 1}: #{l.strip}" },
      "PLASTIC.md must not mention a gate; nothing blocks a write in 2.0"
  end

  def test_plastic_md_names_the_two_modes_plus_auto
    body = normalized(PLASTIC_MD)
    assert_includes body, "**Direct**"
    assert_includes body, "**Thinking**"
    assert_includes body, "**Auto**"
    assert_includes body, "There are no tiers: there is only work."
    assert_includes body, "The Coordinator loop (build, observe, repeat) wraps every intent"
  end

  def test_plastic_md_describes_the_shipped_store_layout
    body = read(PLASTIC_MD)
    assert_includes body, ".sessions/<YYYYMMDD>/", "the day ledger directory"
    assert_includes body, ".tmp/<session>/", "the per-session directory"
    assert_includes body, "current (the pointer)", "the pointer file"
    assert_includes body, "heartbeat", "the heartbeat file"
    assert_includes body, "first eight characters of the session id", "the short session id"
    assert_includes normalized(PLASTIC_MD), "The pointer holds a day id (the day ledger takes the record) or an intent id (an auto team owns the record)"
    assert_includes body, "digits only (`20260828`)", "the day id rule"
    assert_includes body, "mode: direct", "the day ledger's one extra frontmatter field"
  end

  def test_plastic_md_carries_the_power_tools_mandate_as_a_recommendation
    body = normalized(PLASTIC_MD)
    assert_includes body, "Recommendations, not obligations, and only when present."
    assert_includes body, "prefer `qmd search` / `qmd query` over the `plastic-*` collections"
    assert_includes body, "Enola, or Serena when Enola is absent"
    assert_includes body, "for code navigation over grep"
  end

  def test_plastic_md_scopes_locks_and_worktrees_to_auto_teams
    body = normalized(PLASTIC_MD)
    assert_includes body, "Locks and worktrees exist only for auto teams."
    assert_includes body, "`delivery.lock`"
  end

  # PlasticChapterWiringTest reads only skills/*/SKILL.md, so a chapter pointer
  # dropped from PLASTIC.md is invisible to it (review A3). The core names
  # every chapter once, so a reader holding only the core knows where deeper
  # doctrine lives.
  def test_plastic_md_names_every_conventions_chapter
    body = read(PLASTIC_MD)
    chapters = Dir.glob(File.join(ROOT, "skills", "conventions", "references", "*.md"))
                  .map { |p| File.basename(p, ".md") }.sort
    refute_empty chapters
    missing = chapters.reject { |name| body.include?(name) }
    assert_empty missing, "PLASTIC.md must name every conventions chapter; missing: #{missing.join(', ')}"
  end

  # --- harness-adapters.md ---------------------------------------------------

  def test_adapters_doc_describes_no_live_gate
    offenders = read(ADAPTERS).lines.each_with_index.select do |line, _|
      line.match?(/\bgates?\b/i) && !line.match?(REMOVAL_NOTE)
    end
    assert_empty offenders.map { |l, i| "#{i + 1}: #{l.strip}" },
      "harness-adapters.md must not describe a gate as live"
    refute_includes read(ADAPTERS), "pre-write veto"
    refute_includes read(ADAPTERS), "PreToolUse hooks observe"
  end

  def test_adapters_doc_names_the_record_hook_and_the_shell_write_caveat
    body = normalized(ADAPTERS)
    assert_includes body, "`record`"
    assert_includes body, "seven hooks through `settings.json`"
    assert_includes body, "does not include `Bash`"
  end

  # --- the gates guide is replaced -------------------------------------------

  def test_old_gates_guide_is_gone_and_the_ledgers_guide_exists
    refute File.exist?(File.join(GUIDES, "#{OLD_GUIDE}.md")), "the gates guide must be deleted"
    assert File.file?(NEW_GUIDE), "docs/guides/reading-the-ledgers.md must exist"
    body = read(NEW_GUIDE)
    assert_includes body, "savepoint.md"
    assert_includes body, ".sessions/<YYYYMMDD>/"
    assert_includes body, "`current`"
    assert_includes body, "delivery.lock"
  end

  def test_nothing_links_to_the_old_guide
    roots = %w[docs/guides skills README.md AGENTS.md templates docs/architecture.md docs/internals.md]
    files = roots.flat_map do |r|
      path = File.join(ROOT, r)
      File.directory?(path) ? Dir.glob(File.join(path, "**", "*.md")) : [path]
    end
    hits = files.select { |f| File.file?(f) && File.read(f).include?(OLD_GUIDE) }
    assert_empty hits.map { |f| relative(f) },
      "no shipped doc, skill, or template may still link to the deleted gates guide"
  end

  def test_guides_index_lists_the_ledgers_guide
    index = read(File.join(GUIDES, "index.md"))
    assert_includes index, "(reading-the-ledgers.md)"
  end

  # subtraction_304_test's scan_files returns [] for a path that does not
  # exist, so a deleted or renamed file in SCAN_ROOTS silently drops out of
  # the removed-name scan instead of failing (review A4). Pin every entry to
  # disk.
  def test_subtraction_scan_roots_exist_on_disk
    source = read(File.join(ROOT, "test", "subtraction_304_test.rb"))
    match = source.match(/SCAN_ROOTS = %w\[(.*?)\]/m)
    refute_nil match, "subtraction_304_test.rb must declare SCAN_ROOTS"
    missing = match[1].split.reject { |rel| File.exist?(File.join(ROOT, rel)) }
    assert_empty missing,
      "SCAN_ROOTS entries missing on disk (the scan would silently skip them): #{missing.join(', ')}"
  end

  # --- guides, tutorial, README ----------------------------------------------

  def test_pick_your_mode_describes_direct_thinking_and_auto
    body = read(PICK_MODE)
    refute_match(/\bgates?\b/i, body)
    ["## Direct", "## Thinking", "## Auto"].each { |h| assert_includes body, h }
  end

  def test_no_guide_or_tutorial_asks_auto_or_guided
    files = Dir.glob(File.join(GUIDES, "*.md")) +
            Dir.glob(File.join(ROOT, "skills", "tutorial", "**", "*.md"))
    hits = files.select { |f| File.read(f).match?(/auto or guided/i) }
    assert_empty hits.map { |f| relative(f) },
      "the auto-or-guided question was removed in 2.0 (intent 304); no guide or tutorial may still ask it"
  end

  def test_tutorial_track_2_walks_the_record_not_the_gates
    body = read(File.join(ROOT, "skills", "tutorial", "references", "track-2-auto.md"))
    refute_includes body, "Walking the gates"
    refute_match(/the code gate|the create gate|the links gate|the bash gate/, body)
    assert_includes body, "### 3. Walking the record"
  end

  def test_readme_carries_no_tier_brief_grammar
    refute_includes read(File.join(ROOT, "README.md")), "S, M, or L"
  end

  # --- chapters and intent-executing ------------------------------------------

  def test_chapters_name_no_retired_hook
    CHAPTERS.each do |path|
      body = read(path)
      name = File.basename(path)
      RETIRED_HOOK_NAMES.each do |hook|
        refute_includes body, hook, "#{name} still names the retired hook #{hook}"
      end
      refute_includes body, "lock_gate_decision", "#{name} cites bridge code removed in 2.0 (intent 302)"
      refute_includes body, "solo_delivery?", "#{name} cites the solo-mode relaxation removed in 2.0 (intent 302)"
    end
  end

  def test_intent_executing_carries_no_tier_grammar_and_no_gate
    body = read(EXECUTING)
    refute_includes body, "at L " # removed in 2.0 (intent 304)
    refute_includes body, "at S and M" # removed in 2.0 (intent 304)
    refute_match(/\bgates?\b/i, body, "intent-executing must not tell the executor to wait for a gate")
  end
end
