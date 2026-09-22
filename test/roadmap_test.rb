# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# ACTION_4 (intent 124): hermetic structural tests for the roadmap feature.
# Asserts the template's born-complete shape and the roadmaps chapter's
# contract invariants (moved out of PLASTIC.md in intent 127, then out of
# PLASTIC-reference.md into skills/conventions/references/roadmaps.md in
# intent 223, out of the conventions skill into docs/help/roadmaps.md in
# intent 372's family 4, then out of skills/roadmap/SKILL.md and its
# references/ entirely in family 3: `plastic roadmap show/next/log/check` run
# the scripts directly, so the skill's frontmatter, line budget and reference
# chapters have no file left to assert against). Reads ONLY in-repo files;
# the live project-store roadmap instance (Action 05) is a runtime
# deliverable, not a test target, so this stays hermetic.
class RoadmapTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TEMPLATE = File.join(ROOT, "templates", "roadmap.md")
  ROADMAPS_CHAPTER = File.join(ROOT, "docs", "help", "roadmaps.md")
  STATUS_TOKENS = %w[queued delivering delivered abandoned blocked].freeze

  # --- templates/roadmap.md -------------------------------------------------

  def test_template_has_title_and_meta_header
    body = File.read(TEMPLATE)
    assert_match(/\A# Roadmap:/, body, "must open with a '# Roadmap:' header")
  end

  # Intent 337 (n7): the template gained an optional "## Graph" section
  # between Goal and Batches, teaching the edge grammar so a new roadmap is
  # never born graphless.
  def test_template_has_the_four_sections_in_order
    body = File.read(TEMPLATE)
    headings = body.scan(/^## .+$/)
    assert_equal ["## Goal", "## Graph", "## Batches", "## Log"], headings,
                 "must contain ## Goal, ## Graph, ## Batches, ## Log in that order"
  end

  def test_template_waves_has_a_status_entry_line
    body = File.read(TEMPLATE)
    status_alt = STATUS_TOKENS.join("|")
    assert_match(/^- .+ — (#{status_alt})\s*$/, body,
                 "## Batches must show an entry line '- <id> <title> — <status>'")
  end

  def test_template_log_has_a_dated_line
    body = File.read(TEMPLATE)
    assert_match(/^- \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC /, body,
                 "## Log must show a 'YYYY-MM-DD HH:MM UTC'-prefixed example line")
  end

  # --- amendment (2026-07-06 human rulings): checkboxes, EM-to-CTO log, archive ---

  def test_template_wave_entries_use_checkbox_syntax
    body = File.read(TEMPLATE)
    assert_match(/^- \[ \] .+ — \w+\s*$/, body,
                 "## Batches must show an unchecked '- [ ] <id> <title> — <status>' entry")
    assert_match(/^- \[x\] .+ — delivered\s*$/, body,
                 "## Batches must show a checked '- [x] <id> <title> — delivered' entry")
  end

  def test_template_log_documents_outcome_link_and_lossless_rule
    body = File.read(TEMPLATE)
    assert_match(/outcome\.md/, body, "## Log docs must mention linking to outcome.md")
    assert_match(/lossless-by-reference|never restate/i, body,
                 "## Log docs must state the lossless-by-reference / never-restate rule")
    assert_match(/plain-language|EM-to-CTO/i, body,
                 "## Log docs must state the plain-language / EM-to-CTO voice rule")
  end

  def test_template_notes_archive_on_close
    body = File.read(TEMPLATE)
    assert_match(%r{roadmaps/archived/}, body,
                 "template header must note the archived/ destination on close")
  end

  # --- amendment (2026-07-06 human rulings 5+6): project-root location, HH:MM UTC log ---

  def test_docs_do_not_place_roadmaps_under_store
    body = File.read(ROADMAPS_CHAPTER)
    refute_match(%r{store/roadmaps}, body, "#{ROADMAPS_CHAPTER} must not place roadmaps/ under store/")
    refute_match(/store[- ]root/i, body, "#{ROADMAPS_CHAPTER} must not describe roadmaps/ location as store-root")
  end

  def test_docs_state_sibling_of_index_rule
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(/sibling of\s+`?INDEX\.md`?/, body, "#{ROADMAPS_CHAPTER} must state roadmaps/ is a sibling of INDEX.md")
  end

  # test_skill_frontmatter_has_name_and_description, test_skill_body_is_under_line_budget,
  # test_skill_states_status_vocabulary_and_index_wins_rule, test_references_dir_exists_
  # one_level_deep_with_markdown, test_skill_documents_close_archive_verb,
  # test_operations_doc_wires_roadmap_reindex_in_each_mutating_verb and
  # test_references_document_close_archive_checkbox_and_log_formats were retired by intent
  # 372 (family 3): skills/roadmap/SKILL.md and its references/ (file-format.md,
  # operations.md) are gone, moved into `plastic roadmap show/next/log/check`, thin
  # command wrappers with no frontmatter, line budget or reference chapter of their own.
  # The status vocabulary and INDEX-wins rule they checked stay covered below by
  # test_plastic_md_states_index_wins_rule, reading the surviving docs/help/roadmaps.md
  # chapter. The per-verb QMD reindex wiring they checked is exercised at the code level
  # (scripts/lib/roadmap_savepoint.rb, scripts/roadmap-graph), not by a documentation read.

  # --- roadmaps chapter contract (moved out of PLASTIC.md in 127, then out of --
  # --- PLASTIC-reference.md into skills/conventions/references/roadmaps.md in 223

  def test_plastic_md_states_file_location
    body = File.read(ROADMAPS_CHAPTER)
    assert_includes body, "roadmaps/{slug}.md", "must name the roadmaps/{slug}.md location"
  end

  def test_plastic_md_states_the_four_sections
    body = File.read(ROADMAPS_CHAPTER)
    ["## Goal", "## Batches", "## Log"].each do |heading|
      assert_includes body, heading, "must name section #{heading}"
    end
  end

  def test_plastic_md_states_wave_parallel_safety
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(/parallel-safe/, body, "must state wave parallel-safety semantics")
  end

  def test_plastic_md_states_goal_as_prose_rule
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(/checkable prose condition/, body, "must state the goal-as-prose rule")
  end

  def test_plastic_md_states_index_wins_rule
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(/INDEX wins/, body, "must state the status-mirror / INDEX-wins rule")
  end

  # test_plastic_md_has_skills_reference_row intentionally removed: it asserted against
  # PLASTIC-reference.md's "Skills Reference" table, which intent 223 (D10) deleted as
  # superseded by the plastic-conventions router. Repointing the constant to
  # ROADMAPS_CHAPTER made the assertion match an unrelated sentence ("Use `plastic-roadmap`
  # to create, order, close, and consume one.") instead, so it passed for the wrong reason
  # and could never fail for the reason its message named. No real replacement exists: no
  # chapter or skill still carries a "Skills Reference" table to assert against.

  def test_plastic_md_states_archived_rule
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(%r{roadmaps/archived/}, body,
                 "must state the roadmaps/archived/ subdirectory and its move-on-close rule")
  end

  def test_plastic_md_states_purpose_line_verbatim
    body = File.read(ROADMAPS_CHAPTER)
    assert_includes body,
                     "planned parallel delivery of intents in a coherent and organized way",
                     "must state the verbatim purpose line"
  end

  def test_plastic_md_states_loop_relationship
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(/intent 69/, body, "must name intent 69 as the loop-engineering consumer")
    assert_match(/planning half/i, body, "must state roadmap = planning half, loop = runtime")
  end

  def test_plastic_md_states_checkbox_and_em_to_cto_log_format
    body = File.read(ROADMAPS_CHAPTER)
    assert_match(/checkbox/i, body, "must mention the checkbox wave-entry rendering")
    assert_match(/outcome\.md/, body, "must mention linking log lines to outcome.md")
  end

end
