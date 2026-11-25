# frozen_string_literal: true

require_relative "../errors"

module Plastic
  module Console
    # IRB in Plastic's own process over the console databases. It reads no rc
    # file, no history file and starts no pager, so a session writes nothing.
    # IRB is the one of the Ruby installation, loaded through RubyGems here,
    # when a session opens, so --eval and every other command load neither.
    class IrbSession
      # Reads lines from the call's input and prints each prompt to its output.
      class LineInput
        attr_accessor :prompt

        def initialize(input, out)
          @input = input
          @out = out
          @prompt = ""
        end

        def gets
          @out.print(prompt)
          @input.gets
        end

        def eof? = @input.eof?

        def readable_after_eof? = false

        def support_history_saving? = false

        def prompting? = false

        def winsize = [24, 80]

        def encoding = Encoding::UTF_8

        def inspect = "Plastic console input"
      end

      MISSING = "plastic console needs irb, which this Ruby installation does not have; add it with `gem install irb`"

      def initialize(databases, environment)
        @databases = databases
        @environment = environment
      end

      def start
        load_irb
        IRB.setup(nil, argv: ["-f"])
        IRB.conf[:SAVE_HISTORY] = nil
        IRB.conf[:USE_PAGER] = false
        printing_to(@environment.out) { IRB::Irb.new(IRB::WorkSpace.new(@databases), LineInput.new(@environment.input, @environment.out)).run(IRB.conf) }
      end

      private

      def load_irb
        require "rubygems"
        require "irb"
      rescue LoadError
        raise Failed, MISSING
      end

      def printing_to(stream)
        saved = $stdout
        $stdout = stream
        yield
      ensure
        $stdout = saved
      end
    end
  end
end
