# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require "plastic/installations/agent_set"
require "plastic/installations/transaction"

class TransactionTest < Plastic::TestCase
  include InstallFixture

  Installations = Plastic::Installations

  def record = Installations::AgentRecord.new(hermes_config)

  def hermes(*parts) = File.join(fresh, ".hermes", *parts)

  def run_with(verified: true, &install)
    capture_io do
      @result = Installations::Transaction.new(plastic, record, [hermes], verified: -> { verified }).call(&install)
    end
    @result
  end

  def written(name)
    path = write(hermes("skills", name), "new\n")
    record.manifest.write([path], FixedClock::AT)
    { agent: "Hermes", success: true, files: 1 }
  end

  def test_a_missing_agent_folder_is_a_refusal_that_names_the_folder
    result = run_with { flunk "no install" }

    assert_equal [false, "#{hermes} not found, Hermes not installed?"], [result[:success], result[:reason]]
  end

  def test_a_successful_install_carries_the_versions_it_moved_between
    make_agent_folders(hermes_config)
    write(hermes("plastic", "VERSION"), "2.0.2\n")
    result = run_with { written("a.md") }

    assert_equal [true, "2.0.2"], [result[:success], result[:from_version]]
  end

  def test_a_file_the_new_install_dropped_is_pruned_and_counted
    make_agent_folders(hermes_config)
    old = write(hermes("skills", "old.md"), "old\n")
    record.manifest.write([old], FixedClock::AT)
    result = run_with { written("a.md") }

    refute_path_exists old
    assert_equal 1, result[:pruned]
  end

  def test_a_failed_install_prunes_nothing_and_names_no_pruned_count
    make_agent_folders(hermes_config)
    result = run_with { { agent: "Hermes", success: false, reason: "broke" } }

    assert_equal [false, nil], [result[:success], result[:pruned]]
  end

  def test_the_legacy_manifest_is_deleted_after_an_install
    make_agent_folders(hermes_config)
    legacy = write(hermes("plastic-manifest.json"), "{}")
    run_with { written("a.md") }

    refute_path_exists legacy
  end

  def test_a_failed_check_with_a_prior_record_restores_the_files_it_listed
    make_agent_folders(hermes_config)
    kept = write(hermes("skills", "kept.md"), "before\n")
    record.manifest.write([kept], FixedClock::AT)
    result = run_with(verified: false) do
      File.write(kept, "after\n")
      { agent: "Hermes", success: true, files: 1 }
    end

    assert_equal ["before\n", false, "verify failed - restored prior snapshot"], [File.read(kept), result[:success], result[:reason]]
  end

  def test_a_failed_check_with_no_prior_record_prunes_the_partial_install
    make_agent_folders(hermes_config)
    result = run_with(verified: false) { written("a.md") }

    refute_path_exists hermes("skills", "a.md")
    assert_equal "verify failed - partial install pruned", result[:reason]
  end
end
