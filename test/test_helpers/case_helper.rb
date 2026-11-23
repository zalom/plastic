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
      LEGACY_ROADMAP = <<~MARKDOWN
        # Roadmap: Make It Useful

        ## Goal
        The shop registers every button in the backend.

        ## Waves

        ### Wave 1 — Ship-stopping blockers
        - [ ] 2 Lock down guest order access — queued
        - [ ] 3 Un-nest the wishlist button — queued

        ### Wave 2 — Core commerce
        - [ ] 4 Fix the first-add cart quantity — queued

        ## Graph
        - 2 needs nothing
        - 3 needs nothing
        - 4 needs 2 3
      MARKDOWN
      BATCH_GOAL = 'roadmap batch make-it-useful 1 --goal "Close the two blockers" ' \
                   '--done "a guest sees only their own order" --done "add to cart works on every page"'
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

      # A legacy store with one roadmap file, read into rows, whose first batch has a goal and two done criteria.
      def legacy_roadmap
        FileUtils.cp_r(File.join(LEGACY_STORE, "."), store_root)
        write("roadmaps/make-it-useful.md", LEGACY_ROADMAP)
        sync_up
        ran(BATCH_GOAL)
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

      # The roadmap shop, whose first batch is Blockers.
      def shop_batch
        ran("roadmap new shop", 'roadmap batch shop 1 --title Blockers --goal "guest checkout is safe"')
      end

      # The shop batch with its first item, guest.
      def shop_guest
        shop_batch
        ran('roadmap add shop 1 guest --title "Lock down guest orders"')
      end
    end
  end
end
