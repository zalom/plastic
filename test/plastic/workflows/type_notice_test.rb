# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/workflows/type_notice"

class TypeNoticeTest < Minitest::Test
  # A settings file the person edited by hand: it reads, and it refuses a write.
  class HandEditedConfig
    def list(_key) = %w[md html]

    def set(key, _value) = raise(Plastic::Config::HandEdited.new("#{key} was edited by hand", "config.yml"))
  end

  def test_a_hand_edited_config_still_tells_the_type_and_records_nothing
    lines = Plastic::Workflows::TypeNotice.new(HandEditedConfig.new).lines(%w[pdf])

    assert_equal ["files of type .pdf are not synced; run plastic config set sync.types md,html,pdf to include them"], lines
  end
end
