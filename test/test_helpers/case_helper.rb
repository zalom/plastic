# frozen_string_literal: true

require "shellwords"

module Plastic
  class TestCase
    # The setup of a command case: command lines run in order, as session s-1,
    # each one required to succeed, then the call under test.
    module CaseHelper
      SESSION = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze
      ONE_CRITERION = "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n"
      TWO_CRITERIA = "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n- [suite-green] suite green\n"
      UNKEYED_CRITERION = "# Spec\n\n## Done criteria\n\n- the CLI ships\n"

      LEGACY_STORE = File.expand_path("../fixtures/legacy_store", __dir__)
      TWO_KEYED_CRITERIA = "# Spec\n\n## Done criteria\n\n- [ ] [it-is-done] it is done\n- [ ] [it-builds] it builds\n"

      # One command line, called in the test's own process.
      def line(text, input: "") = plastic(*text.shellsplit, env: SESSION, input:, table: Plastic::CLI::TABLE)

      # The command lines, in order; each must exit 0.
      def ran(*lines)
        lines.each { |text| assert_ran(text) }
      end

      def assert_ran(text)
        result = line(text)

        assert_equal 0, result.code, "#{text}: #{result.err}"
      end

      # The exit code, the lines printed and the error of a call, with the spaces that align columns squeezed to one.
      def assert_case(result, code:, out: [], err: "")
        assert_call result.with(out: result.out.squeeze(" "), err: result.err.squeeze(" ")), code:, out:, err:
      end

      # Intent 1, Alpha, whose spec.md holds the text and is read into rows.
      def alpha_specified(text = ONE_CRITERION)
        ran("intent new Alpha")
        write("store/1--alpha/spec.md", text)
        sync_up
      end

      # Intent 1 in progress with a spec, the owner's go-ahead and one node, Build, on the criterion tests-pass.
      def alpha_with_node(approved: true)
        alpha_specified
        ran("intent approve 1") if approved
        ran("intent start 1", "node add 1 Build --criterion tests-pass")
      end

      # Intent 1 after a full pass of the work graph: two rulings, the second superseding the first,
      # two nodes with an edge, and the first node failed, released, claimed again and done.
      def work_graph_pass
        ran("intent new Alpha", 'intent rule 1 "Flowbite styles every delivery"', 'intent rule 1 "Direct mode only" --supersedes D1')
        write("store/1--alpha/spec.md", TWO_KEYED_CRITERIA)
        sync_up
        ran("intent approve 1", "intent start 1", 'node add 1 "do the thing" --criterion it-is-done', 'node add 1 "build it" --criterion it-builds',
          "edge add 1 n1 n2", "node claim 1 n1 --agent tester", "node fail 1 n1 broke", "node release 1 n1", "node claim 1 n1 --agent tester", 'node done 1 n1 "it passed"')
      end
    end
  end
end
