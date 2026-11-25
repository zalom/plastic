# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # One node an old intent gives: its title, its state, the brief that is its packet, the findings it keeps and,
          # for an abandoned step, the reason.
          NodeDraft = Data.define(:title, :state, :packet, :findings, :reason)
        end
      end
    end
  end
end
