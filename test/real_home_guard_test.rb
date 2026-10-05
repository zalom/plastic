# encoding: UTF-8
# frozen_string_literal: true

require_relative "test_helper"
require "etc"

# Real-home guard (intent 363). The incident: `bin/verify-change` spawned every
# gate child with the session's own HOME, and the mutation step mutates
# scripts/lib/cli/legacy.rb, where `@runner = runner || DEFAULT_RUNNER` decides
# whether an installer verb runs its injected test runner or spawns the real
# scripts/install.rb. A mutant that defeats the injection turns a hermetic unit
# test into a real install, and eleven of them landed in the owner's
# ~/.plastic and ~/.claude before anyone noticed.
#
# Two halves. The static scan
# catches a test that spawns an installer or the launcher without a throwaway
# HOME. The dynamic backstop catches everything the scan cannot see, including
# a spawn a mutant invented, by fingerprinting the real home before the suite
# runs and again after it.
class RealHomeGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SPAWN = /\bsystem\(|Open3\.|IO\.popen|Process\.spawn/
  VERB = %r{(?:"|'|/)(?:install|uninstall|update|rollback)\.rb(?:"|')|"scripts", "(?:install|uninstall|update|rollback)\.rb"}
  LAUNCHER = %r{bin/plastic(?![-.\w])|"bin", "plastic"}
  INSTALLER_PATH = %r{bin/plastic(?![-.\w])|"bin", "plastic"|(?:install|uninstall|update|rollback)\.rb}
  ASSIGNMENT = /^\s*(@{0,2}[A-Za-z_]\w*)\s*(?:\|\|)?=\s*(.+)$/

  # The passwd entry, not ENV["HOME"], so the guard still watches the machine's
  # own home when the suite itself runs under a throwaway one.
  REAL_HOME = Etc.getpwuid(Process.uid).dir

  # What an install or an uninstall changes and a working session never does.
  def self.fingerprint
    files = %w[.plastic/versions.json .plastic/VERSION .plastic/manifest.json]
    directories = %w[.claude/hooks .claude/skills]
    files.to_h { |path| [path, file_body(path)] }
      .merge(directories.to_h { |path| [path, directory_children(path)] })
  end

  def self.file_body(path)
    File.read(File.join(REAL_HOME, path))
  rescue SystemCallError
    nil
  end

  def self.directory_children(path)
    Dir.children(File.join(REAL_HOME, path)).sort
  rescue SystemCallError
    nil
  end

  BEFORE = fingerprint.freeze

  # Constants and variables naming an installer script or the launcher, so a
  # spawn through LAUNCHER or @launcher reads as an installer spawn even though
  # the line holds no path.
  def installer_names(source)
    source.scan(ASSIGNMENT).select { |_name, value| value.match?(INSTALLER_PATH) }.map(&:first).uniq
  end

  def installer_spawns(source)
    named = installer_names(source).map { |name| /(?<![\w@])#{Regexp.escape(name)}\b/ }
    installer = Regexp.union(VERB, LAUNCHER, *named)
    spawning = source.lines.each_with_index.select { |line, _number| line.match?(SPAWN) && line.match?(installer) }
    spawning.map { |_line, number| number + 1 }
  end

  def test_the_detector_reads_a_literal_installer_spawn
    source = %(Open3.capture3(env, RbConfig.ruby, File.join(REPO, "scripts", "install.rb"))\n)

    assert_equal [1], installer_spawns(source)
  end

  def test_the_detector_reads_a_spawn_through_a_launcher_constant
    source = %(LAUNCHER = File.join(ROOT, "bin", "plastic")\nOpen3.capture3(LAUNCHER, "help")\n)

    assert_equal [2], installer_spawns(source)
  end

  def test_the_detector_reads_a_spawn_through_an_instance_variable
    source = %(@launcher = File.join(ROOT, "bin", "plastic")\nOpen3.capture3(@launcher, "help")\n)

    assert_equal [2], installer_spawns(source)
  end

  def test_the_detector_reads_a_spawn_through_a_local_variable
    source = %(script = File.join(REPO, "scripts", "update.rb")\nsystem(RbConfig.ruby, script)\n)

    assert_equal [2], installer_spawns(source)
  end

  def test_the_detector_ignores_an_installer_path_that_is_only_asserted_on
    source = %(assert_path_exists File.join(REPO, "bin/plastic")\n)

    assert_empty installer_spawns(source)
  end

  def test_the_detector_ignores_a_neighbouring_binary_with_a_longer_name
    source = %(CENSUS = File.join(REPO, "bin/plastic-skill-census")\nOpen3.capture3(CENSUS, "--json")\n)

    assert_empty installer_spawns(source)
  end

  def scanned_test_files
    Dir[File.join(ROOT, "test", "**", "*_test.rb")]
  end

  def test_the_scan_reads_a_list_of_test_files_that_is_not_empty
    refute_empty scanned_test_files
  end

  def test_every_test_that_spawns_an_installer_gives_it_a_throwaway_home
    offenders = scanned_test_files.sort.reject do |path|
      source = File.read(path)
      installer_spawns(source).empty? || source.include?(%("HOME"))
    end

    assert_empty offenders.map { |path| path.delete_prefix("#{ROOT}/") },
      "these tests spawn an installer or the launcher without injecting HOME"
  end

  Minitest.after_run do
    after = fingerprint
    if after != BEFORE
      changed = after.keys.reject { |key| after[key] == BEFORE[key] }
      warn "REAL HOME VIOLATION: the suite changed #{changed.join(", ")} under #{REAL_HOME}. " \
           "A test or a mutant spawned an installer against the machine's own home."
      exit 1
    end
  end
end
