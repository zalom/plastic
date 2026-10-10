# frozen_string_literal: true

module CommandReference
  Row = Data.define(:kind, :name, :check, :stops, :say, :file, :line)
  Outcome = Data.define(:name, :check, :fallback, :offers, :because, :to, :exit_code, :file, :line)
  Flow = Data.define(:key, :klass, :lane, :file, :line, :comment, :facts, :rows, :outcomes)
  Edge = Data.define(:from, :to, :outcomes)
  OwnCall = Data.define(:file, :line, :code)
  Ending = Data.define(:kind, :exit_code, :next_text, :text, :file, :line)

  # Everything one command page says, read from the kernel.
  Page = Data.define(:words, :klass, :kind, :file, :line, :summary, :comment, :usage, :arguments, :options, :own_call,
    :entry, :flows, :edges, :touches, :endings) do
    def slug = words.tr(" ", "-")

    def flow(key) = flows.find { |flow| flow.key == key }
  end
end
