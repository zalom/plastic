# Command reference

Each page explains one plastic command in six parts: what it does, how to call it, the workflows it runs, the events of one call, what one call changes, and the texts an agent gets. A script writes every page from the command classes, so a page always matches the code it links to.

## Core

| Command | What it does |
| --- | --- |
| [`plastic version`](version/README.md) | Print the installed Plastic version and release channel |
| [`plastic doctor`](doctor/README.md) | Check the installation, the databases, the hooks of this harness and the folder layout of each store, rebuild a search index that is out of step, and name each repair |
| [`plastic init`](init/README.md) | Find the installed harnesses and install Plastic into the ones the person picks |
| [`plastic install`](install/README.md) | Install the core files and make the global store |
| [`plastic update`](update/README.md) | Sync a newer package into the home or name the installer command |
| [`plastic rollback`](rollback/README.md) | Switch the active release back to the previous one or to a named installed one |
| [`plastic uninstall`](uninstall/README.md) | Remove Plastic from agents and keep the home |
| [`plastic status`](status/README.md) | List every store's intents by group, with node counts by state |
| [`plastic next`](next/README.md) | Pick the intent in play and offer its next command |
| [`plastic search`](search/README.md) | Search indexed passages across selected stores for the words of a question, best match first |
| [`plastic console`](console/README.md) | Open IRB over the store databases read-only, or run one piece of Ruby with --eval and print its value |

## intent

| Command | What it does |
| --- | --- |
| [`plastic intent abandon`](intent-abandon/README.md) | Close an intent that will not ship once outcome.md records the revert, or print the revert steps |
| [`plastic intent end`](intent-end/README.md) | Close a delivered intent once its verdict, nodes and outcome allow it, or print what is missing |
| [`plastic intent new`](intent-new/README.md) | Write a future intent: its rows and its folder |
| [`plastic intent start`](intent-start/README.md) | Start an intent for guided work: set it in progress and print its worktree |
| [`plastic intent auto`](intent-auto/README.md) | Start an intent for agent delivery: set it in progress and print its worktree |
| [`plastic intent park`](intent-park/README.md) | Park an intent in progress with the reason it waits; intent start resumes it |
| [`plastic intent rule`](intent-rule/README.md) | Write an owner ruling, with --supersedes to replace an older one |
| [`plastic intent revise`](intent-revise/README.md) | Rewrite an intent's What and Why after grilling, keeping the old text as a revision |
| [`plastic intent note`](intent-note/README.md) | Add one line to the outcome of an intent, a note under Notes or a record of the delivery or the close under Verification, keeping the earlier text as a revision |
| [`plastic intent outcome`](intent-outcome/README.md) | Write the summary of the outcome of an intent from a file, keeping its title and every section |
| [`plastic intent report`](intent-report/README.md) | Record a report of an intent so the sync reads it |
| [`plastic intent unreport`](intent-unreport/README.md) | Remove a report recorded by mistake: its rows, its outcome line and its file, which --to-tmp moves to resources/tmp/ |
| [`plastic intent approve`](intent-approve/README.md) | Write the owner's go-ahead for an intent; no node of it is claimed without it |
| [`plastic intent judge`](intent-judge/README.md) | Print the steps that start the judge of an intent |
| [`plastic intent verdict`](intent-verdict/README.md) | Record the verdict of the next review round of an intent |
| [`plastic intent grant`](intent-grant/README.md) | Grant one extra review round, on the owner's word, to an intent whose rounds are used |
| [`plastic intent spec`](intent-spec/README.md) | Write spec.md from a file with --from, then print the grilling method, how done criteria are written, and the open decisions of spec.md |
| [`plastic intent discover`](intent-discover/README.md) | Record deterministic retrieval candidates for an intent |
| [`plastic intent context`](intent-context/README.md) | Read or submit selected retrieval context for an intent |
| [`plastic intent show`](intent-show/README.md) | Print one intent's status, criteria, decisions, rulings and nodes |
| [`plastic intent brief`](intent-brief/README.md) | Print an intent's goal, criteria, rulings, ready nodes and command usage |
| [`plastic intent link`](intent-link/README.md) | Write a typed link from an intent to a ref |
| [`plastic intent unlink`](intent-unlink/README.md) | Remove a link |
| [`plastic intent archive`](intent-archive/README.md) | Archive an intent directory |
| [`plastic intent repair`](intent-repair/README.md) | Apply the folder layout to one intent folder, or to every one with --all |
| [`plastic intent unarchive`](intent-unarchive/README.md) | Restore an archived intent's directory exactly as it was archived |

## project

| Command | What it does |
| --- | --- |
| [`plastic project list`](project-list/README.md) | List the registered projects with their paths |
| [`plastic project load`](project-load/README.md) | Print a short digest of each named project to warm the context before the next ask |
| [`plastic project new`](project-new/README.md) | Register a project and leave its store ready for intent new |
| [`plastic project links`](project-links/README.md) | List the links that name an intent or a ruling this store lacks |

## session

| Command | What it does |
| --- | --- |
| [`plastic session note`](session-note/README.md) | Write the one prose line of this session |

## config

| Command | What it does |
| --- | --- |
| [`plastic config`](config/README.md) | Pick which on/off settings are on, on the choice screen |
| [`plastic config list`](config-list/README.md) | List every setting with its value, globally or for one harness |
| [`plastic config get`](config-get/README.md) | Print the value of one setting |
| [`plastic config set`](config-set/README.md) | Write one setting to the settings rows, globally or for one harness |

## store

| Command | What it does |
| --- | --- |
| [`plastic store backup`](store-backup/README.md) | Copy one store's databases into a new backup folder |
| [`plastic store backup list`](store-backup-list/README.md) | List one store's backups with status and goal, flagging a missing or changed file |
| [`plastic store backup purge`](store-backup-purge/README.md) | Delete one store's backups; give one of --all, --failed, --interrupted or --older-than |
| [`plastic store backup restore`](store-backup-restore/README.md) | Replace one store's databases with those of a done backup |
| [`plastic store migration list`](store-migration-list/README.md) | Print the ledger rows of one store and what a down would undo now |
| [`plastic store migration down`](store-migration-down/README.md) | Put back the rows the newest migration of one store kept in legacy.db and remove its version, after a backup |
| [`plastic store migration purge`](store-migration-purge/README.md) | Remove the rows one migration of a store kept in legacy.db, so a down can no longer undo it |
| [`plastic store sync up`](store-sync-up/README.md) | Read the files changed by hand into rows |
| [`plastic store sync down`](store-sync-down/README.md) | Write the rows that changed into files |

## document

| Command | What it does |
| --- | --- |
| [`plastic document get`](document-get/README.md) | Fetch the current text of one document; an older pinned reference is named as changed |
| [`plastic document batch`](document-batch/README.md) | Fetch qualified documents in request order |

## architecture

| Command | What it does |
| --- | --- |
| [`plastic architecture status`](architecture-status/README.md) | Tell the agent to check the architecture map with its own tool |
| [`plastic architecture refresh`](architecture-refresh/README.md) | Tell the agent to regenerate the architecture map with its own tool |

## node

| Command | What it does |
| --- | --- |
| [`plastic node add`](node-add/README.md) | Add a node to an intent's work graph, of kind work, orchestrator or retrieval |
| [`plastic node remove`](node-remove/README.md) | Remove a node; its edges stay as rows |
| [`plastic node claim`](node-claim/README.md) | Claim an open node, or take a lapsed claim, and print its brief |
| [`plastic node renew`](node-renew/README.md) | Renew this session's claim on a node so it does not lapse |
| [`plastic node release`](node-release/README.md) | Release a claimed or failed node back to open |
| [`plastic node done`](node-done/README.md) | Mark a claimed node done, with its findings as TEXT |
| [`plastic node fail`](node-fail/README.md) | Mark a claimed node failed, with the reason as TEXT |
| [`plastic node ask`](node-ask/README.md) | Move a claimed node to needs_info with a question for the owner |
| [`plastic node impede`](node-impede/README.md) | Move a claimed node to impeded with the impediment |
| [`plastic node resolve`](node-resolve/README.md) | Reopen a needs_info or impeded node with its resolution |

## edge

| Command | What it does |
| --- | --- |
| [`plastic edge add`](edge-add/README.md) | Add a needs edge between two nodes |
| [`plastic edge remove`](edge-remove/README.md) | Remove an edge |

## graph

| Command | What it does |
| --- | --- |
| [`plastic graph check`](graph-check/README.md) | Find a done node with no findings, an isolated node, a retry cap, no done criterion, a need on a removed node, a loop, output that is not JSON or a schema file with no live node |
| [`plastic graph lapsed`](graph-lapsed/README.md) | List the agent deliveries whose claims lapsed and the command that restarts each |
| [`plastic graph ready`](graph-ready/README.md) | List the nodes ready to claim |
| [`plastic graph resume`](graph-resume/README.md) | Say where each named store's work stopped and what runs next |
| [`plastic graph show`](graph-show/README.md) | Print every node, with the node it was found in, and every need of an intent |

## chat

| Command | What it does |
| --- | --- |
| [`plastic chat list`](chat-list/README.md) | List the recorded chat messages of every store in time order, from a day on with --since |

## hook

| Command | What it does |
| --- | --- |
| [`plastic hook start`](hook-start/README.md) | SessionStart: name the harness, open the session row, print the state the rows carry |
| [`plastic hook prompt`](hook-prompt/README.md) | UserPromptSubmit: record the prompt in the machine's chat history |
| [`plastic hook guard`](hook-guard/README.md) | PreToolUse: refuse an agent write to a store's core files, a closed intent or a project's intent records |
| [`plastic hook stop`](hook-stop/README.md) | Stop: stamp the turn, renew claims, run the stop gate |
| [`plastic hook end`](hook-end/README.md) | SessionEnd: set the session's end time and reason |
