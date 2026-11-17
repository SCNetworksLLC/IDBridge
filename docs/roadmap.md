# Roadmap

Work planned and not built yet. A finished item leaves this page; [CHANGELOG.md](../CHANGELOG.md)
records what shipped.

## Planned

- **A timeout for plugins.** Nothing times a plugin out today. A PostRun plugin is called in
  the run's own process (`& $plugin.Function -RunResult $RunResult`,
  `Private/Core/Invoke-PostRunPlugins.ps1`), before the Google Sheet log push and before the
  single-run lock is released (`Public/Core/Invoke-IDBridge.ps1`), so one that hangs — a web
  request with no `-TimeoutSec`, a file share that stopped answering — holds the lock, and
  every scheduled run after it aborts as "already in progress" until the task's 1-hour
  `ExecutionTimeLimit` kills the process. A plugin that throws is already isolated; one that
  never returns is not. Wanted: a limit per plugin (a default, and a per-descriptor override
  in the `Plugins` array), past which the plugin is abandoned, logged as a `Warn` naming it,
  and the run carries on. Source and Override plugins run earlier in the same process and
  hang the same way; decide with this whether they get the same limit (a Source plugin that
  times out has no data, so its run must fail rather than carry on). Until then a plugin
  that makes a network call sets its own `-TimeoutSec`, as the shipped webhook does.

- **A run ID.** A run has no identifier of its own: the RunResult carries `RunStart` and the
  log lines carry timestamps, and that is all that ties a log, a `LastRun.json` and a
  PostRun plugin's post to one run. Wanted: a GUID made as the run starts, on the RunResult
  (`RunId`, an additive field, schema unchanged), in `Data\LastRun.json` and on the run's
  opening log line, so a receiver can keep a run posted twice once and a person can find a
  run's log from what a plugin sent.

## Smaller

- **The webhook's error text.** `Invoke-PluginPostRunWebhook` sends `RunError` as text, and
  an error's message can name a UPN or a DN; [plugins.md](plugins.md) calls its payload
  "no per-user data". Either the doc says so or the plugin sends the error's type alone, as
  `LastRun.json` does.
