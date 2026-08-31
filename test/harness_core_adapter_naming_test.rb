# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Intent 316a1, O2 (D3, D5): the intent screen splits into a harness-agnostic
# core and a Claude adapter. Each half carries the same phrase, verbatim, on
# every file that belongs to it, so the boundary cannot rot silently: a new
# core file that forgets the phrase, a core file that slips in a harness
# name, or a file that adopts a phrase without being registered here, all
# fail a test rather than going unnoticed.
class HarnessCoreAdapterNamingTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  CORE_PHRASE = "Harness-agnostic core: no harness assumption lives here."
  ADAPTER_PHRASE = "Claude adapter: Claude Code only; the core is harness-agnostic."

  CORE = %w[
    scripts/lib/intent_screen.rb
    scripts/lib/intent_screen_ansi.rb
    scripts/intent-screen
  ].freeze

  ADAPTER = %w[
    scripts/lib/message_display.rb
    scripts/hook-message-display
    hooks/message-display
  ].freeze

  def text_for(relative_path)
    File.read(File.join(ROOT, relative_path))
  end

  # --- matrix 10: core named ---------------------------------------------------

  def test_every_core_file_carries_the_core_phrase
    CORE.each do |path|
      assert_includes text_for(path), CORE_PHRASE, "#{path} is missing the core phrase"
    end
  end

  # --- matrix 11: adapter named ------------------------------------------------

  def test_every_adapter_file_carries_the_adapter_phrase
    ADAPTER.each do |path|
      assert_includes text_for(path), ADAPTER_PHRASE, "#{path} is missing the adapter phrase"
    end
  end

  # --- matrix 12: no harness named in the core ---------------------------------
  # No exemption needed: the core phrase itself contains no "Claude", and the
  # contrast clause ("the core is harness-agnostic") lives only in the
  # adapter phrase, which never appears in a core file.

  def test_no_core_file_names_a_harness
    CORE.each do |path|
      refute_match(/claude/i, text_for(path), "#{path} names Claude in a shared-core file")
    end
  end

  # --- matrix 13: unlisted claimant --------------------------------------------

  def all_scripts_and_hooks_files
    Dir.glob(File.join(ROOT, "scripts", "**", "*")).select { |f| File.file?(f) } +
      Dir.glob(File.join(ROOT, "hooks", "*")).select { |f| File.file?(f) }
  end

  def test_no_file_carries_either_phrase_without_being_registered
    expected = (CORE + ADAPTER).map { |p| File.expand_path(p, ROOT) }.sort
    claimants = all_scripts_and_hooks_files.select do |f|
      # Binary-safe: a non-UTF-8 or binary file added under scripts/ or
      # hooks/ later must fail this check by not matching, never by raising
      # ArgumentError out of String#include? on invalid byte sequences.
      content = File.read(f, mode: "rb")
      content.include?(CORE_PHRASE.b) || content.include?(ADAPTER_PHRASE.b)
    end.sort
    assert_equal expected, claimants
  end

  # --- matrix 5: adapter pin, cheap twin ---------------------------------------
  # Beside the expensive spawn test (test/hook_message_display_test.rb), a
  # cheap source pin so deleting the literal at message_display.rb:233 fails
  # twice.

  def test_adapter_passes_markdown_safe_true_at_the_call_site
    # Anchored on the render CALL itself, not the bare string: the same
    # change that added this literal to the call also added it to two
    # nearby comments (see the class-level comment and the one above this
    # call in `finalize`), so a plain `assert_includes` for the string
    # passes even after the argument is deleted from the actual call.
    assert_match(/IntentScreenAnsi\.render\([^\n]*markdown_safe: true/,
                 text_for("scripts/lib/message_display.rb"))
  end

  # --- matrix 8: stale comment corrected ---------------------------------------

  def test_width_cap_comment_no_longer_claims_pre_cleaned_text
    refute_includes text_for("scripts/lib/intent_screen_ansi.rb"), "already markdown-clean"
  end

  # --- matrix 14: registry comment restated, not appended ---------------------

  def test_hook_registry_comment_restated_to_316a1_d3
    text = text_for("scripts/lib/hook_registry.rb")
    refute_includes text, "Intent 316a (D6): Claude Code only, no Codex projection"
    assert_includes text, "316a1"
    assert_includes text, "D3"
  end
end
