require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/intent_validator"

# Hermetic unit tests for the born-complete validator (intent 60). Each test
# that touches the filesystem builds its own Dir.mktmpdir; the pure helpers need
# none. No eval, no global-constant injection.
class IntentValidatorTest < Minitest::Test
  def complete_frontmatter(overrides = {})
    {
      "id" => "1",
      "intent" => "Test intent",
      "sources" => [],
      "chain" => [],
      "created" => "2026-01-01",
      "author" => "test",
      "tags" => [],
    }.merge(overrides)
  end

  # The five sanctioned `##` sections (intent 60b), for building born-complete
  # intent file bodies in tests that exercise `validate`/`validate_content`.
  SANCTIONED_BODY = <<~BODY
    ## Intent
    Test intent

    ## Context
    Why

    ## Outcome
    Result

    ## Insights
    Notes

    ## Links
    - none
  BODY

  # --- valid_id? ---

  def test_valid_id_accepts_folgezettel_forms
    assert IntentValidator.valid_id?("14")
    assert IntentValidator.valid_id?("14a")
    assert IntentValidator.valid_id?("4a1")
  end

  def test_valid_id_rejects_junk
    refute IntentValidator.valid_id?("")
    refute IntentValidator.valid_id?("a")
    refute IntentValidator.valid_id?("14-x")
    refute IntentValidator.valid_id?(nil)
    refute IntentValidator.valid_id?("global:")
    refute IntentValidator.valid_id?("global:abc")
  end

  # Regression (intent 60a): alpha.30 false-flagged legitimate cross-store
  # references (the [[global:ID]] link form) and integer-typed ids. Both are valid.
  def test_valid_id_accepts_cross_store_and_integer_ids
    assert IntentValidator.valid_id?("global:1a2")
    assert IntentValidator.valid_id?("knowdb:1")
    assert IntentValidator.valid_id?("global:14a")
    assert IntentValidator.valid_id?(17)
    assert IntentValidator.valid_id?(14)
  end

  def test_valid_id_with_known_stores_accepts_recognized_prefix
    assert IntentValidator.valid_id?("knowdb:1", known_stores: %w[global plastic knowdb])
  end

  # THE exact hazard: the tag form has a legal shape, but its prefix is not a real store.
  def test_valid_id_with_known_stores_rejects_unrecognized_prefix
    refute IntentValidator.valid_id?("project-ai-agents-resources:1",
                                      known_stores: %w[global plastic knowdb ai-agents-resources])
  end

  def test_valid_id_with_known_stores_still_shape_checks_first
    refute IntentValidator.valid_id?("14-x", known_stores: %w[global])
  end

  # Fallback (unsupplied known_stores): unchanged shape-only behavior, so every existing
  # caller of valid_id? keeps working.
  def test_valid_id_without_known_stores_falls_back_to_shape_only
    assert IntentValidator.valid_id?("project-ai-agents-resources:1")
  end

  def test_valid_id_known_stores_ignores_bare_ids
    assert IntentValidator.valid_id?("14a", known_stores: %w[global])
  end

  # --- validate_frontmatter: missing fields ---

  def test_missing_chain_is_reported
    result = IntentValidator.validate_frontmatter(complete_frontmatter.tap { |h| h.delete("chain") })

    refute result[:ok]
    assert_includes result[:missing], "chain"
  end

  def test_each_required_field_when_omitted_is_reported
    IntentValidator::REQUIRED_FIELDS.each do |field|
      fm = complete_frontmatter
      fm.delete(field)
      result = IntentValidator.validate_frontmatter(fm)

      refute result[:ok], "omitting #{field} should be incomplete"
      assert_includes result[:missing], field, "#{field} should be reported missing"
    end
  end

  # --- validate_frontmatter: shape ---

  def test_sources_not_an_array_is_an_error
    result = IntentValidator.validate_frontmatter(complete_frontmatter("sources" => "nope"))

    refute result[:ok]
    assert result[:errors].any? { |e| e.include?("must be an array") }
  end

  def test_chain_with_bad_element_is_an_error
    result = IntentValidator.validate_frontmatter(complete_frontmatter("chain" => ["1", "bad id"]))

    refute result[:ok]
    assert result[:errors].any? { |e| e.include?("invalid id") }
  end

  def test_validate_frontmatter_reports_unknown_store_with_named_prefix
    fm = { "id" => "1", "intent" => "t", "sources" => ["project-ai-agents-resources:1"],
           "chain" => [], "created" => "2026-01-01", "author" => "t", "tags" => ["t"] }
    result = IntentValidator.validate_frontmatter(
      fm, known_stores: %w[global plastic knowdb ai-agents-resources]
    )
    refute result[:ok]
    assert(result[:errors].any? { |e|
      e.include?("project-ai-agents-resources") && e.include?("not a known store")
    })
  end

  def test_validate_frontmatter_without_known_stores_still_accepts_tag_form_shape
    fm = { "id" => "1", "intent" => "t", "sources" => ["project-ai-agents-resources:1"],
           "chain" => [], "created" => "2026-01-01", "author" => "t", "tags" => ["t"] }
    result = IntentValidator.validate_frontmatter(fm) # no known_stores: unchanged fallback
    assert result[:ok], "shape-only fallback must accept this the same as before"
  end

  def test_well_formed_arrays_pass
    result = IntentValidator.validate_frontmatter(complete_frontmatter("sources" => ["1", "4a1"], "chain" => ["14a"]))

    assert result[:ok], "well-formed frontmatter should pass, got #{result[:errors].inspect}"
    assert_empty result[:errors]
  end

  def test_nil_or_non_hash_reports_no_frontmatter
    [nil, "not a hash", 42].each do |bad|
      result = IntentValidator.validate_frontmatter(bad)
      refute result[:ok]
      assert result[:errors].any? { |e| e.include?("no frontmatter") }, "#{bad.inspect} should report no frontmatter"
    end
  end

  # --- validate(intent_dir) ---

  def test_validate_reads_intent_dir
    Dir.mktmpdir do |dir|
      id = "9z--smoke"
      intent_dir = File.join(dir, id)
      FileUtils.mkdir_p(intent_dir)
      md = File.join(intent_dir, "#{id}.md")

      File.write(md, "---\nid: 9z\nintent: x\nsources: []\nchain: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n\n#{SANCTIONED_BODY}")
      assert IntentValidator.validate(intent_dir)[:ok]

      File.write(md, "---\nid: 9z\nintent: x\nsources: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n\n#{SANCTIONED_BODY}")
      result = IntentValidator.validate(intent_dir)
      refute result[:ok]
      assert_includes result[:missing], "chain"
    end
  end

  # --- intent-51 regression: an intent born without `chain` ---
  # Intent 51 was created with no `chain` key; nothing caught it at birth.
  # The library is one of three detection paths (CLI and doctor are the others,
  # asserted in test/doctor_test.rb's Intent51RegressionTest).

  def test_intent_51_chainless_intent_is_caught_by_library
    Dir.mktmpdir do |dir|
      id = "51--chainless"
      intent_dir = File.join(dir, id)
      FileUtils.mkdir_p(intent_dir)
      File.write(File.join(intent_dir, "#{id}.md"),
                 "---\nid: 51\nintent: born without chain\nsources: []\ncreated: 2026-01-01\nauthor: test\ntags: []\n---\n")

      result = IntentValidator.validate(intent_dir)
      refute result[:ok], "chainless intent must be flagged incomplete"
      assert_includes result[:missing], "chain"
    end
  end

  def test_intent_51_chainless_intent_is_caught_by_cli
    Dir.mktmpdir do |dir|
      id = "51--chainless"
      intent_dir = File.join(dir, id)
      FileUtils.mkdir_p(intent_dir)
      File.write(File.join(intent_dir, "#{id}.md"),
                 "---\nid: 51\nintent: born without chain\nsources: []\ncreated: 2026-01-01\nauthor: test\ntags: []\n---\n")

      cli = File.expand_path("../scripts/validate-intent", __dir__)
      ok = system(cli, intent_dir, out: File::NULL, err: File::NULL)
      refute ok, "validate-intent must exit non-zero for an intent missing chain"
    end
  end

  # --- validate_sections (intent 60b) ---

  def test_validate_sections_flags_unknown_heading
    body = SANCTIONED_BODY + "\n## Foo\nbogus\n"
    result = IntentValidator.validate_sections(body)
    refute result[:ok]
    assert_includes result[:unknown], "## Foo"
  end

  def test_validate_sections_flags_missing_links
    body = SANCTIONED_BODY.sub(/## Links.*\z/m, "")
    result = IntentValidator.validate_sections(body)
    refute result[:ok]
    assert_includes result[:missing], "## Links"
  end

  def test_validate_sections_does_not_flag_missing_decisions
    # All five sanctioned sections, no ### Decisions subsection: ok.
    result = IntentValidator.validate_sections(SANCTIONED_BODY)
    assert result[:ok], "missing optional ### Decisions must not be flagged: #{result.inspect}"
    assert_empty result[:missing]
    assert_empty result[:unknown]
  end

  def test_validate_sections_ignores_present_decisions_subsection
    body = SANCTIONED_BODY.sub("## Context\nWhy\n", "## Context\nWhy\n\n### Decisions\n- D1\n")
    result = IntentValidator.validate_sections(body)
    assert result[:ok], "### Decisions under Context must not be flagged: #{result.inspect}"
  end

  # --- validate / validate_content merge (intent 60b) ---

  def test_validate_content_fails_on_bad_sections_with_complete_frontmatter
    fm = "---\nid: 1\nintent: x\nsources: []\nchain: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n\n"
    content = fm + SANCTIONED_BODY + "\n## Foo\nbogus\n"
    result = IntentValidator.validate_content(content)
    refute result[:ok]
    assert result[:errors].any? { |e| e.include?("unknown section: ## Foo") }
  end

  def test_validate_content_ok_for_born_complete_intent
    fm = "---\nid: 1\nintent: x\nsources: []\nchain: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n\n"
    content = fm + SANCTIONED_BODY
    result = IntentValidator.validate_content(content)
    assert result[:ok], "born-complete + sanctioned content must pass: #{result[:errors].inspect}"
  end

  def test_validate_surfaces_missing_section_in_errors
    Dir.mktmpdir do |dir|
      id = "7--nolinks"
      intent_dir = File.join(dir, id)
      FileUtils.mkdir_p(intent_dir)
      body = SANCTIONED_BODY.sub(/## Links.*\z/m, "")
      File.write(File.join(intent_dir, "#{id}.md"),
                 "---\nid: 7\nintent: x\nsources: []\nchain: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n\n#{body}")
      result = IntentValidator.validate(intent_dir)
      refute result[:ok]
      assert result[:errors].any? { |e| e.include?("missing required section: ## Links") }
    end
  end

  # --- validate_graph: cross-intent graph-shape invariants (intent 68) ---
  # Pure helper, so no tmpdir: pass a `nodes` Hash directly.

  def test_validate_graph_warns_on_i1_violation
    nodes = {
      "A" => { sources: [], chain: [] },
      "B" => { sources: ["A"], chain: [] },
    }
    result = IntentValidator.validate_graph(nodes)
    refute_empty result[:i1]
    assert result[:i1].any? { |f| f.include?("A") && f.include?("B") }
  end

  def test_validate_graph_no_warn_on_i2_asymmetry
    # A relational chain entry (A.chain lists B) with no reciprocal B.sources is
    # valid (I2) and must NOT be flagged by any invariant.
    nodes = {
      "A" => { sources: [], chain: ["B"] },
      "B" => { sources: [], chain: [] },
    }
    result = IntentValidator.validate_graph(nodes)
    assert_empty result[:i1]
    assert_empty result[:i3]
    assert_empty result[:i4]
  end

  def test_validate_graph_flags_i3_overlap
    nodes = {
      "X" => { sources: ["A"], chain: ["A"] },
      "A" => { sources: [], chain: ["X"] },
    }
    result = IntentValidator.validate_graph(nodes)
    refute_empty result[:i3]
    assert result[:i3].any? { |f| f.include?("A") }
  end

  def test_validate_graph_flags_i4_dangler_but_not_cross_store_ref
    nodes = {
      "X" => { sources: [], chain: ["zzz", "global:1a"] },
    }
    result = IntentValidator.validate_graph(nodes)
    assert result[:i4].any? { |f| f.include?("zzz") }
    refute result[:i4].any? { |f| f.include?("global:1a") }
  end
end
