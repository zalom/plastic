# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../scripts/lib/installer_core"
require_relative "varar/support/kernel_command"

# A throwaway home for each InstallerCore test.
module InstallerCoreHome
  def setup
    @home = Dir.mktmpdir("installer-core")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def installer(package_root = Dir.pwd) = InstallerCore.new(package_root: package_root, plastic_home: File.join(@home, ".plastic"))

  def read_json(*parts) = JSON.parse(File.read(File.join(*parts)))
end

class InstallerCoreHooksTest < Minitest::Test
  include InstallerCoreHome

  def settings_with(settings)
    path = File.join(@home, "settings.json")
    File.write(path, JSON.generate(settings))
    path
  end

  def install(settings, times: 1)
    path = settings_with(settings)
    times.times { capture_io { installer.merge_claude_hooks(path) } }
    JSON.parse(File.read(path))
  end

  def rebind(package_root, hooks)
    FileUtils.mkdir_p(package_root)
    File.write(File.join(package_root, "VERSION"), "2.0.3\n")
    path = settings_with("hooks" => hooks)
    capture_io { installer(package_root).merge_claude_hooks(path) }
    JSON.parse(File.read(path))
  end

  def commands(settings, event) = Array(settings["hooks"][event]).flat_map { |group| group["hooks"].map { |hook| hook["command"] } }

  def test_the_install_writes_the_kernel_hooks
    settings = install({})
    kernel = %("#{File.join(@home, ".plastic", "bin", "plastic")}")
    expected = { "SessionStart" => "#{kernel} hook start",
                 "Stop" => "#{kernel} hook stop", "SessionEnd" => "#{kernel} hook end" }

    assert_empty(expected.reject { |event, text| commands(settings, event).any? { |cmd| cmd.include?(text) } })
  end

  def test_the_install_keeps_check_update
    assert(commands(install({}), "SessionStart").any? { |cmd| cmd.end_with?("plastic-check-update") })
  end

  def test_a_release_install_binds_the_hooks_to_the_active_launcher
    share = File.join(@home, ".local", "share", "plastic")
    former = %(env -u RUBYOPT "#{File.join(@home, ".plastic", "bin", "plastic")}" hook resume --harness claude-code || true)
    settings = rebind(File.join(share, "releases", "2.0.3"), "SessionStart" => [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => former }] }])

    resume = commands(settings, "SessionStart").grep(/hook start/)

    assert_equal [%(env -u RUBYOPT "#{File.join(share, "active", "bin", "plastic")}" hook start || true)], resume
  end

  def test_a_second_install_keeps_one_group_per_event
    assert_equal 1, commands(install({}, times: 2), "Stop").size
  end

  def test_removing_the_hooks_keeps_the_hooks_of_the_person
    own = { "type" => "command", "command" => "echo mine" }
    path = settings_with("hooks" => { "Stop" => [{ "matcher" => "", "hooks" => [own] }] })
    capture_io { installer.merge_claude_hooks(path) }
    capture_io { installer.remove_claude_hooks(path) }

    assert_equal ["echo mine"], commands(JSON.parse(File.read(path)), "Stop")
  end
end

class InstallerCoreTest < Minitest::Test
  include InstallerCoreHome

  def agents_file = File.join(@home, "AGENTS.md")

  def test_the_ledger_and_the_manifest_carry_local_time_with_its_offset
    installer.ledger_append("2.0.3", "install")
    installer.write_manifest([], File.join(@home, "manifest.json"))

    times = [read_json(@home, ".plastic", "versions.json")["at"], read_json(@home, "manifest.json")["created"]]

    assert_empty(times.grep_v(/[+-]\d\d:\d\d\z/))
  end

  def test_the_ledger_reads_back_its_rows_in_order_and_skips_a_broken_line
    installer.ledger_append("2.0.2", "install")
    File.write(installer.ledger_path, "{ broken\n", mode: "a")
    installer.ledger_append("2.0.3", "update", harness: "claude")

    assert_equal [%w[2.0.2 2.0.3], "claude"], [installer.ledger_read.map { |row| row["version"] }, installer.ledger_read.last["harness"]]
  end

  def test_versions_compare_by_semver_and_an_unparsed_version_compares_to_nil
    assert_equal [-1, 1, nil], [installer.semver_compare("2.0.0-beta.1", "2.0.0"), installer.semver_compare("2.0.10", "2.0.9"), installer.semver_compare("2.0", "2.0.0")]
  end

  def test_the_version_names_its_channel
    assert_equal %w[alpha beta latest], %w[2.0.0-alpha.1 2.0.0-beta.1 2.0.3].map { |version| installer.channel_for(version) }
  end

  def test_the_agent_flags_name_the_agent_keys
    assert_equal [%w[codex], %w[claude codex hermes]], [installer.agent_keys_from(%w[--codex --verbose]), installer.agent_keys_from(%w[--all --claude])]
  end

  def test_a_marked_section_is_appended_then_replaced_in_place
    File.write(agents_file, "# Mine\n")

    assert_equal %i[appended replaced], [installer.inject_marked_section(agents_file, body: "one"), installer.inject_marked_section(agents_file, body: "two")]
    assert_equal 1, File.read(agents_file).scan(InstallerCore::CODEX_SECTION_BEGIN_PREFIX).size
  end

  def test_stripping_the_marked_section_gives_back_the_file_of_the_person
    File.write(agents_file, "# Mine\n")
    installer.inject_marked_section(agents_file, body: "one")
    installer.strip_marked_section(agents_file)

    assert_equal "# Mine\n", File.read(agents_file)
  end

  def test_a_section_with_no_end_marker_is_refused
    File.write(agents_file, "#{InstallerCore::CODEX_SECTION_BEGIN_PREFIX} -->\nhalf\n")

    assert_equal :refused, installer.inject_marked_section(agents_file, body: "one")
  end

  def test_frontmatter_splits_from_the_body
    assert_equal [[{ "name" => "lead" }, "Body\n"], [{}, "Body\n"]], [installer.split_frontmatter("---\nname: lead\n---\nBody\n"), installer.split_frontmatter("Body\n")]
  end

  def test_toml_strings_escape_quotes_backslashes_and_newlines
    assert_equal ['a \\"b\\" \\\\ c', "a\n\\\"\\\"\\\""], [installer.toml_inline_escape("a \"b\"\n\\ c"), installer.toml_ml_escape("a\r\n\"\"\"")]
  end

  def test_json_with_comments_and_trailing_commas_is_read_and_garbage_is_nil
    File.write(File.join(@home, "loose.json"), %({ "a": 1, // note\n }))
    File.write(File.join(@home, "garbage.json"), "{ broken")

    assert_equal [{ "a" => 1 }, nil], %w[loose garbage].map { |name| installer.read_json_safe(File.join(@home, "#{name}.json")) }
  end

  def test_a_file_that_exists_is_not_overwritten
    path = File.join(@home, "note.md")
    installer.write_if_missing(path, "first\n")
    installer.write_if_missing(path, "second\n")

    assert_equal "first\n", File.read(path)
  end

  def test_a_sibling_that_shares_a_prefix_is_not_contained
    root = File.join(@home, "x")

    assert_equal [true, true, false], [File.join(root, "a"), root, "#{root}-evil"].map { |path| installer.path_contained?(path, [root]) }
  end

  def test_the_former_advisor_names_move_to_the_current_names
    config = { "advisor" => { "claude" => { "default" => "plastic-advisor" } }, "agents" => { "models" => { "claude" => { "plastic-faux-advisor" => "opus" } } } }
    migrated = installer.migrate_advisor_config(config)

    assert_equal ["plastic-primary-advisor", { "plastic-secondary-advisor" => "opus" }], [migrated.dig("advisor", "claude", "default"), migrated.dig("agents", "models", "claude")]
  end
end

class InstallerCoreBootstrapTest < Minitest::Test
  include InstallerCoreHome

  def plastic_home = File.join(@home, ".plastic")

  def global(*parts) = File.join(plastic_home, "stores", "global", *parts)

  def bootstrap = capture_io { installer.bootstrap }

  def test_a_first_install_writes_no_legacy_index_into_the_global_store
    bootstrap

    refute_path_exists global("INDEX.md")
  end

  def test_a_first_install_creates_the_three_store_databases
    bootstrap

    assert_equal %w[knowledge_graph.db references.db work_graph.db], Dir.children(global).grep(/\.db\z/).sort
  end

  def test_a_first_install_leaves_the_store_ready_for_intent_new
    bootstrap
    call = KernelCommand.new(@home).run("intent", "new", "First")

    assert_equal [0, true], [call.code, Dir.exist?(global("store", "1--first"))]
  end

  def test_a_first_install_leaves_the_store_readable_by_search
    bootstrap
    call = KernelCommand.new(@home).run("search", "nothing-matches-this")

    assert_equal [0, ""], [call.code, call.err]
  end

  def test_a_first_install_leaves_the_store_readable_by_document_get
    bootstrap
    call = KernelCommand.new(@home).run("document", "get", "plastic://global/1/spec.md")

    refute_includes call.err, "maintenance is required"
  end

  def test_a_first_install_over_a_legacy_home_creates_no_new_global_store
    FileUtils.mkdir_p(plastic_home)
    File.write(File.join(plastic_home, "INDEX.md"), "# Index\n")
    bootstrap

    refute_path_exists global("work_graph.db")
  end

  def test_an_install_over_a_store_that_has_its_index_leaves_it_byte_for_byte
    FileUtils.mkdir_p(global)
    File.binwrite(global("INDEX.md"), "# Index\n\n## Active\n\n- 1 first\n")
    bootstrap

    assert_equal "# Index\n\n## Active\n\n- 1 first\n", File.binread(global("INDEX.md"))
  end
end

class InstallerCoreCodexTest < Minitest::Test
  include InstallerCoreHome

  def codex = { key: "codex", name: "Codex CLI", dir: File.join(@home, ".agents"), home_dir: File.join(@home, ".codex") }

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def test_a_codex_install_writes_each_agent_as_toml_and_records_the_version
    result = nil
    capture_io { result = installer.install_codex(codex, false) }

    assert_equal [true, true, true],
      [result[:success], File.exist?(File.join(@home, ".codex", "agents", "plastic-executor.toml")),
        File.exist?(File.join(@home, ".agents", "plastic", "VERSION"))]
  end

  def test_a_codex_install_from_a_package_with_no_skills_folder_writes_no_skills
    package = File.join(@home, "package")
    write(File.join(package, "VERSION"), "2.0.3\n")
    capture_io { installer(package).install_codex(codex, false) }

    refute_path_exists File.join(@home, ".agents", "skills")
  end

  def test_the_core_files_reach_the_plastic_home_with_their_manifest
    capture_io { installer.distribute(:install, tmp_dirs: []) }
    manifest = read_json(@home, ".plastic", "manifest.json")

    assert_includes manifest["files"].keys, File.join(@home, ".plastic", "bin", "plastic")
  end

  def test_a_skill_folder_is_copied_whole_and_a_shared_fragment_lands_in_the_plastic_home
    source = File.join(@home, "skills")
    write(File.join(source, "demo", "refs", "a.md"), "a\n")
    write(File.join(source, "_shared.md"), "shared\n")
    root = File.join(@home, "installed")

    installed = installer.install_skills_flat(source, root)

    assert_equal [File.join(root, "plastic-demo", "refs", "a.md"), File.join(@home, ".plastic", "_shared.md")].sort,
      installed.sort
  end

  def test_a_codex_install_names_the_hooks_it_changed
    result = nil
    capture_io { result = installer.install_codex(codex, false) }

    assert_equal ["hook end", "hook start", "hook stop"], result[:changed_hooks].sort
  end

  def test_a_second_codex_install_changes_no_hook
    capture_io { installer.install_codex(codex, false) }
    result = nil
    capture_io { result = installer.install_codex(codex, false) }

    assert_empty result[:changed_hooks]
  end
end

class InstallerCoreConfigTest < Minitest::Test
  include InstallerCoreHome

  def config_with(text)
    FileUtils.mkdir_p(File.join(@home, ".plastic"))
    File.write(File.join(@home, ".plastic", "config.yml"), text)
  end

  def config = YAML.safe_load_file(File.join(@home, ".plastic", "config.yml"))

  def test_the_agent_models_come_from_the_section_of_the_harness
    config_with("global: {}\nharnesses:\n  codex:\n    agents:\n      models:\n        plastic-executor: gpt-x\n")

    assert_equal [{ "plastic-executor" => "gpt-x" }, {}], [installer.agent_model_overrides(harness: "codex"), installer.agent_model_overrides]
  end

  def test_the_agent_efforts_come_from_the_section_of_the_harness
    config_with("harnesses:\n  claude-code:\n    agents:\n      efforts:\n        plastic-executor: high\n")

    assert_equal({ "plastic-executor" => "high" }, installer.agent_effort_overrides)
  end

  def test_the_advisor_is_off_when_the_global_section_turns_it_off
    config_with("global:\n  advisor:\n    enabled: false\n")

    refute_predicate installer, :advisor_enabled?
  end

  def test_the_advisor_flags_write_the_global_and_the_claude_code_sections
    config_with("version: 3\n")
    installer.apply_config_flags(["--no-advisor", "--advisor", "secondary"])

    assert_equal [false, "plastic-secondary-advisor"], [config.dig("global", "advisor", "enabled"), config.dig("harnesses", "claude-code", "advisor", "default")]
  end

  def test_with_no_advisor_flag_the_config_is_left_alone
    config_with("version: 3\n")
    installer.apply_config_flags([])

    assert_equal({ "version" => 3 }, config)
  end

  def test_a_flat_config_moves_into_the_sections_and_loses_the_agent_type
    config_with("version: 3\nagent:\n  type: claude-code\nstatusline: false\n")
    installer.migrate_config

    assert_equal({ "version" => 3, "global" => { "statusline" => false } }, config)
  end
end
