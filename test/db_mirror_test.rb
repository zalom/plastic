require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "sqlite3"

require_relative "../scripts/lib/db"

# Hermetic unit tests for Plastic::DB::Mirror (intent 41, ACTION_6): the
# derived `intents` frontmatter mirror and `edges` graph table, reconciled by
# content_hash (never mtime), debounced, with a format_version bump forcing a
# full cold_rebuild. Everything runs against Dir.mktmpdir stores, injected
# now:/debounce:, single process, no ENV/global seam.
class DbMirrorTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("plastic-db-mirror-store")
    @conn = Plastic::DB.connect(@store_home)
    @t0 = Time.utc(2026, 7, 9, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  # intent "1": flow-style empty sources, flow-style chain to "2"; body has a
  # same-store prose link to "3" and a cross-store prose link to "global:99".
  def write_intent1(tags: %w[plastic alpha])
    write_intent(
      id: "1", slug: "alpha", sources: [], chain: ["2"], tags: tags,
      body_extra: "See [[3--gamma|Gamma Doc]] and [[global:99--ghost|Ghost]]."
    )
  end

  # intent "2": block-style sources referencing "1", flow-style empty chain.
  def write_intent2
    dir = File.join(@store_home, "store", "2--beta")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "2--beta.md"), <<~MD)
      ---
      id: '2'
      intent: Beta intent
      sources:
      - "1"
      chain: []
      created: 2026-01-02
      author: human
      tags:
      - plastic
      - beta
      ---

      ## Intent
      Beta intent body.
    MD
  end

  def write_intent3
    write_intent(id: "3", slug: "gamma", sources: [], chain: [], tags: %w[plastic gamma])
  end

  def write_intent(id:, slug:, sources:, chain:, tags:, body_extra: "")
    dir = File.join(@store_home, "store", "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    fm = +"---\n"
    fm << "id: '#{id}'\n"
    fm << "intent: #{slug.capitalize} intent\n"
    fm << "sources: #{sources.inspect}\n"
    fm << "chain: #{chain.inspect}\n"
    fm << "created: 2026-01-0#{id}\n"
    fm << "author: human\n"
    fm << "tags:\n"
    tags.each { |t| fm << "- #{t}\n" }
    fm << "---\n\n"
    content = "#{fm}## Intent\n#{slug.capitalize} intent body.\n\n## Context\n#{body_extra}\n"
    File.write(File.join(dir, "#{id}--#{slug}.md"), content)
  end

  def intent_row(intent_id)
    cols = %w[id intent_id title slug tags author created chain sources content_hash status quadrant updated_at]
    row = @conn.execute("SELECT #{cols.join(', ')} FROM intents WHERE intent_id = ?", [intent_id]).first
    return nil if row.nil?

    cols.zip(row).to_h
  end

  def edges_for(row_id)
    @conn.execute(
      "SELECT target_ref, target_intent_id, kind, position FROM edges WHERE source_intent_id = ? ORDER BY kind, position",
      [row_id]
    )
  end

  # --- mirror populates -----------------------------------------------------

  def test_mirror_populates_derived_columns_for_every_intent
    write_intent1
    write_intent2
    write_intent3

    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)

    r1 = intent_row("1")
    refute_nil r1
    assert_equal "Alpha intent", r1["title"]
    assert_equal "alpha", r1["slug"]
    assert_equal "plastic,alpha", r1["tags"]
    assert_equal "human", r1["author"]
    assert_equal "2026-01-01", r1["created"]
    assert_equal "2", r1["chain"]
    assert_equal "", r1["sources"]
    refute_nil r1["content_hash"]

    r2 = intent_row("2")
    refute_nil r2
    assert_equal "1", r2["sources"] # block-style frontmatter parses identically to flow
    assert_equal "", r2["chain"]

    r3 = intent_row("3")
    refute_nil r3
  end

  # --- edges -----------------------------------------------------------------

  def test_edges_reflect_chain_sources_and_prose_links
    write_intent1
    write_intent2
    write_intent3
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)

    r1 = intent_row("1")
    r2 = intent_row("2")
    r3 = intent_row("3")

    edges1 = edges_for(r1["id"])
    chain_edge = edges1.find { |e| e[2] == "chain" }
    assert_equal ["2", r2["id"], "chain"], chain_edge[0..2]

    link_to_gamma = edges1.find { |e| e[0] == "3" }
    assert_equal r3["id"], link_to_gamma[1]
    assert_equal "link", link_to_gamma[2]

    link_cross_store = edges1.find { |e| e[0] == "global:99" }
    refute_nil link_cross_store
    assert_nil link_cross_store[1], "cross-store target_ref must leave target_intent_id NULL, not error"
    assert_equal "link", link_cross_store[2]

    edges2 = edges_for(r2["id"])
    sources_edge = edges2.find { |e| e[2] == "sources" }
    assert_equal ["1", r1["id"], "sources"], sources_edge[0..2]

    assert_empty edges_for(r3["id"])
  end

  # --- AC11: content-hash reconcile, never mtime ------------------------------

  def test_touch_without_content_change_is_a_noop
    write_intent1
    write_intent2
    write_intent3
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)

    before = intent_row("1")

    path = File.join(@store_home, "store", "1--alpha", "1--alpha.md")
    FileUtils.touch(path, mtime: @t0 + 3600) # mtime changes, content identical

    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0 + 10, debounce: 0)

    after = intent_row("1")
    assert_equal before["content_hash"], after["content_hash"]
    assert_equal before["updated_at"], after["updated_at"], "an mtime-only touch must not update the row"
  end

  def test_frontmatter_edit_updates_only_that_row
    write_intent1
    write_intent2
    write_intent3
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)

    r1_before = intent_row("1")
    r2_before = intent_row("2")
    r3_before = intent_row("3")

    write_intent1(tags: %w[plastic alpha extra]) # frontmatter content actually changes

    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0 + 10, debounce: 0)

    r1_after = intent_row("1")
    refute_equal r1_before["content_hash"], r1_after["content_hash"]
    assert_equal "plastic,alpha,extra", r1_after["tags"]
    refute_equal r1_before["updated_at"], r1_after["updated_at"]

    assert_equal r2_before["updated_at"], intent_row("2")["updated_at"], "unrelated row must stay untouched"
    assert_equal r3_before["updated_at"], intent_row("3")["updated_at"], "unrelated row must stay untouched"
  end

  # --- Q4: debounce ------------------------------------------------------------

  def test_reconcile_within_debounce_window_is_a_noop
    write_intent1
    write_intent2
    write_intent3
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 2)
    last_after_first = @conn.execute("SELECT last_reconcile_at FROM schema_meta WHERE id = 1").first.first

    write_intent1(tags: %w[plastic alpha extra]) # edit happens inside the debounce window

    result = Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0 + 1, debounce: 2)

    assert_equal :debounced, result
    assert_equal last_after_first, @conn.execute("SELECT last_reconcile_at FROM schema_meta WHERE id = 1").first.first
    assert_equal "plastic,alpha", intent_row("1")["tags"], "the burst edit must not be picked up while debounced"

    result2 = Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0 + 3, debounce: 2)
    assert_equal :reconciled, result2
    assert_equal "plastic,alpha,extra", intent_row("1")["tags"], "the collapsed burst is picked up once the window passes"
  end

  def test_debounce_zero_always_runs
    write_intent1
    write_intent2
    write_intent3
    result1 = Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)
    assert_equal :reconciled, result1

    result2 = Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)
    assert_equal :reconciled, result2
  end

  # --- files win: authoritative columns survive a reconcile -------------------

  def test_reconcile_preserves_authoritative_columns
    write_intent1
    write_intent2
    write_intent3
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)

    r1 = intent_row("1")
    @conn.execute("UPDATE intents SET status = ?, quadrant = ? WHERE id = ?", ["active", "Q1", r1["id"]])

    write_intent1(tags: %w[plastic alpha extra]) # force a derived-column refresh
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0 + 10, debounce: 0)

    after = intent_row("1")
    assert_equal "active", after["status"], "reconcile must never clobber the authoritative status column"
    assert_equal "Q1", after["quadrant"], "reconcile must never clobber the authoritative quadrant column"
    assert_equal "plastic,alpha,extra", after["tags"], "derived columns still refresh"
  end

  # --- AC12: format_version bump forces a cold rebuild ------------------------

  def test_format_version_bump_forces_cold_rebuild
    write_intent1
    write_intent2
    write_intent3
    Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0, debounce: 0)

    r1_before = intent_row("1")
    r3_before = intent_row("3")
    refute_nil r1_before
    refute_nil r3_before

    # Remove intent 3's file so its stale derived row must disappear.
    FileUtils.rm_rf(File.join(@store_home, "store", "3--gamma"))

    @conn.execute("UPDATE schema_meta SET format_version = 0 WHERE id = 1")
    assert Plastic::DB::Schema.rebuild_needed?(@conn)

    result = Plastic::DB::Mirror.reconcile(@conn, store_home: @store_home, now: @t0 + 100, debounce: 0)

    assert_equal :cold_rebuilt, result
    refute Plastic::DB::Schema.rebuild_needed?(@conn)

    assert_nil intent_row("3"), "a stale derived row for a deleted file must be gone after cold_rebuild"

    r1_after = intent_row("1")
    refute_nil r1_after
    assert_equal r1_before["content_hash"], r1_after["content_hash"], "unchanged files rebuild to the same hash"

    stored_version = @conn.execute("SELECT format_version FROM schema_meta WHERE id = 1").first.first
    assert_equal Plastic::DB::Schema::FORMAT_VERSION, stored_version

    # Edges for the removed intent are gone; the surviving chain edge still resolves.
    edges1 = edges_for(r1_after["id"])
    chain_edge = edges1.find { |e| e[2] == "chain" }
    refute_nil chain_edge
    link_to_gamma = edges1.find { |e| e[0] == "3" }
    assert_nil link_to_gamma[1], "the deleted intent 3 no longer resolves locally"
  end
end
