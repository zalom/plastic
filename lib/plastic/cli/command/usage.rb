# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # The call was made wrong: a missing argument or an extra word. Exit 2,
      # with the usage line.
      class Usage < StandardError; end
    end
  end
end
