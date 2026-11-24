# The intent folder

This page is generated from `lib/plastic/layout.yml` by `ruby bin/layout-docs`. Change the layout file, not this page.

A folder is named `{id}--{slug}` and made by `plastic intent new`. The slug takes up to 6 words of the title and never changes. One folder for each intent, in store/. The folder name never changes after the intent is made.

An intent is in one of these states: open, done, abandoned. An intent that is future, open, in progress or parked is open.


## Files

| File | Purpose | Required in | Writer |
| --- | --- | --- | --- |
| `intent.md` | The intent's own file, with its identity and the sections a person fills. | open, done, abandoned | plastic intent new |
| `spec.md` | The goal, the done criteria, the open decisions and the constraints. | open, done | plastic intent spec |
| `outcome.md` | What was delivered, or why the work was dropped, with its delivery line or its abandon reason under Verification, and the notes and reports of the intent. | done, abandoned | plastic intent outcome and plastic intent note |
| `graph.json` | The work graph, with its nodes, edges, runs and verdicts. | open, done, abandoned | rows |
| `work.log` | The work log, one line for each event of the intent. | open, done, abandoned | rows |
| `context.json` | The discovery and the context the intent was grilled with. | never | rows |

Plastic prints a file whose writer is rows from the database rows, and the named commands write each other file. The agent writes no core file by hand.

## Shape of each file

- `intent.md`: front matter `id`, `intent`, `parent`, `ref`, `origin`, `created`; headings Intent, Context, Outcome, Insights.
- `spec.md`: headings Goal / Goals (old), Done criteria / Acceptance Criteria (old) / Acceptance (old), Open decisions / Open Questions (old), Constraints / Constraint (old).
- `outcome.md`: headings Verification, Notes, Reports.

## Resources

Everything else the work makes or reads. The agent writes here and no core file.

| Folder | Purpose | Sync |
| --- | --- | --- |
| `resources/output/reports/` | A report that `plastic intent report` recorded, or one that the setting reports.mandatory names. | recorded |
| `resources/output/files/` | The files the work delivers. | by type |
| `resources/references/` | Copies of outside material the work reads. | setting |
| `resources/tmp/` | Tool output, packets, plans, notes, link lists and parts of a research job. | never |

## Files of an older layout

`plastic store sync up` reads or skips each of these by the sync column, and any file that is neither here nor above is named as a stray. The repair column says what a repair of an older folder does.

| Name | Sync | Repair | Why |
| --- | --- | --- | --- |
| `{id}--{slug}.md` | document | rename to `intent.md` | Older folders named the intent file after the folder. |
| `revisions.md` | report | amend | Each entry becomes an amended line of work.log with its original date, and the file goes. |
| `graph.md` | report | remove | graph.json holds the steps of the intent, and the removal is recorded as an amendment. |
| `plan.md` | legacy rows | move to `resources/references/` | The plan of an older release; graph.json holds the plan now. |
| `checklist.md` | legacy rows | move to `resources/references/` | The checklist of an older release; the nodes of graph.json hold it now. |
| `actions/` | legacy rows | move to `resources/references/actions/` | The action files of an older release. The folder moves as one change, and an empty .gitkeep in it is removed. |
| `savepoint.md` | lines | remove | work.log holds its lines, and a sync down removes the file when it still holds the printed bytes. |
| `handoff.md` | report | move to `resources/tmp/` | A note between two sessions, never a record. |
| `*.lock` | skip | remove | Machine state of an older release's locks; claims are rows now. |
| `nodes/` | report | move to `resources/tmp/nodes/` | Node files of an older release. |
| `packets/` | report | move to `resources/tmp/packets/` | Packets are tool output. |
| `reviews/` | report | move to `resources/tmp/reviews/` | Reviews are tool output. |
| `references/` | report | move to `resources/references/` | Outside material belongs under resources/. |
| `resources/sources/` | report | move to `resources/references/sources/` | Sources are references. |


## The store folder

What a store folder, stores/SLUG/, may hold beside its intent folders.

| Name | Status | Purpose or repair |
| --- | --- | --- |
| `store/` | allowed | The intent folders, store/index.json, and an empty .gitkeep in a store with no intent. |
| `backups/` | allowed | Copies of the work and knowledge databases, one folder for each backup. |
| `*.db` | allowed | The work, knowledge, retrieval and legacy databases, with their journal files. |
| `.gitignore` | allowed | Lists the databases and the backups, so they are never versioned. |
| `.enola/` | allowed | The snapshot folder of Enola, which a person or an agent runs beside Plastic. |
| `INDEX.md` | import | The index of a store written before store/index.json; the first sync up imports it. |
| `originals/` | keep | Files a legacy import copied before it removed them; the databases hold them now. |
| `roadmaps/` | remove | Roadmaps became needs links between intents. |
| `project.yml` | keep | The release settings of a project, which an older release wrote; nothing reads this file now. |
| `AGENTS.md` | keep | A copy of the AGENTS.md of the project, which an older release kept in the store; the repository holds the file, and nothing reads this copy. |

What the folder store/ of a store folder may hold beside its intent folders. `plastic intent repair --all` removes each leftover.

| Name | Status | Purpose or repair |
| --- | --- | --- |
| `store/{id}--{slug}/` | allowed | One folder for each intent. |
| `store/index.json` | allowed | The index of the store, printed from the rows. |
| `store/.gitkeep` | allowed | An empty file that keeps the folder of a store with no intent. |
| `store/.obsidian/` | allowed | The settings of a note tool, such as Obsidian, that a person opens the store with. |
| `store/.sessions/` | remove | The day ledger of an older release; session rows hold it. |
| `store/.tmp/` | remove | Heartbeat files of an older release. |
| `store/work_graph.db` | remove empty | An empty database made by mistake; the databases of a store sit beside store/. One that holds data is named and left. |
| `store/.enola/` | remove | Enola's snapshot folder sits beside store/, at the store root. |

## Amendments

`plastic intent repair` changes the structure of a done or abandoned intent, and inside its files only a relative link that points at a file it moved. Its renames, moves and removals share one `amended` line for each intent folder, each kind with its reason. Each link it rewrites, in a done intent as in an open one, is an amendment of its own, whose row keeps the exact old and new link.

| Change | Reason |
| --- | --- |
| rename | the layout names the intent's own file intent.md |
| move | the layout names the folder this file belongs in |
| remove | a newer record holds what this file held |
| revision | an entry of the old revisions.md, with its own date |
| link | the repair moved the file this link names |
| report | plastic intent unreport took out a report recorded by mistake |
