# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/intent_validator"
require_relative "../scripts/lib/doctor_exclusions"
require_relative "../scripts/doctor"
require_relative "../scripts/dashboard"

# scripts/rebuild-graph and scripts/project-links carry no .rb extension (they
# are executable shell entry points), so `require_relative` cannot resolve
# them (it only appends a .rb/.so suffix, it does not load an exact
# extensionless path). `load` has no such restriction and, like
# require_relative, only defines the classes below: both files guard their
# runner with `if $PROGRAM_NAME == __FILE__`, which stays false for a loaded
# test file, so this has no side effect beyond the class definitions.
load File.expand_path("../scripts/rebuild-graph", __dir__)
load File.expand_path("../scripts/project-links", __dir__)

# Intent 297, task 7: the 1.14 store compatibility proof. Changes NO
# production code. All four 1.14 store walkers already reject dot-prefixed
# children, so `.sessions/` and `.tmp/` are invisible to them today with no
# change; these tests lock that in, since a future refactor of any walker
# could quietly break it and every later batch item (298, 300, 301, batch 4)
# depends on it.
class StoreWalkerCompatTest < Minitest::Test
  TEMPLATES = File.expand_path("../templates", __dir__)
  DAY = "20260829"

  def setup
    @home = Dir.mktmpdir("store-walker-compat")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)

    write_real_intent(@store, "1", "test-intent")

    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "test", now: Time.now)

    root = SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(File.join(root, "b7137962"))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_real_intent(store, id, slug)
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "A real intent"
      sources: []
      chain: []
      created: 2026-08-29
      author: test
      tags: []
      mode: direct
      ---

      ## Intent
      A real intent.

      ## Context
      Fixture.

      ## Outcome
      Fixture.

      ## Insights
      (none)

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
  end

  # --- doctor ------------------------------------------------------------------

  def test_doctor_store_intent_dirs_skips_dot_directories
    doctor = Doctor.new(plastic_home: @home)
    entries = doctor.store_intent_dirs(@store)
    assert_equal ["1--test-intent"], entries
    refute_includes entries, ".sessions"
    refute_includes entries, ".tmp"
  end

  # --- dashboard -----------------------------------------------------------------

  def test_dashboard_intent_dirs_skips_dot_directories
    entries = intent_dirs(@store)
    assert_equal ["1--test-intent"], entries
    refute_includes entries, ".sessions"
    refute_includes entries, ".tmp"
  end

  # --- rebuild-graph ---------------------------------------------------------------

  def test_rebuild_graph_load_nodes_has_no_day_id_or_dot_dir_entry
    tool = RebuildGraph.new(plastic_home: @home)
    nodes = tool.load_nodes(@store)
    assert_equal ["1"], nodes.keys
    refute_includes nodes.keys, DAY
    nodes.each_value do |node|
      refute_match(/\.sessions|\.tmp/, node[:path])
    end
  end

  # --- project-links -----------------------------------------------------------------

  def test_project_links_load_nodes_has_no_day_id_or_dot_dir_entry
    tool = ProjectLinks.new(plastic_home: @home)
    nodes = tool.load_nodes(@store)
    assert_equal ["1"], nodes.keys
    refute_includes nodes.keys, DAY
    nodes.each_value do |node|
      refute_match(/\.sessions|\.tmp/, node[:path])
    end
  end

  # --- folgezettel-id ----------------------------------------------------------------

  def run_folgezettel_id(*args)
    script = File.expand_path("../scripts/folgezettel-id", __dir__)
    out = IO.popen([RbConfig.ruby, script, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def test_folgezettel_id_returns_1_on_store_with_only_a_day_directory
    day_only_store = Dir.mktmpdir("day-only-store")
    SessionLedger.open_day(store: day_only_store, day: DAY, templates: TEMPLATES, author: "test", now: Time.now)

    out, status = run_folgezettel_id(day_only_store)
    assert_equal 0, status
    assert_equal "1", out
  ensure
    FileUtils.rm_rf(day_only_store) if day_only_store
  end

  def test_folgezettel_id_with_real_intent_and_day_dir_present
    out, status = run_folgezettel_id(@store)
    assert_equal 0, status
    assert_equal "2", out, "the day directory must never be mistaken for id 1 or leak into the next id"
  end

  # --- the three id patterns, spec goal ----------------------------------------------

  def test_day_id_passes_all_three_id_patterns
    [DAY, "20261231"].each do |id|
      assert id.match?(IntentValidator::ID_PATTERN), "#{id} must match IntentValidator::ID_PATTERN"
      assert id.match?(DoctorExclusions::FOLGEZETTEL_ID), "#{id} must match DoctorExclusions::FOLGEZETTEL_ID"
      assert root_intent?(id), "#{id} must satisfy dashboard root_intent?"
    end
  end

  def test_hyphenated_day_form_fails_all_three_id_patterns
    hyphenated = "2026-08-29"
    refute hyphenated.match?(IntentValidator::ID_PATTERN), "a hyphenated day id must not match ID_PATTERN"
    refute hyphenated.match?(DoctorExclusions::FOLGEZETTEL_ID), "a hyphenated day id must not match FOLGEZETTEL_ID"
    refute root_intent?(hyphenated), "a hyphenated day id must not satisfy dashboard root_intent?"
  end

  # --- no special case, spec goal -----------------------------------------------------

  WALKER_SOURCES = {
    "scripts/doctor.rb" => "def store_intent_dirs",
    "scripts/dashboard.rb" => "def intent_dirs",
    "scripts/rebuild-graph" => "def load_nodes",
    "scripts/project-links" => "def load_nodes",
  }.freeze

  ID_PATTERN_SOURCES = %w[
    scripts/lib/intent_validator.rb
    scripts/lib/doctor_exclusions.rb
    scripts/dashboard.rb
  ].freeze

  def repo_root
    File.expand_path("..", __dir__)
  end

  def test_no_walker_or_id_pattern_source_special_cases_the_dot_paths
    files = (WALKER_SOURCES.keys + ID_PATTERN_SOURCES).uniq
    offenders = files.select do |rel|
      src = File.read(File.join(repo_root, rel))
      src.include?(".sessions") || src.include?(".tmp")
    end
    assert_empty offenders,
      "these files special-case the day-ledger dot paths, when the design point is that " \
      "the 1.14 surface needs no knowledge of them: #{offenders.join(", ")}"
  end
end
