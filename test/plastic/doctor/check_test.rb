# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/doctor/check"
require_relative "../../../scripts/lib/plastic/workflows/installation_health"

class DoctorCheckTest < Plastic::TestCase
  Part = Plastic::Workflows::InstallationHealth::Check

  def test_a_part_with_a_repair_stays_a_finding
    assert_equal ["ruby:", "3.4.7", "install Ruby 4.0 or later"], Plastic::Doctor::Check.from(Part.new("ruby:", "3.4.7", "install Ruby 4.0 or later")).to_a
  end

  def test_a_part_with_no_repair_reads_ok
    assert_equal ["ruby:", "ok, 4.0.3", nil], Plastic::Doctor::Check.from(Part.new("ruby:", "4.0.3", nil)).to_a
  end

  def test_a_check_judged_with_no_problem_reads_ok_and_drops_its_repair
    assert_equal ["x:", "ok, whole", nil], Plastic::Doctor::Check.new("x:", "whole", "fix").judged(nil).to_a
  end

  def test_a_check_judged_with_a_problem_shows_it_and_keeps_its_repair
    assert_equal ["x:", "broken", "fix"], Plastic::Doctor::Check.new("x:", "whole", "fix").judged("broken").to_a
  end
end
