# frozen_string_literal: true

# Builds the reference pages of every command from the kernel's own code.
module CommandReference
  KERNEL_LIB = File.expand_path("../scripts/lib", __dir__)
  $LOAD_PATH.unshift(KERNEL_LIB).uniq!

  require "plastic"
  require "plastic/graph"
  require "plastic/hook"
  require "plastic/routine"

  %w[snippet source schema row outcome flow edge own_call call_closure ending reach page locator touches touches/target touches/delegations touches/facade touches/scan prints workflow_reading step_readings gate_reading read_reading step_reading agent_reading outcome_reading flow_reader own_call_reading hook_files file_endings endings command_reading model
    figures/style figures/point figures/anchored figures/box figures/label figures/circle figures/head figures/path figures/frame figures/canvas words figures/call figures/chain_layout figures/chain figures/step_box figures/workflow figures/outcome_words figures/outcomes figures/database_box figures/component
    markdown/links markdown/prose markdown/rows markdown/workflow_sections markdown/page markdown/index
    dsl/code_row dsl/class_rows dsl/statements dsl/layout dsl/wrapper dsl/fitter dsl/splitter dsl/code_panel dsl/notes dsl/code_drawing dsl/declare_command dsl/code_flow dsl/agent_flow dsl/end_values dsl/section dsl/command_section dsl/chain_section dsl/code_section dsl/agent_section dsl/endings_sections dsl_page dsl_markdown page_files build disk cli].each do |name|
    require_relative "command_reference/#{name}"
  end
end
