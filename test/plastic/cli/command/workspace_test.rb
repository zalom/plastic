# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandWorkspaceTest < Plastic::TestCase
  Environment = Data.define(:session)

  def test_the_scope_is_made_once_by_the_source
    made = []
    workspace = Plastic::CLI::Command::Workspace.new(Environment.new(nil), -> { made << :scope && :the_scope })

    assert_equal [:the_scope, :the_scope], [workspace.scope, workspace.scope]
    assert_equal [:scope], made
  end

  def test_a_call_that_never_reached_the_store_renews_nothing
    source = -> { flunk "the scope was made" }

    assert_nil Plastic::CLI::Command::Workspace.new(Environment.new("s-1"), source).renew_claims
  end

  def test_a_call_without_a_session_renews_nothing
    workspace = Plastic::CLI::Command::Workspace.new(Environment.new(nil), -> { :scope })
    workspace.scope

    assert_nil workspace.renew_claims
  end
end
