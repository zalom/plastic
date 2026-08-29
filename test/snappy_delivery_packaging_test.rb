require "minitest/autorun"
require "tmpdir"

require_relative "../scripts/lib/installer_core"

# SnappyDeliveryPackagingTest (intent 213): a packaging regression test for the files
# this intent added (three thin-CLI scripts under scripts/ and their scripts/lib/ modules;
# the spec header and start-intent were removed in 2.0, intent 304). Guards both directions:
#
#   1. Source with no manifest key: orphaned. The file ships in the repo but is never
#      copied to ~/.plastic/scripts, so an installed script that requires it raises
#      LoadError at run time (the bug intent 172 fixed for scripts/end-intent).
#   2. Manifest key with no source file: DESTRUCTIVE. distribute prunes old_files minus
#      the still-existing global_files, so a key whose source went away gets DELETED from
#      every existing install on the next update. Parked intent 247 names this gap for the
#      whole manifest; this file also closes it generally, not just for these files.
#
# Hermetic: no network, no ~/.plastic read (plastic_home is a throwaway tmpdir), no eval.
class SnappyDeliveryPackagingTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  SNAPPY_FILES = %w[
    scripts/lib/scaffold_intent.rb
    scripts/scaffold-intent
    scripts/lib/verify_intent.rb
    scripts/verify-intent
    scripts/lib/exec_worktree.rb
    scripts/exec-worktree
  ].freeze

  SNAPPY_SCRIPTS = %w[
    scripts/scaffold-intent
    scripts/verify-intent
    scripts/exec-worktree
  ].freeze

  SNAPPY_SCRIPT_LIBS = {
    "scripts/scaffold-intent" => "scaffold_intent",
    "scripts/verify-intent" => "verify_intent",
    "scripts/exec-worktree" => "exec_worktree",
  }.freeze

  def core_files
    @core_files ||= Dir.mktmpdir("snappy-packaging-test") do |home|
      InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-alpha.18").core_files
    end
  end

  def test_every_snappy_delivery_file_is_in_the_manifest
    refute_empty SNAPPY_FILES, "the six-file list must not go empty"
    assert_equal 6, SNAPPY_FILES.length, "the six-file list must stay at exactly six entries"

    missing = SNAPPY_FILES.reject { |path| core_files.key?(path) }
    assert_empty missing,
      "these files ship in the repo but have no hand_registered_files manifest entry, " \
      "so they never reach a real install: #{missing.join(', ')}"
  end

  def test_every_snappy_delivery_manifest_key_has_a_real_source_file
    missing = SNAPPY_FILES.reject { |path| File.exist?(File.join(REPO, path)) }
    assert_empty missing,
      "a manifest key whose source file is gone is DESTRUCTIVE on update: it lands in " \
      "the prune diff and gets deleted from every existing install on the next update " \
      "(see intent 247): #{missing.join(', ')}"
  end

  def test_every_manifest_key_in_the_whole_manifest_has_a_real_source_file
    missing = core_files.keys.reject { |key| File.exist?(File.join(REPO, key)) }
    assert_empty missing,
      "manifest keys whose source file is gone are DESTRUCTIVE on update: each lands in " \
      "the prune diff and gets deleted from every existing install on the next update " \
      "(see intent 247): #{missing.join(', ')}"
  end

  def test_every_snappy_delivery_script_is_executable
    SNAPPY_SCRIPTS.each do |path|
      assert File.executable?(File.join(REPO, path)),
        "#{path} is shipped as a CLI and must be executable, or install leaves a broken command"
    end
  end

  def test_the_four_new_scripts_are_thin_clis_over_lib_modules
    SNAPPY_SCRIPT_LIBS.each do |script, lib|
      full_path = File.join(REPO, script)
      content = File.read(full_path)

      assert_match(/require_relative\s+["']lib\/#{lib}["']/, content,
        "#{script} must require_relative its own lib module (lib/#{lib}) to stay a thin CLI")

      line_count = File.readlines(full_path).count
      assert line_count <= 120,
        "#{script} has #{line_count} lines; a script over the 120-line thin-CLI ceiling " \
        "is no longer thin and its logic belongs in lib/#{lib}"
    end
  end
end
