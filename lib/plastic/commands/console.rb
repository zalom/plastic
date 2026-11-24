# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../console/databases"

module Plastic
  module Commands
    # Opens the databases of one store and the machine-wide plastic.db read-only,
    # in IRB for a person or, with --eval, as one piece of Ruby for an agent.
    # The names are work, knowledge, retrieval and plastic. The console is no
    # sandbox: Ruby can still write files.
    class Console < CLI::Command
      reads :work, :knowledge, :retrieval
      changes({})
      skips_daily_backup
      renews_no_claims

      option :eval, switch: "-e, --eval CODE", text: "run this Ruby once, print its value and exit"
      long_description "Opens work, knowledge, retrieval and plastic read-only: the three files of the store and plastic.db.",
        "The console is no sandbox: Ruby can still write files."

      def call
        raise Usage, "--json needs --eval" if json? && !code
        databases = Plastic::Console::Databases.open(scope)
        code ? evaluate(databases) : irb(databases)
      ensure
        databases&.close
      end

      private

      def code = parsed[:eval]

      def json? = argv.include?("--json")

      def evaluate(databases)
        value = databases.evaluate(code)
        json? ? output.data("value", self.class.json_data(value)) : output.raw(value.inspect)
      rescue StandardError, ScriptError => error
        raise Failed, Failed.describe(error)
      end

      def irb(databases)
        require_relative "../console/irb_session"
        Plastic::Console::IrbSession.new(databases, environment).run
      end

      # A value JSON holds as it is stays as it is; anything else prints as its inspect text.
      def self.json_data(value)
        case value
        when String, Integer, true, false, nil then value
        when Float then value.finite? ? value : value.inspect
        when Array then value.map { |item| json_data(item) }
        when Hash then value.to_h { |key, item| [key.to_s, json_data(item)] }
        else value.inspect
        end
      end
    end
  end
end
