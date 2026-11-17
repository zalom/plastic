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

  MEDIA_TYPES = %w[png jpg jpeg gif webp svg avif heic bmp ico tif tiff mp4 mov webm m4v avi mkv].freeze

  def synced(home) = JSON.parse(setting_rows(home).to_h { |_scope, key, value| [key, value] }.fetch("sync.types"))

  def test_sync_media_true_becomes_the_media_types
    home = Dir.mktmpdir

    import(home, "global:\n  sync:\n    media: true\n")

    assert_equal %w[md html] + MEDIA_TYPES, synced(home)
  end

  def test_sync_documents_true_becomes_the_document_types
    home = Dir.mktmpdir

    import(home, "global:\n  sync:\n    documents: true\n")

    assert_equal %w[md html] + Plastic::Config::SyncTypes::DOCUMENTS, synced(home)
  end

  def test_both_old_keys_add_both_lists_once
    home = Dir.mktmpdir

    import(home, "global:\n  sync:\n    media: true\n    documents: true\n    types: [md]\n")

    assert_equal %w[md] + MEDIA_TYPES + Plastic::Config::SyncTypes::DOCUMENTS, synced(home)
  end

  def test_old_sync_keys_leave_no_row
    home = Dir.mktmpdir

    import(home, "global:\n  sync:\n    media: true\n    documents: false\n    references: true\n")

    assert_equal %w[sync.references sync.types], setting_rows(home).map { |_scope, key, _value| key }
  end

  def test_old_keys_set_to_false_add_no_type
    home = Dir.mktmpdir

    import(home, "global:\n  sync:\n    media: false\n    documents: false\n")

    assert_empty setting_rows(home)
  end
end
