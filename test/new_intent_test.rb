# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/intent_validator"
require_relative "../scripts/lib/links_section"
require_relative "../scripts/doctor"

# ACTION_4 (intent 60b): the new-intent scaffolding CLI. Drive the real script as
# a subprocess (hermetic tmp store, repo templates) and assert it scaffolds a
# born-complete intent with sentinel placeholder lifecycle files.
class NewIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/new-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  SENTINEL = "<!-- plastic:placeholder -->".freeze

  def setup
    @store = Dir.mktmpdir("new-intent")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def run_new_intent(*args)
    out = IO.popen([RbConfig.ruby, SCRIPT, "--templates", TEMPLATES, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def first_line(path)
    File.open(path, &:gets).to_s.chomp
  end

  def test_single_invocation_scaffolds_complete_intent
    dir, status = run_new_intent("--store", @store, "--intent", "Build the thing", "--slug", "build-thing")
    assert_equal 0, status, "expected exit 0, got: #{dir}"
    assert File.directory?(dir)
    assert File.directory?(File.join(dir, "actions"))
    assert File.directory?(File.join(dir, "resources"))
    base = File.basename(dir)
    assert File.exist?(File.join(dir, "#{base}.md"))
    %w[spec.md plan.md checklist.md outcome.md].each do |f|
      assert File.exist?(File.join(dir, f)), "#{f} should exist"
    end
  end

  def test_lifecycle_files_first_line_is_sentinel
    dir, = run_new_intent("--store", @store, "--intent", "Demo", "--slug", "demo")
    %w[spec.md plan.md checklist.md outcome.md].each do |f|
      assert_equal SENTINEL, first_line(File.join(dir, f)), "#{f} first line must be the sentinel"
    end
  end

  def test_intent_file_is_born_complete
    dir, = run_new_intent("--store", @store, "--intent", "Demo", "--slug", "demo")
    result = IntentValidator.validate(dir)
    assert result[:ok], "intent file must be born complete: #{result[:errors].inspect}"
  end

  def test_root_id_is_numeric
    dir, = run_new_intent("--store", @store, "--intent", "Root", "--slug", "root")
    id = File.basename(dir).split("--").first
    assert_match(/\A\d+\z/, id)
  end

  def test_branch_id_starts_with_parent
    parent, = run_new_intent("--store", @store, "--intent", "Parent", "--slug", "parent")
    pid = File.basename(parent).split("--").first
    child, status = run_new_intent("--store", @store, "--intent", "Child", "--slug", "child", "--parent", pid)
    assert_equal 0, status
    cid = File.basename(child).split("--").first
    assert cid.start_with?(pid), "child id #{cid} should start with parent #{pid}"
  end

  def test_scaffolded_intent_never_advances_past_why
    dir, = run_new_intent("--store", @store, "--intent", "Demo", "--slug", "demo")
    assert_equal "why", Bridge.derive_stage(dir)
  end

  def test_reciprocal_link_is_wired_and_idempotent
    parent, = run_new_intent("--store", @store, "--intent", "Parent", "--slug", "parent")
    pid = File.basename(parent).split("--").first
    parent_base = File.basename(parent)
    parent_file = File.join(parent, "#{parent_base}.md")

    child, = run_new_intent("--store", @store, "--intent", "Child", "--slug", "child", "--parent", pid)
    cid = File.basename(child).split("--").first
    child_base = File.basename(child)
    child_file = File.join(child, "#{child_base}.md")

    # Canonical I5 projection (intent 72): clickable id--slug target + full intent
    # label, NOT the legacy bare [[id]] form.
    assert_includes File.read(child_file), "- [[#{parent_base}|Parent]]"
    assert_includes File.read(parent_file), "- [[#{child_base}|Child]]"

    # Idempotent: the canonical back-reference appears exactly once in the parent.
    assert_equal 1, File.read(parent_file).scan("[[#{child_base}|Child]]").length
  end

  def test_requires_store_intent_and_slug
    _out, status = run_new_intent("--intent", "x", "--slug", "y")
    refute_equal 0, status
  end

  # --- I1 frontmatter chain backlink (intent 68, ACTION_6) ---

  def chain_of(intent_dir)
    file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    Array(IntentValidator.parse_frontmatter(file)["chain"]).map(&:to_s)
  end

  def sources_of(intent_dir)
    file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    Array(IntentValidator.parse_frontmatter(file)["sources"]).map(&:to_s)
  end

  def test_parent_gets_child_in_chain_frontmatter
    parent, = run_new_intent("--store", @store, "--intent", "Parent", "--slug", "parent")
    pid = File.basename(parent).split("--").first

    child, = run_new_intent("--store", @store, "--intent", "Child", "--slug", "child", "--parent", pid)
    cid = File.basename(child).split("--").first

    # The I1 reciprocal backlink lands in the PARENT's frontmatter chain (distinct
    # from the `## Links` wikilink), and the parent stays born-complete.
    assert_includes chain_of(parent), cid
    assert IntentValidator.validate(parent)[:ok], "parent must stay born-complete"
  end

  # --- Born-canonical ## Links projection (intent 72) ---

  def links_section_of(intent_dir)
    file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    body = IntentValidator.body_of(File.read(file))
    LinksSection.extract_section(body)
  end

  def test_root_with_no_sources_is_born_with_empty_state_links
    dir, = run_new_intent("--store", @store, "--intent", "Lonely root", "--slug", "lonely")
    assert_equal(
      "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      links_section_of(dir),
      "a root with no sources/chain must be born with the canonical empty-state ## Links"
    )
  end

  def test_child_links_are_canonical_sources_first
    parent, = run_new_intent("--store", @store, "--intent", "Parent", "--slug", "parent")
    pbase = File.basename(parent)
    child, = run_new_intent("--store", @store, "--intent", "Child", "--slug", "child",
                            "--parent", pbase.split("--").first)
    assert_equal(
      "## Links\n- [[#{pbase}|Parent]]\n",
      links_section_of(child),
      "a --parent child must be born with the canonical sources-first ## Links"
    )
  end

  def test_sources_path_links_are_canonical
    a, = run_new_intent("--store", @store, "--intent", "Root A", "--slug", "root-a")
    abase = File.basename(a)
    b, = run_new_intent("--store", @store, "--intent", "Root B", "--slug", "root-b",
                        "--sources", abase.split("--").first)
    assert_equal "## Links\n- [[#{abase}|Root A]]\n", links_section_of(b),
                 "a --sources intent must be born with a canonical sources-first ## Links"
    # The source A gained B in its chain; its ## Links was re-projected canonically.
    bbase = File.basename(b)
    assert_equal "## Links\n- [[#{bbase}|Root B]]\n", links_section_of(a),
                 "the source intent's ## Links must be re-projected canonically (chain entry)"
  end

  # Cross-store source: a project intent created with a cross-store --sources ref
  # (global:<id>) must be born with a canonical cross-store link
  # [[store:id--slug|<full intent text>]], slug + label resolved from the target
  # store. Build a real <home>/store + <home>/projects/<slug>/store family.
  def test_cross_store_source_renders_canonical_cross_store_link
    home = Dir.mktmpdir("new-intent-xstore")
    global = File.join(home, "store")
    proj = File.join(home, "projects", "plastic", "store")
    [global, proj].each { |d| FileUtils.mkdir_p(d) }
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n")
    File.write(File.join(home, "projects", "plastic", "INDEX.md"), "# Index\n\n## Relocated\n(none)\n")

    gov, = run_new_intent("--store", global, "--intent", "Governing intent", "--slug", "governing")
    gov_base = File.basename(gov)
    gov_id = gov_base.split("--").first

    child, status = run_new_intent("--store", proj, "--intent", "Sourced child", "--slug",
                                   "sourced-child", "--sources", "global:#{gov_id}")
    assert_equal 0, status, "cross-store --sources create must succeed: #{child}"
    assert_equal "## Links\n- [[global:#{gov_base}|Governing intent]]\n", links_section_of(child),
                 "cross-store source must render [[global:id--slug|label]]"
  ensure
    FileUtils.rm_rf(home) if home
  end

  # The decisive guarantee: a freshly created intent AND its parent are both
  # canonical, i.e. the doctor graph_links_projection check passes with no drift.
  # Build a real <home>/store layout so the doctor resolves the store family.
  def test_created_intents_pass_graph_links_projection_no_drift
    home = Dir.mktmpdir("new-intent-home")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n\n## Completed\n")

    parent, = run_new_intent("--store", store, "--intent", "Parent", "--slug", "parent")
    pid = File.basename(parent).split("--").first
    run_new_intent("--store", store, "--intent", "Child", "--slug", "child", "--parent", pid)
    run_new_intent("--store", store, "--intent", "Lonely", "--slug", "lonely")

    doctor = Doctor.new(plastic_home: home)
    check = doctor.check_conventions.find { |c| c[:name] == "graph_links_projection" }
    assert_equal "pass", check[:status],
                 "freshly created intents must be born canonical (no drift): #{check[:details].inspect}"
  ensure
    FileUtils.rm_rf(home) if home
  end

  def test_sources_path_gets_child_in_chain_frontmatter
    # The related-but-not-spawned / created-from scenario: B is created with
    # --sources A (no --parent). A's frontmatter chain must gain B (I1), and B's
    # sources must include A (the line-126 redundant-explicit fold).
    a, = run_new_intent("--store", @store, "--intent", "Root A", "--slug", "root-a")
    a_id = File.basename(a).split("--").first

    b, = run_new_intent("--store", @store, "--intent", "Root B", "--slug", "root-b", "--sources", a_id)
    b_id = File.basename(b).split("--").first

    assert_includes chain_of(a), b_id, "source intent A must backlink B in its chain"
    assert_includes sources_of(b), a_id, "B's sources must include A"
    assert IntentValidator.validate(a)[:ok], "source intent must stay born-complete"
  end
end
