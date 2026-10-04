# Codex Pet · Xiao Ke

A Windows desktop coding companion with 16 transparent GIF animations, local Codex usage statistics, and four interface languages. Built with Windows PowerShell 5.1 and WPF; no extra runtime installation is required.

[简体中文](README.md) · [Download for Windows](https://github.com/hahahaha0123/codex-pet/releases/latest) · [MIT License](LICENSE)

Current version: **2.6.1**. See [CHANGELOG.md](CHANGELOG.md).

![Wave animation](GIF动作/举手打招呼.gif)

## Quick start

Download the Windows ZIP from Releases, extract it to a permanent folder, and double-click `start-pet.cmd`. The local configuration is created on first launch.

Or clone the source:

```powershell
git clone https://github.com/hahahaha0123/codex-pet.git
cd codex-pet
.\start-pet.cmd
```

Requires Windows 10 or 11 and the built-in Windows PowerShell 5.1. Right-click for controls, drag with the left mouse button, and double-click the character to collapse the card.

The launcher installs a per-user helper that starts quietly at sign-in and opens the companion when the Codex desktop window opens. Closing the companion manually does not repeatedly respawn it in the same window. Disable it from the menu or with `disable-follow-codex.cmd`; re-enable with `enable-follow-codex.cmd`.

## Features

- Sixteen six-frame GIFs, connected to work, completion, idle, dragging, feeding and interaction.
- Simplified Chinese, Traditional Chinese, English and Japanese; live switching, saved selection and a system-language option.
- 20%–100% scaling, 80% by default; text is laid out at its final pixel size.
- Automatic recent-session selection or a pinned session; project names follow Codex's saved metadata.
- Context percentage, average task output rate, current-model usage and persistent local history totals.
- Expandable per-model history details and API-equivalent USD estimates.

Open `动作预览.html` to view all animations.

## Data and privacy

The companion reads the current user's local Codex session index and logs. It does not read login credentials, modify Codex data, or contact account APIs.

Task speed is output tokens divided by task elapsed time, including reasoning and tool waits. It is average task throughput, not instantaneous decoding speed. Context values may lag the latest generation.

Current-model usage belongs to the selected session. History totals include readable local sessions, archived sessions and subtasks, with duplicate counters and inherited fork records handled separately. Previously indexed totals are cached locally; deleted logs that were never indexed cannot be recovered.

Amounts are USD API text-token estimates, not subscription charges. Unknown models remain unpriced. See [PRICE-SOURCES.md](PRICE-SOURCES.md) for the dated price snapshot and calculation limits.

Runtime data is stored in `state/`, `pet.config.json` and `follow.config.json`. These files are excluded from Git. The repository ships a portable [configuration template](pet.config.example.json).

## Development

Run offline fixtures with Windows PowerShell:

```powershell
.\tools\Test-Data.ps1
.\tools\Test-Usage.ps1
.\tools\Test-History.ps1
.\tools\Test-Languages.ps1
.\tools\Test-Diagnostics.ps1 -Animation
.\CodexPet.Follow.ps1 -SelfTest
.\CodexPet.ps1 -Preview -ExpandedPreview -Language en-US
```

Codex installation and authentication are not required for fixture tests. Preview, smoke and animation checks use isolated configuration and synthetic data under `dist/checks/runs/<random-id>/`. They do not read real sessions or change the running pet's settings, stop signal or mutex. `Test-Usage.ps1` defaults to offline fixtures; set `CODEX_PET_TEST_LOCAL_CATALOG=1` to opt into its read-only local catalog check. Windows CI also renders a preview. Use `-SmokeSeconds 6` for window checks or `-AnimationCheck` to verify animation frame changes.

Build a portable release with `tools/Build-Release.ps1 -Version 2.6.1`. The build checks required runtime/animation files, rejects tracked local state and sensitive file types, and writes a SHA256 checksum. See [release verification](docs/release-2.6.1.md). GIF re-encoding requires Pillow, but using the companion does not require Python.

## License and artwork

[MIT](LICENSE). The original character artwork was generated with ImageGen for this project; source atlases and prompts are included. See [ASSETS.md](ASSETS.md).

This is a community project and is not an official OpenAI product. Issues, translations and pull requests are welcome.
