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
    _out, err, status = Open3.capture3("npm", "pack", "--pack-destination", root, chdir: REPO)
    raise "npm pack: #{err}" unless status.success?

    archives = Dir.glob(File.join(root, "*.tgz"))
    raise "npm pack: expected one archive, found #{archives.length}" unless archives.length == 1

    archive = archives.fetch(0)
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

    def refuse_old_package(row)
      command("install", "--#{@harness}", "--no-advisor")
      version_file = File.join(@plastic, "VERSION")
      version = File.read(version_file)
      File.open(File.join(@plastic, "versions.json"), "a") do |file|
        file.puts(JSON.generate("version" => "1.14.1", "action" => "install"))
      end
      paths = [version_file, File.join(@plastic, "versions.json"),
        *REGISTRATIONS.fetch(@harness).map { |path| File.join(@home, path) }]
      before = paths.to_h { |path| [path, File.binread(path)] }
      bin = File.join(@home, "fake-bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "npm"), "#!/bin/sh\nprintf '%s\n' '{\"beta\":\"1.10.0\"}'\n")
      File.write(File.join(bin, "npx"), "#!/bin/sh\nexit 99\n")
      FileUtils.chmod(0o755, Dir.glob(File.join(bin, "*")))
      @env["PATH"] = "#{bin}:#{ENV.fetch("PATH")}"
      args = (row.fetch("command") == "update") ? %w[update --beta --yes] : %w[rollback --version 1.14.1]
      code = command(*args, expected: 3)
      unchanged = before.all? { |path, bytes| File.binread(path) == bytes }
      row.merge("exit" => code, "installation" => unchanged ? "unchanged" : "changed",
        "version" => (File.read(version_file) == version) ? "unchanged" : "changed")
    end

    def project_links(row)
      command("install", "--#{@harness}", "--no-advisor")
      before = tree_snapshot
      args = ["project", "links"]
      args << "--dry-run" if row.fetch("mode") == "preview"
      command(*args)
      audit = File.join(@plastic, "stores", "global", "resources", "audit--links-projection.md")
      row.merge("legacy tree" => present(File.exist?(File.join(@plastic, "projects"))),
        "audit" => present(File.file?(audit)), "changes" => (tree_snapshot == before) ? "none" : "written")
    end

    def tree_snapshot
      Dir.glob(File.join(@plastic, "**", "*"), File::FNM_DOTMATCH).sort.to_h do |path|
        [path, File.file?(path) ? File.binread(path) : nil]
      end
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

  sensor("the harness, command, exit, installation, and version") do |_state, row|
    Dir.mktmpdir("varar-update-safety") do |home|
      StoreLayoutAcceptance::Scenario.new(home, row.fetch("harness")).refuse_old_package(row)
    end
  end
  sensor("the harness, mode, legacy tree, audit, and changes") do |_state, row|
    Dir.mktmpdir("varar-project-links") do |home|
      StoreLayoutAcceptance::Scenario.new(home, row.fetch("harness")).project_links(row)
    end
  end
end
