# plastic config

`plastic config` asks which on/off settings are on, on the choice screen. With no terminal it
prints the settings as a numbered list and a next line that takes the answer, and
`plastic config ANSWER` saves the settings the answer turns on or off. The rows below run the
storage kernel's command line in a fresh home each time, as session s-1.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| none | `config` | 0 | question: Which settings are on? / choices: 1 [x] statusline / answer: answer with numbers separated by commas (1,2), a for all, or q to leave with no change | plastic config <answer> |
| none | `config 1` | 0 | screens false / advisor.enabled false | plastic config list |
| none | `config --harness codex` | 0 | question: Which settings are on? / choices: 1 [x] statusline / answer: answer with numbers separated by commas (1,2), a for all, or q to leave with no change | plastic config --harness codex <answer> |
