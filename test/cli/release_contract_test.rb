# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../lib/cli_fixture"
require "tmpdir"
require "open3"
require "json"
require "rbconfig"

class CliReleaseContractTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-release-contract")
    @fixture = CliFixture.new(@dir).global_store.project("sample")
    @env = @fixture.env("HOME" => @fixture.home, "PLASTIC_TMP" => File.join(@dir, "tmp"),
      "CLAUDE_CODE_SESSION_ID" => "release-contract-test")
    @bin = ENV.fetch("PLASTIC_ACCEPTANCE_BIN") { File.expand_path("../../bin/plastic", __dir__) }
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def command(*args, directory: @dir)
    stdout, stderr, status = Open3.capture3(@env, RbConfig.ruby, @bin, *args, "--json", chdir: directory)
    [JSON.parse(stdout), stderr, status.exitstatus]
  end

  def new_intent
    result, error, status = command("intent", "new", "A sample delivery", "--slug", "sample", "--project", "sample")

    raise error unless status.zero?
    raise "new intent lost scope" unless result.fetch("next") == "plastic intent spec 1 --project sample"

    @fixture.intent_dir("sample", "1")
  end

  def test_new_show_spec_and_direct_step_produce_one_json_document
    new_intent
    %w[show spec step].each do |verb|
      result, error, status = command("intent", verb, "1", "--project", "sample")

      assert_equal 0, status, error
      assert_match(/--project sample\z/, result.fetch("next"))
      refute_includes error, "lock_not_held"
    end
  end

  def test_direct_work_advances_from_preparation_through_verification
    dir = new_intent
    %w[spec plan].each { |name| File.write(File.join(dir, "#{name}.md"), "# Accepted #{name}\n") }
    File.write(File.join(dir, "checklist.md"), "# Checklist\n- [ ] Write the example\n")
    result, error, status = command("intent", "step", "1", "--project", "sample")

    assert_equal 0, status, error
    assert_equal "Write the example", result.dig("result", "work")
    assert_equal "none", result.fetch("next")
  end

  def test_completed_direct_work_advances_to_verification
    dir = new_intent
    %w[spec plan].each { |name| File.write(File.join(dir, "#{name}.md"), "# Accepted #{name}\n") }
    File.write(File.join(dir, "checklist.md"), "# Checklist\n- [x] Write the example\n")
    result, error, status = command("intent", "show", "1", "--project", "sample")

    assert_equal 0, status, error
    assert_equal "plastic intent verify 1 --project sample", result.fetch("next")
  end

  def test_graph_without_a_lock_routes_to_public_take
    dir = new_intent
    File.write(File.join(dir, "graph.md"), "# Graph\n")
    result, error, status = command("intent", "step", "1", "--project", "sample")

    assert_equal 0, status, error
    assert_equal "plastic auto take 1 --project sample", result.fetch("next")
    refute_includes error, "plastic-lock"
  end

  def test_graph_return_without_ownership_is_refused_without_consuming_the_file
    dir = new_intent
    File.write(File.join(dir, "graph.md"), "# Graph\n")
    payload = File.join(@dir, "return.yml")
    File.write(payload, "status: done\n")
    result, error, status = command("intent", "step", "1", "--project", "sample", "--return", "n1=#{payload}")

    assert_equal 3, status, error
    assert_equal "refused", result.dig("result", "error", "kind")
    assert_equal "status: done\n", File.read(payload)
  end

  def test_store_directory_resolves_the_project
    dir = new_intent
    result, error, status = command("intent", "show", "1", directory: dir)

    assert_equal 0, status, error
    assert_equal "plastic intent spec 1 --project sample", result.fetch("next")
  end

  def test_unknown_project_returns_usage_json_and_diagnostics
    result, error, status = command("intent", "show", "1", "--project", "missing")

    assert_equal 2, status
    assert_equal "usage", result.dig("result", "error", "kind")
    assert_includes error, "no project named"
  end

  def test_blocked_future_intent_is_not_dispatchable
    root = File.join(@fixture.plastic_home, "projects", "sample")
    File.write(File.join(root, "INDEX.md"), "# Index\n## Active\n## Future\n- [1 — Blocked](store/1--blocked/1--blocked.md)\n")
    @fixture.roadmap("sample", "release", "# Release\n## Batches\n### First\n- [ ] 1 Blocked — blocked\n")
    result, error, status = command("next", "--project", "sample", "--why")

    assert_equal 0, status, error
    assert_equal "none", result.fetch("next")
    assert_equal "1", result.dig("result", "blocked")
  end

  def test_roadmap_show_and_lock_inspection_do_not_leak_child_output
    new_intent
    @fixture.roadmap("sample", "release", "# Release\n## Batches\n### First\n- [ ] 1 Sample — queued\n")
    result, error, status = command("roadmap", "show", "release", "--project", "sample")

    assert_equal 0, status, error
    assert_kind_of Array, result.dig("result", "output")
  end

  def test_lock_inspection_needs_no_mutation
    new_intent
    result, error, status = command("auto", "lock", "status", "1", "--project", "sample")

    assert_equal 0, status, error
    assert_equal "none", result.fetch("next")
  end

  def test_started_session_requires_owner_approval_before_inline_delivery
    dir = new_intent
    FileUtils.mkdir_p(File.join(@fixture.plastic_home, "store", ".tmp", "releasec"))
    result, _error, status = command("auto", "take", "1", "--project", "sample")

    assert_equal 3, status
    assert_equal "refused", result.dig("result", "error", "kind")
    refute_path_exists File.join(dir, "delivery.lock")
  end

  def test_explicit_inline_approval_is_available_through_the_public_cli
    dir = new_intent
    FileUtils.mkdir_p(File.join(@fixture.plastic_home, "store", ".tmp", "releasec"))
    result, error, status = command("auto", "take", "1", "--project", "sample", "--allow-inline")

    assert_equal 0, status, error
    assert_equal "plastic auto brief 1 --project sample", result.fetch("next")
    assert_equal "release-contract-test", JSON.parse(File.read(File.join(dir, "delivery.lock"))).fetch("owner_session")
  end
end
