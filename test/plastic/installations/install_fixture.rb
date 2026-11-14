# frozen_string_literal: true

require_relative "package_fixture"

# A small shipped package and a fresh home under the test home, with the three
# agent folders the installer knows.
module InstallFixture
  include PackageFixture

  def fresh = File.join(@home, "fresh")

  def plastic = File.join(fresh, ".plastic")

  def config_with(text) = write(File.join(plastic, "config.yml"), text)

  def claude_config = { key: "claude", name: "Claude Code", dir: File.join(fresh, ".claude"), skill_prefix: "/" }

  def codex_config = { key: "codex", name: "Codex CLI", dir: File.join(fresh, ".agents"), home_dir: File.join(fresh, ".codex"), skill_prefix: "$" }

  def hermes_config = { key: "hermes", name: "Hermes", dir: File.join(fresh, ".hermes") }

  def agent_configs = [claude_config, codex_config, hermes_config]

  def shipped
    root = File.join(@home, "shipped")
    files = { "PLASTIC.md" => "plastic\n", "exe/plastic" => "#!/bin/sh\n", "lib/plastic.rb" => "# kernel\n", "lib/plastic/one.rb" => "# one\n",
              "docs/help/tutorial.md" => "tutorial\n", "hooks/session-start" => "#!/bin/sh\n",
              "hooks/statusline" => "#!/bin/sh\n", "skills/demo/SKILL.md" => "demo\n", "skills/_shared.md" => "shared\n",
              "skills/agent-advisor/SKILL.md" => "advisor\n", "agents/demo-role.md" => ROLE, "VERSION" => "2.0.3\n" }
    files.each { |path, text| write(File.join(root, path), text) }
    root
  end

  def shipped_package(version = "2.0.3") = Plastic::Installations::Package.new(shipped, plastic, version)

  def make_agent_folders(*configs) = configs.each { |config| FileUtils.mkdir_p(config[:home_dir] || config[:dir]) }
end
