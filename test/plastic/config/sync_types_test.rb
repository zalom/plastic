# frozen_string_literal: true

require_relative "../../test_helper"

class ConfigSyncTypesTest < Plastic::TestCase
  include ConfigHomes

  SyncTypes = Plastic::Config::SyncTypes

  def test_a_list_value_gives_its_extensions_lowercase_without_a_dot
    assert_equal %w[md pdf], SyncTypes.parse([".MD", "pdf", " "])
  end

  def test_a_comma_value_gives_the_same_list
    assert_equal %w[md pdf], SyncTypes.parse("md, .PDF,")
  end

  def test_no_value_gives_no_type
    assert_empty SyncTypes.parse(nil)
  end

  def test_with_media_adds_each_media_type_once
    assert_equal %w[md html] + SyncTypes::MEDIA, SyncTypes.with_media(%w[md html png])
  end

  def test_without_media_leaves_the_other_types
    assert_equal %w[md pdf], SyncTypes.without_media(%w[md png pdf mp4])
  end

  def test_the_config_gives_the_shipped_types_when_nothing_is_set
    assert_equal %w[md html], Plastic::Wiring.config(@plastic_home).list("sync.types")
  end

  def test_the_config_reads_a_comma_value_set_by_the_person
    Plastic::Wiring.config(@plastic_home).set("sync.types", "md,html,pdf")

    assert_equal %w[md html pdf], Plastic::Wiring.config(@plastic_home).list("sync.types")
  end
end
