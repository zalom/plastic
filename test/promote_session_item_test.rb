# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "date"
require_relative "../scripts/lib/session_ledger"

# Intent 301: scripts/promote-session-item turns one day-ledger line into a
# real intent through the real scripts/new-intent, in a hermetic tmp store.
class PromoteSessionItemTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/promote-session-item", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260829"

  def setup
    @home = Dir.mktmpdir("promote-home")
    @tmp = Dir.mktmpdir("promote-scratch")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    File.write(File.join(@store, "INDEX.md"), File.read(File.join(TEMPLATES, "index.md")))
    File.write(File.join(@home, "projects.yml"), "projects: {}\n")
    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "t")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_promote(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => @tmp }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, "--store", @store, "--templates", TEMPLATES, "--no-reindex",
                         "--day", DAY, *args], err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def append(state, summary, session: "abc")
    SessionLedger.append_line(SessionLedger.checklist_path(@store, DAY),
                              SessionLedger.checklist_line(state, session, "plastic", summary),
                              header: SessionLedger.checklist_header(DAY))
  end

  def markers
    File.readlines(SessionLedger.checklist_path(@store, DAY)).grep(/\A- \[/).map { |l| l[0, 5] }
  end

  def frontmatter(intent_dir)
    file = Dir.glob(File.join(intent_dir, "*--*.md")).first
    body = File.read(file)
    [YAML.safe_load(body.split(/^---\s*$/, 3)[1], permitted_classes: [Date]), body]
  end

  def test_promotes_an_open_line_into_a_born_complete_intent
    append(:open, "Change how titles appear on the resume page")
    out, status = run_promote("--match", "titles")
    assert_equal 0, status, out
    intent_dir = out.lines.last.strip
    assert Dir.exist?(intent_dir), out
    assert_equal @store, File.dirname(intent_dir)
    fm, body = frontmatter(intent_dir)
    assert_equal DAY, fm["session_day"]
    assert_equal "Change how titles appear on the resume page", fm["intent"]
    assert_includes body, "Promoted from the session ledger of #{DAY}: Change how titles appear on the resume page"
    assert_equal ["- [^]"], markers
    assert_includes File.read(SessionLedger.savepoint_path(@store, DAY)), "promoted \"Change how titles appear on the resume page\" to intent "
    assert_match(/^- \[/, File.read(File.join(@store, "INDEX.md")))
  end

  def test_promotes_a_pending_line_when_no_open_line_matches
    append(:pending, "draft the release note")
    out, status = run_promote("--match", "release")
    assert_equal 0, status, out
    assert_equal ["- [^]"], markers
  end

  def test_flips_exactly_the_newest_of_several_matching_lines
    append(:open, "fix typo one", session: "aaa")
    append(:open, "fix typo two", session: "bbb")
    append(:open, "fix typo three", session: "ccc")
    out, status = run_promote("--match", "typo")
    assert_equal 0, status, out
    assert_equal ["- [ ]", "- [ ]", "- [^]"], markers
    fm, _body = frontmatter(out.lines.last.strip)
    assert_equal "fix typo three", fm["intent"]
  end

  def test_session_filter_addresses_only_that_sessions_line
    append(:open, "shared words", session: "aaa")
    append(:open, "shared words too", session: "bbb")
    _out, status = run_promote("--match", "shared", "--session", "aaa")
    assert_equal 0, status
    assert_equal ["- [^]", "- [ ]"], markers
  end

  def test_slug_is_derived_from_odd_summaries
    append(:open, "!!! ??? ...")
    out, status = run_promote("--match", "???")
    assert_equal 0, status, out
    assert_match(%r{/\d+--item\z}, out.lines.last.strip)

    append(:open, "Ünïcödé words in a summary that is really long " + ("word " * 40))
    out, status = run_promote("--match", "summary that is really long")
    assert_equal 0, status, out
    slug = out.lines.last.strip.split("--", 2).last
    assert_match(/\A[a-z0-9-]+\z/, slug)
    assert_operator slug.split("-").size, :<=, 5
  end

  def test_no_match_exits_2_and_writes_nothing
    append(:open, "something")
    before = File.binread(SessionLedger.checklist_path(@store, DAY))
    out, status = run_promote("--match", "absent")
    assert_equal 2, status, out
    assert_equal before, File.binread(SessionLedger.checklist_path(@store, DAY))
    assert_empty Dir.glob(File.join(@store, "*--*"))
  end

  def test_project_flag_lands_the_intent_in_that_projects_store
    project_store = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(project_store)
    File.write(File.join(project_store, "INDEX.md"), File.read(File.join(TEMPLATES, "index.md")))
    File.write(File.join(@home, "projects.yml"),
               YAML.dump("projects" => { "demo" => { "path" => File.join(@home, "demo-repo") } }))
    append(:open, "a project item")
    out, status = run_promote("--match", "project item", "--project", "demo")
    assert_equal 0, status, out
    assert_equal project_store, File.dirname(out.lines.last.strip)
  end
end
