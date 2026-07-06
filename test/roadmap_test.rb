# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# ACTION_4 (intent 124): hermetic structural tests for the roadmap feature.
# Asserts the template's born-complete shape, the skill's frontmatter + slim
# body + references, and the PLASTIC.md contract invariants. Reads ONLY
# in-repo files; the live project-store roadmap instance (Action 05) is a
# runtime deliverable, not a test target, so this stays hermetic.
class RoadmapTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TEMPLATE = File.join(ROOT, "templates", "roadmap.md")
  SKILL = File.join(ROOT, "skills", "roadmap", "SKILL.md")
  REFERENCES_DIR = File.join(ROOT, "skills", "roadmap", "references")
  FILE_FORMAT = File.join(REFERENCES_DIR, "file-format.md")
  OPERATIONS = File.join(REFERENCES_DIR, "operations.md")
  PLASTIC_MD = File.join(ROOT, "PLASTIC.md")
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
    assert_equal ["## Goal", "## Waves", "## Log"], headings,
                 "must contain ## Goal, ## Waves, ## Log in that order"
  end

  def test_template_waves_has_a_status_entry_line
    body = File.read(TEMPLATE)
    status_alt = STATUS_TOKENS.join("|")
    assert_match(/^- .+ — (#{status_alt})\s*$/, body,
                 "## Waves must show an entry line '- <id> <title> — <status>'")
  end

  def test_template_log_has_a_dated_line
    body = File.read(TEMPLATE)
    assert_match(/^- \d{4}-\d{2}-\d{2} /, body,
                 "## Log must show a dated example line")
  end

  # --- amendment (2026-07-06 human rulings): checkboxes, EM-to-CTO log, archive ---

  def test_template_wave_entries_use_checkbox_syntax
    body = File.read(TEMPLATE)
    assert_match(/^- \[ \] .+ — \w+\s*$/, body,
                 "## Waves must show an unchecked '- [ ] <id> <title> — <status>' entry")
    assert_match(/^- \[x\] .+ — delivered\s*$/, body,
                 "## Waves must show a checked '- [x] <id> <title> — delivered' entry")
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

  # --- PLASTIC.md contract ---------------------------------------------------

  def test_plastic_md_states_file_location
    body = File.read(PLASTIC_MD)
    assert_includes body, "roadmaps/{slug}.md", "must name the roadmaps/{slug}.md location"
  end

  def test_plastic_md_states_the_four_sections
    body = File.read(PLASTIC_MD)
    ["## Goal", "## Waves", "## Log"].each do |heading|
      assert_includes body, heading, "must name section #{heading}"
    end
  end

  def test_plastic_md_states_wave_parallel_safety
    body = File.read(PLASTIC_MD)
    assert_match(/parallel-safe/, body, "must state wave parallel-safety semantics")
  end

  def test_plastic_md_states_goal_as_prose_rule
    body = File.read(PLASTIC_MD)
    assert_match(/checkable prose condition/, body, "must state the goal-as-prose rule")
  end

  def test_plastic_md_states_index_wins_rule
    body = File.read(PLASTIC_MD)
    assert_match(/INDEX wins/, body, "must state the status-mirror / INDEX-wins rule")
  end

  def test_plastic_md_has_skills_reference_row
    body = File.read(PLASTIC_MD)
    assert_match(/plastic-roadmap/, body, "must list plastic-roadmap in Skills Reference")
  end

  def test_plastic_md_states_archived_rule
    body = File.read(PLASTIC_MD)
    assert_match(%r{roadmaps/archived/}, body,
                 "must state the roadmaps/archived/ subdirectory and its move-on-close rule")
  end

  def test_plastic_md_states_purpose_line_verbatim
    body = File.read(PLASTIC_MD)
    assert_includes body,
                     "planned parallel delivery of intents in a coherent and organized way",
                     "must state the verbatim purpose line"
  end

  def test_plastic_md_states_loop_relationship
    body = File.read(PLASTIC_MD)
    assert_match(/intent 69/, body, "must name intent 69 as the loop-engineering consumer")
    assert_match(/planning half/i, body, "must state roadmap = planning half, loop = runtime")
  end

  def test_plastic_md_states_checkbox_and_em_to_cto_log_format
    body = File.read(PLASTIC_MD)
    assert_match(/checkbox/i, body, "must mention the checkbox wave-entry rendering")
    assert_match(/outcome\.md/, body, "must mention linking log lines to outcome.md")
  end

end
