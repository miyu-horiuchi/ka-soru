# ka-soru

A macOS menu bar app: highlight any text anywhere, press **Cmd+E**, and a small popover appears with an explanation from `codex` or `claude` CLI. Like the macOS dictionary Look Up — but for any sentence, any app.

> **Status:** Pre-alpha. Core flow works, UI rendering still being debugged. Not yet packaged for distribution.

---

## What it does

1. Lives quietly in your menu bar (small `ks` text icon, no Dock icon)
2. Watches for **Cmd+E** globally (any app, any window)
3. When you press it, reads the currently highlighted text via the macOS Accessibility API (or falls back to a quick clipboard read if that fails)
4. Spawns `codex exec "<your prompt>"` (or `claude -p`) in the background
5. Opens a small floating popover near your cursor, streams the answer in
6. You can type follow-ups in the popover — same `codex` / `claude` session continues
7. Click outside → popover closes (session memory stays for the next Cmd+E)

## Why

I wanted something like macOS's built-in dictionary popover, but powered by a real LLM CLI I'm already logged into — no extra API keys, no browser tab, no "switch to ChatGPT desktop." Just highlight → Cmd+E → answer.

## Requirements

- macOS 14 Sonoma or later
- One of the following CLIs installed and logged in:
  - [OpenAI Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`, then `codex login`
  - [Anthropic Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — `npm install -g @anthropic-ai/claude-code`, then `claude login`
- For development: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
git clone https://github.com/miyu-horiuchi/ka-soru.git
cd ka-soru
xcodegen generate
open KaSoru.xcodeproj
# In Xcode: ⌘R to build & run
```

On first launch, macOS will ask for **Accessibility** permission — grant it (System Settings → Privacy & Security → Accessibility → toggle KaSoru on). That's the only permission required.

## Settings

Click the `ks` menu bar icon → **Open Settings…**. You can edit:

- **Prompt template** — `<TEXT>` placeholder gets replaced with the highlighted sentence. Default: `Explain this sentence in simpler, more concise terms: "<TEXT>"`
- **Default CLI** — `codex` or `claude`

Stored at `~/Library/Application Support/ka-soru/settings.json`.

## Architecture

Single-target Swift + SwiftUI app. Project file generated from `project.yml` via XcodeGen so it stays clean in version control.

| File | Job |
|---|---|
| `KaSoruApp.swift` | `@main` entry + `AppDelegate` |
| `AppCoordinator.swift` | Wires everything together |
| `MenuBarController.swift` | `NSStatusItem` + dropdown menu |
| `HotkeyListener.swift` | Global Cmd+E via `NSEvent.addGlobalMonitorForEvents` |
| `SelectionReader.swift` | Read highlighted text via Accessibility API, fallback to clipboard |
| `CLISession.swift` | Spawn `codex exec` / `claude -p`, stream output, manage conversation history |
| `LookupPopover.swift` | Floating `NSPanel` positioned near cursor |
| `LookupView.swift` | SwiftUI: transcript + follow-up input |
| `SettingsWindow.swift` | Prompt template + CLI choice |
| `PermissionGuide.swift` | First-launch permission flow |
| `Settings.swift` | Codable model + JSON persistence |
| `PromptTemplate.swift` | `<TEXT>` substitution |
| `Toast.swift` | Transient screen notifications |

## Documentation

- [Design spec](docs/superpowers/specs/2026-05-20-ka-soru-design.md)
- [Implementation plan](docs/superpowers/plans/2026-05-20-ka-soru.md)

## Known issues

- Popover content sometimes renders blank — actively being debugged
- Accessibility permission gets revoked on every dev rebuild (unsigned binary; macOS treats each rebuild as a new app). Mitigation: `tccutil reset Accessibility dev.kasoru.KaSoru` and re-grant. Long-term fix is proper code signing.
- The fallback clipboard read briefly overwrites your clipboard (then restores) — visible to clipboard manager apps.

## License

MIT (or whatever — pick one before shipping)
