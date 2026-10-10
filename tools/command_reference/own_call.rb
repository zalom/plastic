# frozen_string_literal: true

module CommandReference
  # The call method a command writes for itself.
  OwnCall = Data.define(:file, :line, :code) do
    def responds = Ending.new(:respond, 0, Endings::NONE, "answers the event", file, line)
  end
end
