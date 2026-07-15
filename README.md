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
- **Launch at login** - Start GroundLoop automatically when you log in.

### Installation & Launch-at-Login

**Important**: The launch-at-login feature only works when GroundLoop is installed as a proper macOS app bundle (.app), not when running via `swift run`.

**Quick Setup (Recommended):**
```bash
# One command to build, install, and launch GroundLoop
./Scripts/setup-launch-at-login.sh
```

### No more repeating keychain prompts

GroundLoop reads your Claude/Copilot tokens from the macOS Keychain. macOS pins
the requesting app's **code signature** when you click **"Always Allow"** — but an
ad-hoc signature (the default) changes on every build, so the prompt keeps coming
back after each reinstall.

The fix is a one-time, self-signed signing identity. After this, a single
"Always Allow" sticks **permanently** across rebuilds:

```bash
# 1. Create the stable signing identity (asks for your Mac password once)
./Scripts/create-signing-cert.sh

# 2. Build + install + launch (now signed with that stable identity)
./Scripts/install-menubar.sh
```

When the keychain dialog appears after launch, click **"Always Allow"** once — and
you're done for good. `install-menubar.sh` auto-creates the identity if you skip
step 1, and you can override it with `CODESIGN_IDENTITY="Developer ID Application: …"`.

**Manual Setup:**
```bash
# Build the .app bundle
./Scripts/bundle-menubar.sh

# Install to /Applications
./Scripts/install-menubar.sh
```

**Enable Launch-at-Login:**
Once installed, you can enable launch-at-login via:
- Right-click the menubar icon → "Launch at Login"
- Preferences → General → "Launch at login"

**Development Mode:**
To run from source without installing, use the dev-run script — it signs
the binary with the same stable identity as the installed app, so it
inherits your existing "Always Allow" grant and won't re-prompt on every
rebuild:
```bash
./Scripts/dev-run.sh              # debug build, sign, launch
./Scripts/dev-run.sh --release    # release build, sign, launch
```
Plain `swift run groundloop-menubar` / `swift build` still produce an
ad-hoc signature that changes every build, so they will keep re-prompting
for the Keychain — use `dev-run.sh` instead for iterative development.

Note: Launch-at-login (SMAppService) still requires a proper installed
`.app` bundle — it doesn't apply to `dev-run.sh` or `swift run`. Also,
since `dev-run.sh` runs a loose binary (not a `.app`), you'll see a Dock
icon during dev; this is cosmetic and matches existing `swift run`
behavior.

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
