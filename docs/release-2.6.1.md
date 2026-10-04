# 2.6.1 release verification

Date: 2026-10-05 (Asia/Shanghai). Scope: Windows PowerShell 5.1 + WPF source and portable ZIP. Maintainer: repository owner. This record is updated from actual commands before publication; pending checks must not be reported as passing.

## Changes and review

The local 2.6.0 source and remote README-only initial commit are combined without discarding either history. Review found that diagnostic modes used the normal state directory and could clear a live stop signal; they also read live Codex sessions. Diagnostic modes now use a unique output directory, template configuration, independent mutex and synthetic sessions. The current-usage worker previously exited on a transient file failure; it now clears stale state and retries, with lock/delete/recreate fixtures.

Source review covers runtime entry points, worker ownership, startup-helper behavior, configuration, animation loading, Git exclusions and package inputs. This is a developer review, not a separate security audit. The documented launcher continues to register a per-user follow-Codex helper; direct script startup does not install it. No new automatic-start registration was needed for this verification.

## Verification commands

Run each script in a fresh built-in Windows PowerShell 5.1 process:

```powershell
.\tools\Test-Data.ps1
.\tools\Test-Usage.ps1
.\tools\Test-History.ps1
.\tools\Test-Languages.ps1
.\CodexPet.Follow.ps1 -SelfTest
.\tools\Test-Diagnostics.ps1 -Animation
.\tools\Build-Release.ps1 -Version 2.6.1
.\tools\Test-Package.ps1 -Version 2.6.1
```

Rules use temporary synthetic files. Optional real-catalog usage tests are opt-in. Diagnostic isolation checks copy runtime files into a temporary workspace, seed mock preferences and a stop signal, hold the normal mutex, run preview/smoke/animation modes, and verify unchanged mock state. WPF smoke checks switch four languages, three synthetic sessions and 20/60/80/100% layout. Animation checks require all six frames in every one of sixteen clips.

## Results

Executed on Windows 10 Pro 10.0.19045 using the system Windows PowerShell 5.1. All processes below exited with code 0:

| Suite | Result |
|---|---|
| Data | 6 PASS lines |
| Current usage | 13 PASS lines; optional real-catalog check skipped by default |
| History | 11 PASS lines |
| Languages | 331 PASS lines, including its overall summary |
| Follow-helper rules | 5 PASS lines |
| Diagnostic isolation and animation | 15 PASS lines; all 16 actions showed all 6 frames |
| Extracted portable package | 16 PASS lines; preview and smoke ran successfully from the extracted ZIP |

Source hygiene checked 168 tracked files: no tracked normal runtime-state/private file paths and no common API-token/private-key patterns were detected. This bounded pattern scan is not a proof against every possible secret. The inspected ZIP contains default configuration only, required runtime files, all animation inputs, MIT license and matching version/checksum. Actual WPF previews were inspected; they show synthetic data.

The updated normal app was restarted and remained responsive (181.62 MiB working set at a single short startup sample). This is not a sustained performance benchmark. Local evidence is kept in ignored `dist/checks/`; no real session/history data belongs in the repository or ZIP. Package SHA256 is stored beside the ZIP and uploaded as a release asset. GitHub-hosted CI outcome is available in the repository's Actions run, separately from these local results.

## Limits and operations

The pet was started on the current Windows host and its process remained responsive. This does not prove a clean Windows 10/11 installation, every DPI/multi-monitor layout, long-running resource stability or the login-startup experience. WPF routed-event checks do not prove physical mouse interaction. Pricing fixtures validate arithmetic against the repository's dated price table; this release does not refresh or independently certify that price snapshot, and estimates are not subscription charges.

Upgrade: close the old pet, extract the new package to a separate folder, then migrate only your own `pet.config.json` if desired. Avoid overwriting it with the bundled default. If the follow helper was enabled, disable it in the old location and re-enable it from the new location so its shortcut points at the new folder. Roll back by stopping the new pet and starting the previous folder; Codex source data is never modified. No schema changes were made to normal configuration or history caches.
