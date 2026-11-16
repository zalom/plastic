# frozen_string_literal: true

module Plastic
  module Graph
    # A database whose layout is older than this code. Nothing on open changes it: the install and the update run the migrations.
    class Behind < StandardError
      def next_command = "plastic update"
    end

    # A database whose layout is newer than this code.
    class Ahead < Behind; end
  end
end
