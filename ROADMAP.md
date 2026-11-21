# Roadmap

Planned work, newest intentions first. Rough effort in brackets. Items are pulled from my own working notes; none are committed to a release.

## Soon

- **Pause / resume per account.** `LLMAccount.isActive` gates fetching everywhere but there is no way to set it to `false` — hidden accounts still poll their provider every refresh. Context-menu toggle plus dimmed row state. [3h]
- **Windsurf: discover but cannot fetch.** `WindsurfDiscovery` imports Windsurf accounts, but no usage client is registered for `.windsurf`, so those rows render a raw `noClientForService` error on every refresh. Either ship a `WindsurfClient` (dashboard endpoints, similar shape to the Cursor client) or exclude Windsurf from discovery until it exists. [6h client, 1h exclusion]
- **GLM endpoint must not depend on the editable label.** The z.ai vs Zhipu host is chosen by lowercasing the account label at request time; renaming the account silently breaks auth. Store the platform at discovery time on the account. [2h]
- **Structured logging with os.log.** Discovery, API clients, storage and the view model are silent or use `print`, which goes nowhere in the installed app. `Logger(subsystem:category:)` wrappers at the boundaries, and replace silent `try?` calls with logged catches. [4h]
- **CLI: accept tokens on stdin instead of argv.** `groundloop account add claude <TOKEN>` exposes the token in shell history and `ps`. Prompt and read with echo disabled when the argument is omitted. [1h]

## Later

- **Request timeouts in every client.** No client sets `timeoutInterval`; one slow provider can eat the whole auto-refresh cycle. Shared request factory with a 10 s timeout; parallelize Cursor's sequential calls; cap Antigravity port probes; invalidate the per-request session in `AntigravityClient`. [3h]
- **Refresh re-entrancy guard.** The auto-refresh timer and discover-and-merge can both enter `refreshUsage()` while a pass is still running. Guard with an `isRefreshing` check plus a trailing-tick flag. [1h]
- **`groundloop account --json`.** Machine-readable list output for scripts and status bars; suppress the ANSI decoration path. [2h]
- **Per-row refresh button.** `fetchUsage(account:)` already supports single-account fetch; expose it next to the row's other actions. [1h]
- **Confirm before deleting an account.** One accidental click on the red minus button removes the account and its tokens. Confirmation dialog, same pattern as history clearing. [1h]
- **Launch-at-login error handling.** A failed `SMAppService` register triggers the `didSet` revert, which re-enters service calls and can clear its own error message before it is read. Guard the revert. [2h]
- **Keychain hardening.** Explicit `kSecAttrAccessibleAfterFirstUnlock`, keep a corrupt-timestamp copy when the stored blob fails to decode, distinguish `errSecInteractionRequired` in the UI. [3h]

## Open questions

- Whether a `WindsurfClient` is feasible without an official usage API.
- Whether account metadata should move out of the single Keychain blob to avoid cross-process overwrites between the CLI and the app.
