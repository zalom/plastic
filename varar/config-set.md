# plastic config set

`plastic config set KEY VALUE` writes one setting to `config.yml` in the Plastic home, in the
global section or, with `--harness NAME`, in that harness's section. The file keeps only what
was set. A key that no default names, a harness the registry lacks, and an on/off setting given
a value other than true or false are refused, and nothing is written. The rows below run the
storage kernel's command line in a fresh home each time, as session s-1.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| none | `config set screens false` | 0 | screens false | plastic config get screens |
| none | `config set agents.models.plastic-executor opus --harness codex` | 0 | agents.models.plastic-executor opus | plastic config get agents.models.plastic-executor --harness codex |
| none | `config set agents.models.plastic-executor opus` | 2 | no setting agents.models.plastic-executor; plastic config list names them | none |
| none | `config set screens maybe` | 2 | screens takes true or false | none |
| none | `config set screens false --harness gemini` | 2 | no harness gemini; the registered harnesses are claude-code, codex, hermes | none |
