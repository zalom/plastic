# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

# A throwaway package, home and agent folder for the installer commands.
module InstallerHelper
  PACKAGE_ROOT = File.expand_path("../../..", __dir__)

  def call(*argv, env: {}) = plastic(*argv, env:, table: Plastic::CLI::TABLE)

  def package_version = JSON.parse(File.read(File.join(PACKAGE_ROOT, "package.json"))).fetch("version")

  def fake_package(version)
    root = File.join(@home, "package")
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "package.json"), JSON.generate("version" => version))
    root
  end

  def installed(version, ledger: [])
    FileUtils.mkdir_p(@plastic_home)
    File.write(File.join(@plastic_home, "VERSION"), "#{version}\n")
    lines = ledger.map { |number| JSON.generate("version" => number, "action" => "install", "at" => "2026-10-03T12:00:00+02:00") }
    File.write(File.join(@plastic_home, "versions.json"), lines.map { |line| "#{line}\n" }.join)
  end

  def claude_folder = FileUtils.mkdir_p(File.join(@home, ".claude")).first

  def tree_snapshot(path)
    return [] unless Dir.exist?(path)

    Dir.chdir(path) do
      Dir.glob("**/*", File::FNM_DOTMATCH).reject { |entry| entry.end_with?(".") }.sort.map do |entry|
        File.file?(entry) ? [entry, File.binread(entry)] : [entry, :directory]
      end
    end
  end
end
