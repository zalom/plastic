# frozen_string_literal: true

require_relative "../config"
require_relative "../../routine"
require_relative "../config_scope"

module Plastic
  module Commands
    class Config
      # Lists every setting with its value: the global settings, or those of
      # one harness with --harness. It writes nothing.
      class List < Routine
        include ConfigScope

        workflow :code_list_config, next: :noop
      end
    end
  end
end
