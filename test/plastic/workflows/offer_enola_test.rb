# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/offer_enola"

class OfferEnolaTest < Plastic::TestCase
  def offer(reinstall) = run_workflow(Plastic::Workflows::OfferEnola, reinstall:).first

  def test_a_first_install_offers_enola_as_optional
    outcome = offer(false)

    assert_match(/It is optional: Plastic works without it/, sole(outcome.steps))
    assert_equal "plastic version", outcome.next_command
  end

  def test_a_reinstall_offers_nothing
    assert_equal :done, offer(true)
  end
end
