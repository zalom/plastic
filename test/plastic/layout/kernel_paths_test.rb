# frozen_string_literal: true

require_relative "../../test_helper"
require "open3"
require "yaml"

class KernelPathsTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  SELF = "test/plastic/layout/kernel_paths_test.rb"
  OLD_KERNEL = File.join("scripts", "lib", "plastic")
  RETIRED_NAMES = [OLD_KERNEL].freeze

  def tracked
    @tracked ||= Dir.chdir(ROOT) { `git ls-files -z`.split("\0") }.reject do |path|
      path == "CHANGELOG.md" || path == SELF || !File.file?(File.join(ROOT, path))
    end
  end

  def text_of(path)
    text = File.read(File.join(ROOT, path), encoding: "UTF-8")
    text.valid_encoding? ? text : nil
  end

  def test_no_tracked_file_names_the_old_kernel_path_or_a_retired_name
    hits = tracked.select do |path|
      text = text_of(path)
      text && RETIRED_NAMES.any? { |name| text.include?(name) }
    end

    assert_empty hits
  end

  def test_no_ruby_file_joins_the_old_kernel_path_from_words
    joined = /["']scripts["'],\s*["']lib["'],\s*["']plastic["']/
    hits = tracked.select { |path| path.end_with?(".rb") && text_of(path)&.match?(joined) }

    assert_empty hits
  end

  def test_the_kernel_lives_under_lib
    assert File.file?(File.join(ROOT, "lib", "plastic.rb"))
    assert File.directory?(File.join(ROOT, "lib", "plastic", "commands"))
    refute File.exist?(File.join(ROOT, "scripts", "lib", "plastic.rb"))
    refute File.exist?(File.join(ROOT, "scripts", "lib", "plastic"))
  end

  def test_the_dir_relative_constants_point_into_the_package
    require "plastic/cli"
    require "plastic/workflows/installation"
    require "plastic/workflows/show_spec"

    assert File.file?(File.join(Plastic::Workflows::Installation::PACKAGE_ROOT, "package.json"))
    assert Dir.glob(File.join(Plastic::CLI::TOPICS, "*.md")).any?
    assert File.file?(Plastic::Workflows::ShowSpec::GRILLING)
  end

  def test_a_fresh_process_requires_every_kernel_file_and_the_installer
    kernel = Dir.glob(File.join(ROOT, "lib", "plastic", "**", "*.rb"))
    refute_empty kernel
    files = kernel + [File.join(ROOT, "scripts", "lib", "installer_core.rb"), File.join(ROOT, "scripts", "install.rb")]

    assert_empty files.reject { |file| loads_alone?(file) }
  end

  def loads_alone?(file)
    code = %(require "plastic"; load ARGV.fetch(0) unless ARGV.fetch(0).end_with?("install.rb"))
    _out, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-I", File.join(ROOT, "scripts", "lib"),
                                   "-e", code, file, chdir: ROOT)
    status.success?
  end

  def test_the_test_helper_covers_lib
    helper = File.read(File.join(ROOT, "test", "test_helper.rb"))

    assert_match(/cover "\{[^}]*\blib\b[^}]*\}/, helper)
  end

  def test_every_path_the_lint_debt_names_exists
    todo = YAML.load_file(File.join(ROOT, ".rubocop_todo.yml")).values.flat_map { |entry| entry.is_a?(Hash) ? Array(entry["Exclude"]) : [] }
    reek = Array(YAML.load_file(File.join(ROOT, ".reek.yml"))["exclude_paths"])
    missing = (todo + reek).select { |path| path.match?(%r{\A(lib|scripts|bin|tools)/.+\.rb\z}) }.reject { |path| File.exist?(File.join(ROOT, path)) }

    assert_empty missing
  end
end
