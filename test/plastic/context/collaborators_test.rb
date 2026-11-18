# frozen_string_literal: true

require_relative "../../test_helper"

class ContextCollaboratorsTest < Plastic::TestCase
  def collaborators
    harness = Plastic::Context::Harness.new("abc", :scope)
    Plastic::Context::Collaborators.new({ work: :w, retrieval: :r, databases: { main: :db } }, harness, Time)
  end

  def test_the_graphs_read_by_name
    assert_equal [:w, :r, :db], [collaborators.work, collaborators.retrieval, collaborators.database(:main)]
  end

  def test_the_session_and_scope_come_from_the_harness
    assert_equal ["abc", :scope], [collaborators.session, collaborators.scope]
  end
end
