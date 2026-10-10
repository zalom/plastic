# frozen_string_literal: true

module CommandReference
  # One way a command call ends.
  Ending = Data.define(:kind, :exit_code, :next_text, :text, :file, :line)
end
