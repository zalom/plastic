# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# What every session carries before the person types: PLASTIC.md, the name and description of each
# agent and skill, and the context that `plastic hook start` prints. The sum stays under the cap.
class StandingSurfaceTest < Plastic::TestCase
  ROOT = File.expand_path("..", __dir__)
  CAP = 5_000

  CLAUDE = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze

  def under_cap?(bytes) = bytes < CAP

  def registered_project
    File.join(@home, "proj").tap do |project_dir|
      FileUtils.mkdir_p([project_dir, File.join(@plastic_home, "stores", "widgets")])
      File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  widgets:\n    path: #{project_dir}\n")
    end
  end

  def boot_context
    project_dir = registered_project
    plastic("intent", "new", "Alpha", "--project", "widgets", env: CLAUDE, table: Plastic::CLI::TABLE)
    plastic("hook", "start", input: JSON.generate(source: "startup", cwd: project_dir), env: CLAUDE, table: Plastic::CLI::TABLE)
  end

  # The name and description of one agent or skill, as the harness lists them.
  def catalog_value(path)
    data = YAML.safe_load(File.read(path).split(/^---\s*$/, 3).fetch(1), permitted_classes: [Date, Time], aliases: true)
    "#{data.fetch("name")}#{data.fetch("description")}"
  end

  def catalog_bytes
    paths = Dir[File.join(ROOT, "agents", "*.md")] + Dir[File.join(ROOT, "skills", "*", "SKILL.md")]
    paths.sum { |path| catalog_value(path).bytesize }
  end

  def standing_bytes(boot_context) = File.binread(File.join(ROOT, "PLASTIC.md")).bytesize + catalog_bytes + boot_context.bytesize

  def test_the_boot_of_a_known_harness_in_a_registered_project_carries_no_unknown_harness_warning
    boot = boot_context

    assert_equal [0, ""], [boot.code, boot.err]
    assert_includes boot.out, "Alpha"
    refute_includes boot.out, "recorded as unknown"
  end

  def test_the_standing_surface_stays_under_its_cap
    boot = boot_context

    assert under_cap?(standing_bytes(boot.out)), "the standing surface is #{standing_bytes(boot.out)} bytes, not under #{CAP}"
  end

  def test_the_scan_finds_the_core_block_and_the_agents
    refute_empty File.read(File.join(ROOT, "PLASTIC.md"))
    refute_empty Dir[File.join(ROOT, "agents", "*.md")]
  end
end
