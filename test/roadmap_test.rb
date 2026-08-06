# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# ACTION_4 (intent 124): hermetic structural tests for the roadmap feature.
# Asserts the template's born-complete shape, the skill's frontmatter + slim
# body + references, and the roadmaps chapter's contract invariants (moved out
# of PLASTIC.md in intent 127, then out of PLASTIC-reference.md into
# skills/conventions/references/roadmaps.md in intent 223). Reads ONLY in-repo
# files; the live project-store roadmap instance (Action 05) is a runtime
# deliverable, not a test target, so this stays hermetic.
class RoadmapTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TEMPLATE = File.join(ROOT, "templates", "roadmap.md")
  SKILL = File.join(ROOT, "skills", "roadmap", "SKILL.md")
  REFERENCES_DIR = File.join(ROOT, "skills", "roadmap", "references")
  FILE_FORMAT = File.join(REFERENCES_DIR, "file-format.md")
  OPERATIONS = File.join(REFERENCES_DIR, "operations.md")
  ROADMAPS_CHAPTER = File.join(ROOT, "skills", "conventions", "references", "roadmaps.md")
  STATUS_TOKENS = %w[queued delivering delivered abandoned blocked].freeze
  LINE_BUDGET = 500

  # --- templates/roadmap.md -------------------------------------------------

  def test_template_has_title_and_meta_header
    body = File.read(TEMPLATE)
    assert_match(/\A# Roadmap:/, body, "must open with a '# Roadmap:' header")
  end

  def test_template_has_the_four_sections_in_order
    body = File.read(TEMPLATE)
    headings = body.scan(/^## .+$/)
    assert_equal ["## Goal", "## Batches", "## Log"], headings,
                 "must contain ## Goal, ## Batches, ## Log in that order"
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
    [SKILL, FILE_FORMAT, OPERATIONS, ROADMAPS_CHAPTER].each do |path|
      body = File.read(path)
      refute_match(%r{store/roadmaps}, body,
                   "#{path} must not place roadmaps/ under store/")
      refute_match(/store[- ]root/i, body,
                   "#{path} must not describe roadmaps/ location as store-root")
    end
  end

  def test_docs_state_sibling_of_index_rule
    [SKILL, FILE_FORMAT, OPERATIONS, ROADMAPS_CHAPTER].each do |path|
      body = File.read(path)
      assert_match(/sibling of\s+`?INDEX\.md`?/, body,
                   "#{path} must state roadmaps/ is a sibling of INDEX.md")
    end
  end

  # --- skills/roadmap/SKILL.md ----------------------------------------------

  def test_skill_frontmatter_has_name_and_description
    body = File.read(SKILL)
    assert body.start_with?("---\n"), "frontmatter must open on the first line"
    fm = body.split(/^---\s*$/)[1].to_s
    assert_match(/^name:\s*plastic-roadmap\s*$/, fm, "name must be plastic-roadmap")
    assert_match(/^description:\s*\S.+$/, fm, "description must be present and non-empty")
  end

  def test_skill_body_is_under_line_budget
    lines = File.readlines(SKILL)
    assert lines.length < LINE_BUDGET,
           "SKILL.md must stay under #{LINE_BUDGET} lines, got #{lines.length}"
  end

  def test_skill_states_status_vocabulary_and_index_wins_rule
    body = File.read(SKILL)
    STATUS_TOKENS.each do |token|
      assert_includes body, token, "SKILL.md must state status token '#{token}'"
    end
    assert_match(/INDEX wins/, body, "SKILL.md must state the INDEX-wins mirror rule")
  end

  def test_references_dir_exists_one_level_deep_with_markdown
    assert File.directory?(REFERENCES_DIR), "skills/roadmap/references/ must exist"
    md_files = Dir.glob(File.join(REFERENCES_DIR, "*.md"))
    refute_empty md_files, "references/ must hold at least one .md file"
    nested = Dir.glob(File.join(REFERENCES_DIR, "**", "*", "*.md"))
    assert_empty nested, "references/ must stay one level deep"
  end

  def test_skill_documents_close_archive_verb
    body = File.read(SKILL)
    assert_match(/Close.*archive|Close \/ archive/i, body,
                 "SKILL.md must list a Close/archive verb")
    assert_match(%r{roadmaps/archived/}, body,
                 "SKILL.md must name the roadmaps/archived/ destination")
  end

  # --- intent 135: roadmap mutating verbs must wire their own QMD reindex ---

  ROADMAP_REINDEX_LINE = "qmd-sync reindex --store <roadmaps-dir> --async"
  MUTATING_HEADINGS = [
    "Create",
    "Add / reorder entries",
    "Sync status mirror",
    "Append a log line",
    "Close / archive",
  ].freeze

  def test_operations_doc_wires_roadmap_reindex_in_each_mutating_verb
    body = File.read(OPERATIONS)
    sections = body.split(/^## /).drop(1)

    MUTATING_HEADINGS.each do |heading|
      section = sections.find { |s| s.start_with?(heading) }
      refute_nil section, "operations.md must contain a '## #{heading}' section"
      assert_includes section, ROADMAP_REINDEX_LINE,
                       "'## #{heading}' section must wire the roadmap reindex call"
    end

    read_section = sections.find { |s| s.start_with?("Read / consume") }
    refute_nil read_section, "operations.md must contain a '## Read / consume' section"
    refute_includes read_section, ROADMAP_REINDEX_LINE,
                     "'## Read / consume' is non-mutating and must not wire a reindex call"
  end

  def test_references_document_close_archive_checkbox_and_log_formats
    file_format = File.read(FILE_FORMAT)
    operations = File.read(OPERATIONS)
    assert_match(/\[x\]/, file_format, "file-format.md must document the checkbox syntax")
    assert_match(/\[ \]/, file_format, "file-format.md must document the unchecked checkbox")
    assert_match(/outcome\.md/, file_format, "file-format.md must document the outcome.md link")
    assert_match(/EM-to-CTO|plain-language/i, file_format,
                 "file-format.md must document the EM-to-CTO / plain-language log rule")
    assert_match(%r{roadmaps/archived/}, file_format,
                 "file-format.md must document the archived/ location")
    assert_match(/close.*archive|archive/i, operations,
                 "operations.md must document the close/archive operation")
    assert_match(%r{roadmaps/archived/}, operations,
                 "operations.md must document the move to roadmaps/archived/")
    assert_match(/under a minute|human-comprehension/i, operations,
                 "operations.md must state the human-comprehension goal")
  end

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
