# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # What `plastic help --json` prints for one tool. The summary lives in
      # TABLE only, so `plastic help` lists tools without loading any of them.
      Description = Data.define(:name, :summary, :usage, :subject, :arguments, :options, :reads, :writes)
    end
  end
end
