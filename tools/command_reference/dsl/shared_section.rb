# frozen_string_literal: true

module CommandReference
  module Dsl
    # What every call shares, so a command page does not repeat it.
    class SharedSection < Section
      def lines
        ["---", "", "## What every call shares", "",
          "A command page names only what its own call does. These three things hold for every call, and no page repeats them.", "",
          "| What | When it happens | Defined in |", "| --- | --- | --- |", *rows, ""]
      end

      private

      def rows
        [
          "| Verify the wiring | Once per process, on the first call of the command. A fault in the wiring stops the call before any step runs. | #{link(:routine, /def verify\b/)} |",
          "| Usage error | A missing or wrong argument prints the usage line and exits 2, before any workflow runs. | #{link(:command, /USAGE = 2/)} |",
          "| The write lock | Each write to a database runs in one immediate transaction, so two calls never write one database at once. A second writer waits for the busy timeout. | #{link(:pool, /def atomically\b/)} |"
        ]
      end
    end
  end
end
