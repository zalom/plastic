# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/codex_toml"

class CodexTomlTest < Plastic::TestCase
  CodexToml = Plastic::Installations::CodexToml

  def test_frontmatter_splits_from_the_body
    assert_equal [[{ "name" => "lead" }, "Body\n"], [{}, "Body\n"], [{}, "Body\n"]],
      [CodexToml.split("---\nname: lead\n---\nBody\n"), CodexToml.split("Body\n"), CodexToml.split("---\n: [\n---\nBody\n")]
  end

  def test_frontmatter_that_is_not_a_mapping_reads_as_empty
    assert_equal [{}, "Body\n"], CodexToml.split("---\njust text\n---\nBody\n")
  end

  def test_toml_strings_escape_quotes_backslashes_newlines_and_control_characters
    assert_equal ['a \\"b\\" \\\\ c', "a\n\\\"\\\"\\\"", "\\u0001"],
      [CodexToml.inline("a \"b\"\n\\ c"), CodexToml.multiline("a\r\n\"\"\""), CodexToml.inline("\u0001")]
  end

  def test_a_tier_alias_emits_the_model_and_the_effort
    assert_match(/\Amodel = ".+"\nmodel_reasoning_effort = "high"\z/, CodexToml.model_fields("opus", effort: "high"))
  end

  def test_a_literal_model_id_emits_the_model_and_the_effort
    assert_equal %(model = "gpt-x"\nmodel_reasoning_effort = "low"), CodexToml.model_fields("gpt-x", effort: "low")
  end

  def test_a_model_with_no_effort_emits_only_the_model
    assert_equal %(model = "gpt-x"), CodexToml.model_fields("gpt-x", effort: "")
  end

  def test_an_empty_model_emits_nothing
    assert_equal ["", ""], [CodexToml.model_fields(nil, effort: "low"), CodexToml.model_fields("", effort: "low")]
  end

  def test_a_document_has_a_fixed_field_order_and_the_body_in_a_multi_line_string
    source = File.join(@home, "demo.md")
    File.write(source, %(---\nname: demo\ndescription: A "demo"\nmodel: gpt-x\n---\nBody.\n))

    assert_equal <<~TOML, CodexToml.render(source, nil, "high")
      name = "demo"
      description = "A \\"demo\\""
      model = "gpt-x"
      model_reasoning_effort = "high"
      developer_instructions = """\nBody.\n"""
    TOML
  end

  def test_an_override_wins_over_the_frontmatter_model_and_a_frontmatter_effort_over_the_shipped_one
    source = File.join(@home, "demo.md")
    File.write(source, "---\nname: demo\nmodel: gpt-x\neffort: low\n---\nBody.\n")
    document = CodexToml.render(source, "gpt-y", nil)

    assert_includes document, %(model = "gpt-y"\nmodel_reasoning_effort = "low")
  end

  def test_a_file_with_no_frontmatter_takes_its_name_from_the_file
    source = File.join(@home, "plain.md")
    File.write(source, "Body.\n")

    assert_match(/\Aname = "plain"\ndescription = ""\n/, CodexToml.render(source, nil, nil))
  end
end
