# ka-soru — Design Spec

**Date:** 2026-05-20
**Status:** Approved, ready for implementation planning

---

## Summary

ka-soru is a macOS menu bar app. You highlight a sentence anywhere on your Mac, press Cmd+E, and a floating terminal popup opens running `codex` (or `claude`) with a configurable prompt that explains the sentence in simpler terms. The CLI session persists across popup closes, so follow-up triggers continue the same conversation.

---

## User experience

### Trigger

1. Highlight any text in any macOS app (Safari, Chrome, Preview, Notes, Slack, Mail, etc.).
2. Press `Cmd+E`.
3. A borderless, always-on-top terminal window appears above your current app.
4. The terminal shows the prompt being sent and streams the CLI's reply.
5. Type follow-up questions directly into the terminal; close the window when done.

### Session model

- First trigger spawns `codex` (default) or `claude` in a pseudoterminal.
- The session stays alive in the background when the popup closes.
- Subsequent triggers reopen the popup attached to the same session, with full scrollback and conversation memory. The new highlighted sentence is appended as the next prompt.
- A **"New Session"** button in the popup toolbar ends the current session and starts fresh. The popup stays open showing the new empty session.
- Quitting ka-soru ends the session.
- If the CLI process dies unexpectedly, the next trigger silently starts a new one (toast: *"Session restarted."*).

### Configuration

A separate Settings window lets you edit:
- **Prompt template** — string with a `<TEXT>` placeholder. Default: `Explain this sentence in simpler, more concise terms: "<TEXT>"`
- **Default CLI** — `codex` or `claude` (radio).

Stored in `~/Library/Application Support/ka-soru/settings.json`:

```json
{
  "promptTemplate": "Explain this sentence in simpler, more concise terms: \"<TEXT>\"",
  "defaultCLI": "codex"
}
```

### First launch

App walks the user through granting two macOS permissions:
- **Accessibility** — needed to read highlighted text from other apps.
- **Input Monitoring** — needed to detect Cmd+E globally.

A `PermissionGuide` window explains why and deep-links into each pane of System Settings. App will not function until both are granted, and will recheck on every launch.

---

## Architecture

Single Swift + SwiftUI macOS app. Deployment target: macOS 14 Sonoma. Project structure follows Xcode conventions.

### Components

Eight focused modules, each with a single responsibility:

1. **`MenuBarController`** — `NSStatusItem` with `ks` icon. Dropdown menu: *Open Settings · New Session · Quit*. Entry point that wires up the other components on launch.

2. **`HotkeyListener`** — `CGEventTap` watching system-wide key events. Fires on `Cmd+E` (key code `kVK_ANSI_E` with the Command modifier and no Shift/Option/Control). Note: Cmd+E system-wide intercepts the browser's built-in "Use Selection for Find" shortcut.

3. **`SelectionReader`** — calls Accessibility API on the focused element of the frontmost app via `kAXSelectedTextAttribute`. Returns the highlighted string or `nil`.

4. **`SessionManager`** — long-lived service that owns the running CLI process. Public API:
   - `sendPrompt(_ text: String)` — spawns the CLI if needed, writes prompt + `\n` to pty stdin
   - `attachTerminal(_ term: TerminalView)` — wire pty stdout/stderr to a terminal view, pty stdin from the view's keystrokes
   - `detachTerminal()` — keep process running, drop the UI binding
   - `startNewSession()` — kill current process, drop state
   - Publishes events: `processExitedUnexpectedly`, `sessionStarted`

5. **`TerminalWindow`** — borderless floating `NSWindow` (`.floating` level, draggable, resizable). Contains a SwiftUI view with **SwiftTerm** wrapped as `NSViewRepresentable`. Toolbar: *New Session · Settings · Close*. Opens/focuses on trigger.

6. **`PromptTemplate`** — value type with a `<TEXT>` placeholder. `render(with text: String) -> String` performs substitution.

7. **`SettingsWindow`** — separate small SwiftUI window. Edits `PromptTemplate` (textarea) and default CLI (radio). Writes to settings.json on change.

8. **`PermissionGuide`** — first-launch + on-demand window. Two-button UI to deep-link System Settings panes. Polls permission state and dismisses when both granted.

### Dependencies (Swift Package Manager)

- **SwiftTerm** — terminal emulator widget for the popup
- macOS Accessibility framework (built-in)
- pty: `Darwin` + `Foundation.Process` (built-in)
- Global hotkey: custom `CGEventTap` wrapper that fires on Cmd+E

### Data flow (happy path)

1. User highlights *"The mitochondria is the powerhouse of the cell"* in Safari.
2. User presses `Cmd+E`.
3. `HotkeyListener` → modifier flags match (Command only) → fires `trigger()`.
4. `SelectionReader` → Accessibility API → returns the sentence.
5. `SessionManager.sendPrompt(promptTemplate.render(with: sentence))`:
   - If no session: spawn CLI in pty.
   - Write rendered prompt + `\n` to stdin.
6. `TerminalWindow` opens (or refocuses). SwiftTerm attaches to pty stream, renders scrollback then live output.
7. User reads response. Optional: types follow-up keystrokes → SwiftTerm → pty stdin → CLI.
8. User closes popup. `SessionManager.detachTerminal()`. CLI keeps running.
9. Later: another Cmd+E. Same SessionManager reused. New sentence appended as next prompt in same conversation.

---

## Edge cases

| Situation | Behavior |
|---|---|
| Cmd+E, nothing highlighted, no session exists | Screen toast: *"Highlight a sentence first."* No popup. |
| Cmd+E, nothing highlighted, session exists | Popup opens attached to existing session. User can type freely. |
| First launch, permissions not granted | Opens `PermissionGuide`. App is non-functional until both granted. |
| CLI binary not on `$PATH` | Toast: *"codex CLI not found on PATH. Install it first."* No popup. |
| CLI not logged in | No special handling — CLI prints its own OAuth URL; SwiftTerm renders normally; user clicks/copies it, logs in via browser, returns. |
| Session process dies | Next trigger silently spawns new session. Toast: *"Session restarted."* No data lost (CLI manages its own conversation persistence). |
| Cmd+E pressed in a browser | Intercepted globally — overrides the browser's "Use Selection for Find" shortcut while ka-soru is running. |
| User Ctrl+C in popup | SIGINT sent to CLI process (standard terminal behavior). Session stays alive. |
| New trigger while CLI still responding | New prompt queued, sent after current response finishes. Don't interrupt. |

---

## Testing

### Unit tests (`KaSoruTests/`)

- `PromptTemplate` — substitution including text with quotes, newlines, very long content, missing placeholder.
- `SessionManager` — process lifecycle: start, reuse, dead-process recovery, "New Session" tear-down. Mock pty.

### Manual integration tests

- Highlight text in Safari → Cmd+E → popup opens with CLI explanation.
- Same in Preview (PDF), Notes, Slack, ChatGPT.com, Mail.
- Close popup → Cmd+E again → same session reopens with full scrollback.
- "New Session" button → previous CLI process killed, new one spawned, popup empty.
- Quit app → CLI process cleanly terminated.
- Edit prompt template in Settings → next trigger uses new template.
- First-launch permission flow → PermissionGuide → grant Accessibility → grant Input Monitoring → app becomes functional.

---

## Build & distribution

- Xcode project at repo root: `KaSoru.xcodeproj`.
- Build & run via Xcode (`⌘R`) for development.
- Distribution v1: archive → export unsigned `.app` → distribute as zip. Recipients right-click → Open once to bypass Gatekeeper.
- Code signing and notarization deferred to a later release.

### Repo layout

```
ka-soru/
├── README.md
├── docs/
│   └── superpowers/specs/2026-05-20-ka-soru-design.md
├── KaSoru.xcodeproj/
├── KaSoru/
│   ├── KaSoruApp.swift              # @main
│   ├── MenuBarController.swift
│   ├── HotkeyListener.swift
│   ├── SelectionReader.swift
│   ├── SessionManager.swift
│   ├── TerminalWindow.swift
│   ├── PromptTemplate.swift
│   ├── SettingsWindow.swift
│   ├── PermissionGuide.swift
│   ├── Settings.swift               # codable settings + persistence
│   └── Assets.xcassets/
└── KaSoruTests/
    ├── PromptTemplateTests.swift
    ├── SessionManagerTests.swift
    ├── SettingsTests.swift
    └── SmokeTest.swift
```

---

## Non-goals for v1

- Windows / Linux support
- iCloud sync of settings or session history
- Code signing / notarized installer
- Multiple parallel sessions (tabs)
- Custom hotkey configuration (Cmd+E is hardcoded)
- Saving session transcripts to disk
- Per-app or per-document session scoping
