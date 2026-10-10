# frozen_string_literal: true

module CommandReference
  # Everything one command page says, read from the kernel.
  Page = Data.define(:words, :klass, :kind, :file, :line, :summary, :comment, :usage, :arguments, :options, :own_call,
    :entry, :flows, :edges, :touches, :endings) do
    def slug = words.tr(" ", "-")

    def graph_lines = [*klass.writes.map { |graph| "writes #{graph}" }, *klass.reads.map { |graph| "reads #{graph}" }]

    def flow(key) = flows.find { |flow| flow.key == key }
  end
end
