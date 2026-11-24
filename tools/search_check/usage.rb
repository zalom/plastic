# frozen_string_literal: true

module SearchCheck
  # A call that cannot run: the file or the store is missing, or an option is wrong.
  class Usage < StandardError; end
end
