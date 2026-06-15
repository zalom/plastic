require "minitest/autorun"

# Regression guard (intent 27 hotfix): a hook script can be added and wired into
# hooks.json / settings without being copied to ~/.plastic/scripts on install,
# leaving the installed wrapper pointing at a missing file. These tests fail loudly
# if the two sides drift.
class InstallSyncTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  # core_files now lives in the shared lib (intent 30a1a).
  def core_lib
    @core_lib ||= File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
  end

  # Every scripts/hook-* must be registered in core_files, otherwise it never
  # reaches ~/.plastic/scripts.
  def test_every_hook_script_is_registered_for_install
    scripts = Dir.glob(File.join(REPO, "scripts", "hook-*")).map { |p| File.basename(p) }
    refute_empty scripts, "expected hook-* scripts to exist"
    missing = scripts.reject { |s| core_lib.include?("scripts/#{s}") }
    assert_empty missing,
      "hook scripts missing from core_files (installed wrappers would point at nothing): #{missing.join(", ")}"
  end

  # Every verb script + the shared lib must be distributed, so the installed
  # ~/.plastic/scripts copy is self-complete (update/uninstall/versions run from there).
  def test_every_verb_script_is_distributed
    expected = %w[
      scripts/install.rb scripts/update.rb scripts/uninstall.rb scripts/versions.rb
      scripts/lib/installer_core.rb
    ]
    missing = expected.reject { |s| core_lib.include?(%("#{s}")) }
    assert_empty missing, "verb scripts/lib missing from core_files: #{missing.join(", ")}"
  end

  # Every hook wrapper that delegates to ../scripts/hook-<name> must reference a
  # script that actually exists in the repo.
  def test_every_wrapper_references_an_existing_script
    broken = []
    Dir.glob(File.join(REPO, "hooks", "*")).each do |wrapper|
      base = File.basename(wrapper)
      next if %w[hooks.json run-hook].include?(base)
      body = File.read(wrapper)
      body.scan(%r{scripts/(hook-[\w-]+)}).flatten.uniq.each do |script|
        broken << "#{base} -> #{script}" unless File.exist?(File.join(REPO, "scripts", script))
      end
    end
    assert_empty broken, "hook wrappers reference missing scripts: #{broken.join(", ")}"
  end
end
