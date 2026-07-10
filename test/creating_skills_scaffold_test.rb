# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

# ACTION_4 (intent 85c): the creating-skills scaffolder CLI. Drive the real
# scaffold.rb as a subprocess into a hermetic tmpdir and assert the generated
# SKILL.md is born slim and well formed (frontmatter with name + description,
# body within the line budget, no em-dashes or en-dashes anywhere).
class CreatingSkillsScaffoldTest < Minitest::Test
  SCRIPT = File.expand_path(
    "../skills/skill-creating/scripts/scaffold.rb", __dir__
  )
  LINE_BUDGET = 500
  EM_DASH = "\u2014"
  EN_DASH = "\u2013"

  def setup
    @dir = Dir.mktmpdir("creating-skills-scaffold")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def run_scaffold(*args)
    out = IO.popen(
      [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read
    )
    [out, $?.exitstatus]
  end

  def skill_md_path(name)
    File.join(@dir, name, "SKILL.md")
  end

  def test_skill_subcommand_exits_zero_and_writes_skill_md
    out, status = run_scaffold("skill", "pdf-extractor", "--out", @dir)
    assert_equal 0, status, "expected exit 0, got: #{out}"
    assert File.exist?(skill_md_path("pdf-extractor")), "SKILL.md should be created"
    assert File.exist?(File.join(@dir, "pdf-extractor", "references", ".gitkeep"))
    assert File.exist?(File.join(@dir, "pdf-extractor", "evals", "evals.json"))
  end

  def test_generated_skill_md_has_name_and_description_frontmatter
    run_scaffold("skill", "pdf-extractor", "--out", @dir)
    body = File.read(skill_md_path("pdf-extractor"))
    assert body.start_with?("---\n"), "frontmatter must open on the first line"

    fm = body.split("---\n")[1].to_s
    assert_match(/^name:\s*pdf-extractor\s*$/, fm, "frontmatter must carry the name")
    assert_match(/^description:\s*>/, fm, "frontmatter must carry a description")
  end

  def test_generated_skill_md_is_born_slim
    run_scaffold("skill", "pdf-extractor", "--out", @dir)
    lines = File.readlines(skill_md_path("pdf-extractor"))
    assert lines.length < LINE_BUDGET,
           "born-slim body must stay under #{LINE_BUDGET} lines, got #{lines.length}"
  end

  def test_generated_skill_md_has_no_em_or_en_dashes
    run_scaffold("skill", "pdf-extractor", "--out", @dir)
    body = File.read(skill_md_path("pdf-extractor"))
    refute_includes body, EM_DASH, "generated SKILL.md must contain no em-dash"
    refute_includes body, EN_DASH, "generated SKILL.md must contain no en-dash"
  end

  def test_bad_name_is_rejected_with_validation_exit
    _out, status = run_scaffold("skill", "Bad_Name", "--out", @dir)
    assert_equal 2, status, "an invalid name must exit with the validation code"
    refute File.exist?(File.join(@dir, "Bad_Name")), "no scaffold on a bad name"
  end
end
