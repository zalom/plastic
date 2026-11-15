# plastic backup restore

Replace one store's databases with those of a done backup.

```sh
plastic backup restore --store SLUG [--timestamp TS] [--latest] [--databases LIST] [--dry-run]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--store SLUG` | the registered project whose backups the call works on |  |
| `--timestamp TS` | the backup to restore, by its folder name |  |
| `--latest` | restore the newest backup that is done | `false` |
| `--databases LIST` | the databases to restore, comma separated; all the backup holds when left out |  |
| `--dry-run` | list what would be replaced and change nothing | `false` |

## The workflows of one call

![The workflows of one call of plastic backup restore](workflows.svg)

Each box is a workflow. The words between the boxes say when the call moves on, and the last boxes say how the call ends.

## The events of one call, step by step

![The events of one call of plastic backup restore](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The chosen databases of the store are replaced by the copies of the backup folder | the database files of the store, in the store folder | stays on this machine |
| A safety backup of the replaced databases is written | the backups folder, in the store folder | stays on this machine |

The command is `Plastic::Commands::Backup::Restore`, in [`restore.rb:12`](../../../../lib/plastic/commands/backup/restore.rb#L12).
