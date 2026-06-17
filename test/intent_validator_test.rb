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
    refute IntentValidator.valid_id?(14)
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

      File.write(md, "---\nid: 9z\nintent: x\nsources: []\nchain: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n")
      assert IntentValidator.validate(intent_dir)[:ok]

      File.write(md, "---\nid: 9z\nintent: x\nsources: []\ncreated: 2026-01-01\nauthor: x\ntags: []\n---\n")
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
end
