require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

require_relative "../scripts/lib/installer_core"

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
  # ~/.plastic/scripts copy is self-complete (update/uninstall/rollback run from there).
  def test_every_verb_script_is_distributed
    expected = %w[
      scripts/install.rb scripts/update.rb scripts/uninstall.rb scripts/rollback.rb
      scripts/lib/installer_core.rb
    ]
    missing = expected.reject { |s| core_lib.include?(%("#{s}")) }
    assert_empty missing, "verb scripts/lib missing from core_files: #{missing.join(", ")}"
  end

  # Every lib file a shipped scripts/* file require_relatives must itself be
  # distributed (intent 36a1 hotfix): hook-session-start added
  # `require_relative "lib/boot_banner"` but boot_banner.rb was not in core_files,
  # so the installed hook raised LoadError on session start. This fails loudly if
  # any scripts/* requires a lib/*.rb that core_files does not register.
  def test_every_required_lib_is_distributed
    missing = []
    Dir.glob(File.join(REPO, "scripts", "*")).each do |path|
      next unless File.file?(path)
      File.read(path).scan(/require_relative\s+["']lib\/(\w+)["']/).flatten.uniq.each do |libname|
        rel = "scripts/lib/#{libname}.rb"
        missing << "#{File.basename(path)} -> #{rel}" unless core_lib.include?(%("#{rel}"))
      end
    end
    assert_empty missing,
      "scripts require_relative lib files missing from core_files (installed boot would LoadError): #{missing.join(", ")}"
  end

  # 317a (B1): the scan above sees only scripts/* -> lib requires; a
  # lib-to-lib require (message_display -> screen_paint -> intent_screen_ansi)
  # was invisible, so a new lib could pass the whole suite while absent from
  # every real install. Walk the libs too.
  def test_every_lib_to_lib_require_is_distributed
    missing = []
    Dir.glob(File.join(REPO, "scripts", "lib", "*.rb")).each do |path|
      next unless core_lib.include?(%("scripts/lib/#{File.basename(path)}"))
      File.read(path).scan(/require_relative\s+["'](\w+)["']/).flatten.uniq.each do |libname|
        rel = "scripts/lib/#{libname}.rb"
        missing << "#{File.basename(path)} -> #{rel}" unless core_lib.include?(%("#{rel}"))
      end
    end
    assert_empty missing,
      "registered libs require_relative lib files missing from core_files: #{missing.join(", ")}"
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

  # Regression guard (intent 151): scripts/insight-append is the blessed write path
  # every spawn preamble and agent-report-contract instructs agents to shell out to,
  # but it was never registered in core_files, so install/update never copied it to
  # ~/.plastic/scripts. This fails loudly if the entry drops out again.
  def test_insight_append_script_is_registered_for_install
    home = Dir.mktmpdir("core-test")
    core = InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test")
    assert core.core_files.key?("scripts/insight-append"),
      "scripts/insight-append missing from core_files (installed wrapper would point at nothing)"
    assert_equal "scripts/insight-append", core.core_files["scripts/insight-append"]
  ensure
    FileUtils.rm_rf(home)
  end

  # Companion guard: registration alone isn't enough, distribute must actually land an
  # executable copy with a matching manifest entry, the same contract every other
  # core_files script gets.
  def test_distribute_installs_executable_insight_append_with_manifest_entry
    home = Dir.mktmpdir("core-test")
    core = InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test")
    core.distribute(:install)

    dest = File.join(home, "scripts", "insight-append")
    assert File.exist?(dest), "distribute must install scripts/insight-append"
    mode = File.stat(dest).mode & 0o777
    assert_equal 0o755, mode, "installed scripts/insight-append must be executable (0755)"

    manifest = JSON.parse(File.read(File.join(home, "manifest.json")))
    assert manifest["files"].key?(dest), "manifest must list #{dest}"
    assert_equal Digest::SHA256.file(dest).hexdigest, manifest["files"][dest],
      "manifest sha256 for #{dest} must match on-disk digest"
  ensure
    FileUtils.rm_rf(home)
  end

  # Regression guard (intent 172): generalizes the 78/86/151 manifest-drift class instead of
  # patching one more one-off instance. Any shipped skill can reference a scripts/<name> path
  # that is real on disk but missing from core_files, so install/update never copy it and the
  # skill points at nothing post-install. This scans every shipped skill file for such
  # references, keeps only the ones that resolve to a real repo file (doc-example paths like
  # scripts/scaffold.rb or scripts/validate_slug.rb, and directory tokens like scripts/lib,
  # name no real file and are correctly ignored, no hardcoded skip-list), and asserts each
  # surviving ref is registered in core_files.
  def test_every_skill_referenced_script_that_exists_is_registered_for_install
    refs = Dir.glob(File.join(REPO, "skills", "**", "*")).select { |p| File.file?(p) }.flat_map do |path|
      File.read(path).scan(%r{scripts/[A-Za-z0-9._-]+})
    end.uniq

    real_refs = refs.select { |ref| File.file?(File.join(REPO, ref)) }
    refute_empty real_refs, "expected skills to reference at least one real scripts/* file"

    missing = real_refs.reject { |ref| core_lib.include?(%("#{ref}")) }
    assert_empty missing,
      "skill-referenced scripts missing from core_files (installed skills would point at nothing): #{missing.join(", ")}"
  end
end
