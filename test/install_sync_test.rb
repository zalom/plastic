require "minitest/autorun"

# Regression guard (intent 27 hotfix): a hook script can be added and wired into
# hooks.json / settings without being copied to ~/.plastic/scripts on install,
# leaving the installed wrapper pointing at a missing file. These tests fail loudly
# if the two sides drift.
class InstallSyncTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  def install_rb
    @install_rb ||= File.read(File.join(REPO, "scripts", "install.rb"))
  end

  # Every scripts/hook-* must be registered in install.rb's core_files map,
  # otherwise it never reaches ~/.plastic/scripts.
  def test_every_hook_script_is_registered_for_install
    scripts = Dir.glob(File.join(REPO, "scripts", "hook-*")).map { |p| File.basename(p) }
    refute_empty scripts, "expected hook-* scripts to exist"
    missing = scripts.reject { |s| install_rb.include?("scripts/#{s}") }
    assert_empty missing,
      "hook scripts missing from install.rb core_files (installed wrappers would point at nothing): #{missing.join(", ")}"
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
