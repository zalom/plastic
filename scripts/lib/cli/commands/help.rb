# encoding: UTF-8
# frozen_string_literal: true

require_relative "../command"
require_relative "../table"

# `plastic help` - the command list, straight out of the table, or one command's
# usage line. The list loads no command file: that is what the table's summary
# column is for.
module Plastic
  class CLI
    module Commands
      class Help < Command
        USAGE_LINE = "plastic help [COMMAND] [--json]"

        private

        def call
          return one_command(@argv.join(" ")) unless @argv.empty?

          @output.row("usage", "plastic <command> [options]")
          TABLE.sort.each { |name, (_file, _const, summary)| @output.row(name, summary) }
          @output.next_step("plastic status", because: "it needs no argument and names the rest")
        end

        def one_command(name)
          file, const, summary = TABLE.fetch(name) { raise Usage, "no command named #{name.inspect}" }
          require_relative "../#{file}"
          @output.row("usage", Commands.const_get(const)::USAGE_LINE)
          @output.row("summary", summary)
          @output.next_step("plastic #{name} --json", because: "the same answer with stable keys")
        end
      end
    end
  end
end
