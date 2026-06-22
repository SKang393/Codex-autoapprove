# Codex Auto Approve

Small Windows helper for clicking the Codex `Approve for session` button whenever the Windows approval notification appears.

## Status

- Current release: `v1.2.0`
- Platform: Windows
- License: Apache License 2.0

## Use

Recommended GUI launch:

- Double-click `Start Codex Auto Approve GUI.vbs` for the wrapped version. This starts the GUI without showing a command window.
- Double-click `Start Codex Auto Approve GUI.cmd` for the unwrapped version. This starts the same GUI with a visible command window.

The GUI lets you pick one of these scan intervals:

- 30 seconds
- 1 minute
- 5 minutes
- 30 minutes
- 1 hour

Click `Start` to begin scanning. Use `Hide to tray` or minimize the window to keep the program running in the system tray. Double-click the tray icon to show the GUI again. Use the tray menu or the `Exit` button to fully close it.

Turn on `Start with Windows` if you want the GUI to launch automatically when you sign in. It uses the current user's Windows startup setting, starts minimized to the system tray, and does not require administrator permission. Turn the checkbox off to remove the startup entry.

Command-line launch:

Double-click `Click Approve For Session.cmd` and leave the window open.

The script searches Windows UI Automation first, then falls back to the visible four-button notification layout across all monitors. It works with secondary monitors and negative screen coordinates. It clicks one matching `Approve for session` button per scan and keeps running until you close the window or press `Ctrl+C`.

It does not inspect or depend on the command message text. It only looks for the session approval button.

## Windows Notification Requirement

This program depends on the Codex approval notification being visible on the Windows desktop. If you want to use it, make sure Windows notifications are enabled for Codex and that notification banners are not hidden by Do Not Disturb, Focus Assist, or similar settings.

## Commands

Preview one scan without sending a click:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ApproveForSessionClicker.ps1 -DryRun -MaxScans 1
```

Force a physical mouse click instead of UI Automation invoke:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ApproveForSessionClicker.ps1 -ClickMode Mouse
```

Check more or less often:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ApproveForSessionClicker.ps1 -IntervalSeconds 10
```

Run the GUI directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CodexAutoApproveGui.ps1
```

Build wrapped and unwrapped release packages:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\packaging\build-release.ps1 -Version v1.2.0
```

Run tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

## Notes

- No external packages are required.
- It only targets buttons named `Approve for session` or visibly truncated as `Approve for sessi...`.
- Keep the approval prompt visible and unobstructed when it appears.

## Build History

- `v0.1.0`: Initial lightweight one-shot clicker using Windows UI Automation.
- `v0.2.0`: Persistent mode that checks every 30 seconds until stopped.
- `v1.0.0`: Release build with UI Automation plus visible notification-layout fallback for Windows approval notifications.
- `v1.0.1`: Handles transient Windows UI Automation `FindAll` failures by continuing to screenshot-layout fallback instead of crashing.
- `v1.1.0`: Adds Windows GUI, fixed interval picker, system tray background mode, hidden wrapped launcher, visible unwrapped launcher, and wrapped/unwrapped release packages.
- `v1.2.0`: Adds a GUI `Start with Windows` toggle that starts the app minimized to the system tray through the current-user Windows startup setting.

## Safety Disclaimer

This tool automatically approves Codex session permissions when it detects the session approval button. Use it only when you understand the command approval risk. The authors and contributors are not responsible for any issue, damage, data loss, security problem, unintended command execution, or other consequence caused by auto approval.

## Release

See [RELEASE.md](RELEASE.md) for release notes.

The release package builder creates:

- `dist/CodexAutoApprove-v1.2.0-wrapped.zip`: GUI plus `.vbs` launcher that hides the command window.
- `dist/CodexAutoApprove-v1.2.0-unwrapped.zip`: GUI and command-line launchers with visible command windows.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
