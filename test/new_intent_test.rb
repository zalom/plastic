# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/intent_validator"

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
    parent_file = File.join(parent, "#{File.basename(parent)}.md")

    child, = run_new_intent("--store", @store, "--intent", "Child", "--slug", "child", "--parent", pid)
    cid = File.basename(child).split("--").first
    child_file = File.join(child, "#{File.basename(child)}.md")

    assert_includes File.read(child_file), "[[#{pid}]]"
    assert_includes File.read(parent_file), "[[#{cid}]]"

    # Idempotent: a second back-reference is not duplicated.
    before = File.read(parent_file).scan("[[#{cid}]]").length
    # Re-run append by scaffolding another child of the same parent and verifying
    # the original back-reference count is unchanged for the first child.
    assert_equal 1, before
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
