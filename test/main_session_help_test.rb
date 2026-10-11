# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/plastic/graph/work/main_session"

# The agent-architecture help topic and the brief name the same main session
# steps with the same commands.
class MainSessionHelpTest < Minitest::Test
  TOPIC = File.expand_path("../docs/help/agent-architecture.md", __dir__)

  def section
    File.read(TOPIC)[/^## The Main Session\n(.*?)(?=^## )/m, 1].to_s.gsub(/\s+/, " ")
  end

  def test_the_topic_has_a_main_session_section
    refute_empty section
  end

  def test_the_help_topic_names_every_step
    Plastic::Graph::Work::MainSession::STEPS.each { |step, _| assert_includes section, step }
  end

  def test_the_help_topic_names_every_main_session_command
    Plastic::Graph::Work::MainSession::STEPS.each { |_, command| assert_includes section, "`#{command}`" }
  end
end
