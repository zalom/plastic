require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/qmd_sync"

# Hermetic unit tests for the QMD helper (intent 45a). A fake runner records the
# qmd argv it would have invoked and returns canned output, so no real `qmd`
# binary, no network, and no model downloads are involved.
class QmdSyncTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("qmd-sync-home")
    FileUtils.mkdir_p(File.join(@home, "store"))
    FileUtils.mkdir_p(File.join(@home, "projects", "dealintell", "store"))
    File.write(File.join(@home, "projects.yml"), <<~YML)
      projects:
        dealintell:
          path: "/Users/zlatko/apps/personal/dealintell"
          status: active
    YML
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # A recording runner. `responses` maps the first argv token to [stdout, ok].
  def fake_runner(responses = {})
    calls = []
    runner = lambda do |args|
      calls << args
      responses.fetch(args.first, ["", true])
    end
    [runner, calls]
  end

  def present
    ->(*) { true }
  end

  def absent
    ->(*) { false }
  end

  def test_detect_true_and_false
    assert_equal true, QmdSync.detect(path_probe: -> { true })
    assert_equal false, QmdSync.detect(path_probe: -> { false })
  end

  def test_collection_name_global_and_project
    assert_equal "plastic-global",
      QmdSync.collection_name(File.join(@home, "store"), plastic_home: @home)
    assert_equal "plastic-dealintell",
      QmdSync.collection_name(File.join(@home, "projects", "dealintell", "store"), plastic_home: @home)
  end

  def test_enumerate_stores_includes_global_and_projects
    stores = QmdSync.enumerate_stores(plastic_home: @home)
    names = stores.map { |s| s[:collection] }
    assert_includes names, "plastic-global"
    assert_includes names, "plastic-dealintell"
  end

  def test_register_issues_collection_add_and_context_add
    runner, calls = fake_runner
    res = QmdSync.register(collection: "plastic-global", dir: "/x/store",
                           runner: runner, detector: present)
    assert res[:ran]
    assert_equal ["collection", "add", "/x/store", "--name", "plastic-global"], calls[0]
    assert_equal ["context", "add"], calls[1][0, 2]
    assert_equal "plastic-global", calls[1][2]
  end

  def test_reindex_issues_update_then_scoped_embed
    runner, calls = fake_runner
    res = QmdSync.reindex(collection: "plastic-dealintell", runner: runner, detector: present)
    assert res[:ran]
    assert_equal ["update"], calls[0]
    assert_equal ["embed", "-c", "plastic-dealintell"], calls[1]
  end

  def test_register_and_reindex_noop_when_absent
    runner, calls = fake_runner
    r1 = QmdSync.register(collection: "c", dir: "/x", runner: runner, detector: absent)
    r2 = QmdSync.reindex(collection: "c", runner: runner, detector: absent)
    assert r1[:skipped]
    assert r2[:skipped]
    assert_empty calls, "no qmd commands when absent"
  end

  def test_status_absent
    st = QmdSync.status(plastic_home: @home, detector: absent)
    assert_equal false, st[:present]
  end

  def test_status_parses_registered_and_missing
    listing = "Collections (1):\n\nplastic-global (qmd://plastic-global/)\n  Files: 10\n"
    runner, = fake_runner("collection" => [listing, true])
    st = QmdSync.status(plastic_home: @home, runner: runner, detector: present)
    assert_equal true, st[:present]
    assert_includes st[:registered], "plastic-global"
    assert_includes st[:missing], "plastic-dealintell"
    assert_equal false, st[:all_registered]
  end
end
