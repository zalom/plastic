# Ask a question

`plastic search --ask "QUESTION"` takes a whole question instead of search terms. A plain
search needs every term in one file, so a full sentence usually finds nothing. With `--ask`,
Plastic drops the common words, searches for each remaining word, and ranks each file by the
number of words it holds. The following run shows the first two rows for one question, with the
excerpts cut short:

```text
$ plastic search --ask "Why was the install script limited to stable releases?" --limit 2
stores/plastic/store/144--installer-default-channel-stable/plan.md     ... Installer first-[install] default channel (stable) ...
stores/plastic/store/144--installer-default-channel-stable/outcome.md  ... Installer first-[install] default channel (stable) ...
```

The command takes `--project SLUG`, `--limit N` and `--json`, as a plain search does. No
model runs and nothing leaves the machine.

## What the ranking can and cannot do

The ranking counts matched words. It does not read the question, so the first rows hold the
most words of the question, and they may not hold the answer. A question with common words
only prints `no match`.

## The library behind it

The code is three small classes under `scripts/lib/rlm/`. RLM stands for Recursive Language
Models, a method where a program queries a corpus and no model loads the corpus. The
following table shows each class and its job:

| Class | Job |
| ----- | --- |
| `RLM::Corpus` | Holds one search function that the host gives it. |
| `RLM::Probe` | Splits the question into words, searches for each one, and ranks the rows. |
| `RLM::Query` | Runs the probe. When a judge is given and more rows come back than its limit, it hands the rows to the judge. |

The judge is the seam for a model. It is any object that answers `call(question, rows)`.
Nothing fills it today, so `--ask` always prints the probe's rows. The library names nothing
of Plastic, because it moves into a gem of its own later.
