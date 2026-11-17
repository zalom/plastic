# frozen_string_literal: true

# Builds the reference pages of every command from the kernel's own code.
module CommandReference
  KERNEL_LIB = File.expand_path("../lib", __dir__)
  $LOAD_PATH.unshift(KERNEL_LIB).uniq!

  require "plastic/cli"
  require "plastic/graph"
  require "plastic/hook"
  require "plastic/routine"

  %w[snippet source row outcome flow edge own_call call_closure ending reach page locator workflow_reading step_readings gate_reading read_reading step_reading agent_reading outcome_reading flow_reader own_call_reading hook_files file_endings endings changes reasons event_list command_reading model
    figures/style figures/point figures/anchored figures/box figures/label figures/circle figures/head figures/path figures/frame figures/canvas words page_words places figures/box_rule figures/event_row figures/glyphs figures/event_key figures/events figures/plate figures/sides figures/overview
    markdown/links markdown/page markdown/index
    page_files build disk cli].each do |name|
    require_relative "command_reference/#{name}"
  end
end
