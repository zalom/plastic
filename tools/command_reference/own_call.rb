# frozen_string_literal: true

module CommandReference
  # A method a command writes for itself, with the file, line and code it sits on.
  Place = Data.define(:file, :line, :code)

  # The call method a command writes for itself, the check_call it adds to a
  # shared call, and the lines of its file that the call can run.
  OwnCall = Data.define(:file, :line, :code, :check, :reachable) do
    def responds = Ending.new(:respond, 0, Endings::NONE, "answers the event", file, line)
  end
end
