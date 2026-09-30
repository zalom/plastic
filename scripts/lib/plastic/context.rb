# frozen_string_literal: true

module Plastic
  # What every step of one call sees. A context holds three things:
  #
  #   facts          named values; only declared names exist
  #   collaborators  the graphs and the routine run
  #   printed        the lines the call prints before next:
  #
  # A fact is declared by the tool (argument, option) or by a workflow in the
  # chain (`sets :name`). There is one read form, `c.name`, and one write
  # form, `c[:name] = value`. An undeclared name raises at once, so a typo
  # never reads as nil.
  class Context
    attr_reader :work, :retrieval, :routine_run, :session, :printed

    # `session` names the harness session that made the call, or nil when
    # the harness sets none. The write lock is held by a session.
    def initialize(declared:, facts:, graphs:, routine_run:, session: nil)
      @declared = declared.to_set
      @facts = facts.slice(*@declared)
      @routine_run = routine_run
      @session = session
      @printed = []
      hold(graphs)
      expose_facts
    end

    def []=(name, value)
      raise Invalid, "fact #{name} is not declared" unless @declared.include?(name)

      @facts[name] = value
    end

    # Facts are saved with the routine run, so a resumed call sees what the first
    # call found. Only declared names are ever saved.
    def facts = @facts.dup

    def print(line)
      @printed << line
      self
    end

    # Fills %{name} from the facts. A name with no value raises, so a
    # printed command never carries a hole.
    def fill(template)
      names = template.scan(/%\{(\w+)\}/).flatten.map(&:to_sym)
      missing = names.reject { |name| @facts.key?(name) && !@facts[name].nil? }
      raise Invalid, "no value for #{missing.join(", ")} in #{template.inspect}" if missing.any?

      format(template, **@facts.slice(*names))
    end

    private

    def hold(graphs)
      @work, @retrieval = graphs.to_h.values_at(:work, :retrieval)
    end

    # Each declared fact reads as a method, so a step writes `c.id`, and a
    # fact can never shadow a Context method.
    def expose_facts
      clash = @declared.to_a & public_methods
      raise Invalid, "fact names #{clash.join(", ")} are Context methods" if clash.any?

      @declared.each { |name| define_singleton_method(name) { @facts[name] } }
    end
  end
end
