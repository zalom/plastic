# frozen_string_literal: true

require_relative "../support/kernel"

class LegacyStoreTest < Minitest::Test
  include KernelFixtures::StoreCalls

  def setup
    super
    copy_legacy_store
  end

  def test_sync_down_waits_for_the_import
    call = run_plastic("sync", "down")

    assert_equal 1, call.code
    assert_includes call.err, "this store still has INDEX.md; run plastic sync up to import it first"
    assert_path_exists store_path("INDEX.md")
  end

  def test_an_intent_with_no_own_file_imports_with_no_kind
    FileUtils.rm(store_path("store/1a--litellm-proxmox-gateway/1a--litellm-proxmox-gateway.md"))
    call = run_plastic("sync", "up")
    intent = store_graphs.retrieval.intent("1a")

    assert_equal 0, call.code, call.err
    assert_equal ["future", nil, nil], [intent.status, intent.kind, intent.opened_at]
  end
end
