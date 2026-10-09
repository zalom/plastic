# plastic intent verdict

`plastic intent verdict ID accept|revise TEXT` writes the verdict row of the next review round, the text being the findings. A revise offers `plastic node add` for the fix node. An accept offers `plastic intent end`. A review has two rounds: a second revise is written and then refused as the owner's step, and a call after two verdicts is refused. A verdict other than accept or revise, or blank text, is a usage error. A missing, done or abandoned intent fails. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| intent new Alpha | intent verdict 1 accept "Every criterion holds" | 0 | verdict: accept round 1 | plastic intent end 1 --project global |
| intent new Alpha | intent verdict 1 revise "One edge fails" | 0 | verdict: revise round 1 | plastic node add 1 TITLE --criterion KEY --project global |
| intent new Alpha ; intent verdict 1 revise "One" | intent verdict 1 revise "Two" | 3 | verdict: revise round 2 / the judge's review round of intent 1 is used; the owner decides between abandoning the intent and a follow-up intent | none |
| intent new Alpha | intent verdict 1 maybe "x" | 2 | the verdict takes accept or revise | none |
| none | intent verdict 9 accept "x" | 1 | no intent 9 in this store | none |
