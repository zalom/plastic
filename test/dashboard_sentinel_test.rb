# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../scripts/dashboard"

# ACTION_2 (intent 60b): a freshly scaffolded intent whose lifecycle files are
# sentinel placeholders must read as What/Why in the dashboard: the
# spec/plan/checklist/outcome flags are absent and status is not completed.
class DashboardSentinelTest < Minitest::Test
  SENTINEL = "<!-- plastic:placeholder -->".freeze

  def setup
    @store = Dir.mktmpdir("dash-sentinel")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def status_index
    { active: [], abandoned: [], completed: [] }
  end

  def store_info
    { store: @store, scope: :global, index: File.join(@store, "INDEX.md") }
  end

  def scaffold(id, slug)
    dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "#{id}--#{slug}.md"),
               "---\nid: \"#{id}\"\nintent: \"Demo\"\nchain: []\n---\n\n## Intent\nDemo\n\n## Context\nWhy this exists\n")
    %w[spec.md plan.md checklist.md outcome.md].each do |f|
      File.write(File.join(dir, f), "#{SENTINEL}\n\nplaceholder\n")
    end
    dir
  end

  def test_scaffolded_intent_flags_absent_and_not_completed
    scaffold("60", "demo")
    rec = parse_intent(store_info, "60--demo", status_index)
    refute rec[:spec]
    refute rec[:plan]
    refute rec[:checklist]
    refute rec[:outcome]
    refute_equal "completed", rec[:status]
  end

  def test_scaffolded_intent_lifecycle_stage_is_why
    scaffold("60", "demo")
    rec = parse_intent(store_info, "60--demo", status_index)
    assert_equal "why", lifecycle_stage(rec)
  end

  def test_real_spec_flips_flag_and_stage
    dir = scaffold("60", "demo")
    File.write(File.join(dir, "spec.md"), "# Spec\nreal content\n")
    rec = parse_intent(store_info, "60--demo", status_index)
    assert rec[:spec]
    refute_equal "what", lifecycle_stage(rec)
  end
end
