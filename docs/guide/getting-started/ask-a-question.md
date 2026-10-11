# Prepare context for a question

Plastic retrieves literal evidence. It does not interpret a question or produce an answer.

Choose useful search terms, search the relevant stores, and read the returned qualified documents. If the question supports an intent, save the candidate set with `plastic intent discover ID TERMS...` and submit the agent-selected references through `plastic intent context`.

```text
$ plastic search stable releases --source-project plastic --limit 20
$ plastic document get "plastic://plastic/144/spec.md?revision=SHA256" --json
```

The search ranking is lexical. It returns passages with provenance so a person or agent can evaluate them. Plastic does not call a model or decide whether any passage answers the question.
