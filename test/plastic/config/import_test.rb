# frozen_string_literal: true

require_relative "../../test_helper"

class ConfigImportTest < Plastic::TestCase
  include ConfigHomes

  YAML_TEXT = <<~YAML
    version: 3
    global:
      advisor:
        level: high
      color: true
    harnesses:
      claude:
        agents:
          models:
            executor: sonnet
  YAML

  def local(home) = Plastic::Graph::Database.open_local(home).fetch(:local).tap(&:migrate)

  def import(home, text = YAML_TEXT)
    path = File.join(home, "config.yml")
    File.write(path, text)
    Plastic::Config::Import.new(path, into: local(home)).call
  end

  def test_nested_scopes_land_as_one_settings_row_each
    home = Dir.mktmpdir

    import(home)

    assert_equal [["claude", "agents.models.executor", '"sonnet"'], ["global", "advisor.level", '"high"'], ["global", "color", "true"]], setting_rows(home)
  end

  def test_a_second_import_changes_nothing
    home = Dir.mktmpdir
    import(home)
    before = setting_rows(home)

    import(home, YAML_TEXT.sub("high", "low"))

    assert_equal before, setting_rows(home)
  end

  def test_a_file_that_is_not_a_mapping_imports_nothing
    home = Dir.mktmpdir

    import(home, "- a\n- b\n")

    assert_empty setting_rows(home)
  end

  def test_a_malformed_file_is_refused_and_imports_no_row
    home = Dir.mktmpdir

    assert_raises(Psych::SyntaxError) { import(home, "global: [unclosed\n") }

    assert_empty setting_rows(home)
  end

  def test_a_missing_file_imports_nothing
    home = Dir.mktmpdir
    Plastic::Config::Import.new(File.join(home, "config.yml"), into: local(home)).call

    assert_empty setting_rows(home)
  end
end
