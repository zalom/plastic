require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

require_relative "../scripts/lib/project_validator"

# Hermetic unit tests for the project spawn self-check (intent 190). Every
# test builds its own Dir.mktmpdir for plastic_home AND a separate
# Dir.mktmpdir for the project root, and never touches the real ~/.plastic.
class ProjectValidatorTest < Minitest::Test
  CLI = File.expand_path("../scripts/validate-project", __dir__)

  # Registers `slug` in a tmp plastic_home's projects.yml, pointing at a
  # separate tmp project_root. Yields [plastic_home, project_root].
  def with_registered_project(slug: "demo")
    Dir.mktmpdir do |home|
      Dir.mktmpdir do |project_root|
        File.write(File.join(home, "projects.yml"),
                   YAML.dump({ "projects" => { slug => { "path" => project_root } } }))
        yield home, project_root
      end
    end
  end

  # A fully complete spawn: project.yml, store/, INDEX.md under plastic_home,
  # AGENTS.md at the project root.
  def build_complete_spawn(home, project_root, slug: "demo")
    project_dir = File.join(home, "projects", slug)
    FileUtils.mkdir_p(File.join(project_dir, "store"))
    File.write(File.join(project_dir, "project.yml"), "governing_docs:\n  - AGENTS.md\n")
    File.write(File.join(project_dir, "INDEX.md"), "# Index\n")
    File.write(File.join(project_root, "AGENTS.md"), "# Project\n")
  end

  def test_complete_spawn_is_ok
    with_registered_project do |home, project_root|
      build_complete_spawn(home, project_root)
      result = ProjectValidator.validate("demo", plastic_home: home)
      assert result[:ok], result.inspect
      assert_empty result[:missing]
      assert_empty result[:errors]
    end
  end

  # THE fixture named in D11: the intent-26 partial-spawn shape. A registered
  # project with a store/ and INDEX.md, but NO project.yml and NO root
  # AGENTS.md. Must flag BOTH by name, not just the first one found.
  def test_intent_26_shape_flags_both_missing_project_yml_and_agents_md
    with_registered_project do |home, project_root|
      project_dir = File.join(home, "projects", "demo")
      FileUtils.mkdir_p(File.join(project_dir, "store"))
      File.write(File.join(project_dir, "INDEX.md"), "# Index\n")
      # deliberately: no project.yml, no AGENTS.md at project_root

      result = ProjectValidator.validate("demo", plastic_home: home)

      refute result[:ok]
      assert_includes result[:missing], "project.yml"
      assert_includes result[:missing], "AGENTS.md (project root)"
    end
  end

  def test_unregistered_slug_is_not_ok
    Dir.mktmpdir do |home|
      File.write(File.join(home, "projects.yml"), YAML.dump({ "projects" => {} }))
      result = ProjectValidator.validate("ghost", plastic_home: home)
      refute result[:ok]
      assert_includes result[:missing], "projects.yml registration"
    end
  end

  def test_missing_projects_yml_treated_as_unregistered
    Dir.mktmpdir do |home|
      result = ProjectValidator.validate("demo", plastic_home: home)
      refute result[:ok]
    end
  end

  # Removing project_root itself would race Dir.mktmpdir's own cleanup (its
  # ensure block also tries to remove that same path), so this registers a
  # nested directory as the project path and removes only that, leaving
  # project_root (the mktmpdir root) intact for mktmpdir to clean up normally.
  def test_missing_project_directory_on_disk_is_flagged
    with_registered_project do |home, project_root|
      real_project_dir = File.join(project_root, "real")
      FileUtils.mkdir_p(real_project_dir)
      File.write(File.join(home, "projects.yml"),
                 YAML.dump({ "projects" => { "demo" => { "path" => real_project_dir } } }))
      build_complete_spawn(home, real_project_dir)
      FileUtils.remove_entry(real_project_dir)

      result = ProjectValidator.validate("demo", plastic_home: home)
      refute result[:ok]
      assert_includes result[:missing], "project directory"
    end
  end

  def test_malformed_project_yml_is_flagged
    with_registered_project do |home, project_root|
      build_complete_spawn(home, project_root)
      File.write(File.join(home, "projects", "demo", "project.yml"), "not: valid: yaml: [")
      result = ProjectValidator.validate("demo", plastic_home: home)
      refute result[:ok]
      assert_includes result[:missing], "project.yml (valid YAML)"
    end
  end

  def test_missing_store_dir_and_index_are_both_flagged
    with_registered_project do |home, project_root|
      build_complete_spawn(home, project_root)
      FileUtils.remove_entry(File.join(home, "projects", "demo", "store"))
      File.delete(File.join(home, "projects", "demo", "INDEX.md"))
      result = ProjectValidator.validate("demo", plastic_home: home)
      refute result[:ok]
      assert_includes result[:missing], "store/"
      assert_includes result[:missing], "INDEX.md"
    end
  end

  # --- CLI smoke, mirrors validate-intent's own test pattern ---

  def test_cli_exits_zero_for_a_complete_spawn
    with_registered_project do |home, project_root|
      build_complete_spawn(home, project_root)
      ok = system(CLI, "demo", "--home", home, out: File::NULL, err: File::NULL)
      assert ok, "CLI should exit 0 for a structurally complete spawn"
    end
  end

  def test_cli_exits_nonzero_for_an_incomplete_spawn
    with_registered_project do |home, project_root|
      # registered, but nothing else built: incomplete on every later invariant
      ok = system(CLI, "demo", "--home", home, out: File::NULL, err: File::NULL)
      refute ok, "CLI must exit non-zero for an incomplete spawn"
    end
  end

  def test_cli_missing_slug_exits_usage
    Dir.mktmpdir do |home|
      ok = system(CLI, "--home", home, out: File::NULL, err: File::NULL)
      refute ok, "CLI must exit non-zero (usage) when no slug is given"
    end
  end
end
