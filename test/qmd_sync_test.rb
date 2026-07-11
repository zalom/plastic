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
    FileUtils.mkdir_p(File.join(@home, "roadmaps"))
    FileUtils.mkdir_p(File.join(@home, "projects", "dealintell", "store"))
    FileUtils.mkdir_p(File.join(@home, "projects", "dealintell", "roadmaps"))
    File.write(File.join(@home, "projects.yml"), <<~YML)
      projects:
        dealintell:
          path: "/Users/zlatko/apps/personal/dealintell"
          status: active
    YML
  end

  # A tmp plastic_home with only store/ dirs (no roadmaps/ anywhere), for
  # asserting the negative branch: a tier with no roadmap yet contributes no
  # roadmap-companion entry and no phantom "missing" warning.
  def bare_home
    home = Dir.mktmpdir("qmd-sync-bare-home")
    FileUtils.mkdir_p(File.join(home, "store"))
    FileUtils.mkdir_p(File.join(home, "projects", "dealintell", "store"))
    File.write(File.join(home, "projects.yml"), <<~YML)
      projects:
        dealintell:
          path: "/Users/zlatko/apps/personal/dealintell"
          status: active
    YML
    yield home
  ensure
    FileUtils.rm_rf(home)
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

  def test_collection_name_resolves_roadmap_companion_suffix
    assert_equal "plastic-global-roadmaps",
      QmdSync.collection_name(File.join(@home, "roadmaps"), plastic_home: @home)
    assert_equal "plastic-dealintell-roadmaps",
      QmdSync.collection_name(File.join(@home, "projects", "dealintell", "roadmaps"), plastic_home: @home)
  end

  def test_enumerate_stores_includes_global_and_projects
    stores = QmdSync.enumerate_stores(plastic_home: @home)
    names = stores.map { |s| s[:collection] }
    assert_includes names, "plastic-global"
    assert_includes names, "plastic-dealintell"
  end

  def test_enumerate_stores_includes_roadmap_companions_when_dirs_exist
    stores = QmdSync.enumerate_stores(plastic_home: @home)
    by_collection = stores.each_with_object({}) { |s, h| h[s[:collection]] = s[:dir] }
    assert_equal File.expand_path(File.join(@home, "roadmaps")),
                 by_collection["plastic-global-roadmaps"]
    assert_equal File.expand_path(File.join(@home, "projects", "dealintell", "roadmaps")),
                 by_collection["plastic-dealintell-roadmaps"]
  end

  def test_enumerate_stores_omits_roadmap_companion_when_dir_absent
    bare_home do |home|
      stores = QmdSync.enumerate_stores(plastic_home: home)
      names = stores.map { |s| s[:collection] }
      refute_includes names, "plastic-global-roadmaps"
      refute_includes names, "plastic-dealintell-roadmaps"
    end
  end

  def test_register_adds_when_not_present
    # default fake returns empty listing, so collection is absent -> add issued
    runner, calls = fake_runner
    res = QmdSync.register(collection: "plastic-global", dir: "/x/store",
                           runner: runner, detector: present)
    assert res[:ran]
    add = calls.find { |c| c[0, 2] == ["collection", "add"] }
    assert_equal ["collection", "add", "/x/store", "--name", "plastic-global"], add
  end

  def test_register_is_idempotent_when_collection_exists
    listing = "Collections (1):\n\nplastic-global (qmd://plastic-global/)\n"
    runner, calls = fake_runner("collection" => [listing, true])
    res = QmdSync.register(collection: "plastic-global", dir: "/x/store",
                           runner: runner, detector: present)
    assert res[:ok]
    assert_equal "exists", res[:output]
    refute calls.any? { |c| c[0, 2] == ["collection", "add"] },
           "no collection add when it already exists"
  end

  def test_register_all_loop_registers_roadmap_companion_dirs
    # Mirrors the loop body `qmd-sync register --all` runs (scripts/qmd-sync):
    # iterate enumerate_stores, register each dir that exists on disk.
    runner, calls = fake_runner
    stores = QmdSync.enumerate_stores(plastic_home: @home)
    stores.each do |s|
      next unless Dir.exist?(s[:dir])
      QmdSync.register(collection: s[:collection], dir: s[:dir], runner: runner, detector: present)
    end
    adds = calls.select { |c| c[0, 2] == ["collection", "add"] }
    assert adds.any? { |c| c[2] == File.expand_path(File.join(@home, "roadmaps")) && c[4] == "plastic-global-roadmaps" },
           "register --all must issue a collection add for the global roadmaps dir"
    assert adds.any? { |c| c[2] == File.expand_path(File.join(@home, "projects", "dealintell", "roadmaps")) && c[4] == "plastic-dealintell-roadmaps" },
           "register --all must issue a collection add for the project roadmaps dir"
  end

  def test_reindex_issues_update_then_scoped_embed
    runner, calls = fake_runner
    res = QmdSync.reindex(collection: "plastic-dealintell", runner: runner, detector: present)
    assert res[:ran]
    assert_equal ["update"], calls[0]
    assert_equal ["embed", "-c", "plastic-dealintell"], calls[1]
  end

  def test_reindex_async_noop_when_absent
    spawned = []
    spawner = ->(c) { spawned << c; 99 }
    res = QmdSync.reindex_async(collection: "plastic-dealintell", detector: absent, spawner: spawner)
    assert res[:skipped]
    assert_empty spawned, "spawner must not run when qmd is absent"
  end

  def test_reindex_async_spawns_via_injected_spawner
    spawned = []
    spawner = ->(c) { spawned << c; 4242 }
    res = QmdSync.reindex_async(collection: "plastic-dealintell", detector: present, spawner: spawner)
    assert_equal({ ran: true, async: true, pid: 4242 }, res)
    assert_equal ["plastic-dealintell"], spawned, "spawner received the collection name"
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

  def test_status_all_registered_true_when_no_roadmaps_dirs_exist
    bare_home do |home|
      listing = "Collections (2):\n\nplastic-global (qmd://plastic-global/)\n" \
                "plastic-dealintell (qmd://plastic-dealintell/)\n"
      runner, = fake_runner("collection" => [listing, true])
      st = QmdSync.status(plastic_home: home, runner: runner, detector: present)
      assert_empty st[:missing], "a tier with no roadmaps/ dir must never be reported missing"
      assert_equal true, st[:all_registered]
    end
  end

  def test_status_reports_missing_for_existing_but_unregistered_roadmap_collection
    listing = "Collections (2):\n\nplastic-global (qmd://plastic-global/)\n" \
              "plastic-dealintell (qmd://plastic-dealintell/)\n"
    runner, = fake_runner("collection" => [listing, true])
    st = QmdSync.status(plastic_home: @home, runner: runner, detector: present)
    assert_includes st[:missing], "plastic-global-roadmaps"
    assert_includes st[:missing], "plastic-dealintell-roadmaps"
    assert_equal false, st[:all_registered]
  end

  SEARCH_JSON = <<~JSON
    [
      {"docid":"#a1","score":0.81,"file":"qmd://plastic-plastic/15--enforce/15.md","line":1,"title":"Enforce Plastic supremacy","snippet":"@@ ..."},
      {"docid":"#b2","score":0.62,"file":"qmd://plastic-global/9--org/9.md","line":3,"title":"GitHub org migration","snippet":"@@ ..."},
      {"docid":"#c3","score":0.40,"file":"qmd://plastic-plastic/3--obs/3.md","line":2,"title":"Store observer","snippet":"@@ ..."}
    ]
  JSON

  def test_search_returns_scored_hits_above_min_score
    runner, calls = fake_runner("search" => [SEARCH_JSON, true])
    hits = QmdSync.search("supremacy", collections: ["plastic-plastic", "plastic-global"],
                          min_score: 0.5, limit: 3, runner: runner, detector: present)
    assert_equal 2, hits.size, "0.40 hit is below min_score and must be dropped"
    assert_equal 0.81, hits.first[:score]
    assert_equal "Enforce Plastic supremacy", hits.first[:title]
    assert_includes calls.first, "--json"
    assert_includes calls.first, "-c"
    assert_includes calls.first, "plastic-global"
  end

  def test_search_respects_limit
    runner, _ = fake_runner("search" => [SEARCH_JSON, true])
    hits = QmdSync.search("x", collections: ["plastic-plastic"], min_score: 0.0, limit: 1, runner: runner, detector: present)
    assert_equal 1, hits.size
  end

  def test_search_noops_when_qmd_absent
    runner, calls = fake_runner("search" => [SEARCH_JSON, true])
    hits = QmdSync.search("x", collections: ["plastic-plastic"], runner: runner, detector: ->(*) { false })
    assert_equal [], hits
    assert_empty calls, "must not shell out when qmd is absent"
  end

  def test_search_survives_bad_json
    runner, _ = fake_runner("search" => ["not json", true])
    assert_equal [], QmdSync.search("x", collections: ["plastic-plastic"], runner: runner, detector: present)
  end

  def test_collections_for_cwd_matches_project_plus_global
    listing = "Collections (1):\n\nplastic-dealintell (qmd://plastic-dealintell/)\n"
    runner, = fake_runner("collection" => [listing, true])
    cols = QmdSync.collections_for_cwd("/Users/zlatko/apps/personal/dealintell", plastic_home: @home,
                                       runner: runner, detector: present)
    assert_equal ["plastic-dealintell", "plastic-global"], cols
  end

  def test_collections_for_cwd_matches_subdir_of_project
    listing = "Collections (1):\n\nplastic-dealintell (qmd://plastic-dealintell/)\n"
    runner, = fake_runner("collection" => [listing, true])
    cols = QmdSync.collections_for_cwd("/Users/zlatko/apps/personal/dealintell/lib/x", plastic_home: @home,
                                       runner: runner, detector: present)
    assert_equal ["plastic-dealintell", "plastic-global"], cols
  end

  def test_collections_for_cwd_falls_back_to_global_only
    listing = "Collections (1):\n\nplastic-dealintell (qmd://plastic-dealintell/)\n"
    runner, = fake_runner("collection" => [listing, true])
    cols = QmdSync.collections_for_cwd("/tmp/somewhere-else", plastic_home: @home,
                                       runner: runner, detector: present)
    assert_equal ["plastic-global"], cols
  end

  def test_collections_for_cwd_includes_registered_roadmap_companions
    listing = "Collections (2):\n\nplastic-dealintell (qmd://plastic-dealintell/)\n" \
              "plastic-dealintell-roadmaps (qmd://plastic-dealintell-roadmaps/)\n"
    runner, = fake_runner("collection" => [listing, true])
    cols = QmdSync.collections_for_cwd("/Users/zlatko/apps/personal/dealintell", plastic_home: @home,
                                       runner: runner, detector: present)
    assert_equal ["plastic-dealintell", "plastic-dealintell-roadmaps", "plastic-global"], cols
  end

  def test_collections_for_cwd_omits_unregistered_roadmap_companion_without_erroring
    listing = "Collections (1):\n\nplastic-dealintell (qmd://plastic-dealintell/)\n"
    runner, = fake_runner("collection" => [listing, true])
    cols = QmdSync.collections_for_cwd("/Users/zlatko/apps/personal/dealintell", plastic_home: @home,
                                       runner: runner, detector: present)
    assert_equal ["plastic-dealintell", "plastic-global"], cols
  end

  # --- fresh? (intent 84 freshness probe) ---

  STATUS_FRESH = <<~TXT
    QMD Status
    Documents
      Total:    833 files indexed
      Pending:  0 need embedding
  TXT

  STATUS_STALE = <<~TXT
    QMD Status
    Documents
      Total:    833 files indexed
      Pending:  20 need embedding (run 'qmd embed')
  TXT

  STATUS_NO_PENDING = <<~TXT
    QMD Status
    Documents
      Total:    833 files indexed
  TXT

  def test_fresh_true_when_pending_zero
    runner, _ = fake_runner("status" => [STATUS_FRESH, true])
    assert_equal true, QmdSync.fresh?(runner: runner)
  end

  def test_fresh_false_when_pending_nonzero
    runner, _ = fake_runner("status" => [STATUS_STALE, true])
    assert_equal false, QmdSync.fresh?(runner: runner)
  end

  def test_fresh_true_on_parse_miss
    # No Pending line -> conservative fresh (do not block reads on a parse miss).
    runner, _ = fake_runner("status" => [STATUS_NO_PENDING, true])
    assert_equal true, QmdSync.fresh?(runner: runner)
  end

  def test_fresh_false_when_runner_fails
    runner, _ = fake_runner("status" => ["", false])
    assert_equal false, QmdSync.fresh?(runner: runner)
  end
end
