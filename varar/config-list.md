# plastic config list

`plastic config list` prints every setting with its value, one row each: the global settings
alone, or with `--harness NAME` the settings that harness reads, its own models among them. The
rows below run the storage kernel's command line in a fresh home each time, as session s-1.

Each row gives the setup, the call, the exit code, the first line, the open lines and the next line:

| setup | call | exit | first line | open lines | next line |
| ----- | ---- | ---- | ---------- | ---------- | --------- |
| none | `config list` | 0 | statusline true | none | plastic config set KEY VALUE |
| none | `config list --harness codex` | 0 | statusline true | none | plastic config set KEY VALUE --harness codex |
| none | `config list --harness gemini` | 2 | no harness gemini; the registered harnesses are claude-code, codex | none | none |
