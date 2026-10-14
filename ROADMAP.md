# Roadmap

Tracked by [issue #3](https://github.com/Maxaubert/Hide-Any-Window/issues/3).

## Stop means stopped

Pressing **Stop service** currently writes `serviceState=stopped`. The AHK service notices that
change, restores hidden windows, releases its mutex, and exits. However, the
`HideAnyWindowService` logon task remains registered, so Windows still launches
`HideAnyWindowManager.exe --start-service` at every sign-in. The manager reads the stopped state
and exits without starting the service, but the unnecessary startup process is still visible in
Task Scheduler and can briefly appear to the user.

The target behavior is simple: after the user presses **Stop service**, no Hide Any Window process
should launch again until the user explicitly asks for it.

## Lifecycle contract

| User action | Service now | Future logons |
|---|---|---|
| Stop service | Save `stopped`, restore windows, exit service | Remove the logon task |
| Start service | Save `running`, start the service | Leave autostart unchanged |
| Enable **Start service at logon** | Ensure the service is running | Create an enabled logon task |
| Disable **Start service at logon** | Leave the current service running | Remove the logon task |

These invariants must hold:

1. `serviceState=stopped` and an enabled logon task must not coexist after a manager action.
2. Pressing **Start service** starts only the current session. It must not silently opt the user
   back into autostart.
3. **Start service at logon** is the only UI action that creates or re-enables the task.
4. Task Scheduler failures must be logged and shown to the user instead of being treated as
   success.
5. The service process must still exit when stopped. Do not reintroduce a resident paused mode.

## Implementation plan

### 1. Make autostart detection truthful

`AutostartManager.IsEnabled()` currently returns true whenever `schtasks /Query` finds the task,
including when the task exists but is disabled. `App.OnLaunched` then calls `TryEnable()` and
silently re-enables it.

- Query the task as XML and read its `<Settings><Enabled>` value, or use another
  locale-independent Task Scheduler API.
- Return three internal states where useful: missing, disabled, and enabled.
- Treat missing and disabled as autostart off.
- When a disabled legacy task is found, delete it rather than re-registering it.
- Keep `TryDisable()` idempotent and verify that the task is absent after deletion.

### 2. Couple Stop to task removal

Move the button's lifecycle work into a testable manager service or coordinator rather than
growing `MainWindow.xaml.cs`.

When **Stop service** is pressed:

1. Save `serviceState=stopped` immediately.
2. Ask `AutostartManager.TryDisable()` to remove the logon task.
3. Let the AHK service observe the config change, restore hidden windows, and exit.
4. Refresh the manager status after the mutex disappears.
5. If task removal fails, keep the service stopped but show a clear partial-failure message with
   the task name and a retry action.

### 3. Keep manual Start session-only

The existing **Start service** path should continue to save `running` and launch the service via
ShellExecute. It must not call `AutostartManager.TryEnable()`.

This preserves user intent: stopping opts out of future startup, while starting manually does not
silently change the logon preference.

### 4. Define the settings-toggle transition

When **Start service at logon** is enabled:

1. Save `serviceState=running`.
2. Start the service if its mutex is absent.
3. Create and verify the enabled logon task.
4. Roll the toggle back and report an error if task creation fails.

When the setting is disabled, remove the task but leave the currently running service alone.

The settings dialog should refresh its switch from the verified task state after each operation,
not assume that `schtasks` succeeded.

### 5. Migrate existing installations

On the first manager launch after the fix:

- Delete a disabled `HideAnyWindowService` task.
- If the config is `stopped`, remove any enabled copy of the task.
- If the config is `running` and the task is enabled, preserve and, only when necessary, migrate
  its action to `HideAnyWindowManager.exe --start-service`.
- Log the detected state and migration result to `manager.log`.

The installer and uninstaller should remain idempotent. Uninstall must continue removing the task
regardless of its enabled state.

## Verification

Add unit tests around an injectable task-command runner and a WinUI-free lifecycle coordinator:

- Missing, disabled, and enabled tasks are distinguished correctly.
- `TryDisable()` succeeds when the task is already absent.
- Stop saves `stopped` and removes autostart.
- Manual Start launches the service without creating a task.
- Enabling autostart from a stopped state saves `running`, starts the service, and creates the task.
- Disabling autostart leaves an already-running service running.
- Task creation or deletion failure is returned to the caller and does not produce a false UI
  state.
- Legacy stopped-plus-enabled and disabled-task states migrate to no task.

Manual end-to-end verification:

1. Enable **Start service at logon**, sign out and back in, and confirm the service starts.
2. Press **Stop service** and confirm the service exits and the scheduled task is absent.
3. Sign out and back in and confirm no Hide Any Window process or new manager-log entry appears.
4. Press **Start service** and confirm the service runs while the scheduled task remains absent.
5. Enable **Start service at logon** again and confirm the task is recreated and works after the
   next sign-in.

## Done when

- Stop leaves no service process and no logon task.
- Later logons launch no Hide Any Window process until autostart is explicitly enabled.
- Manual Start does not alter the autostart preference.
- The settings switch always reflects the verified Task Scheduler state.
- Automated tests and the manager build pass.
