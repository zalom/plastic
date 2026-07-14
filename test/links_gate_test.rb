# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/links_gate"

# LinksGate, the pure(ish) decision logic behind the links-gate PreToolUse
# hook (intent 192). Hermetic: every fixture lives under Dir.mktmpdir, never
# touches the real ~/.plastic. LinksGate.decision takes plastic_home as an
# explicit parameter (no ENV read inside the lib), matching the DI convention
# this suite uses everywhere else.
class LinksGateTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("links-gate-test")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_intent(basename, id:, intent:, sources:, chain:, links:)
    dir = File.join(@store, basename)
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << "id: \"#{id}\"\n"
    content << "intent: \"#{intent}\"\n"
    content << "sources: #{flow(sources)}\n"
    content << "chain: #{flow(chain)}\n"
    content << "created: 2026-07-01\n"
    content << "author: test\n"
    content << "tags: [t]\n"
    content << "---\n\n## Intent\nBody #{id}.\n\n"
    content << links
    path = File.join(dir, "#{basename}.md")
    File.write(path, content)
    path
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def write_index(body = "(none)")
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Relocated\n#{body}\n\n## Completed\n")
  end

  def decide(path, before:, after:)
    LinksGate.decision(file_path: path, before_content: before, after_content: after,
                        plastic_home: @home)
  end

  # --- intent_file? path matcher ---

  def test_intent_file_matches_own_named_file_under_store
    assert LinksGate.intent_file?(File.join(@store, "10--demo", "10--demo.md"))
  end

  def test_intent_file_rejects_sibling_lifecycle_files
    refute LinksGate.intent_file?(File.join(@store, "10--demo", "spec.md"))
  end

  def test_intent_file_rejects_non_store_paths
    refute LinksGate.intent_file?("/tmp/random.md")
  end

  # --- allow: unrelated edit (## Links untouched) ---

  def test_allow_when_links_section_is_untouched
    write_index
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    before = File.read(path)
    after = before.sub("Body 20.", "Body 20, edited.")
    assert_nil decide(path, before: before, after: after)
  end

  # --- deny: a hand-typed bullet not backed by frontmatter ---

  def test_deny_hand_typed_bullet_not_backed_by_frontmatter
    write_index
    write_intent("10--other", id: "10", intent: "Other intent", sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    before = File.read(path)
    after = before.sub(
      "<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "- [[10--other|Other intent]]\n"
    )
    reason = decide(path, before: before, after: after)
    refute_nil reason
    assert_includes reason, "PLASTIC LINKS GATE"
    assert_includes reason, "project-links"
  end

  # --- deny: reordering (membership same, order flipped) ---

  def test_deny_reordering_sources_and_chain
    write_index
    write_intent("10--a", id: "10", intent: "A intent", sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    write_intent("11--b", id: "11", intent: "B intent", sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: ["10"], chain: ["11"],
                         links: "## Links\n- [[10--a|A intent]]\n- [[11--b|B intent]]\n")
    before = File.read(path)
    after = before.sub(
      "- [[10--a|A intent]]\n- [[11--b|B intent]]\n",
      "- [[11--b|B intent]]\n- [[10--a|A intent]]\n"
    )
    reason = decide(path, before: before, after: after)
    refute_nil reason, "sources must precede chain; reordering must be denied"
  end

  # --- allow: the edit lands EXACTLY the canonical projection ---

  def test_allow_when_new_links_matches_canonical_projection_exactly
    write_index
    write_intent("10--other", id: "10", intent: "Other intent", sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: ["10"], chain: [],
                         links: "## Links\n<!-- WRONG placeholder -->\n")
    before = File.read(path)
    after = before.sub("## Links\n<!-- WRONG placeholder -->\n", "## Links\n- [[10--other|Other intent]]\n")
    assert_nil decide(path, before: before, after: after),
               "a hand-edit that lands exactly the canonical projection must be allowed"
  end

  # --- allow: fence-aware, an edit inside an example fence never fires ---

  def test_allow_edit_inside_a_fenced_example_links_heading
    write_index
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: <<~MD)
                           ## Context
                           Example:
                           ~~~markdown
                           ## Links
                           - [[99--fake|Fake]]
                           ~~~

                           ## Links
                           <!-- No sources or chain; this intent has no graph edges to project. -->
                         MD
    before = File.read(path)
    after = before.sub("Fake", "Renamed fake")
    assert_nil decide(path, before: before, after: after),
               "editing text inside a fenced example must never touch the REAL ## Links"
  end

  # --- allow: cannot judge (not an intent file) ---

  def test_allow_when_path_is_not_an_intent_file
    assert_nil decide(File.join(@home, "notes.md"), before: "a", after: "b")
  end

  # --- allow: cannot judge (ambiguous real Links sections) ---

  def test_allow_when_links_section_is_ambiguous
    write_index
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: "## Links\nfirst\n\n## Links\nsecond\n")
    before = File.read(path)
    after = before.sub("first", "changed")
    assert_nil decide(path, before: before, after: after)
  end

  # --- allow: dead frontmatter ref pre-existing elsewhere; cannot judge this edit ---

  def test_allow_when_frontmatter_has_an_unrelated_dead_ref
    write_index
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: ["does-not-exist"],
                         chain: [],
                         links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    before = File.read(path)
    after = before.sub(
      "<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "- [[whatever|Anything]]\n"
    )
    assert_nil decide(path, before: before, after: after),
               "a dead frontmatter ref makes the projection uncomputable; this gate must not judge it"
  end
end
