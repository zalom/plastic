# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/intent_validator"

# Intent 297, task 5: `new-intent --tmp`, the CLI over
# SessionLedger.open_day. Drives the real script as a subprocess, hermetic
# per file: an explicit --session-free environment (this branch reads no
# session id at all), a Dir.mktmpdir store, and PLASTIC_HOME/PLASTIC_TMP
# isolated from the real store.
class NewIntentTmpTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/new-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @home = Dir.mktmpdir("new-intent-tmp-home")
    @tmp = Dir.mktmpdir("new-intent-tmp-scratch")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @day = "20260829"
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_new_intent(*args, env: {})
    base = {
      "CLAUDE_CODE_SESSION_ID" => nil,
      "PLASTIC_HOME" => @home,
      "PLASTIC_TMP" => @tmp,
    }
    out = IO.popen(base.merge(env), [RbConfig.ruby, SCRIPT, "--templates", TEMPLATES, *args],
                   err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def snapshot(dir)
    Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |path|
      next if File.basename(path) == "." || File.basename(path) == ".."
      next if File.directory?(path)

      [path.delete_prefix(dir), File.binread(path)]
    end
  end

  # --- create vs join, spec D1, D10 ------------------------------------------

  def test_first_call_creates_and_reports_created
    out, status = run_new_intent("--tmp", "--store", @store, "--day", @day)
    assert_equal 0, status, "expected exit 0, got: #{out}"
    line = out.strip
    assert line.start_with?("created "), "expected a created line, got: #{line.inspect}"

    dir = File.join(@store, ".sessions", @day)
    assert_equal dir, line.split(" ", 2).last
    assert File.directory?(dir)
    assert_equal ["#{@day}.md"], Dir.children(dir)
  end

  def test_second_call_joins_and_changes_zero_bytes
    run_new_intent("--tmp", "--store", @store, "--day", @day)
    dir = File.join(@store, ".sessions", @day)
    before = snapshot(dir)

    out, status = run_new_intent("--tmp", "--store", @store, "--day", @day)
    assert_equal 0, status, "expected exit 0, got: #{out}"
    line = out.strip
    assert line.start_with?("joined "), "expected a joined line, got: #{line.inspect}"

    after = snapshot(dir)
    assert_equal before, after, "a joining --tmp call must change zero bytes on disk"
  end

  def test_scaffold_passes_intent_validator
    run_new_intent("--tmp", "--store", @store, "--day", @day)
    dir = File.join(@store, ".sessions", @day)
    result = IntentValidator.validate(dir)
    assert result[:ok], "day ledger must be born complete: #{result[:errors].inspect}"

    fm = IntentValidator.parse_frontmatter(File.join(dir, "#{@day}.md"))
    assert_equal "direct", fm["mode"]
  end

  # --- flag rejection, spec D1 ------------------------------------------------

  def test_rejects_intent_flag
    out, status = run_new_intent("--tmp", "--store", @store, "--intent", "x")
    refute_equal 0, status
    assert_includes out, "--intent"
  end

  def test_rejects_slug_flag
    out, status = run_new_intent("--tmp", "--store", @store, "--slug", "x")
    refute_equal 0, status
    assert_includes out, "--slug"
  end

  def test_rejects_parent_flag
    out, status = run_new_intent("--tmp", "--store", @store, "--parent", "1")
    refute_equal 0, status
    assert_includes out, "--parent"
  end

  def test_rejects_sources_flag
    out, status = run_new_intent("--tmp", "--store", @store, "--sources", "1")
    refute_equal 0, status
    assert_includes out, "--sources"
  end

  def test_rejects_tags_flag
    out, status = run_new_intent("--tmp", "--store", @store, "--tags", "x")
    refute_equal 0, status
    assert_includes out, "--tags"
  end

  # --- --day validation, spec D1 ----------------------------------------------

  def test_day_with_hyphens_is_rejected
    _out, status = run_new_intent("--tmp", "--store", @store, "--day", "2026-08-29")
    refute_equal 0, status
  end

  def test_day_too_short_is_rejected
    _out, status = run_new_intent("--tmp", "--store", @store, "--day", "2026082")
    refute_equal 0, status
  end

  def test_day_too_long_is_rejected
    _out, status = run_new_intent("--tmp", "--store", @store, "--day", "202608299")
    refute_equal 0, status
  end

  def test_day_non_digits_is_rejected
    _out, status = run_new_intent("--tmp", "--store", @store, "--day", "abcdefgh")
    refute_equal 0, status
  end

  def test_day_out_of_range_is_rejected
    _out, status = run_new_intent("--tmp", "--store", @store, "--day", "20261340")
    refute_equal 0, status
  end

  def test_day_digits_only_is_accepted
    out, status = run_new_intent("--tmp", "--store", @store, "--day", "20260829")
    assert_equal 0, status, "expected exit 0, got: #{out}"
    dir = File.join(@store, ".sessions", "20260829")
    assert File.directory?(dir)
  end

  # --- default store, spec D1 --------------------------------------------------

  def test_default_store_derives_from_plastic_home
    out, status = run_new_intent("--tmp", "--day", @day)
    assert_equal 0, status, "expected exit 0, got: #{out}"
    dir = File.join(@store, ".sessions", @day)
    assert File.directory?(dir), "expected the day dir under PLASTIC_HOME's default store: #{dir}"
  end

  # --- store root never flattens, spec goal ------------------------------------

  def test_store_root_gains_no_child_other_than_sessions
    run_new_intent("--tmp", "--store", @store, "--day", @day)
    visible = Dir.children(@store).reject { |e| e.start_with?(".") }
    assert_empty visible, "a day ledger must never flatten to the store root"
  end
end
