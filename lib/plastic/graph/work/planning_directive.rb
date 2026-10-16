# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      module PlanningDirective
        TEXT = "Every plan and every planned code change follows the Principle of Least Surprise: a name does what " \
          "it says, a word means the same thing everywhere, nothing has hidden side effects, and standard conventions " \
          "come first. The work graph handles every ambiguity, newly found issue and blocker. Resolve an ambiguity " \
          "by search or research with at least 3 attempts, then ask with plastic node ask ID NODE TEXT, naming the " \
          "question and what you tried. An impediment such as no access, a missing source or missing resources stops " \
          "the node at once: plastic node impede ID NODE TEXT. plastic node resolve ID NODE TEXT reopens either. " \
          "A newly found issue becomes a new node with plastic node add and plastic edge add. plastic node fail ID " \
          "NODE TEXT is for work that was tried and failed."
      end
    end
  end
end
