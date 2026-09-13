# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/installer_core"

# bridge_retired_test (intent 344, n1; extended by n5): scripts/lib/bridge.rb is
# gone, the two libraries it split into are registered where the installer ships
# them, no live script still reaches for it, and every library this node touched
# still loads clean in a fresh subprocess.
class BridgeRetiredTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  CHANGED_LIBS = %w[
    scripts/lib/arm.rb scripts/lib/worktree.rb scripts/lib/exec_worktree.rb
    scripts/lib/worktree_sweep.rb scripts/lib/scaffold_intent.rb
    scripts/lib/index_entry.rb scripts/lib/project_config.rb
  ].freeze

  SCAN_ROOTS = %w[scripts hooks].freeze

  def core_files
    Dir.mktmpdir("bridge-retired-core") do |home|
      return InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test").core_files
    end
  end

  def test_bridge_library_is_gone_from_the_core_set
    refute File.exist?(File.join(REPO, "scripts", "lib", "bridge.rb"))
    files = core_files
    refute files.key?("scripts/lib/bridge.rb"), "core_files still registers scripts/lib/bridge.rb"
    refute_includes files.values, "scripts/lib/bridge.rb", "core_files still ships scripts/lib/bridge.rb"
  end

  def test_new_libraries_are_in_the_core_set
    files = core_files
    assert files.key?("scripts/lib/index_entry.rb"), "core_files is missing scripts/lib/index_entry.rb"
    assert files.key?("scripts/lib/project_config.rb"), "core_files is missing scripts/lib/project_config.rb"
  end

  def test_no_script_requires_the_bridge
    offenders = []
    scan_files.each do |path|
      File.foreach(path).with_index(1) do |line, n|
        offenders << "#{path.sub("#{REPO}/", '')}:#{n}" if line.include?("bridge") && line =~ /require(_relative)?\s+["'][^"']*bridge["']/
      end
    end
    assert_empty offenders, "still requires the retired bridge: #{offenders.join(', ')}"
  end

  def test_changed_libraries_load_in_a_subprocess
    Dir.mktmpdir("bridge-retired-home") do |home|
      env = { "HOME" => home, "RUBYOPT" => nil, "PLASTIC_TMP" => nil, "CLAUDE_CODE_SESSION_ID" => nil }
      CHANGED_LIBS.each do |rel|
        lib = File.join(REPO, rel)
        _out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", "require #{lib.inspect}")
        assert status.success?, "#{rel} does not load: #{err}"
      end
      %w[scripts/end-intent scripts/plastic-lock].each do |rel|
        _out, err, status = Open3.capture3(env, RbConfig.ruby, "-c", File.join(REPO, rel))
        assert status.success?, "#{rel} does not parse: #{err}"
      end
    end
  end

  private

  def scan_files
    SCAN_ROOTS.flat_map do |root|
      abs = File.join(REPO, root)
      File.directory?(abs) ? Dir[File.join(abs, "**", "*")].select { |f| File.file?(f) } : [abs]
    end
  end
end
