# Ground Loop

Ground Loop is an all-in-one solution for managing and monitoring your LLM service accounts on macOS. It consists of a **Swift library**, a **CLI tool**, and a **macOS Menu Bar application**.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/NeverTheSame/GroundLoop.git
cd GroundLoop

# Discover and import existing tokens from your apps
swift run groundloop discover

# View current usage and limits
swift run groundloop account
```

## Features

- **Multi-token accounts** -- Store multiple tokens per service (personal, work, etc.)
- **Auto-discovery** -- Finds existing tokens from Claude, Copilot, Cursor, Windsurf, Codex, Antigravity, GLM
- **Secure storage** -- macOS Keychain via Security framework
- **Usage fetching** -- API clients for each service with live metrics
- **Swift 6 / async-await** -- Full concurrency support

## Menu Bar App (macOS)

Monitor your LLM usage directly from your macOS menu bar. The app provides real-time visibility into your session and usage across multiple services.

**Features:**
- Quick overview of all accounts and current usage.
- Auto-refresh and manual refresh support.
- One-click token discovery.
- Detachable window for persistent monitoring.

To run the menu bar app from source:
```bash
swift run groundloop-menubar
```

## CLI Tool

Manage your accounts and fetch usage directly from the terminal.

```bash
# Discover and import tokens
swift run groundloop discover

# Show accounts and fetch usage
swift run groundloop account
```

Example output:
```
Discovering tokens...
Found and imported 3 account(s)

Listing 3 account(s)...
  Claude
   Session: [================----] 60%
```

## Swift Library

Ground Loop can be integrated into your own Swift projects as a package.

### Usage

```swift
import GroundLoop

let gl = GroundLoop()
try await gl.setup()

let imported = try await gl.discoverAndImport()
print("Found \(imported.count) accounts")

let results = await gl.fetchAllUsage()
for result in results {
    switch result {
    case .success(let usage):
        print("\(usage.account.service): \(usage.metrics.count) metrics")
    case .failure(let error):
        print("Error: \(error)")
    }
}
```

## Supported Services

| Service | Discovery | API |
|---------|-----------|-----|
| Claude | `~/.claude/.credentials.json`, Keychain | Yes |
| Copilot | `gh:github.com` Keychain | Yes |
| Cursor | SQLite `state.vscdb` | Yes |
| Windsurf | SQLite `state.vscdb` | Yes |
| Codex | `~/.config/codex/auth.json` | Yes |
| Antigravity | Process discovery (language server) | Yes |
| GLM | `~/.claude/settings.json` (Z.AI) | Yes |

## Requirements

- macOS 14+
- Swift 6.0+

## License

MIT
