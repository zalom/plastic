## Numbered Decision Tables

The shared procedure for collecting owner rulings during any stage (Why, How, Exec).
Any stage skill that needs the owner to choose between options or rule on a batch of
open questions follows this procedure instead of improvising its own format.

Read this when a stage skill's own text says to.

### The procedure

1. **Collect the candidate decisions.** Gather every open question or option set that
   needs an owner ruling right now. Do not present them one at a time across separate
   messages; batch them into a single collection first.

2. **Present exactly ONE table.** Its first column is the row number. One decision per
   row. Add a recommendation column stating the agent's recommended choice and a short
   reason. Example shape:

   | # | Decision | Recommendation |
   |---|---|---|
   | 1 | Ship the setting as a CLI flag or a config file? | Config file: survives across invocations |
   | 2 | Retry, circuit breaker, or fallback for the flaky call? | Retry: matches existing error handling elsewhere in this module |

3. **Let the owner rule by row number.** The owner responds with a ruling per row
   number (e.g. "1: config file, 2: retry"). Do not require prose paragraphs back; a
   row-number ruling is enough.

4. **Persist each ruling immediately, one at a time.** For every ruling, before moving
   to the next row, run:

   ```
   ruby ~/.plastic/scripts/insight-append {intent_dir} "<ruling text>" --stage <stage> --author human
   ```

   Never batch rulings into a single call and never wait until all rows are ruled to
   start persisting. `<stage>` is the current stage (Why, How, or Exec). If a ruling
   supersedes an earlier one already on record, append a second insight that names the
   superseded decision and states plainly that this ruling supersedes it. Both insights
   stay on record; the later one wins.

5. **Write the full ruling set to a rulings file.** After the last row is ruled and
   persisted, write the complete table plus every ruling to
   `{intent_dir}/resources/rulings--<slug>.md` so the full set is readable in one place
   alongside the per-row insights.

### Why one table, not a chip per row

A single table lets the owner rule on everything in one pass and reference row numbers
in their reply. Multiple small prompts force the owner to context-switch per decision
and make later replies ambiguous about which decision they answer.
