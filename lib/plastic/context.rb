# frozen_string_literal: true

require "forwardable"
require_relative "facts"

module Plastic
  # What every step of one call sees. A context holds three things:
  #
  #   facts          named values; only declared names exist
  #   collaborators  the graphs, the session, the store scope and the environment
  #   printed        the lines and rows the call prints before next:
  #
  # A fact is declared by the tool (argument, option) or by a workflow in the
  # chain (`sets :name`). There is one read form, `c.name`, and one write
  # form, `c[:name] = value`. An undeclared name raises at once, so a typo
  # never reads as nil.
  class Context
    extend Forwardable

    # The session and store scope that made the call.
    Harness = Struct.new(:session, :scope)
    # One printed line.
    Line = Struct.new(:text) do
      def print_to(output) = output.raw(text)
    end

    # A labelled value among the printed lines.
    Row = Struct.new(:label, :value) do
      def print_to(output) = output.row(label, value)
    end

    def_delegators :@harness, :session, :scope

    # `harness` holds the session that made the call, or nil when the harness
    # sets none, and the store scope. The write lock is held by a session.
    def initialize(declared:, facts:, graphs:, harness: Harness.new)
      @facts = Facts.new(declared, facts)
      @graphs = graphs.to_h
      @harness = harness
      @printed = []
      expose_facts
    end

    def work = @graphs[:work]

    def retrieval = @graphs[:retrieval]

    def database(name) = @graphs.fetch(:databases).fetch(name)

    def []=(name, value)
      @facts[name] = value
    end

    # Facts are saved with the routine run, so a resumed call sees what the first
    # call found. Only declared names are ever saved.
    def facts = @facts.to_h

    def printed = @printed.grep(Line).map(&:text)

    def print(line) = tap { @printed << Line.new(line) }

    # A labelled value the call reports as a row, such as the passages a search found.
    def row(label, value) = tap { @printed << Row.new(label, value) }

    def print_to(output) = @printed.each { |entry| entry.print_to(output) }

    def fill(template) = @facts.fill(template)

    private

    # Each declared fact reads as a method, so a step writes `c.id`, and a
    # fact can never shadow a Context method.
    def expose_facts
      names = @facts.declared.to_a
      refuse_clashes(names)
      names.each { |name| define_singleton_method(name) { @facts[name] } }
    end

    def refuse_clashes(names)
      clash = names & public_methods
      raise Invalid, "fact names #{clash.join(", ")} are Context methods" if clash.any?
    end
  end
end
