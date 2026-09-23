# frozen_string_literal: true

require "minitest/autorun"
require "varar/minitest"

# Turn every Markdown oath matched by varar.config.json into Minitest tests —
# varar.config.json lives at the project root (the parent of test/).
Varar::Minitest.generate_tests(Object, root: File.expand_path("..", __dir__))

class VararCoverageTest < Minitest::Test
  def test_project_new_keeps_every_slug_row
    assert_equal 4, Var_varar_project_new_md.runnable_methods.grep(/\Atest_the_slug_/).length
  end

  def test_intent_end_keeps_every_record_and_mode
    assert_equal 6, Var_varar_intent_end_md.runnable_methods.grep(/\Atest_the_record_/).length
  end

  def test_project_links_keeps_both_harnesses_and_both_modes
    assert_equal 4, Var_varar_project_links_md.runnable_methods.grep(/\Atest_the_harness_/).length
  end

  def test_update_safety_keeps_both_harnesses_and_both_commands
    assert_equal 4, Var_varar_update_safety_md.runnable_methods.grep(/\Atest_the_harness_/).length
  end

  def test_store_layout_keeps_both_harnesses_and_both_starting_layouts
    assert_equal 4, Var_varar_store_layout_md.runnable_methods.grep(/\Atest_the_harness_/).length
  end
end
