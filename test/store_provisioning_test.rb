require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

require_relative "../scripts/lib/store_provisioning"

# Hermetic unit tests for the project-store provisioner (intent 61). Each test
# builds its own Dir.mktmpdir used as plastic_home and injects package_root
# pointing at the repo root so templates resolve. No eval, no global-constant
# injection.
class StoreProvisioningTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.expand_path("../scripts/provision-project-store", __dir__)

  # Build a tmp plastic_home with `demo` registered in projects.yml.
  def with_registered_home
    Dir.mktmpdir do |home|
      File.write(File.join(home, "projects.yml"),
                 YAML.dump({ "projects" => { "demo" => { "path" => "/tmp/demo" } } }))
      yield home
    end
  end

  # --- create the store and the three files ---

  def test_provision_creates_store_and_three_files
    with_registered_home do |home|
      result = StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)

      assert result[:ok], "expected ok, got #{result.inspect}"

      store_dir = File.join(home, "projects", "demo", "store")
      assert File.directory?(store_dir), "store dir should exist"
      assert File.exist?(File.join(store_dir, ".gitkeep")), ".gitkeep should exist"

      index = File.join(home, "projects", "demo", "INDEX.md")
      project_yml = File.join(home, "projects", "demo", "project.yml")
      assert File.exist?(index), "INDEX.md should exist at project root"
      assert File.exist?(project_yml), "project.yml should exist at project root"

      assert_equal File.read(File.join(REPO, "templates", "index.md")), File.read(index)
      assert_equal File.read(File.join(REPO, "templates", "project.yml")), File.read(project_yml)
    end
  end

  # --- idempotent + never clobbers existing files ---

  def test_provision_is_idempotent_and_no_clobber
    with_registered_home do |home|
      project_dir = File.join(home, "projects", "demo")
      store_dir = File.join(project_dir, "store")
      FileUtils.mkdir_p(store_dir)
      File.write(File.join(store_dir, ".gitkeep"), "SENTINEL-GITKEEP")
      File.write(File.join(project_dir, "INDEX.md"), "SENTINEL-INDEX")
      File.write(File.join(project_dir, "project.yml"), "SENTINEL-YML")

      first = StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)
      second = StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)

      assert first[:ok]
      assert second[:ok]
      assert_empty first[:created], "nothing should be (re)written when all files exist"
      assert_empty second[:created], "second run must create nothing"

      assert_equal "SENTINEL-GITKEEP", File.read(File.join(store_dir, ".gitkeep"))
      assert_equal "SENTINEL-INDEX", File.read(File.join(project_dir, "INDEX.md"))
      assert_equal "SENTINEL-YML", File.read(File.join(project_dir, "project.yml"))
    end
  end

  # --- plastic.db* is git-ignored at the shared plastic_home root (ACTION_12) ---
  # Every store (global + every project) lives under the ONE git repo rooted at
  # plastic_home, so one unanchored .gitignore entry there covers every store's
  # plastic.db/-wal/-shm sidecars, present and future.

  def test_provision_ensures_plastic_db_gitignored_at_plastic_home
    with_registered_home do |home|
      StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)

      gitignore = File.read(File.join(home, ".gitignore"))
      assert_includes gitignore.lines.map(&:strip), "plastic.db*"
    end
  end

  def test_provision_never_creates_the_db_file_itself
    with_registered_home do |home|
      StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)

      refute File.exist?(File.join(home, "plastic.db")),
             "provisioning a store must never force-create plastic.db (D3: lazy on first connect)"
    end
  end

  def test_provision_is_idempotent_for_the_gitignore_entry
    with_registered_home do |home|
      StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)
      StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)

      gitignore = File.read(File.join(home, ".gitignore"))
      assert_equal 1, gitignore.lines.map(&:strip).count("plastic.db*"),
                   "a second provision must not duplicate the entry"
    end
  end

  # --- unregistered slug errors and writes nothing ---

  def test_unregistered_slug_errors_and_writes_nothing
    with_registered_home do |home|
      result = StoreProvisioning.provision("ghost", plastic_home: home, package_root: REPO)

      refute result[:ok], "unregistered slug must not succeed"
      assert_match(/projects\.yml/, result[:error])
      refute File.exist?(File.join(home, "projects", "ghost")),
             "no files should be created for an unregistered slug"
    end
  end

  def test_missing_projects_yml_treated_as_unregistered
    Dir.mktmpdir do |home|
      result = StoreProvisioning.provision("demo", plastic_home: home, package_root: REPO)
      refute result[:ok]
      refute File.exist?(File.join(home, "projects", "demo"))
    end
  end

  # --- pure filesystem: no qmd / system / spawn / backticks in the lib source ---

  def test_no_qmd_mutation_in_source
    # Scan only executable code, not the explanatory doc comments (which
    # legitimately state that the lib performs no qmd mutation).
    code = File.readlines(File.join(REPO, "scripts", "lib", "store_provisioning.rb"))
               .reject { |line| line.strip.start_with?("#") }
               .join
    refute_match(/\bqmd\b/i, code, "lib code must not reference qmd")
    refute_match(/\bsystem\b/, code, "lib code must not call system")
    refute_match(/\bspawn\b/, code, "lib code must not call spawn")
    refute_match(/`/, code, "lib code must not use backticks")
  end

  # --- CLI smoke (mirrors intent_validator_test.rb's system(...) cases) ---

  def test_cli_provisions_with_home_override
    with_registered_home do |home|
      ok = system(CLI, "demo", "--home", home, out: File::NULL, err: File::NULL)
      assert ok, "CLI should exit 0 for a registered slug"
      assert File.directory?(File.join(home, "projects", "demo", "store"))
      assert File.exist?(File.join(home, "projects", "demo", "store", ".gitkeep"))
    end
  end

  def test_cli_unregistered_slug_exits_nonzero
    with_registered_home do |home|
      ok = system(CLI, "ghost", "--home", home, out: File::NULL, err: File::NULL)
      refute ok, "CLI must exit non-zero for an unregistered slug"
    end
  end

  def test_cli_missing_slug_exits_usage
    with_registered_home do |home|
      ok = system(CLI, "--home", home, out: File::NULL, err: File::NULL)
      refute ok, "CLI must exit non-zero (usage) when no slug is given"
    end
  end
end
