# frozen_string_literal: true

require_relative "../command"
require_relative "../table"

# `plastic help` - the command list plus the help topics, straight out of the
# table and docs/help, or one command's usage line, or one topic's chapter. A
# command name always wins over a topic of the same name. The list loads no
# command file: that is what the table's summary column is for.
module Plastic
  class CLI
    module Commands
      class Help < Command
        USAGE_LINE = "plastic help [COMMAND|TOPIC] [--json]"

        def call
          name = arguments.join(" ")
          return list if name.empty?
          return one_command(name) if TABLE.key?(name)
          return one_topic(name) if topic?(name)

          raise Usage, "no command or help topic named #{name.inspect}"
        end

        private

        def list
          @output.row("usage", "plastic <command> [options]")
          TABLE.sort.each { |name, (_file, _const, summary)| @output.row(name, summary) }
          @output.row("topics", topic_names)
          @output.next_step("plastic status", because: "it needs no argument and names the rest")
        end

        def one_command(name)
          file, const, summary = TABLE.fetch(name)
          require_relative "../#{file}"
          @output.row("usage", Commands.const_get(const)::USAGE_LINE)
          @output.row("summary", summary)
          @output.next_step("none", because: "the usage line is the whole answer")
        end

        def one_topic(name)
          @output.row(name, File.read(topic_path(name)))
          @output.next_step("none", because: "the chapter is the whole answer")
        end

        def topic?(name)
          name == File.basename(name) && File.file?(topic_path(name))
        end

        def topic_names
          Dir.glob(File.join(help_dir, "*.md")).map { |path| File.basename(path, ".md") }.sort
        end

        def topic_path(name)
          File.join(help_dir, "#{name}.md")
        end

        def help_dir
          File.join(package_root, "docs", "help")
        end

        def package_root
          @env["PLASTIC_PACKAGE_ROOT"] || File.expand_path("../../../..", __dir__)
        end
      end
    end
  end
end
