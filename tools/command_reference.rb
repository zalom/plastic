# frozen_string_literal: true

KERNEL_LIB = File.expand_path("../scripts/lib", __dir__)
$LOAD_PATH.unshift(KERNEL_LIB).uniq!

require "plastic"
require "plastic/graph"
require "plastic/hook"
require "plastic/routine"

# Builds the reference pages of every command from the kernel's own code.
module CommandReference
  %w[snippet source schema page locator touches touches/target touches/delegations touches/facade touches/scan prints workflow_reading step_readings flow_reader own_call_reading hook_files file_endings endings command_reading model
    figures/style figures/geometry figures/canvas words figures/call figures/chain_layout figures/chain figures/step_box figures/workflow figures/outcome_words figures/outcomes figures/database_box figures/component
    markdown/links markdown/prose markdown/rows markdown/workflow_sections markdown/page markdown/index
    dsl/code_rows dsl/layout dsl/code_panel dsl/notes dsl/code_drawing dsl/end_values dsl/sections dsl/endings_sections dsl_page dsl_markdown page_files build disk cli].each do |name|
    require_relative "command_reference/#{name}"
  end
end
