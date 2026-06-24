# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "digest"
require "stringio"

load File.expand_path("../scripts/link-suggest", __dir__)

# Hermetic tests for the link-suggest helper (intent 91, D7). Links are decided by
# CONTEXT INFLUENCE (an agent judgement), so the helper does NOT grade. These tests
# cover what it DOES do: gather candidates with their Intent+Context (discovery via an
# injected finder), record a confirmed frontmatter edge plus a link-decisions.md line,
# the no-write / no-delete guarantee, and drift detection (with fence-skipping). Temp
# store under Dir.mktmpdir; constructor dependency injection only; single process; no
# eval and no ENV / global-constant seam.
class LinkSuggestionsTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("link-suggest-test")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture builder ---

  def write_intent(basename, id:, intent:, sources: [], chain: [], tags: [],
                   context: nil, links: nil)
    dir = File.join(@store, basename)
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << %(id: "#{id}"\n)
    content << %(intent: "#{intent}"\n)
    content << "sources: #{flow(sources)}\n"
    content << "chain: #{flow(chain)}\n"
    content << "tags: [#{tags.join(", ")}]\n"
    content << "created: 2026-06-01\n"
    content << "---\n\n# #{intent}\n\n## Intent\n#{intent}.\n"
    content << "\n## Context\n#{context}\n" if context
    content << "\n## Links\n#{links}\n" if links
    File.write(File.join(dir, "#{basename}.md"), content)
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| %("#{i}") }.join(", ")}]"
  end

  # An explicit, injectable candidate-finder so discovery is deterministic and
  # hermetic (no QMD, no real store). Returns exactly the ids it is told to.
  class FakeFinder
    def initialize(ids)
      @ids = ids
    end

    def call(_subject_id, _nodes)
      @ids
    end
  end

  def tool(finder_ids: nil)
    finder = finder_ids ? FakeFinder.new(finder_ids) : LinkSuggestions::FamilyTagFinder.new
    LinkSuggestions.new(store_dir: @store, finder: finder)
  end

  def digest_tree
    Dir.glob(File.join(@store, "**", "*"))
       .select { |f| File.file?(f) }
       .sort
       .to_h { |f| [f, Digest::SHA256.hexdigest(File.read(f))] }
  end

  # --- gather: discovery + context evidence ---

  def test_gather_returns_injected_candidates_with_context
    write_intent("90--a", id: "90", intent: "Ninety", context: "Subject context here.")
    write_intent("80--b", id: "80", intent: "Deferred the exact fix",
                 context: "Eighty deferred the precise change that ninety now delivers.")
    write_intent("49--c", id: "49", intent: "Link symmetry",
                 context: "Background work on link symmetry, same area only.")

    cands = tool(finder_ids: %w[80 49]).gather("90")
    assert_equal %w[49 80], cands.map(&:id).sort
    eighty = cands.find { |c| c.id == "80" }
    assert_equal "Deferred the exact fix", eighty.label
    assert_includes eighty.intent, "Deferred the exact fix"
    assert_includes eighty.context, "ninety now delivers"
  end

  def test_gather_does_not_grade
    # The candidate carries evidence, never a grade field.
    write_intent("90--a", id: "90", intent: "Ninety", context: "ctx")
    write_intent("80--b", id: "80", intent: "Eighty", context: "ctx")

    cand = tool(finder_ids: %w[80]).gather("90").first
    refute_respond_to cand, :grade
    assert_respond_to cand, :context
  end

  def test_gather_unknown_subject_is_empty
    write_intent("80--b", id: "80", intent: "Eighty")
    assert_empty tool(finder_ids: %w[80]).gather("does-not-exist")
  end

  def test_default_family_finder_discovers_shared_tag_and_adjacent
    write_intent("90--a", id: "90", intent: "Ninety", tags: ["bridge"])
    write_intent("91--b", id: "91", intent: "Ninety-one")          # adjacent id
    write_intent("40--c", id: "40", intent: "Forty", tags: ["bridge"]) # shared tag
    write_intent("12--d", id: "12", intent: "Twelve", tags: ["other"]) # unrelated

    ids = tool.gather("90").map(&:id)
    assert_includes ids, "91"
    assert_includes ids, "40"
    refute_includes ids, "12"
  end

  # --- record_edge: frontmatter edge + decision ledger ---

  def test_record_edge_appends_frontmatter_and_ledger
    write_intent("90--a", id: "90", intent: "Ninety",
                 links: "## Links\n<!-- derived -->\n")
    write_intent("80--b", id: "80", intent: "Eighty")

    body_before = File.read(File.join(@store, "90--a", "90--a.md")).split("---", 3).last
    fixed_now = Time.utc(2026, 6, 24, 12, 0, 0)

    wrote = tool.record_edge("90", "80", edge: :chain, rating: "high",
                             reason: "80 deferred the exact fix 90 delivers", confirm: true,
                             now: fixed_now)
    assert wrote

    content = File.read(File.join(@store, "90--a", "90--a.md"))
    fm = content.split("---", 3)[1]
    assert_match(/chain:.*"80"/, fm, "the chain edge must be recorded in frontmatter")
    assert_equal body_before, content.split("---", 3).last,
                 "the body (## Links and all) must stay byte-identical"

    ledger = File.read(File.join(@store, "90--a", "link-decisions.md"))
    assert_includes ledger, "2026-06-24T12:00:00Z"
    assert_includes ledger, "| 80 | chain | high | 80 deferred the exact fix 90 delivers"
  end

  def test_record_edge_appends_to_existing_ledger
    write_intent("90--a", id: "90", intent: "Ninety")
    write_intent("80--b", id: "80", intent: "Eighty")
    write_intent("70--c", id: "70", intent: "Seventy")

    tool.record_edge("90", "80", edge: :chain, rating: "high", reason: "first",
                     confirm: true, now: Time.utc(2026, 6, 24, 12, 0, 0))
    tool.record_edge("90", "70", edge: :chain, rating: "medium", reason: "second",
                     confirm: true, now: Time.utc(2026, 6, 24, 13, 0, 0))

    ledger = File.read(File.join(@store, "90--a", "link-decisions.md"))
    assert_includes ledger, "| 80 | chain | high | first"
    assert_includes ledger, "| 70 | chain | medium | second"
    assert_equal 1, ledger.scan(/# Link decisions/).size, "header written once"
  end

  def test_record_edge_is_a_noop_without_confirm
    write_intent("90--a", id: "90", intent: "Ninety")
    write_intent("80--b", id: "80", intent: "Eighty")

    before = digest_tree
    wrote = tool.record_edge("90", "80", edge: :chain, rating: "high", reason: "x",
                             confirm: false)
    refute wrote, "record_edge must decline without confirm: true"
    assert_equal before, digest_tree, "declined record_edge must not mutate or create files"
  end

  def test_record_edge_never_duplicates_existing
    write_intent("90--a", id: "90", intent: "Ninety", chain: ["80"])
    write_intent("80--b", id: "80", intent: "Eighty")

    before = digest_tree
    wrote = tool.record_edge("90", "80", edge: :chain, rating: "high", reason: "x",
                             confirm: true)
    refute wrote, "an existing edge must not be re-written"
    assert_equal before, digest_tree
  end

  def test_record_edge_never_deletes
    write_intent("90--a", id: "90", intent: "Ninety", sources: ["79"], chain: ["80"],
                 links: "## Links\n- [[80--b|Eighty]]\n")
    write_intent("80--b", id: "80", intent: "Eighty")
    write_intent("70--c", id: "70", intent: "Seventy")

    file = File.join(@store, "90--a", "90--a.md")
    before = File.read(file)

    tool.record_edge("90", "70", edge: :chain, rating: "low", reason: "added",
                     confirm: true, now: Time.utc(2026, 6, 24, 12, 0, 0))

    after = File.read(file)
    assert_includes after.split("---", 3)[1], '"79"', "existing sources edge preserved"
    assert_includes after.split("---", 3)[1], '"80"', "existing chain edge preserved"
    assert_includes after.split("---", 3)[1], '"70"', "new chain edge appended"
    assert_equal before.split("---", 3).last, after.split("---", 3).last,
                 "body (including ## Links) untouched: nothing deleted"
  end

  # --- drift detection ---

  def test_drift_flags_loose_links_line
    write_intent("90--a", id: "90", intent: "Ninety",
                 links: "## Links\n- [[49--sym|Symmetry]]\n")
    write_intent("49--sym", id: "49", intent: "Symmetry")

    flaws = tool.drift("90")
    assert_equal 1, flaws.size
    assert_equal "49", flaws.first.ref
  end

  def test_no_drift_when_links_backed_by_frontmatter
    write_intent("90--a", id: "90", intent: "Ninety", chain: ["49"],
                 links: "## Links\n- [[49--sym|Symmetry]]\n")
    write_intent("49--sym", id: "49", intent: "Symmetry")

    assert_empty tool.drift("90"), "a ## Links ref backed by a chain edge is not drift"
  end

  def test_wikilink_inside_code_fence_is_not_drift
    write_intent("90--a", id: "90", intent: "Ninety",
                 links: "```markdown\n- [[49--sym|example only]]\n```\n")
    write_intent("49--sym", id: "49", intent: "Symmetry")

    assert_empty tool.drift("90"),
                 "a wikilink inside a fenced code block is an example, not a ref"
  end

  # --- CLI end-to-end (still hermetic; injected store dir) ---

  def test_cli_report_writes_nothing
    write_intent("90--a", id: "90", intent: "Ninety", tags: ["bridge"],
                 links: "## Links\n- [[49--sym|Symmetry]]\n")
    write_intent("40--b", id: "40", intent: "Forty", tags: ["bridge"], context: "ctx")
    write_intent("49--sym", id: "49", intent: "Symmetry")

    before = digest_tree
    out = StringIO.new
    rc = LinkSuggestCLI.run(["90", "--store-dir", @store], out: out)
    assert_equal 0, rc
    assert_equal before, digest_tree, "a report run must not write or delete any file"
    assert_match(/Candidates for 90/, out.string)
    assert_match(/Drift for 90/, out.string)
    assert_match(/\[drift\].*49/, out.string)
  end

  def test_cli_record_without_confirm_writes_nothing
    write_intent("90--a", id: "90", intent: "Ninety")
    write_intent("80--b", id: "80", intent: "Eighty")

    before = digest_tree
    out = StringIO.new
    rc = LinkSuggestCLI.run(
      ["90", "--store-dir", @store, "--record", "80", "--edge", "chain", "--rating", "high",
       "--reason", "deferred fix"], out: out
    )
    assert_equal 0, rc
    assert_equal before, digest_tree, "no --confirm means nothing is written"
    assert_match(/Would record chain edge 90 -> 80/, out.string)
  end

  def test_cli_record_requires_explicit_edge
    write_intent("90--a", id: "90", intent: "Ninety")
    write_intent("80--b", id: "80", intent: "Eighty")

    out = StringIO.new
    rc = LinkSuggestCLI.run(
      ["90", "--store-dir", @store, "--record", "80", "--confirm"], out: out
    )
    assert_equal 1, rc
    assert_match(/--edge sources\|chain/, out.string)
  end

  def test_cli_chain_record_requires_rating
    write_intent("90--a", id: "90", intent: "Ninety")
    write_intent("80--b", id: "80", intent: "Eighty")

    out = StringIO.new
    rc = LinkSuggestCLI.run(
      ["90", "--store-dir", @store, "--record", "80", "--edge", "chain", "--confirm"], out: out
    )
    assert_equal 1, rc
    assert_match(/--rating high\|medium\|low is required/, out.string)
  end

  def test_cli_help_exits_zero_and_is_not_an_intent_id
    out = StringIO.new
    rc = LinkSuggestCLI.run(["--help"], out: out)
    assert_equal 0, rc
    assert_match(/Usage:/, out.string)
    refute_match(/no intent/, out.string, "--help must not be treated as a subject id")
  end
end
