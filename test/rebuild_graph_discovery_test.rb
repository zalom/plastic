# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

load File.expand_path("../scripts/rebuild-graph", __dir__)

# Regression tests for intent 189: rebuild-graph must discover every real store (not the
# old hardcoded %w[plastic knowdb]) and must never delete a ref into a store it does not
# recognize. `test_ai_agents_resources_cross_store_ref_survives` is the tombstone: the
# exact live shape that proved the data loss on 2026-07-13.
class RebuildGraphDiscoveryTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-rebuild-discovery")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_intent(store_dir, id, sources:, chain:)
    dir = File.join(store_dir, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << "id: \"#{id}\"\n"
    content << "intent: Test #{id}\n"
    content << "sources: #{flow(sources)}\n"
    content << "chain: #{flow(chain)}\n"
    content << "created: 2026-06-01\n"
    content << "author: test\n"
    content << "tags: [t]\n"
    content << "---\n\n## Intent\nBody #{id}.\n\n## Links\n- untouched\n"
    File.write(File.join(dir, "#{id}--slug.md"), content)
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def write_index(path, relocated = "(none)")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n#{relocated}\n\n## Completed\n")
  end

  # THE tombstone: global 26 chains to ai-agents-resources:1, a store outside the old
  # hardcoded list. It must survive a run untouched, and must never be reported dropped.
  def test_ai_agents_resources_cross_store_ref_survives
    global = File.join(@home, "store")
    aar = File.join(@home, "projects", "ai-agents-resources", "store")
    [global, aar].each { |d| FileUtils.mkdir_p(d) }
    write_intent(global, "26", sources: [], chain: ["ai-agents-resources:1"])
    write_intent(aar, "1", sources: [], chain: [])
    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "ai-agents-resources", "INDEX.md"))

    audit = File.join(@home, "audit.md")
    results = RebuildGraph.new(plastic_home: @home, dry_run: true, audit_path: audit).run

    fm = IntentValidator.parse_frontmatter(File.join(global, "26--slug", "26--slug.md"))
    assert_equal ["ai-agents-resources:1"], fm["chain"], "the live edge must survive"

    audit_text = File.read(audit)
    refute_includes audit_text, "ai-agents-resources:1 dropped",
                     "must never be reported as a dropped dead ref"
    total = results.values.sum { |r| r[:changes].size }
    assert_equal 0, total, "nothing should change: the ref is healthy once the store is seen"
  end

  # The unknown-store guard (D2), proven directly: a ref into a store that exists NOWHERE
  # (not on disk, not in projects.yml) is preserved, never dropped, and named in its own
  # audit section.
  def test_ref_into_a_store_that_exists_nowhere_is_preserved_and_reported
    global = File.join(@home, "store")
    FileUtils.mkdir_p(global)
    write_intent(global, "1", sources: [], chain: ["phantom-project:1"])
    write_index(File.join(@home, "INDEX.md"))

    audit = File.join(@home, "audit.md")
    RebuildGraph.new(plastic_home: @home, dry_run: false, audit_path: audit).run

    fm = IntentValidator.parse_frontmatter(File.join(global, "1--slug", "1--slug.md"))
    assert_equal ["phantom-project:1"], fm["chain"], "must survive: the store is unknown, not the id dead"

    audit_text = File.read(audit)
    assert_includes audit_text, "Unknown-store refs preserved"
    assert_includes audit_text, "phantom-project:1"
  end

  # D5: a projects.yml entry with no store directory does not crash the tool and is
  # reported by name in the audit.
  def test_registered_project_with_no_store_is_reported_not_crashed_on
    global = File.join(@home, "store")
    FileUtils.mkdir_p(global)
    write_index(File.join(@home, "INDEX.md"))
    File.write(File.join(@home, "projects.yml"),
               YAML.dump({ "projects" => { "ghost-project" => { "path" => "/tmp/ghost" } } }))

    audit = File.join(@home, "audit.md")
    results = RebuildGraph.new(plastic_home: @home, dry_run: true, audit_path: audit).run
    refute_nil results

    audit_text = File.read(audit)
    assert_includes audit_text, "ghost-project"
    assert_includes audit_text, "no store on disk"
  end

  # The arg-loop hazard this action closes: an unrecognized flag must abort, never fall
  # through to running with defaults.
  def test_cli_unrecognized_flag_aborts
    script = File.expand_path("../scripts/rebuild-graph", __dir__)
    out = IO.popen([RbConfig.ruby, script, "--bogus-flag", "--plastic-home", @home],
                   err: [:child, :out], &:read)
    refute $?.success?, "an unrecognized flag must abort: #{out}"
  end
end
