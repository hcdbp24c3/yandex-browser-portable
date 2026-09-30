# Issue #1 claims — empirical findings (feature `yandex-issue1-claims-test`)

**Status: RUN COMPLETE (Tasks 1–2)** — every `T<n> verdict:` line below is
copied verbatim from a successful `claims.yml` run log (T1–T8 from run
36664258871, T9 from run 36785388609).
The §1–§8 verdict column and the Corrections/Owner-decisions sections stay
`PENDING` until Task 3 aggregates T1–T9 into issue verdicts.

- Repo: `hcdbp24c3/yandex-browser-portable`, branch `main`
- Workflow: `.github/workflows/claims.yml`, dispatch input `test=all` (T1–T9)
- Source run: https://github.com/hcdbp24c3/yandex-browser-portable/actions/runs/36664258871
  (`completed success`, 26 `T[1-8] verdict:` lines in the log, ≥8 required)
- Probe-development runs: 36661822112 and 36663223628 (both `success`) — these
  exposed two probe defects which were fixed test-first: T6 `File.Replace($null)`
  empty-path binding, and T8's wrong `navigator.language in (en*)` expectation
  (negotiated `lang=ru` on an en-US-only tree with a fully rendered page; the
  judge now assesses the render, not the language tag). The final run contains
  the corrected probes.
- Method: one `windows-latest` job, ordered T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T1
  (T1 writes HKCU and must run last so a leak cannot contaminate the others;
  T9 runs before T1 for the same reason). T9 additionally needs Go, installed
  by a `setup-go` step that only runs when T9 is selected.
  A probe `FAIL` is a finding, not a workflow failure: the job only fails when a
  selected probe emitted no verdict line or the shared source install failed.

## Verdict table (issue sections §1–§8)

| Issue section | Claim (short) | Verdict | Probes |
|---|---|---|---|
| §1 Global multi-language support | bilingual (EN/RU) everywhere | PENDING | T8 |
| §2 Upstream base → Corporate/Enterprise | switch to Corporate edition | PENDING | T4 |
| §3 Radical payload trimming (~26 files) | strip to 26 essential files | PENDING | T3 |
| §4 Portable DLL redirection (`version.dll`) | side-by-side DLL relocates Data/Cache | PENDING | spike P2 (prior evidence) |
| §5 Non-admin HKCU policies | HKCU\Software\Policies honored | PENDING | T1, T2 |
| §6 Deep profile preseed | preseeded `Preferences`/`Local State` keys exist | PENDING | T5, T6 |
| §7 Automated profile & cache maintenance | cache/crashpad pruning is safe | PENDING | T7 |
| §8 Native Go launcher, bilingual | mutex + HKCU lifecycle + prune (MVP mechanics) | PENDING | T9 (Task 2, run 36785388609) |

Verdict vocabulary for the final table (Task 3): `CONFIRMED` / `PARTIALLY-TRUE` /
`REFUTED` / `SCOPE-REJECTED`.

## Verdict lines (verbatim from the run log)

Run 36664258871, `Verify verdicts` step (probe-side copies are identical):

```
T2 verdict: 5 of 9 claimed names fabricated; 461 policies; all class=Both
T3 verdict: SAFE - group A; broken=(); saved=2872078 bytes of 515092109; dump OK->OK; webgl OK->OK; eme OK (baseline OK); deleted=D:\a\_temp\claims\trees\gA\Yandex\clidmgr.exe,D:\a\_temp\claims\trees\gA\Yandex\browser_proxy.exe,D:\a\_temp\claims\trees\gA\Yandex\clids_yandex_second.xml,D:\a\_temp\claims\trees\gA\Yandex\clids_yandex.xml; absent=none
T3 verdict: BROKEN - group B; broken=(Dump,Webgl,Eme); saved=14936976 bytes of 515092109; dump OK->BROKEN; webgl OK->BROKEN; eme NO_RESULT (baseline OK); deleted=D:\a\_temp\claims\trees\gB\Yandex\26.8.4.893\widgets; absent=none
T3 verdict: SAFE - group C; broken=(); saved=1427748 bytes of 515092109; dump OK->OK; webgl OK->OK; eme OK (baseline OK); deleted=D:\a\_temp\claims\trees\gC\Yandex\26.8.4.893\voiceactivation; absent=none
T3 verdict: SAFE - group D; broken=(); saved=934475 bytes of 515092109; dump OK->OK; webgl OK->OK; eme OK (baseline OK); deleted=D:\a\_temp\claims\trees\gD\Yandex\26.8.4.893\web_app_config; absent=none
T3 verdict: SAFE - group E; broken=(); saved=8826180 bytes of 515092109; dump OK->OK; webgl OK->OK; eme OK (baseline OK); deleted=cs_FEMININE.pak,cs_MASCULINE.pak,cs_NEUTER.pak,cs.pak,de_FEMININE.pak,de_MASCULINE.pak,de_NEUTER.pak,de.pak,en-US_FEMININE.pak,en-US_MASCULINE.pak,en-US_NEUTER.pak,es_FEMININE.pak,es_MASCULINE.pak,es_NEUTER.pak,es.pak,fr_FEMININE.pak,fr_MASCULINE.pak,fr_NEUTER.pak,fr.pak,it_FEMININE.pak,it_MASCULINE.pak,it_NEUTER.pak,it.pak,ja_FEMININE.pak,ja_MASCULINE.pak,ja_NEUTER.pak,ja.pak,kk_FEMININE.pak,kk_MASCULINE.pak,kk_NEUTER.pak,kk.pak,pt-BR_FEMININE.pak,pt-BR_MASCULINE.pak,pt-BR_NEUTER.pak,pt-BR.pak,pt-PT_FEMININE.pak,pt-PT_MASCULINE.pak,pt-PT_NEUTER.pak,pt-PT.pak,ru_FEMININE.pak,ru_MASCULINE.pak,ru_NEUTER.pak,ru.pak,tr_FEMININE.pak,tr_MASCULINE.pak,tr_NEUTER.pak,tr.pak,uk_FEMININE.pak,uk_MASCULINE.pak,uk_NEUTER.pak,uk.pak,uz_FEMININE.pak,uz_MASCULINE.pak,uz_NEUTER.pak,uz.pak,zh-CN_FEMININE.pak,zh-CN_MASCULINE.pak,zh-CN_NEUTER.pak,zh-CN.pak,zh-TW_FEMININE.pak,zh-TW_MASCULINE.pak,zh-TW_NEUTER.pak,zh-TW.pak; absent=none
T3 verdict: BROKEN - groups B broke a capability vs baseline; per-group lines above; saved: A=2872078B, B=14936976B, C=1427748B, D=934475B, E=8826180B; baselineBytes=515092109
T4 verdict: PUBLIC-ENDPOINT https://download.cdn.yandex.net/browser/corporate/YandexBrowser.admx (HTTP 200)
T5 verdict: neuro_question=ABSENT, video_button_enabled=ABSENT, show_ya_button=PRESEEDED, app_side_promo_service_enabled=PRESEEDED, alissenger=PRESEEDED, default_apps_installed=PRESEEDED; first-run: 6 EXIST (0 materialized, 4 preseeded, 0 lost, 2 absent)
T6 verdict: PASS - atomic .tmp+File.Replace accepted: probe key read back after relaunch, JSON valid, no leftovers (dir Preferences files: Preferences)
T7 verdict: PASS - rule: relaunch ok + >=1 dir recreated + no missing GPUCache/Default\Cache (event-driven dirs reported only); relaunch=ok; recreated=ShaderCache,GrShaderCache,Default\Cache,Default\Code Cache,Crashpad; missing=none; event-driven=none; critical-missing=none
T8 verdict: PASS - rendered with lang=ru (negotiation is profile/OS-level; en-US-only pak trim keeps the render); domBytes=722 (source=reused T3-E tree; Locales=[en-US.pak])
T1 verdict: IGNORED - YandexAliceMsgDisable, Telemetry absent from chrome://policy after HKCU reg add (via=uia bytes=10269)
```

T9 (run 36785388609, `test=t9`):

```
T9 verdict: PASS - mode=skip(IGNORED); policy skipped (T1 IGNORED), HKCU untouched; version.dll preferred, explicit fallback flags when it is set aside; mutex+start-twice forward, prune stale+fresh, EN/RU settings, selftest exit 0
```

All lines above are byte-identical to the run log (the T3 group-E line alone
carries the 63 deleted non-en-US paks: `en-US.pak` is kept, the three
`en-US_{FEMININE,MASCULINE,NEUTER}.pak` variants and 15 other languages x
(base + 3 gender variants) are removed).

---

## T1 — HKCU policy honored at runtime (issue §5)

**Verdict: IGNORED** — after `reg add` of `YandexAliceMsgDisable=1` and
`Telemetry=1` under `HKCU\Software\Policies\YandexBrowser`, neither name
appeared in `chrome://policy/` (UIA dump 10269 bytes; the `finally` cleanup
removed both values and the key). The probe does not claim why — chrome://policy
may refresh asynchronously or the page may list only a subset — but the issue §5
"HKCU values are honored at runtime" claim was NOT observed for these two keys.

Procedure: fresh tree → `reg add HKCU\Software\Policies\YandexBrowser` with
`YandexAliceMsgDisable=1` and `Telemetry=1` (REG_DWORD) → headed launch with
`chrome://policy/` as the startup URL and `--force-renderer-accessibility` →
Windows UIA dump (`probe/uia-dump.ps1`, spike H4/H5 path; CDP is Forbidden on
WebUI targets) → `HONORED` when both names are listed, `IGNORED` when absent →
`finally`: delete both values and the key, log proof of removal.

## T2 — ADMX audit of issue §5 key names (Discovery re-run in CI)

**Verdict: `5 of 9 claimed names fabricated; 461 policies; all class=Both`** —
independently re-confirmed in CI (same result as local Discovery).

Local Discovery evidence (2026-09-29, re-verified by T2 in CI for reproducibility):
`https://download.cdn.yandex.net/browser/corporate/YandexBrowser.admx` is UTF-16LE,
**461 `<policy>` elements, all `class="Both"`** (both Machine + User, i.e. HKCU is
plausible — runtime proof is T1). Issue §5 cites exactly 9 key names:
**4 EXIST** (`SpellCheckServiceEnabled`, `AutofillCreditCardEnabled`,
`AutofillAddressEnabled`, `DefaultSearchProviderEnabled`) and **5 are fabricated**
(`MetricsReportingEnabled`, `YandexAliceEnabled`, `FeedbackAllowed`,
`PromotionalTabsEnabled`, `BrowserAddPersonEnabled`). All 11 shipped names
(`StatisticsReporting`, `CrashesReporting`, `BackgroundModeEnabled`,
`YandexAutoLaunchMode`, `YandexAliceMsgDisable`, `NeuroNtpTools`,
`NtpNotificationsDisable`, `YandexButtonDisable`, `SearchSuggestEnabled`,
`UpdateAllowed`, `BackgroundUpdateAllowed`) are present. Real counterparts:
telemetry → `StatisticsReporting`/`Telemetry`/`TelemetrySelective`; Alice → only
`YandexAliceMsgDisable`.

## T3 — Trim-group safety (issue §3)

**Verdict: BROKEN — group B (`widgets\`) broke a capability vs baseline;
groups A, C, D, E SAFE.** Per-group results (baseline 515,092,109 bytes):

| Group | Trim | Verdict | Broken | Saved |
|---|---|---|---|---|
| A | `clidmgr.exe`, `browser_proxy.exe`, `clids_*.xml` | SAFE | — | 2,872,078 B |
| B | `widgets\` | **BROKEN** | Dump, WebGL, EME (NO_RESULT) | 14,936,976 B |
| C | `voiceactivation\` | SAFE | — | 1,427,748 B |
| D | `web_app_config\` | SAFE | — | 934,475 B |
| E | `Locales\` keep `en-US.pak` | SAFE | — | 8,826,180 B |

Group E is kept for T8. This MEASURES safety only; adopting a trim step into the
builder is a separate owner decision (plan Non-Goals).

Baseline capability capture on a throwaway copy (page capture, WebGL, EME vs the
spike-P4 `CDM_FAIL` baseline), then one fresh copy per group —
A: `clidmgr.exe`+`browser_proxy.exe`+`clids_*.xml`, B: `widgets\`,
C: `voiceactivation\`, D: `web_app_config\`, E: `Locales` keep only `en-US.pak` —
each trimmed, re-probed and compared to baseline (`SAFE`/`BROKEN` + bytes saved).
Group E is kept for T8. This MEASURES safety only; adopting a trim step into the
builder is a separate owner decision (plan Non-Goals).

## T4 — Corporate availability (issue §2)

**Verdict: `PUBLIC-ENDPOINT https://download.cdn.yandex.net/browser/corporate/YandexBrowser.admx (HTTP 200)`** —
the ADMX template is publicly fetchable; the MSI/exe candidates returned 404 and
the support landing page 404'd (as locally observed). A 404 alone is never
stated as proof of login-gating.

Probes 3 corporate CDN candidates under `download.cdn.yandex.net/browser/corporate/`
plus the public landing page `https://yandex.com/support/browser/business/en/`
(HEAD, GET fallback, installer-like hrefs grepped from the landing page).
A 404 alone is **never** stated as proof of login-gating; the verdict only records
what was observed, alongside prior research (Corporate MSI is login-gated).

## T5 — Preseed key existence after first run (issue §6)

**Verdict: `6 EXIST (0 materialized, 4 preseeded, 0 lost, 2 absent)`** —
`show_ya_button`, `app_side_promo_service_enabled`, `alissenger`,
`default_apps_installed` PRESEEDED (written by our preseed, survived first run);
`neuro_question`, `video_button_enabled` ABSENT (never seen before or after the
launch); nothing MATERIALIZED on its own, nothing LOST.

Fresh builder layout → headed launch so the first-run NTP opens naturally →
graceful close → diff `Data\Default\Preferences` + `Data\Local State` before vs
after for the exact issue-named keys: `neuro_question`, `video_button_enabled`,
`show_ya_button`, `app_side_promo_service_enabled`, `alissenger`,
`default_apps_installed` (status `ABSENT`/`PRESEEDED`/`MATERIALIZED`/`LOST`).

## T6 — Atomic write acceptance (issue §6/#7 support)

**Verdict: PASS** — probe key written via `.tmp` + `File.Replace` was read back
after relaunch, JSON valid, and no Preferences-derived leftovers remained.

Corruption leftovers are scoped to names derived from `Preferences` itself
(`Preferences.tmp`/`.bak`/`-journal`): the browser's own SQLite sidecars
(`History-journal`, `Web Data-journal`, …) in the same folder are normal and are
not treated as corruption (run 1/2 learned this the hard way — T6's first green
run flagged every sqlite journal as a false FAIL).

## T7 — Cache prune safety (issue §7)

**Verdict: PASS** — relaunch ok, `ShaderCache`, `GrShaderCache`,
`Default\Cache`, `Default\Code Cache`, `Crashpad` recreated; no missing
launch-critical dirs; event-driven dirs reported only.

Warm-up launch → delete `GPUCache`, `ShaderCache`, `GrShaderCache`, `DawnCache`,
`Default\Cache`, `Default\Code Cache`, `Default\Service Worker\CacheStorage`,
`Crashpad`, `BrowserMetrics-*` → relaunch + dump. Rule: PASS needs relaunch OK,
≥1 dir recreated and no missing launch-critical dir (`GPUCache`, `Default\Cache`);
event-driven dirs (`Crashpad`, `BrowserMetrics-*`) are reported but never fail the
probe by themselves.

## T8 — Locale trim render check (issue §1)

**Verdict: PASS** — `rendered with lang=ru (negotiation is profile/OS-level;
en-US-only pak trim keeps the render); domBytes=722` on the reused T3-E tree
(`Locales=[en-US.pak]`).

The probe judges the RENDER (body marker + readable `navigator.language` + the
en-US-only precondition), not the language tag: run 1 showed `lang=ru` with a
fully rendered page and no `accept_languages` preseed — the negotiated language
comes from profile/OS, unaffected by pak trimming.

## T9 — Native Go launcher MVP (issue §4/§7/§8)

**Verdict: PASS** (run 36785388609) — `mode=skip(IGNORED); policy skipped
(T1 IGNORED), HKCU untouched; version.dll preferred, explicit fallback flags
when it is set aside; mutex+start-twice forward, prune stale+fresh, EN/RU
settings, selftest exit 0`.

Scope: MVP **mechanics only** — single-instance mutex, the ephemeral HKCU
policy lifecycle, the portable launch plan, the T7 cache prune and EN/RU
output. No GUI framework, and the launcher is deliberately NOT added to the
release zip (packaging is Task 3's owner question).

### Delivery mechanism (T1 → T9)

`docs/issue1-claims-findings.md` is the named single source of truth. The
launcher parses the `T1 verdict:` line out of this file (`launcher/mode.go`,
line-anchored regex so the evidence table cannot match it):

| T1 verdict | launcher mode | effect |
|---|---|---|
| `HONORED` | `hkcu` | the 11 `debloater.reg` values are written to `HKCU\Software\Policies\YandexBrowser` for the run and removed on exit |
| anything else (`IGNORED`, `FAIL`, …) | `skip - <exact T1 line>` | nothing is written to HKCU at all |
| file or `T1 verdict:` line missing | — | selftest fails: Task 1 incomplete |

With the T1 verdict on record (`IGNORED`, run 36664258871) the run exercises
the **skip** path. Verbatim from the log:

```
detail: T9: T1 verdict=IGNORED -> launcher mode=skip(IGNORED)
detail: T9: [selftest-dll] mode: skip - T1 verdict: IGNORED - YandexAliceMsgDisable, Telemetry absent from chrome://policy after HKCU reg add (via=uia bytes=10269)
```

HKCU stayed untouched: the driver snapshots
`HKCU\Software\Policies\YandexBrowser` before the first run and after the last
and asserts every one of the 11 names has the same presence and the same
value in both (`detail: T9: HKCU left untouched in skip mode`). The apply
path is not exercised on the runner because T1 has not earned it; it stays
covered by Go unit tests over an in-memory `RegistryView` seam — apply →
verify → cleanup, pre-existing value restored, foreign values untouched, and
rollback on a mid-apply failure.

### What the run proved (verbatim stage lines)

| Claim (issue §) | Evidence from run 36785388609 |
|---|---|
| §8 single instance | `mutex: acquired Global\YandexPortable_SingleInstance`; start-twice: `mutex: held by another instance` → `forward: url delivered to the running instance (https://example.test/from-second)` → primary logged `selftest: hold received url https://example.test/from-second`. Both invocations exited 0. |
| §4 portable launch | `launch: version.dll next to browser.exe - portable Data/Cache redirection`. With the DLL set aside: `launch: version.dll missing - fallback flags: --user-data-dir …\Data --disk-cache-dir …\Cache`. The package did ship `version.dll` this run, so the DLL-present plan is the real one. |
| §7 cache prune | `prune: state.json age 216h0m0s >= 168h0m0s - executing` → `prune: executed - removed 1 dir(s): GPUCache` → `prune: state.json written`. The immediate rerun took the fast path: `prune: state.json age 0s < 168h0m0s - fast skip`. |
| §8 bilingual | `--settings --lang en` → `language: en` / `hkcu-mode: skip - T1 verdict: …`; `--lang ru` → `настройки:` / `язык: ru` / `hkcu-режим: …`. Neither touched the mutex or the registry. |
| §8 selftest | every launcher invocation printed `selftest: ok - all checks passed` and exited 0. |

The prune list in `launcher/prune.go` is exactly T7's delete list
(`GPUCache`, `ShaderCache`, `GrShaderCache`, `DawnCache`, `Default/Cache`,
`Default/Code Cache`, `Default/Service Worker/CacheStorage`, `Crashpad`, plus
`BrowserMetrics*`), and the driver independently asserts `debloater.reg`
yields exactly 11 dwords and that none of the 3-don't-touch names
(`SafeBrowsingProtectionLevel`, `ComponentUpdatesEnabled`) reaches the
launcher.

### Defect this task found and fixed (launcher-only)

Run 36783446605 emitted `T9 verdict: FAIL - launcher 'selftest-dll' did not
exit within 60s` — the first `--dry-run` selftest never returned and printed
nothing. `lock_windows_test.go` (build-tagged `windows`) reproduced it on the
runner and the stack dump named the cause: `stop()` called
`windows.CloseHandle` on the pipe handle while the serving goroutine sat in a
**synchronous** `ConnectNamedPipe` on that same handle (`0x1dc` in both
frames). `CloseHandle` does not return until the pending I/O finishes, and
because the call was made while holding `l.mu` it deadlocked every other
method on that lock too — so `Run`'s deferred `stop()` never returned and the
process never reached `os.Exit`. That is exactly the shape of the claim under
test: a `--dry-run` selftest that never connects to the pipe could never shut
down. Fixed by releasing `l.mu` before touching the handle and issuing
`CancelIoEx` + `CloseHandle` from a background goroutine (`CancelIoEx`, not
`CancelIo`: it cancels the connect issued by the serving goroutine's thread).
`go test ./...` on `windows-latest` went from a 10-minute panic timeout to
1.6 s.

---

## Evidence / run links

Source run for every row: [claims run 36664258871](https://github.com/hcdbp24c3/yandex-browser-portable/actions/runs/36664258871)
(`completed success`, workflow `.github/workflows/claims.yml`, input `test=all`).

| Probe | Run | Log evidence |
|---|---|---|
| T1 | 36664258871 | `T1 verdict: IGNORED - ... (via=uia bytes=10269)` |
| T2 | 36664258871 | `T2 verdict: 5 of 9 claimed names fabricated; 461 policies; all class=Both` |
| T3 | 36664258871 | `T3 verdict: BROKEN - group B; ...` + 4 `SAFE` group lines + summary |
| T4 | 36664258871 | `T4 verdict: PUBLIC-ENDPOINT .../YandexBrowser.admx (HTTP 200)` |
| T5 | 36664258871 | `T5 verdict: neuro_question=ABSENT, ... 6 EXIST (0 materialized, 4 preseeded, 0 lost, 2 absent)` |
| T6 | 36664258871 | `T6 verdict: PASS - atomic .tmp+File.Replace accepted: ...` |
| T7 | 36664258871 | `T7 verdict: PASS - rule: relaunch ok + ...` |
| T8 | 36664258871 | `T8 verdict: PASS - rendered with lang=ru ...; domBytes=722 ...` |
| T9 | 36785388609 | `T9 verdict: PASS - mode=skip(IGNORED); policy skipped (T1 IGNORED), HKCU untouched; version.dll preferred, explicit fallback flags when it is set aside; mutex+start-twice forward, prune stale+fresh, EN/RU settings, selftest exit 0` |

T9 launcher runs (its own dispatch input `test=t9`, same workflow):

| Run | Result | Note |
|---|---|---|
| 36783446605 | `T9 verdict: FAIL` | launcher-only defect: the pipe listener could not be shut down, so the first `--dry-run` selftest hung (60 s) and printed nothing |
| 36784045139 | `T9 verdict: FAIL` | the RED run for `lock_windows_test.go`; the Windows-only test reproduced the hang and its stack dump identified the `CloseHandle`/`ConnectNamedPipe` deadlock |
| 36785388609 | `T9 verdict: PASS` | after the cancellable-shutdown fix; `go test ./...` on the runner 1.6 s (was a 10 m panic timeout) |

Probe-development runs (probe defects found and fixed test-first, same workflow):
36661822112 (T6 `File.Replace($null)` binding crash, T8 `lang=ru` misjudged as
FAIL), 36663223628 (T6 sqlite-journal false positive).

## Corrections to issue #1 (probe-backed)

PENDING (Task 3 aggregates after T1–T9).

## Owner decisions

PENDING (Task 3 asks and records; adoptions are implemented in a follow-up feature).
