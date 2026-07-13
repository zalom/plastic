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
end
