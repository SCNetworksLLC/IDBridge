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
  that makes a network call bounds it itself: the shipped webhook sets `-TimeoutSec`
  (which stops counting once an answer's headers arrive), and the account history template
  keeps a 30-second clock of its own over the whole exchange.

## Smaller

- **The webhook's error text.** `Invoke-PluginPostRunWebhook` sends `RunError` as text, and
  an error's message can name a UPN or a DN; [plugins.md](plugins.md) calls its payload
  "no per-user data". Either the doc says so or the plugin sends the error's type alone, as
  `LastRun.json` does.

- **A write's time in UTC.** An `Applied` record's `Timestamp` is local time with no zone
  (`Private/Add-IDBridgeWriteResult.ps1`), so a reader that needs UTC must guess in the
  hour that repeats when the clocks go back: the account history template posts a write
  made then an hour late. Wanted: a UTC stamp beside it on the record (an additive
  property; check what `Invoke-PluginPostRunExport` and other readers do with a new one).

- **The move check and a comma in a name.** `Get-ADUsersToUpdate` takes an account's OU
  as its distinguished name after the first comma. A name that holds a comma is escaped in
  the DN (`CN=Ann Smith\, Jr. 007,OU=Staff,...`), so that person's OU is read wrong and a
  move may be proposed for them on every run. Not confirmed against a live directory.
