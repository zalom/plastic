# frozen_string_literal: true

require_relative "../../../test_helper"

class SyncResolutionTest < Plastic::TestCase
  Resolution = Plastic::Graph::Sync::Resolution
  SPEC = "store/1--a/spec.md"

  def test_an_overwrite_path_names_one_record_relative_to_the_store
    resolution = Resolution.new(:up, "/root", { overwrite: "/root/#{SPEC}" })

    assert_equal [true, false, true, :read], [resolution.overwrites?(SPEC), resolution.overwrites?("x"), resolution.merging?, resolution.side]
    assert_equal [SPEC, nil], [resolution.unknown_path(["x"]), resolution.unknown_path([SPEC])]
  end

  def test_an_overwrite_with_no_path_takes_every_conflict
    resolution = Resolution.new(:down, "/root", { overwrite: nil })

    assert_equal [true, false, :print, false, nil], [resolution.overwrites?("x"), resolution.merging?, resolution.side, resolution.up?, resolution.unknown_path([])]
  end

  def test_a_plain_call_overwrites_nothing
    resolution = Resolution.new(:up, "/root", {})

    assert_equal [false, false, true], [resolution.overwrites?("x"), resolution.merging?, resolution.up?]
  end

  def test_merge_applies_the_one_sided_changes
    assert_predicate Resolution.new(:down, "/root", { merge: true }), :merging?
  end
end
