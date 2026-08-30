# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "digest"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/compact_instructions"

# Intent 312: the two absolute-token compaction thresholds and the compact-instructions
# block installed into ~/.claude/CLAUDE.md as a marked section.
#
# Every case is hermetic: Dir.mktmpdir agent dirs and plastic homes injected into
# InstallerCore, never a read or a write of the real ~/.claude or ~/.plastic. Modelled on
# test/codex_install_test.rb, which is the working shape for this mechanism.
class CompactInstructionsTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)
  EM_DASH = [0x2014].pack("U") # built from its codepoint: no literal em dash in this repo

  def setup
    @home = Dir.mktmpdir("compact-home")        # plastic_home
    @claude_dir = Dir.mktmpdir("compact-claude") # ~/.claude equivalent
    @agents = [{ key: "claude", name: "Claude Code", dir: @claude_dir, flag: "--claude" }]
    @core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                              agents: @agents, version: "2.0.0-test")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@claude_dir)
  end

  def claude_md
    File.join(@claude_dir, "CLAUDE.md")
  end

  # --- the body ---------------------------------------------------------------

  def test_body_stays_inside_its_byte_budget
    assert_operator CompactInstructions::BODY.bytesize, :<, 1400,
      "the compact block is #{CompactInstructions::BODY.bytesize} bytes; it is injected into " \
      "every top-level and general-purpose agent's context, so it stays under 1,400"
  end

  def test_body_carries_no_em_dash
    refute_includes CompactInstructions::BODY, EM_DASH
  end

  def test_body_states_both_thresholds_and_names_both_config_keys
    assert_includes CompactInstructions::BODY, "350,000"
    assert_includes CompactInstructions::BODY, "500,000"
    assert_includes CompactInstructions::BODY, "context_offer_tokens"
    assert_includes CompactInstructions::BODY, "context_insist_tokens"
  end

  def test_body_names_the_hand_off_and_the_managed_section_rule
    assert_includes CompactInstructions::BODY, "hand-off"
    assert_includes CompactInstructions::BODY, "day ledger"
    assert_includes CompactInstructions::BODY, "managed by the Plastic installer"
  end

  # The block must not name a path 311 has not shipped: it points in words only.
  def test_body_names_no_file_path
    refute_match(%r{\.sessions/}, CompactInstructions::BODY)
    refute_match(/handoff--/, CompactInstructions::BODY)
  end

  # --- the thresholds, in all three places -------------------------------------

  def template_config
    YAML.safe_load(File.read(File.join(WORKTREE, "templates", "config.yml")))
  end

  # scripts/read-config is a CLI: its top-level code exits when given no key, so a test
  # cannot require it to read DEFAULTS. The two rows are read out of the file text.
  def read_config_default(key)
    text = File.read(File.join(WORKTREE, "scripts", "read-config"))
    m = text[/"#{Regexp.escape(key)}"\s*=>\s*([0-9_]+)/, 1]
    m && m.delete("_").to_i
  end

  def test_offer_threshold_agrees_across_the_constant_the_template_and_the_defaults
    assert_equal 350_000, CompactInstructions::OFFER_TOKENS
    assert_equal 350_000, template_config["context_offer_tokens"]
    assert_equal 350_000, read_config_default("context_offer_tokens")
  end

  def test_insist_threshold_agrees_across_the_constant_the_template_and_the_defaults
    assert_equal 500_000, CompactInstructions::INSIST_TOKENS
    assert_equal 500_000, template_config["context_insist_tokens"]
    assert_equal 500_000, read_config_default("context_insist_tokens")
  end

  # --- the section and its hash -------------------------------------------------

  def test_section_carries_the_body_hash_the_lib_computes
    section = @core.claude_compact_section
    assert_includes section, "hash:#{CompactInstructions.body_hash}"
    assert section.start_with?(InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX)
    assert section.rstrip.end_with?(InstallerCore::CLAUDE_SECTION_END)
  end

  # The Claude block gets its own marker pair so a file that carries both sections
  # (a shared or symlinked instruction file) never has one replaced by the other.
  def test_claude_markers_are_distinct_from_the_codex_markers
    refute_equal InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX,
                 InstallerCore::CODEX_SECTION_BEGIN_PREFIX
    refute_equal InstallerCore::CLAUDE_SECTION_END, InstallerCore::CODEX_SECTION_END
    refute_match InstallerCore::CODEX_SECTION_RE, @core.claude_compact_section
    refute_match InstallerCore::CLAUDE_SECTION_RE, @core.codex_section
  end

  # --- injection states ----------------------------------------------------------

  def test_absent_file_is_created_with_the_section
    result = @core.inject_claude_compact_md(claude_md)
    assert_equal :created, result
    assert_equal @core.claude_compact_section, File.read(claude_md)
  end

  def test_existing_user_content_is_appended_to_and_preserved
    seed = "# My rules\n\nAlways use Ruby.\n"
    File.write(claude_md, seed)

    result = @core.inject_claude_compact_md(claude_md)
    content = File.read(claude_md)

    assert_equal :appended, result
    assert content.start_with?(seed), "the user's own text must stay first and intact"
    assert_includes content, InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX
  end

  def test_second_install_replaces_the_section_instead_of_appending_another
    @core.inject_claude_compact_md(claude_md)
    first = File.read(claude_md)

    result = @core.inject_claude_compact_md(claude_md)
    second = File.read(claude_md)

    assert_equal :replaced, result
    assert_equal first, second
    assert_equal 1, second.scan(InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX).length
  end

  def test_an_updated_body_replaces_the_stale_one_and_its_hash
    @core.inject_claude_compact_md(claude_md, body: "Body A\n")
    stale_hash = File.read(claude_md)[/hash:(\w+)/, 1]

    result = @core.inject_claude_compact_md(claude_md, body: "Body B\n")
    content = File.read(claude_md)

    assert_equal :replaced, result
    assert_includes content, "Body B"
    refute_includes content, "Body A"
    refute_includes content, stale_hash
  end

  def test_a_malformed_section_refuses_the_write_and_leaves_the_file_untouched
    corrupt = "# My rules\n\n#{InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX} hash:deadbeef -->\nhalf a block\n"
    File.write(claude_md, corrupt)

    result = @core.inject_claude_compact_md(claude_md)

    assert_equal :refused, result
    assert_equal corrupt, File.read(claude_md), "a corrupt section must leave the file untouched"
  end

  # --- one file carrying both harnesses' sections ---------------------------------

  def test_a_file_with_both_sections_keeps_both_through_an_inject_of_either
    File.write(claude_md, "# Shared\n")
    @core.inject_codex_agents_md(claude_md)
    @core.inject_claude_compact_md(claude_md)
    content = File.read(claude_md)

    assert_includes content, InstallerCore::CODEX_SECTION_BEGIN_PREFIX
    assert_includes content, InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX
    assert_includes content, InstallerCore::CODEX_AGENTS_MD_BODY.strip.lines.first.strip
    assert_includes content, CompactInstructions::BODY.strip.lines.first.strip

    # Re-injecting one must not disturb the other.
    @core.inject_claude_compact_md(claude_md)
    again = File.read(claude_md)
    assert_includes again, InstallerCore::CODEX_SECTION_BEGIN_PREFIX
    assert_equal 1, again.scan(InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX).length
  end

  def test_stripping_one_section_leaves_the_other_and_the_user_text
    File.write(claude_md, "# Shared\n")
    @core.inject_codex_agents_md(claude_md)
    @core.inject_claude_compact_md(claude_md)

    @core.strip_claude_compact_section(claude_md)
    content = File.read(claude_md)

    assert_includes content, "# Shared"
    assert_includes content, InstallerCore::CODEX_SECTION_BEGIN_PREFIX
    refute_includes content, InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX
  end

  # --- symlinks -------------------------------------------------------------------

  def linked_pair
    target = File.join(@home, "dotfiles-CLAUDE.md")
    File.write(target, "# Managed elsewhere\n")
    File.symlink(target, claude_md)
    [target, claude_md]
  end

  def test_injecting_through_a_symlink_writes_the_target_and_keeps_the_link
    target, link = linked_pair

    @core.inject_claude_compact_md(link)

    assert File.symlink?(link), "a dotfiles-managed CLAUDE.md must still be a symlink"
    assert_includes File.read(target), InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX
    assert_includes File.read(target), "# Managed elsewhere"
  end

  def test_stripping_through_a_symlink_writes_the_target_and_keeps_the_link
    target, link = linked_pair
    @core.inject_claude_compact_md(link)

    @core.strip_claude_compact_section(link)

    assert File.symlink?(link), "a dotfiles-managed CLAUDE.md must still be a symlink"
    refute_includes File.read(target), InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX
    assert_includes File.read(target), "# Managed elsewhere"
  end

  # --- the Codex aliases still work -------------------------------------------------

  def test_codex_named_methods_still_default_to_the_codex_body_and_markers
    agents_md = File.join(@claude_dir, "AGENTS.md")

    assert_equal :created, @core.inject_codex_agents_md(agents_md)
    content = File.read(agents_md)
    assert_includes content, InstallerCore::CODEX_SECTION_BEGIN_PREFIX
    assert_includes content, InstallerCore::CODEX_AGENTS_MD_BODY.strip
    refute_includes content, InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX

    assert_equal agents_md, @core.strip_codex_section(agents_md)
  end

  # --- install and uninstall ----------------------------------------------------------

  def test_uninstall_strips_the_section_and_round_trips_user_content
    seed = "# My rules\n\nAlways use Ruby.\n"
    File.write(claude_md, seed)
    @core.inject_claude_compact_md(claude_md)

    stripped = @core.strip_claude_compact_section(claude_md)

    assert_equal claude_md, stripped
    assert_equal seed, File.read(claude_md),
      "pre-existing user content must round-trip byte-identical"
  end

  def test_uninstall_deletes_a_claude_md_plastic_created
    @core.inject_claude_compact_md(claude_md)

    @core.strip_claude_compact_section(claude_md)

    refute File.exist?(claude_md), "a Plastic-created CLAUDE.md must be removed entirely"
  end

  def test_strip_is_a_no_op_when_no_section_is_present
    File.write(claude_md, "# My rules\n")
    assert_nil @core.strip_claude_compact_section(claude_md)
    assert_equal "# My rules\n", File.read(claude_md)
  end

  # --- distribution -----------------------------------------------------------------

  # install_sync_test's lib scan globs scripts/* and matches require_relative "lib/<name>",
  # so it cannot see a lib requiring a sibling lib. This is the pin that can fail.
  def test_the_shared_lib_is_distributed
    assert @core.core_files.key?("scripts/lib/compact_instructions.rb"),
      "scripts/lib/compact_instructions.rb must be in core_files or the installed doctor LoadErrors"
  end

  # --- docs -------------------------------------------------------------------------

  def test_docs_document_the_keys_and_the_block
    internals = File.read(File.join(WORKTREE, "docs", "internals.md"))
    assert_includes internals, "context_offer_tokens"
    assert_includes internals, "context_insist_tokens"
    assert_includes internals, InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX

    adapters = File.read(File.join(WORKTREE, "docs", "reference", "harness-adapters.md"))
    assert_match(/marked section.*CLAUDE\.md|CLAUDE\.md.*marked section/, adapters,
      "the Claude harness row must say the compact block is a marked section, not bare native text")
  end
end
