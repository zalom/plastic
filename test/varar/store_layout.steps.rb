# frozen_string_literal: true

require "varar"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"

module StoreLayoutAcceptance
  REPO = File.expand_path("../..", __dir__)
  REGISTRATIONS = {"claude" => [".claude/CLAUDE.md", ".claude/settings.json"],
                   "codex" => [".codex/AGENTS.md", ".codex/hooks.json"]}.freeze

  def self.package
    return @package if @package

    root = Dir.mktmpdir("varar-package")
    Minitest.after_run { FileUtils.remove_entry(root) }
    out, err, status = Open3.capture3("npm", "pack", "--json", "--pack-destination", root, chdir: REPO)
    raise "npm pack: #{err}" unless status.success?

    archive = File.join(root, JSON.parse(out).first.fetch("filename"))
    _out, err, status = Open3.capture3("tar", "-xzf", archive, "-C", root)
    raise "archive extraction: #{err}" unless status.success?

    @package = File.join(root, "package")
  end

  class Scenario
    def initialize(home, harness)
      @home = home
      @harness = harness
      @plastic = File.join(home, ".plastic")
      FileUtils.mkdir_p(File.dirname(File.join(home, REGISTRATIONS.fetch(harness).first)))
      @env = {"HOME" => home, "PLASTIC_HOME" => @plastic, "PLASTIC_TMP" => File.join(home, "tmp"),
              "CODEX_HOME" => File.join(home, ".codex"), "CLAUDE_CONFIG_DIR" => File.join(home, ".claude"),
              "XDG_CONFIG_HOME" => File.join(home, ".config"), "XDG_CACHE_HOME" => File.join(home, ".cache"),
              "PLASTIC_PACKAGE_ROOT" => StoreLayoutAcceptance.package, "RUBYOPT" => nil,
              "GIT_CONFIG_GLOBAL" => File.join(home, ".gitconfig"), "GIT_CONFIG_SYSTEM" => "/dev/null"}
    end

    def command(*args, expected: 0)
      out, err, status = Open3.capture3(@env, RbConfig.ruby,
        File.join(StoreLayoutAcceptance.package, "bin", "plastic"), *args, chdir: @home)
      raise "#{args.join(" ")}: #{status.exitstatus}\n#{out}\n#{err}" unless status.exitstatus == expected

      status.exitstatus.to_s
    end

    def run(row)
      legacy = row.fetch("starting layout") == "legacy"
      if legacy
        FileUtils.mkdir_p(File.join(@plastic, "store"))
        File.write(File.join(@plastic, "store", "history.txt"), "preserve history")
      end
      command("install", "--#{@harness}", "--no-advisor")
      if legacy
        command("migrate", "stores", "--dry-run")
        command("migrate", "stores")
      end
      project = File.join(@home, "project")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, "AGENTS.md"), "# Acceptance fixture\n")
      command("project", "new", "sample", "--path", project)
      command("intent", "new", "Check store layout", "--slug", "layout-check", "--project", "sample")
      result(row, legacy)
    end

    def result(row, legacy)
      backup = File.join(@plastic + "-before-stores-move", "store", "history.txt")
      moved = File.join(@plastic, "stores", "global", "store", "history.txt")
      retained = legacy && File.read(backup) == "preserve history" && File.read(moved) == "preserve history"
      row.merge(
        "global store" => present(File.directory?(File.join(@plastic, "stores", "global", "store"))),
        "project intent" => present(File.file?(File.join(@plastic, "stores", "sample", "store", "1--layout-check", "1--layout-check.md"))),
        "registered harness" => present(REGISTRATIONS.fetch(@harness).all? { |path| File.file?(File.join(@home, path)) }),
        "legacy directory" => present(%w[store projects].any? { |path| File.exist?(File.join(@plastic, path)) }),
        "backup" => retained ? "preserved" : "absent",
        "repeated migration exit" => legacy ? command("migrate", "stores", expected: 3) : "not run"
      )
    end

    def present(value)
      value ? "present" : "absent"
    end
  end
end

steps do
  sensor("the harness, starting layout, global store, project intent, registered harness, legacy directory, backup, and repeated migration exit") do |_state, row|
    Dir.mktmpdir("varar-store-layout") do |home|
      StoreLayoutAcceptance::Scenario.new(home, row.fetch("harness")).run(row)
    end
  end
end
