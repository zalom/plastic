# frozen_string_literal: true

KERNEL_LIB = File.expand_path("../scripts/lib", __dir__)
$LOAD_PATH.unshift(KERNEL_LIB) unless $LOAD_PATH.include?(KERNEL_LIB)

require "plastic"
require "plastic/graph"
require "plastic/hook"
require "plastic/routine"

# Builds the reference pages of every command from the kernel's own code.
module CommandReference
  %w[source schema page locator touches touches/target touches/facade touches/scan prints flow_reader endings model
    figures/style figures/canvas words figures/call figures/chain figures/step_box figures/workflow figures/outcomes figures/component
    markdown/links markdown/workflow_sections markdown/page markdown/index
    dsl/code_rows dsl/layout dsl/code_panel dsl/notes dsl/drawings dsl/sections dsl/endings_sections dsl_page dsl_markdown build disk cli].each do |name|
    require_relative "command_reference/#{name}"
  end
end
