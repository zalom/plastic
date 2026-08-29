# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/installer_core"

# Intent 297, task 6: the installer manifest carries the new script, library,
# and template so a fresh install ships them (spec D14). Asserts on the
# BUILT core_files hash, not a source-text substring, because that is what
# actually reaches an install, and it is what proves the template arrives
# through the glob rather than through a hand-typed literal.
class SessionLedgerManifestTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  def installer
    @installer ||= InstallerCore.new(package_root: REPO)
  end

  def test_core_files_includes_append_ledger
    assert_includes installer.core_files.keys, "scripts/append-ledger"
  end

  def test_core_files_includes_session_ledger_lib
    assert_includes installer.core_files.keys, "scripts/lib/session_ledger.rb"
  end

  def test_core_files_includes_session_intent_template_via_glob
    assert_includes installer.core_files.keys, "templates/session-intent.md"
  end

  def test_hand_registered_files_carries_the_two_scripts
    assert_includes installer.hand_registered_files.keys, "scripts/append-ledger"
    assert_includes installer.hand_registered_files.keys, "scripts/lib/session_ledger.rb"
  end

  def test_hand_registered_files_excludes_the_template
    refute_includes installer.hand_registered_files.keys, "templates/session-intent.md",
      "the template must ride the template_files glob, not a hand-written manifest entry"
  end

  def test_every_manifest_entry_for_this_intent_exists_on_disk
    %w[scripts/append-ledger scripts/lib/session_ledger.rb templates/session-intent.md].each do |rel|
      path = File.join(REPO, rel)
      assert File.exist?(path), "manifest names #{rel}, which does not exist on disk"
    end
  end
end
