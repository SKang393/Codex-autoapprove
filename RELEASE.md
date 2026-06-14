# Release Notes

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
