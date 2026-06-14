# Codex Auto Approve

Small Windows helper for clicking the Codex `Approve for session` button whenever the Windows approval notification appears.

## Status

- Current release: `v1.0.0`
- Platform: Windows
- License: Apache License 2.0

## Use

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

## Safety Disclaimer

This tool automatically approves Codex session permissions when it detects the session approval button. Use it only when you understand the command approval risk. The authors and contributors are not responsible for any issue, damage, data loss, security problem, unintended command execution, or other consequence caused by auto approval.

## Release

See [RELEASE.md](RELEASE.md) for release notes.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
