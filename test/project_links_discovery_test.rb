# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

load File.expand_path("../scripts/project-links", __dir__)

# Regression tests for intent 189: project-links must discover every real store (not the
# old hardcoded %w[plastic knowdb]).
class ProjectLinksDiscoveryTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-links-discovery")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_intent(store_dir, basename, id:, intent:, sources:, chain:, links: nil)
    dir = File.join(store_dir, basename)
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << "id: \"#{id}\"\n"
    content << "intent: \"#{intent}\"\n"
    content << "sources: #{flow(sources)}\n"
    content << "chain: #{flow(chain)}\n"
    content << "created: 2026-06-01\n"
    content << "author: test\n"
    content << "tags: [t]\n"
    content << "---\n\n## Intent\nBody.\n\n"
    content << links if links
    File.write(File.join(dir, "#{basename}.md"), content)
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def write_index(path, body = "(none)")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n#{body}\n\n## Completed\n")
  end

  # A cross-store ref into a store outside the old hardcoded list must now resolve and
  # regenerate ## Links, instead of failing with a resolver miss.
  def test_cross_store_ref_into_previously_invisible_store_now_projects
    global = File.join(@home, "store")
    aar = File.join(@home, "projects", "ai-agents-resources", "store")
    [global, aar].each { |d| FileUtils.mkdir_p(d) }
    write_intent(global, "40--governing", id: "40", intent: "Governing intent",
                        sources: [], chain: ["ai-agents-resources:1"])
    write_intent(aar, "1--resource", id: "1", intent: "Resource intent", sources: [], chain: [])
    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "ai-agents-resources", "INDEX.md"))

    audit = File.join(@home, "audit.md")
    results = ProjectLinks.new(plastic_home: @home, dry_run: false, audit_path: audit).run

    entry = results["global"][:entries].find { |e| e[:id] == "40" }
    refute_nil entry
    refute_equal :failed, entry[:status], "must resolve now that the store is discovered"

    content = File.read(File.join(global, "40--governing", "40--governing.md"))
    assert_includes content, "ai-agents-resources:1--resource"
  end

  # D5: a projects.yml entry with no store directory is reported in the audit, not
  # silently ignored, and does not crash the run.
  def test_registered_project_with_no_store_is_reported
    global = File.join(@home, "store")
    FileUtils.mkdir_p(global)
    write_intent(global, "1--slug", id: "1", intent: "Solo", sources: [], chain: [])
    write_index(File.join(@home, "INDEX.md"))
    File.write(File.join(@home, "projects.yml"),
               YAML.dump({ "projects" => { "ghost-project" => { "path" => "/tmp/ghost" } } }))

    audit = File.join(@home, "audit.md")
    results = ProjectLinks.new(plastic_home: @home, dry_run: true, audit_path: audit).run
    refute_nil results

    audit_text = File.read(audit)
    assert_includes audit_text, "ghost-project"
    assert_includes audit_text, "no store on disk"
  end

  def test_cli_unrecognized_flag_aborts
    script = File.expand_path("../scripts/project-links", __dir__)
    out = IO.popen([RbConfig.ruby, script, "--bogus-flag", "--plastic-home", @home],
                   err: [:child, :out], &:read)
    refute $?.success?, "an unrecognized flag must abort: #{out}"
  end

  # Finding 2 (independent review of intent 189): a genuinely dead cross-store ref
  # and a ref into a store this run never discovered must produce DISTINGUISHABLE
  # FAILED audit lines, not the same generic resolver-miss text for both. Neither
  # writes; both stay :failed (data-safety unchanged), only the message differs.
  def test_failed_audit_lines_distinguish_dead_from_unknown_store
    global = File.join(@home, "store")
    realproj = File.join(@home, "projects", "realproj", "store")
    [global, realproj].each { |d| FileUtils.mkdir_p(d) }
    write_intent(global, "1--dead", id: "1", intent: "Dead ref holder",
                        sources: [], chain: ["realproj:999"])
    write_intent(global, "2--unknown", id: "2", intent: "Unknown store ref holder",
                        sources: [], chain: ["ghostproj:1"])
    write_intent(realproj, "10--real", id: "10", intent: "Real intent", sources: [], chain: [])
    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "realproj", "INDEX.md"))

    audit = File.join(@home, "audit.md")
    results = ProjectLinks.new(plastic_home: @home, dry_run: true, audit_path: audit).run

    dead_entry = results["global"][:entries].find { |e| e[:id] == "1" }
    unknown_entry = results["global"][:entries].find { |e| e[:id] == "2" }
    assert_equal :failed, dead_entry[:status]
    assert_equal :failed, unknown_entry[:status]
    refute_equal dead_entry[:error], unknown_entry[:error]
    assert_includes dead_entry[:error], "dead"
    assert_includes unknown_entry[:error], "unknown store"

    audit_text = File.read(audit)
    assert_includes audit_text, "- 1: #{dead_entry[:error]}"
    assert_includes audit_text, "- 2: #{unknown_entry[:error]}"
  end
end
