# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandWorkspaceTest < Plastic::TestCase
  Environment = Data.define(:session, :clock)

  def test_the_scope_is_made_once_by_the_source
    made = []
    workspace = Plastic::CLI::Command::Workspace.new(Environment.new(nil, nil), -> { made << :scope && :the_scope })

    assert_equal [:the_scope, :the_scope], [workspace.scope, workspace.scope]
    assert_equal [:scope], made
  end

  def test_a_call_that_never_reached_the_store_renews_nothing
    source = -> { flunk "the scope was made" }

    assert_nil Plastic::CLI::Command::Workspace.new(Environment.new("s-1", nil), source).renew_claims
  end

  def test_a_call_without_a_session_renews_nothing
    workspace = Plastic::CLI::Command::Workspace.new(Environment.new(nil, nil), -> { :scope })
    workspace.scope

    assert_nil workspace.renew_claims
  end

  def test_the_settings_are_bound_to_the_home_and_the_clock_of_the_call
    scope = Struct.new(:plastic_home).new("/plastic-home")
    workspace = Plastic::CLI::Command::Workspace.new(Environment.new(nil, :the_clock), -> { scope })

    assert_equal [Plastic::Wiring::Settings.new(home: "/plastic-home", clock: :the_clock)] * 2, [workspace.settings, workspace.settings]
  end
end
