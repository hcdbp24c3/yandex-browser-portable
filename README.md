# Yandex Browser Portable

[![Validate](https://github.com/hcdbp24c3/yandex-browser-portable/actions/workflows/validate.yml/badge.svg)](https://github.com/hcdbp24c3/yandex-browser-portable/actions/workflows/validate.yml)
[![Build](https://github.com/hcdbp24c3/yandex-browser-portable/actions/workflows/build.yml/badge.svg)](https://github.com/hcdbp24c3/yandex-browser-portable/actions/workflows/build.yml)
[![Smoke](https://github.com/hcdbp24c3/yandex-browser-portable/actions/workflows/smoke.yml/badge.svg)](https://github.com/hcdbp24c3/yandex-browser-portable/actions/workflows/smoke.yml)

A self-contained, debloated, **portable Yandex Browser**: no installer, no background
service, no self-update — profile and cache live next to the app, so the whole package is
a folder you can move, copy or delete.

Built in CI from the official public `Yandex.exe` payload and wrapped with Chrome++
(`version.dll`) so `Data\` and `Cache\` stay at the package root.

**Docs**: [design](docs/plans/2026-09-27-yandex-browser-portable-design.md) ·
[spike findings](docs/spike-findings.md) ·
[issue #8 status](docs/2026-09-27-issue8-status.md) ·
[releases](https://github.com/hcdbp24c3/yandex-browser-portable/releases/latest)

Origin: https://github.com/hoangxg4/helium_browser_portable/issues/8

### Features

- Portable: everything under one folder, nothing written outside it
- Safe-first debloat: exactly 11 documented policies, every one verifiable on `chrome://policy`
- Telemetry, crash reporting, background mode, auto-start, Alice prompts, AI new-tab tools
  and search suggestions disabled
- Updater stripped; version is pinned in `version.txt` and refreshed by `update.bat`
- Vendor bloat trimmed at build time (~14 MB): the call-ID agent, the browser proxy, the
  voice-activation/web-app config trees and every non-`en-US` locale `.pak`
- Single-instance `launcher.exe` with a bilingual (`--lang en|ru`) config dump, an
  ephemeral-HKCU mode that only engages when the policy verdict says it is honored, and a
  stale-cache prune
- Widevine/DRM and SafeBrowsing deliberately left untouched

## Accepted EULA risk (read this)

Yandex's browser agreement (§4.1/§4.2, https://yandex.ru/legal/browser_agreement/en/)
prohibits redistributing modified builds. The owner accepted this risk on 2026-09-27:
releases are published from this repository's CI and **if Yandex objects, only the
releases are taken down — no code impact**. You are responsible for complying with the
agreement in your jurisdiction.

## Layout

The release zip (`yandex-portable_<ver>.zip`) extracts to an outer
`Yandex_Portable\` folder (verified against the shipped `26.8.4.893` zip listing):

```
Yandex_Portable/
├── build-yandex.ps1        builder/extractor at the package root
│                           (update.bat calls $APP_DIR\..\build-yandex.ps1)
├── launcher.exe            single-instance launcher (issue #1 §4/§7/§8);
│                           run it FROM THIS FOLDER - see "Launcher" below
├── docs/                   gate document for the launcher
│   └── issue1-claims-findings.md   the `T1 verdict:` line decides hkcu-mode
├── layout-manifest.txt     builder-written layout listing
├── preseed/                profile preseed sources (Local State / Preferences / First Run)
├── Data/                   profile — seeded at build (Local State / Default\Preferences / First Run)
├── Cache/                  cache (created on first run)
└── Yandex/                 browser tree — also update.bat's own directory
    ├── browser.exe         entry point (NOT chrome.exe)
    ├── version.dll         Chrome++ launcher (or launch.bat fallback — spike P2)
    ├── chrome++.ini        Chrome++ config: Data\ and Cache\ at package root
    ├── debloater.reg       11 safe-first policies (HKLM\SOFTWARE\Policies\YandexBrowser)
    ├── update.bat          updater (re-installs from GitHub Releases)
    ├── version.txt         version = winget PackageVersion (sole source of truth)
    ├── Locales/            en-US.pak only (see "Trimmed vendor files")
    └── WidevineCdm/        flat exe-dir CDM path, only if the CDM was shipped/registered
```

## Usage

1. Download the latest release zip from
   [Releases](https://github.com/hcdbp24c3/yandex-browser-portable/releases/latest)
   (`yandex-portable_<ver>.zip`, currently **26.8.4.893**) and extract it anywhere
   (no admin needed to extract).
2. Start `Yandex\browser.exe`, or run `launcher.exe` from this folder for the
   single-instance entry point (below).

## Launcher (`launcher.exe`)

`launcher.exe` at the package root is a small single-instance front end (no GUI, no
dependency beyond `golang.org/x/sys`). It adds three things on top of launching
`Yandex\browser.exe`:

1. **Single instance** — takes the mutex `Global\YandexPortable_SingleInstance`. A second
   invocation never opens a second browser: it hands its URL argument to the running
   instance, or exits 0 saying there is nothing to hand over to.
2. **Ephemeral HKCU mode** — it reads the single `T1 verdict:` line out of
   `docs\issue1-claims-findings.md`. Only `HONORED` makes it write the 11 `debloater.reg`
   values into `HKCU\Software\Policies\YandexBrowser` for the lifetime of the run; a
   deferred sweep removes exactly what it created. The **shipped** verdict is `IGNORED`
   (measured on the consumer build — see
   [`docs/issue1-claims-findings.md`](docs/issue1-claims-findings.md)), so today it always
   reports `mode: skip - T1 verdict: IGNORED` and leaves your registry alone. A missing
   findings doc is a hard error, not a skip — that is why the doc ships in the zip.
3. **Stale-cache prune** — when `state.json` at the package root is missing or at least
   `--prune-days` old (default 7) and no browser is running, it deletes only the volatile
   cache dirs under `Data\` and re-stamps `state.json`. Profile files are never touched.

Run it **from the package root** (`cd` there first, or pass `--findings` /
`--app-dir` explicitly) — `--findings` defaults to the relative
`docs/issue1-claims-findings.md`.

```powershell
.\launcher.exe --settings --lang en      # print the resolved config, exit 0
.\launcher.exe --dry-run --selftest     # full lifecycle, never spawns browser.exe
.\launcher.exe https://example.com      # forward a URL to the running instance
```

`--lang en|ru` pins the output language (default: the OS UI language). The full flag list
lives in [`launcher/README.md`](launcher/README.md).

### Applying the debloat policies

`Yandex\debloater.reg` writes to `HKLM\SOFTWARE\Policies\YandexBrowser`, which is a
machine-wide (HKLM) key:

- **With admin rights** — double-click `Yandex\debloater.reg` and confirm, or from an
  elevated prompt run `reg import Yandex\debloater.reg`. Verify afterwards on
  `chrome://policy`: each key shows `source = Platform`, `level = Mandatory`
  (proven in spike P3, headed run H5).
- **Without admin rights** — the registry policies cannot be applied (HKLM write is
  denied). The build's **preseeded preferences debloat still applies automatically**
  from `Data\` (`Local State` / `Default\Preferences` + `First Run` sentinel), so the
  no-admin install is debloated too, just through prefs instead of policies.

> Note: CI's smoke job runs `reg import Yandex\debloater.reg` only to prove the file parses;
> it **never applies policies to end users** — applying them is your explicit step.

### Debloat set (11 keys)

`StatisticsReporting=0`, `CrashesReporting=0`, `BackgroundModeEnabled=0`,
`YandexAutoLaunchMode=2 (never)`, `YandexAliceMsgDisable=1`, `NeuroNtpTools=0`,
`NtpNotificationsDisable=1`, `YandexButtonDisable=1`, `SearchSuggestEnabled=0`,
`UpdateAllowed=0`, `BackgroundUpdateAllowed=0`.

### 3-don't-touch (never disabled here)

- `SafeBrowsingProtectionLevel` — phishing/malware protection stays on
- `ComponentUpdatesEnabled` / `--disable-component-update` — disabling breaks Widevine/DRM
- Security updates beyond the `UpdateAllowed` rationale — `UpdateAllowed=0` only stops the
  browser overwriting this portable tree in place; you re-install deliberately from the
  releases (pinned by `version.txt`). Component updates keep running.

These are pinned by `.github/workflows/validate.yml`.

## State CA note

**We bundle no certificates** — no state CA, no custom roots, nothing added to the trust
store. If you want to trust an extra CA (corporate proxy, national root), do it yourself
and know the risk (see nixpkgs `knownVulnerabilities` for why shipping state roots is a
bad default).

## Update

Run `Yandex\update.bat` — it fetches the latest official release of this package, stops
`browser.exe`, copies over the protected files (`chrome++.ini`, `update.bat`,
`debloater.reg`, `version.txt` — `Data\` and `Cache\` are never touched), migrates a
versioned `WidevineCdm` folder to the flat exe-dir path, re-applies policies and
re-checks EME/Widevine.

## Building

`build-yandex.ps1` is the CI/local builder: it extracts the official `Yandex.exe`
payload (7z branch, silent-install fallback), lays out the package, seeds the
preseeded profile, trims the vendor bloat (below), strips the self-updater and writes
`layout-manifest.txt`. It ships at the package root so `update.bat` can reuse it for
rebuilds.

### Trimmed vendor files

Measured per group against the untrimmed baseline (page dump + WebGL + Widevine EME all
still alive), so only the safe groups are removed — the Flutter component directory is
**never** touched because it was measured broken:

| Group | Removed | Measured saving |
|---|---|---|
| A | root-level `clidmgr.exe`, `browser_proxy.exe`, `clids_*.xml` | 2 872 078 B |
| C | every `voiceactivation\` tree | 1 427 748 B |
| D | every `web_app_config\` tree | 934 475 B |
| E | `Yandex\Locales\*.pak` except `en-US.pak` | 8 826 180 B |

**~14.06 MB of a 515 MB payload (2.73 %).** Evidence:
[`docs/issue1-claims-findings.md`](docs/issue1-claims-findings.md) (T3).

Rebuilders can opt out with `-KeepVendorBloat`, which trims nothing and records
`trim: skipped -KeepVendorBloat` in `layout-manifest.txt` — useful when bisecting a
vendor-file problem.

Three caveats, all deliberate:

- **The trim is BUILD-TIME only.** `update.bat` rebuilds into a temp directory and copies
  over **without deleting**, so an install that has already been updated keeps its
  `clidmgr.exe` and its extra locale `.pak` files. **The 14 MB figure applies to fresh
  installs only**; re-extract a new release (or delete those files by hand) to get it back.
- **Group E keeps non-`.pak` files in `Locales\`.** The T3 probe deleted every child that
  was not `en-US.pak`; the builder keeps any non-`.pak` file. The measured failure mode
  for a too-aggressive locale trim is "missing UI strings in a non-English locale", not a
  broken browser, so the safer side was chosen.
- **Group A is root-level only.** A versioned `Yandex\<ver>\clidmgr.exe` is never trimmed,
  because no measurement ever proved a versioned copy safe.

CI lives in `.github/workflows/`:

| Workflow | Purpose |
|---|---|
| `validate.yml` | Pins on every push: required files, 11-key + exact-count debloater pins, never-touch guards, `chrome++.ini` portability, workflow-file pins |
| `build.yml` | check → build → release: resolves winget `PackageVersion`, builds the package plus `launcher.exe` and its findings gate doc into it, publishes `yandex-portable_<ver>.zip` only when that tag has no release yet (hourly + manual) |
| `smoke.yml` | Verdict job on `windows-latest`: layout asserts, 11/11 keys on `browser://policy`, EME probe (WARN on the known baseline), full `update.bat` e2e with protected-hash asserts, shipped-`launcher.exe` phase → `Result: PASSED` |

Local test suites, all green on every push via `validate.yml`:

| Suite | Assertions | Covers |
|---|---|---|
| `pwsh -NoProfile -File tests/build-yandex.tests.ps1` | 187 | extract/layout, preseed, updater strip, flat CDM, the vendor trim (groups A/C/D/E + `-KeepVendorBloat`) and the build/smoke/doc invariants |
| `pwsh -NoProfile -File tests/update.tests.ps1` | 90 | `update.bat` version resolve, copy-over with protected-path hash asserts, `Data\` immutability, debloater re-import |
| `pwsh -NoProfile -File tests/claims.tests.ps1` | 107 | the issue #1 claim-probe harness |

`cd launcher && go vet ./... && go test ./...` covers the Go launcher.
