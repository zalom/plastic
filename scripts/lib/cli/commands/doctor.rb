# frozen_string_literal: true

require_relative "installer_verb"

# `plastic doctor` - diagnoses Plastic installation health. The work is still
# scripts/doctor.rb, run through Legacy; each finding prints its own repair.
module Plastic
  class CLI
    module Commands
      class Doctor < InstallerVerb
        USAGE_LINE = "plastic doctor [--core] [--store WHICH]"
        FLAGS = %w[--core --store].freeze

        SCRIPT = "doctor.rb"
        AFTER = "none"
        BECAUSE = "the findings are the whole answer, and each one names its own repair"
      end
    end
  end
end
