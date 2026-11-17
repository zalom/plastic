# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # What the node commands that move a claimed node share: the node they
      # work on, the work graph they write and the intent they print. Each
      # subclass adds the text it takes and its workflow, and sits in the
      # command table in place of this class.
      class Move < Routine
        def self.inherited(command)
          super
          command.node_subject
          command.writes :work
          command.prints :intent
        end

        def self.reads_files
          option :files, switch: "--file PATH", text: "a file of the intent folder to read as the result; repeat for more; every changed file when left out", repeatable: true
        end
      end
    end
  end
end
