# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# What every session carries before the person types: PLASTIC.md, the name and description of each
# agent and skill, and the context that `plastic hook start` prints. The sum stays under the cap.
class StandingSurfaceTest < Plastic::TestCase
  ROOT = File.expand_path("..", __dir__)
  CAP = 5_000
  START = JSON.generate(source: "startup")

  def within_cap?(bytes) = bytes <= CAP

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

  def test_the_sum_over_the_cap_is_refused
    refute within_cap?(CAP + 1)
  end

  def test_the_sum_under_the_cap_is_kept
    assert within_cap?(CAP - 1)
  end

  def test_the_standing_surface_stays_under_its_cap
    boot = plastic("hook", "start", input: START, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [boot.code, boot.err]
    assert within_cap?(standing_bytes(boot.out)), "the standing surface is #{standing_bytes(boot.out)} bytes, over #{CAP}"
  end

  def test_the_scan_finds_the_core_block_and_the_agents
    refute_empty File.read(File.join(ROOT, "PLASTIC.md"))
    refute_empty Dir[File.join(ROOT, "agents", "*.md")]
  end
end
