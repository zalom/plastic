# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "plastic"
require "plastic/workflow"
require_relative "../../support/child_process"

class WorkflowNamesTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  WORKFLOWS = File.join(ROOT, "lib", "plastic", "workflows")
  POOL = 6

  # Every key with the class under Workflows that runs it. A key is stored in
  # an open routine run, so the keys never change; the classes follow the
  # command a workflow belongs to.
  MAPPING = {
    code_write_intent: "Code::Intent::New",
    code_sync_up: "Code::Sync::Up",
    code_preview_sync: "Code::Sync::Up::Preview",
    code_sync_down: "Code::Sync::Down",
    code_preview_sync_down: "Code::Sync::Down::Preview",
    code_add_ruling: "Code::Intent::Rule",
    code_revise_intent: "Code::Intent::Revise",
    code_note_intent: "Code::Intent::Note",
    code_show_spec: "Code::Intent::Spec",
    code_approve_intent: "Code::Intent::Approve",
    code_prepare_judge: "Code::Intent::Judge",
    agent_judge_intent: "Agent::Intent::Judge",
    code_record_verdict: "Code::Intent::Verdict",
    code_prepare_verdict: "Code::Intent::Verdict::Prepare",
    code_start_auto: "Code::Auto",
    code_pick_delivery: "Code::Auto::Pick",
    code_show_lock: "Code::Intent::Lock::Status",
    code_check_graph: "Code::Graph::Check",
    code_ready_graph: "Code::Graph::Ready",
    code_show_graph: "Code::Graph::Show",
    code_show_intent: "Code::Intent::Show",
    code_show_brief: "Code::Intent::Brief",
    code_delivery_next: "Code::Intent::Brief::Next",
    code_pick_next: "Code::Next",
    code_add_link: "Code::Intent::Link",
    code_remove_link: "Code::Intent::Unlink",
    code_create_roadmap: "Code::Roadmap::New",
    code_write_roadmap_batch: "Code::Roadmap::Batch",
    code_add_roadmap_item: "Code::Roadmap::Add",
    code_show_roadmap: "Code::Roadmap::Show",
    code_next_roadmap: "Code::Roadmap::Next",
    code_drop_roadmap_item: "Code::Roadmap::Drop",
    code_open_roadmap_item: "Code::Roadmap::Open",
    code_check_roadmap: "Code::Roadmap::Check",
    code_log_roadmap: "Code::Roadmap::Log",
    code_remove_roadmap_edge: "Code::Roadmap::Edge::Remove",
    agent_advance_delivery: "Agent::Shared::AdvanceDelivery",
    code_close_intent: "Code::Intent::End",
    code_prepare_ending: "Code::Intent::End::Prepare",
    agent_finish_intent: "Agent::Intent::End",
    agent_check_merge: "Agent::Intent::End::CheckMerge",
    agent_wind_down_intent: "Agent::Shared::WindDownIntent",
    code_discover_retrieval: "Code::Intent::Discover",
    agent_external_agent_workflow: "Agent::Intent::Discover",
    code_search: "Code::Search",
    code_get_document: "Code::Document::Get",
    code_batch_documents: "Code::Document::Batch",
    code_submit_context: "Code::Intent::Context",
    code_check_context_owner: "Code::Intent::Context::CheckOwner",
    code_read_context: "Code::Intent::Context::Read",
    agent_check_architecture: "Agent::Architecture::Status",
    agent_refresh_architecture: "Agent::Architecture::Refresh",
    code_abandon_intent: "Code::Intent::Abandon",
    code_prepare_abandon: "Code::Intent::Abandon::Prepare",
    agent_revert_intent: "Agent::Intent::Abandon",
    code_write_note: "Code::Session::Note",
    code_archive_intent: "Code::Intent::Archive",
    code_unarchive_intent: "Code::Intent::Unarchive",
    code_backup: "Code::Backup",
    code_preview_backup: "Code::Backup::Preview",
    code_backup_list: "Code::Backup::List",
    code_backup_purge: "Code::Backup::Purge",
    code_preview_backup_purge: "Code::Backup::Purge::Preview",
    code_backup_restore: "Code::Backup::Restore",
    code_preview_backup_restore: "Code::Backup::Restore::Preview",
    code_show_version: "Code::Version",
    code_check_health: "Code::Doctor",
    code_install_plastic: "Code::Install",
    code_preview_install: "Code::Install::Preview",
    agent_offer_enola: "Agent::Install",
    code_install_harnesses: "Code::Init",
    code_choose_harnesses: "Code::Init::Choose",
    code_uninstall_plastic: "Code::Uninstall",
    code_preview_uninstall: "Code::Uninstall::Preview",
    code_choose_installations: "Code::Uninstall::Choose",
    code_update_plastic: "Code::Update",
    code_preview_update: "Code::Update::Preview",
    code_rollback_release: "Code::Rollback",
    code_preview_rollback: "Code::Rollback::Preview",
    code_add_node: "Code::Node::Add",
    code_remove_node: "Code::Node::Remove",
    code_claim_node: "Code::Node::Claim",
    code_release_node: "Code::Node::Release",
    code_done_node: "Code::Node::Done",
    code_fail_node: "Code::Node::Fail",
    code_ask_node: "Code::Node::Ask",
    code_impede_node: "Code::Node::Impede",
    code_resolve_node: "Code::Node::Resolve",
    code_add_edge: "Code::Edge::Add",
    code_remove_edge: "Code::Edge::Remove",
  }.freeze

  PARENTS = %w[
    Code::Sync::Up Code::Sync::Down Code::Intent::Verdict Code::Intent::Brief Code::Intent::End Code::Intent::Context
    Code::Intent::Abandon Agent::Intent::End Code::Auto Code::Install Code::Init Code::Uninstall Code::Update Code::Rollback
    Code::Backup Code::Backup::Purge Code::Backup::Restore
  ].freeze

  def camel(word) = word.split("_").map(&:capitalize).join

  def registry = Plastic::Workflows::REGISTRY

  def file_of(path) = File.join(WORKFLOWS, *path.split("::").map { |segment| Plastic.snake(segment) }) + ".rb"

  def test_the_registry_holds_the_ninety_keys_in_order
    assert_equal 90, MAPPING.size
    assert_equal MAPPING.keys, registry.keys
  end

  def test_the_registry_maps_each_key_to_its_class_path
    assert_equal MAPPING, registry
  end

  def test_each_workflow_lives_in_the_folder_of_its_kind
    wrong = MAPPING.reject { |key, path| path.start_with?("#{camel(key.to_s.split("_").first)}::") && File.file?(file_of(path)) }

    assert_empty wrong
  end

  def test_no_workflow_file_is_left_flat_beside_the_helpers
    old = MAPPING.keys.map { |key| File.join(WORKFLOWS, "#{key.to_s.split("_", 2).last}.rb") }.select { |path| File.file?(path) }

    assert_empty old
  end

  def test_the_seventeen_parents_are_the_paths_that_hold_other_workflows
    held = MAPPING.values.flat_map { |path| path.split("::").each_index.map { |index| path.split("::").first(index + 1).join("::") } }
    parents = MAPPING.values.select { |path| held.count { |prefix| prefix.start_with?("#{path}::") }.positive? }

    assert_equal PARENTS.sort, parents.sort
  end

  def fresh(key)
    code = <<~RUBY
      require "plastic"; require "plastic/workflow"; require "json"
      key = ARGV.fetch(0).to_sym
      klass = Plastic::Workflow.fetch(key)
      parts = klass.name.delete_prefix("Plastic::Workflows::").split("::")
      kinds = parts.each_index.to_h do |index|
        path = parts.first(index + 1).join("::")
        [path, parts.first(index + 1).inject(Plastic::Workflows) { |scope, part| scope.const_get(part, false) }.class.name]
      end
      print JSON.generate("name" => klass.name, "key" => klass.key, "lane" => klass.lane, "kinds" => kinds)
    RUBY
    out, status = ChildProcess.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", code, key.to_s, chdir: ROOT)
    status.success? ? JSON.parse(out) : { "error" => out }
  end

  def fetched
    @@fetched ||= MAPPING.keys.each_slice((MAPPING.size / POOL.to_f).ceil).map do |keys|
      Thread.new { keys.to_h { |key| [key, fresh(key)] } }
    end.flat_map { |thread| thread.value.to_a }.to_h
  end

  def test_a_fresh_process_fetches_each_key_as_the_class_of_its_path
    wrong = MAPPING.reject { |key, path| fetched.fetch(key)["name"] == "Plastic::Workflows::#{path}" }

    assert_empty wrong.keys
  end

  def test_the_class_reads_its_key_back
    wrong = MAPPING.keys.reject { |key| fetched.fetch(key)["key"] == key.to_s }

    assert_empty wrong
  end

  def test_the_lane_of_the_class_is_the_prefix_of_its_key
    wrong = MAPPING.keys.reject { |key| fetched.fetch(key)["lane"] == key.to_s.split("_").first }

    assert_empty wrong
  end

  def test_a_nested_key_fetched_alone_leaves_every_parent_the_right_kind
    wrong = MAPPING.keys.flat_map do |key|
      fetched.fetch(key).fetch("kinds", {}).filter_map do |path, kind|
        expected = MAPPING.value?(path) ? "Class" : "Module"
        "#{key}: #{path} is #{kind}" unless kind == expected
      end
    end

    assert_empty wrong
  end

  def test_the_preview_of_sync_down_stands_on_the_preview_of_sync_up
    require "plastic/workflows/code/sync/down/preview"

    assert_operator Plastic::Workflows::Code::Sync::Down::Preview, :<, Plastic::Workflows::Code::Sync::Up::Preview
  end

  def test_the_discovery_handoff_is_the_agent_workflow_of_intent_discover
    require "plastic/workflows/agent/intent/discover"

    refute Plastic.const_defined?(:ExternalAgentWorkflow, false)
    assert_equal :agent_external_agent_workflow, Plastic::Workflows::Agent::Intent::Discover.key
  end

  def top_level_names
    Dir.children(File.join(ROOT, "lib", "plastic")).map { |name| camel(name.delete_suffix(".rb")) }
  end

  def layout_names
    segments = MAPPING.values.flat_map { |path| path.split("::") }
    (segments + ["Hooks"]).uniq & top_level_names
  end

  def bare_receivers(path)
    code = File.read(path).lines.reject { |line| line.strip.start_with?("#") }.join
    layout_names.select { |name| code.match?(/(?<![\w:])#{name}(?=\.|::)/) }
  end

  def test_the_scan_knows_the_reused_names
    assert_empty %w[Graph Doctor Context] - layout_names
  end

  def test_no_workflow_names_a_reused_top_level_constant_without_the_plastic_prefix
    found = %w[code agent].flat_map { |kind| Dir.glob(File.join(WORKFLOWS, kind, "**", "*.rb")) }.filter_map do |path|
      names = bare_receivers(path)
      "#{path.delete_prefix("#{ROOT}/")}: #{names.join(", ")}" if names.any?
    end

    assert_empty found
  end
end
