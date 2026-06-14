# Release Notes

## v1.1.0 - 2026-06-14

GUI and release packaging update.

### Added

- Windows Forms GUI for starting and stopping auto approval.
- Fixed interval picker with 30 seconds, 1 minute, 5 minutes, 30 minutes, and 1 hour choices.
- System tray mode so the program can keep scanning in the background.
- Wrapped launcher, `Start Codex Auto Approve GUI.vbs`, that starts the GUI without showing a command window.
- Unwrapped launcher, `Start Codex Auto Approve GUI.cmd`, for users who want a visible command window.
- Release package builder for wrapped and unwrapped zip packages.

### Release Artifacts

- `CodexAutoApprove-v1.1.0-wrapped.zip`
- `CodexAutoApprove-v1.1.0-unwrapped.zip`

## v1.0.1 - 2026-06-14

Patch release for runtime stability.

### Fixed

- Catches transient Windows UI Automation `FindAll` failures, including `ElementNotAvailableException` and unrecognized UI Automation errors.
- Continues to screenshot-layout fallback when the Windows UI Automation tree changes while scanning.
- Keeps the persistent loop alive instead of stopping on the UI Automation exception.

## v1.0.0 - 2026-06-14

Initial public release for `SKang393/Codex-autoapprove`.

### Added

- Persistent Windows clicker for the Codex `Approve for session` button.
- 30-second scan loop that keeps running until the user closes the window or presses `Ctrl+C`.
- Multi-monitor support, including secondary monitors with negative coordinates.
- Windows UI Automation detection.
- Screenshot-layout fallback for the visible four-button Codex approval notification.
- Dry-run mode for detection checks without clicking.
- Local PowerShell tests for button selection, scan behavior, and screenshot-layout fallback.

### Requirements

- Windows desktop session.
- Codex approval notification banners must be enabled and visible.
- No external packages are required.

### Safety Notice

This release can automatically approve session permissions. Use at your own risk. The authors and contributors are not responsible for issues caused by auto approval.
