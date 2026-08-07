require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

# Hermetic tests for the `qmd-sync search` CLI verb (intent 66a). A fake `qmd`
# executable is placed on PATH so the CLI's real detector and default runner both
# resolve it without any network, model download, or real qmd binary. The fake
# echoes a canned JSON array, so we can assert the verb's ranked output format and
# its no-op-when-absent behavior.
class QmdSyncSearchCliTest < Minitest::Test
  CLI = File.expand_path("../scripts/qmd-sync", __dir__)

  HITS_JSON = <<~JSON.freeze
    [
      {"docid":"#a1","score":0.81,"file":"qmd://plastic-global/15--enforce/15.md","line":1,"title":"Enforce Plastic supremacy","snippet":"x"},
      {"docid":"#b2","score":0.62,"file":"qmd://plastic-global/9--org/9.md","line":3,"title":"GitHub org migration","snippet":"y"},
      {"docid":"#c3","score":0.40,"file":"qmd://plastic-global/3--obs/3.md","line":2,"title":"Store observer","snippet":"z"}
    ]
  JSON

  def setup
    @home = Dir.mktmpdir("qmd-sync-search-home")
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "projects.yml"), "projects: {}\n")
    @bindir = Dir.mktmpdir("qmd-sync-search-bin")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@bindir)
  end

  # Write a fake `qmd` executable that prints `output` and exits 0, place it on a
  # PATH-only directory, and return that PATH string. The fake also records the
  # `qmd search` query it received to @argfile, so tests can assert what was
  # actually searched for (query-parsing robustness).
  def path_with_fake_qmd(output)
    @argfile = File.join(@bindir, "qmd-args.txt")
    fake = File.join(@bindir, "qmd")
    body = <<~RUBY
      #!/usr/bin/env ruby
      if ARGV[0] == "search"
        File.write(#{@argfile.inspect}, ARGV[1].to_s)
      end
      puts #{output.inspect}
    RUBY
    File.write(fake, body)
    File.chmod(0o755, fake)
    @bindir
  end

  # The query argument the fake qmd received on its last `search` call.
  def searched_query
    File.exist?(@argfile.to_s) ? File.read(@argfile) : nil
  end

  # Run the CLI with PATH set to exactly `path` (no inherited PATH), so qmd is
  # present only when the fake lives in `path` and absent otherwise. We still need
  # `ruby` resolvable, so include the running interpreter's bindir.
  def run_cli(args, path:)
    ruby_bin = File.dirname(RbConfig.ruby)
    env = { "PATH" => [path, ruby_bin].join(File::PATH_SEPARATOR),
            "PLASTIC_HOME" => @home }
    Open3.capture3(env, RbConfig.ruby, CLI, *args, "--home", @home, chdir: Dir.tmpdir)
  end

  def test_search_prints_ranked_lines_for_hits
    path = path_with_fake_qmd(HITS_JSON)
    out, _err, status = run_cli(["search", "supremacy"], path: path)
    assert status.success?, "exit 0 expected"
    lines = out.lines.map(&:chomp).reject(&:empty?)
    # 0.40 hit is below the default 0.5 min-score and must be dropped.
    assert_equal 2, lines.size
    assert_equal "[81%] plastic-global/15--enforce/15.md - Enforce Plastic supremacy", lines[0]
    assert_equal "[62%] plastic-global/9--org/9.md - GitHub org migration", lines[1]
  end

  def test_search_prints_no_qmd_hits_when_empty
    path = path_with_fake_qmd("[]")
    out, _err, status = run_cli(["search", "nothing-here"], path: path)
    assert status.success?
    assert_equal "no qmd hits", out.strip
  end

  def test_search_noop_exit_zero_when_qmd_absent
    # Empty PATH-only dir: no qmd anywhere, so the top-level guard short-circuits.
    out, _err, status = run_cli(["search", "anything"], path: @bindir)
    assert status.success?, "exit 0 even when qmd is absent"
    assert_match(/QMD not detected; skipped \(search\)\./, out)
  end

  def test_search_honors_limit_and_min_score_flags
    path = path_with_fake_qmd(HITS_JSON)
    out, _err, status = run_cli(["search", "x", "--limit", "1", "--min-score", "0.1"], path: path)
    assert status.success?
    lines = out.lines.map(&:chomp).reject(&:empty?)
    assert_equal 1, lines.size, "limit caps the printed hits"
    assert_equal "[81%] plastic-global/15--enforce/15.md - Enforce Plastic supremacy", lines[0]
  end

  def test_search_query_is_not_the_value_of_a_preceding_store_flag
    path = path_with_fake_qmd(HITS_JSON)
    _out, _err, status = run_cli(["search", "--store", @home, "real terms"], path: path)
    assert status.success?
    assert_equal "real terms", searched_query,
      "query must be 'real terms', not the --store value"
  end

  def test_search_query_is_not_the_value_of_a_preceding_limit_flag
    path = path_with_fake_qmd(HITS_JSON)
    _out, _err, status = run_cli(["search", "--limit", "5", "real terms"], path: path)
    assert status.success?
    assert_equal "real terms", searched_query,
      "query must be 'real terms', not the --limit value '5'"
  end

  def test_search_query_first_usage_still_works
    path = path_with_fake_qmd(HITS_JSON)
    _out, _err, status = run_cli(["search", "supremacy", "--limit", "3"], path: path)
    assert status.success?
    assert_equal "supremacy", searched_query
  end

  def test_reindex_async_prints_started_and_does_not_block
    path = path_with_fake_qmd("")
    out, _err, status = run_cli(["reindex", "--store", File.join(@home, "store"), "--async"], path: path)
    assert status.success?
    assert_equal "reindex (async) plastic-global (started)", out.strip
  end
end
