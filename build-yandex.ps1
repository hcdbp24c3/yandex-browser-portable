param(
    [string]$Installer,
    [switch]$Download,
    [string]$Version,
    [string]$OutDir,
    [switch]$KeepVendorBloat,
    [string]$ChromePlusUrl = 'https://github.com/bibicadotnet/Chromium_SetDLL/releases/download/1.18.2/Chrome.2B.2B_v1.18.2_x86_x64_arm64.7z'
)

<#
    build-yandex.ps1 - Yandex Browser Portable builder (Task 3: extract, layout,
    version.txt, strip updater, spike reconciliation).

    Stages (design section 3, idempotent):
      1. Resolve source  - -Installer <path> (user-supplied) or -Download (CI, public
                           CDN). The winget PackageVersion passed via -Version is the
                           SOLE source of truth for the release tag, zip name and
                           version.txt; a version read back from the binary is a
                           log-only cross-check. -Download builds the CDN candidate
                           URL from -Version (digits joined by _), HEAD-verifies it
                           and falls back to the winget manifest InstallerUrl. Every
                           download is SHA256-verified against the manifest's
                           InstallerSha256 before extraction (hard fail on mismatch).
      2. Extract         - spike P1 branch A (outer exe resource archive: 7z payload
                           of Yandex.exe -> nested browser.7z/BROWSER.PACKED.7Z) and
                           branch B (post-silent-install tree with
                           Installer\browser.7z). Hard-fails naming BOTH branches
                           when neither yields browser.exe.
      3. Layout          - Yandex_Portable\{Yandex\..., Data\, Cache\}; copy
                           chrome++.ini/debloater.reg/update.bat into Yandex\, this
                           script to the package root (update.bat calls
                           $APP_DIR\..\build-yandex.ps1), write version.txt, apply
                           the flat CDM rule (Yandex\WidevineCdm next to
                           browser.exe - Chrome registers the preinstalled CDM only
                           from the exe-dir flat path), place Chrome++ version.dll
                           next to browser.exe with a launch.bat --user-data-dir
                           fallback (spike P2/P2b), trim the vendor groups A/C/D/E
                           that T3 measured SAFE (step 3b; -KeepVendorBloat opts
                           out), then write layout-manifest.txt.
      4. Debloat         - profile preseed: copy preseed/Local State ->
                           Data\Local State, preseed/Preferences ->
                           Data\Default\Preferences, empty "First Run" sentinel
                           -> Data\ (prefs-only path, works without admin -
                           review fix #10; without the sentinel Yandex discards
                           hand-made profile files). debloater.reg itself is
                           applied outside this builder (admin import / CI
                           smoke validation).
      5. Strip updater   - remove service_update.exe / yupdate-exec.exe;
                           UpdateAllowed=0 and BackgroundUpdateAllowed=0 are already
                           carried by debloater.reg.

    Never: SafeBrowsingProtectionLevel, ComponentUpdatesEnabled, component updates
    switched off on the command line (breaks Widevine/DRM), security updates beyond
    the UpdateAllowed rationale, any bundled certificates.
#>

# ------------------------------------------------------------------ helpers --

function Get-CdnCandidateUrl([string]$version) {
    # CDN pattern from the winget manifest (e.g. 26.8.4.893 -> 26_8_4_893);
    # live releases carry an extra _build suffix, so this is only a candidate.
    $flat = $version -replace '\.', '_'
    return "https://download.cdn.yandex.net/browser/int/$flat/en/Yandex.exe"
}

function Test-Url([string]$uri) {
    try {
        $r = Invoke-WebRequest -Uri $uri -Method Head -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5 -ErrorAction Stop
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300)
    }
    catch {
        return $false
    }
}

function Get-WingetManifestUrl([string]$version) {
    return "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/y/Yandex/Browser/$version/Yandex.Browser.installer.yaml"
}

function Read-InstallerSha256([string]$manifestContent) {
    # Pure parser (test seam): winget's InstallerSha256 is the integrity anchor
    # for every download; a manifest without it cannot be trusted.
    if ($manifestContent -notmatch '(?m)^\s*InstallerSha256:\s*([0-9A-Fa-f]{64})\s*$') {
        throw "winget manifest has no InstallerSha256 (64-hex) - cannot verify the Yandex.exe download"
    }
    return $Matches[1].ToUpperInvariant()
}

function Get-ManifestSha256([string]$version) {
    # winget manifest is authoritative for the payload hash (same source as
    # InstallerUrl) - fetched after every download (review fix: SHA256 integrity).
    $manifestUrl = Get-WingetManifestUrl $version
    $manifest = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    try {
        return Read-InstallerSha256 $manifest.Content
    }
    catch {
        throw "winget manifest for $version could not provide InstallerSha256 (checked $manifestUrl): $($_.Exception.Message)"
    }
}

function Assert-InstallerSha256([string]$Path, [string]$ExpectedSha256) {
    # Hard fail on mismatch: a tampered or corrupted payload never reaches layout.
    $expected = $ExpectedSha256.Trim().ToUpperInvariant()
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        throw "SHA256 mismatch for ${Path}: expected $expected, got $actual (winget manifest InstallerSha256) - refusing to use a tampered or corrupted Yandex.exe download"
    }
    return $actual
}

function Resolve-ManifestUrl([string]$version) {
    # winget manifest is authoritative for the exact InstallerUrl (it carries the
    # CDN _build suffix the bare pattern cannot guess).
    $manifestUrl = Get-WingetManifestUrl $version
    $manifest = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    if ($manifest.Content -notmatch '(?m)^\s*InstallerUrl:\s*(\S+)\s*$') {
        throw "winget manifest for $version has no InstallerUrl (checked $manifestUrl)"
    }
    $url = $Matches[1]
    if (-not (Test-Url $url)) {
        Write-Host "note: HEAD did not confirm $url (CDN may reject HEAD) - download will verify it"
    }
    return $url
}

function Invoke-SevenZipExtract([string]$archive, [string]$dest) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    & 7z x $archive "-o$dest" -y | Out-Null
    return ($LASTEXITCODE -le 1)
}

function Find-BrowserRoot([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $exe = Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'browser.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($exe) { return $exe.Directory.FullName }
    return $null
}

function Find-NestedBrowserArchive([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $hit = Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(browser\.7z|browser\.packed\.7z)$' } |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Get-TrimTargetBytes([string]$path) {
    # Byte total of one trim target (file or whole directory) for the
    # bytes-saved accounting. Absent/unreadable targets contribute 0.
    if (-not (Test-Path -LiteralPath $path)) { return [int64]0 }
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return [int64]0 }
    if (-not $item.PSIsContainer) { return [int64]$item.Length }
    [int64]$total = 0
    Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { $total = $total + [int64]$_.Length }
    return $total
}

function Remove-TrimGroup([string]$Root, [string]$Name, [string]$Filter, [switch]$Directory, [switch]$RootOnly) {
    # Removes one target pattern of a T3 trim group and returns the bytes removed.
    # A = root-level clidmgr.exe / browser_proxy.exe / clids_*.xml, exactly the set
    # T3 deleted; C/D = the voiceactivation\ and web_app_config\ directories.
    # C/D discovery is RECURSIVE on purpose: T3 measured the VERSIONED
    # Yandex\<ver>\voiceactivation and Yandex\<ver>\web_app_config, so a
    # root-only lookup would report 'absent' and save 0 bytes on a real tree.
    # Group A stays root-only so the trimmed set is never wider than the set T3
    # actually proved SAFE. An absent target is logged and is never fatal - a
    # consumer build may legitimately not ship it. A locked target is logged and
    # skipped (the build must not die on a running vendor helper).
    $targets = @()
    if ($RootOnly) {
        if ($Directory) {
            $targets = @(Get-ChildItem -LiteralPath $Root -Directory -Filter $Filter -ErrorAction SilentlyContinue)
        }
        else {
            $targets = @(Get-ChildItem -LiteralPath $Root -File -Filter $Filter -ErrorAction SilentlyContinue)
        }
    }
    elseif ($Directory) {
        $targets = @(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Filter $Filter -ErrorAction SilentlyContinue)
    }
    else {
        $targets = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue)
    }
    if ($targets.Count -eq 0) {
        Write-Host "trim: $Name absent $Filter"
        return [int64]0
    }
    [int64]$saved = 0
    foreach ($t in $targets) {
        $bytes = Get-TrimTargetBytes $t.FullName
        Remove-Item -LiteralPath $t.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $t.FullName) {
            Write-Host "trim: $Name FAILED $($t.FullName) (still present after delete)"
            continue
        }
        $saved = $saved + $bytes
        Write-Host "trim: $Name removed $($t.FullName)"
    }
    return $saved
}

function Remove-TrimLocalePaks([string]$Root) {
    # Group E: inside every recursively located Locales\ directory keep
    # en-US.pak and remove the other *.pak files. Non-pak files in Locales\ are
    # deliberately KEPT - T8 measured UI-locale negotiation as profile/OS level,
    # so a missing pak degrades strings in a non-English locale rather than the
    # browser itself (deliberate divergence from T3's "keep only en-US.pak",
    # which removed every non-kept child; recorded as a residual risk).
    [int64]$saved = 0
    $locales = @(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Filter 'Locales' -ErrorAction SilentlyContinue)
    if ($locales.Count -eq 0) {
        Write-Host 'trim: E absent Locales'
        return $saved
    }
    foreach ($loc in $locales) {
        $paks = @(Get-ChildItem -LiteralPath $loc.FullName -File -Filter '*.pak' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'en-US.pak' })
        if ($paks.Count -eq 0) {
            Write-Host "trim: E absent $($loc.FullName)\*.pak"
            continue
        }
        foreach ($pak in $paks) {
            $bytes = [int64]$pak.Length
            Remove-Item -LiteralPath $pak.FullName -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $pak.FullName) {
                Write-Host "trim: E FAILED $($pak.FullName) (still present after delete)"
                continue
            }
            $saved = $saved + $bytes
            Write-Host "trim: E removed $($pak.FullName)"
        }
    }
    return $saved
}

function Resolve-ChromePlusDll([string]$source, [string]$workDir) {
    # spike P2: pinned Chrome++ version.dll (x64) loaded side-by-side with
    # browser.exe relocates Data/Cache per chrome++.ini. Any failure (offline,
    # archive changed) returns $null -> launch.bat fallback.
    try {
        $archive = $null
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $archive = $source
        }
        elseif ($source -match '^https?://') {
            $archive = Join-Path $workDir 'chromeplus.7z'
            Invoke-WebRequest -Uri $source -OutFile $archive -TimeoutSec 180 -UseBasicParsing -ErrorAction Stop
        }
        else {
            Write-Host "Chrome++: version.dll source not found: $source"
            return $null
        }
        $cppDir = Join-Path $workDir 'chromeplus'
        if (-not (Invoke-SevenZipExtract $archive $cppDir)) {
            Write-Host 'Chrome++: version.dll archive could not be extracted'
            return $null
        }
        $candidates = @(Get-ChildItem -LiteralPath $cppDir -Recurse -File -Filter 'version.dll' -ErrorAction SilentlyContinue)
        if ($candidates.Count -eq 0) {
            Write-Host 'Chrome++: version.dll missing from archive'
            return $null
        }
        $x64 = @($candidates | Where-Object { $_.FullName -match '[\\/]x64[\\/]' })
        if ($x64.Count -gt 0) { $pick = $x64[0] } else { $pick = $candidates[0] }
        Write-Host "Chrome++: version.dll candidate $($pick.FullName)"
        return $pick.FullName
    }
    catch {
        Write-Host "Chrome++: version.dll unavailable ($($_.Exception.Message))"
        return $null
    }
}

# Dot-source (tests) loads only the functions above; a direct run continues.
if ($MyInvocation.InvocationName -eq '.') { return }

# ------------------------------------------------------------ stage 1: source

if ($Download) {
    if (-not $Version) {
        Write-Error '-Download requires -Version <winget PackageVersion> (sole source of truth for tag/zip/version.txt)'
        exit 1
    }
    $candidate = Get-CdnCandidateUrl $Version
    if (Test-Url $candidate) {
        $installerUrl = $candidate
        Write-Host "stage 1: InstallerUrl from CDN pattern: $installerUrl"
    }
    else {
        Write-Host "stage 1: CDN candidate not live (HEAD failed): $candidate - falling back to winget manifest"
        try {
            $installerUrl = Resolve-ManifestUrl $Version
        }
        catch {
            Write-Error "stage 1: cannot resolve InstallerUrl for version $Version - $($_.Exception.Message)"
            exit 1
        }
        Write-Host "stage 1: InstallerUrl from winget manifest: $installerUrl"
    }
    $downloaded = Join-Path ([IO.Path]::GetTempPath()) ("Yandex-" + $Version + ".exe")
    Write-Host "stage 1: downloading $installerUrl -> $downloaded"
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $downloaded -TimeoutSec 900 -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Error "stage 1: download failed: $($_.Exception.Message)"
        exit 1
    }
    # Integrity: every download is verified against the winget manifest's
    # InstallerSha256 (review fix) - mismatch aborts the build.
    try {
        $expectedSha = Get-ManifestSha256 $Version
        $null = Assert-InstallerSha256 -Path $downloaded -ExpectedSha256 $expectedSha
    }
    catch {
        Write-Error "stage 1: SHA256 verification failed: $($_.Exception.Message)"
        exit 1
    }
    Write-Host "stage 1: SHA256 verified against winget manifest InstallerSha256 ($expectedSha)"
    $Installer = $downloaded
}
else {
    if (-not $Installer) {
        Write-Error 'pass -Installer <Yandex.exe | silent-install dir> or -Download -Version <winget PackageVersion>'
        exit 1
    }
    if (-not (Test-Path -LiteralPath $Installer)) {
        Write-Error "stage 1: installer path not found: $Installer"
        exit 1
    }
    Write-Host "stage 1: Installer=$Installer"
}

if (-not $Version) {
    Write-Error 'pass -Version <winget PackageVersion> (winget PackageVersion is the sole version source of truth)'
    exit 1
}

if (-not $OutDir) { $OutDir = Join-Path (Get-Location).Path 'Yandex_Portable' }
$OutDir = [IO.Path]::GetFullPath($OutDir)
Write-Host "stage 1: version=$Version OutDir=$OutDir"

if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    Write-Error 'stage 2: 7z not found in PATH - install p7zip/7-Zip first'
    exit 1
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('yandex-build-' + [guid]::NewGuid().ToString('N'))
$exitCode = 0

try {
    # ------------------------------------------------------- stage 2: extract
    $appRoot = $null

    if (Test-Path -LiteralPath $Installer -PathType Container) {
        # Branch B - post-silent-install tree: Installer\browser.7z
        Write-Host "stage 2: branch B (post-silent-install) - scanning $Installer for Installer\browser.7z"
        $nested = Find-NestedBrowserArchive $Installer
        if ($nested -and (Invoke-SevenZipExtract $nested (Join-Path $work 'app'))) {
            $appRoot = Find-BrowserRoot (Join-Path $work 'app')
        }
        if (-not $appRoot) {
            $appRoot = Find-BrowserRoot $Installer
        }
    }
    else {
        # Branch A - outer exe resource archive (spike P1 verdict: PASS, branch A)
        Write-Host "stage 2: branch A (outer exe resource archive) - opening payload of $Installer"
        $outer = Join-Path $work 'outer'
        if (Invoke-SevenZipExtract $Installer $outer) {
            $appRoot = Find-BrowserRoot $outer
            if (-not $appRoot) {
                $nested = Find-NestedBrowserArchive $outer
                if ($nested -and (Invoke-SevenZipExtract $nested (Join-Path $work 'app'))) {
                    $appRoot = Find-BrowserRoot (Join-Path $work 'app')
                }
            }
        }
        else {
            Write-Host "stage 2: branch A could not open the archive - will report both branches if nothing matches"
        }
    }

    if (-not $appRoot) {
        Write-Error ("build-yandex.ps1: no browser.exe found - neither extraction branch matched. " +
            "Branch A (outer exe resource archive): the Yandex.exe payload is a 7z archive containing a nested browser.7z/BROWSER.PACKED.7Z. " +
            "Branch B (post-silent-install): a silent-install tree containing Installer\browser.7z. " +
            "Pass -Installer <Yandex.exe | install dir> that contains one of them.")
        exit 1
    }
    Write-Host "stage 2: app root = $appRoot"

    # --------------------------------------------------------- stage 3: layout
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    $yandexDir = Join-Path $OutDir 'Yandex'
    if (Test-Path -LiteralPath $yandexDir) {
        Remove-Item -LiteralPath $yandexDir -Recurse -Force   # idempotent rebuild; Data\ and Cache\ are kept
    }
    New-Item -ItemType Directory -Path $yandexDir -Force | Out-Null

    Get-ChildItem -LiteralPath $appRoot -Force | Copy-Item -Destination $yandexDir -Recurse -Force

    # Flat CDM rule: Chrome registers the preinstalled WidevineCdm only from the
    # exe-dir flat path - any versioned Yandex\<ver>\WidevineCdm nesting is dead.
    $flatCdm = Join-Path $yandexDir 'WidevineCdm'
    $nestedCdm = @(Get-ChildItem -LiteralPath $yandexDir -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'WidevineCdm' -and $_.FullName -ne $flatCdm })
    foreach ($n in $nestedCdm) {
        if (-not (Test-Path -LiteralPath $flatCdm)) {
            Move-Item -LiteralPath $n.FullName -Destination $flatCdm
        }
        else {
            Get-ChildItem -LiteralPath $n.FullName | Move-Item -Destination $flatCdm -Force
            Remove-Item -LiteralPath $n.FullName -Recurse -Force
        }
        Write-Host "stage 3: WidevineCdm moved to flat Yandex\WidevineCdm (exe-dir rule)"
    }
    $badCdm = @(Get-ChildItem -LiteralPath $yandexDir -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'WidevineCdm' -and $_.FullName -ne $flatCdm })
    if ($badCdm.Count -gt 0) {
        Write-Error "stage 3: versioned WidevineCdm nesting still present after layout ($($badCdm[0].FullName)) - aborting"
        exit 1
    }

    # ------------------------------------------- stage 3b: trim vendor bloat
    # Groups A, C, D and E were measured SAFE against the baseline (page dump,
    # WebGL and Widevine EME all alive) by T3 in probe/claims/t-trim.ps1 (run
    # 36664258871, verdicts recorded in docs/issue1-claims-findings.md); group B
    # was measured BROKEN, so the Flutter component directory is never a trim
    # target. C/D sit under the versioned Yandex\<ver>\ dir on a real tree,
    # which is why they are discovered recursively, while A is trimmed at the
    # app-dir root only - exactly the paths T3 deleted. This stage runs AFTER the
    # flat-CDM move so CDM layout and detection stay unaffected.
    # -KeepVendorBloat reverts to the untrimmed vendor tree.
    $trimLines = @()
    if ($KeepVendorBloat) {
        $trimLines += 'trim: skipped -KeepVendorBloat'
        Write-Host 'trim: skipped (KeepVendorBloat) - vendor tree left exactly as shipped'
    }
    else {
        [int64]$trimSaved = 0
        $trimSaved = $trimSaved + (Remove-TrimGroup -Root $yandexDir -Name 'A' -Filter 'clidmgr.exe' -RootOnly)
        $trimSaved = $trimSaved + (Remove-TrimGroup -Root $yandexDir -Name 'A' -Filter 'browser_proxy.exe' -RootOnly)
        $trimSaved = $trimSaved + (Remove-TrimGroup -Root $yandexDir -Name 'A' -Filter 'clids_*.xml' -RootOnly)
        $trimSaved = $trimSaved + (Remove-TrimGroup -Root $yandexDir -Name 'C' -Filter 'voiceactivation' -Directory)
        $trimSaved = $trimSaved + (Remove-TrimGroup -Root $yandexDir -Name 'D' -Filter 'web_app_config' -Directory)
        $trimSaved = $trimSaved + (Remove-TrimLocalePaks -Root $yandexDir)
        $trimLines += 'trim: groups=A,C,D,E'
        $trimLines += "trim: bytes_saved=$trimSaved"
        Write-Host "trim: groups A,C,D,E - bytes saved: $trimSaved"
    }

    foreach ($f in 'chrome++.ini', 'debloater.reg', 'update.bat') {
        # Shipped packages carry these inside Yandex\ already (and the update
        # flow treats them as protected), so a missing source here is expected
        # when rebuilding from an extracted package - not an error.
        $src = Join-Path $PSScriptRoot $f
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $yandexDir -Force
        }
    }

    # update.bat invokes $APP_DIR\..\build-yandex.ps1 - ship this script at the
    # package root, as a sibling of Yandex\.
    $selfDest = Join-Path $OutDir 'build-yandex.ps1'
    if ($selfDest -ne $PSCommandPath) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $selfDest -Force
    }

    # version.txt - winget PackageVersion from the caller, never binary-parsed.
    Set-Content -Path (Join-Path $yandexDir 'version.txt') -Value $Version

    $browserExe = Join-Path $yandexDir 'browser.exe'
    if (-not (Test-Path -LiteralPath $browserExe)) {
        Write-Error "stage 3: browser.exe missing in $yandexDir - aborting"
        exit 1
    }
    try {
        $binaryVersion = (Get-Item -LiteralPath $browserExe).VersionInfo.FileVersion
    }
    catch {
        $binaryVersion = ''
    }
    if ($binaryVersion) {
        Write-Host "stage 3: cross-check binary version=$binaryVersion (log only; version.txt stays winget PackageVersion $Version)"
    }
    else {
        Write-Host "stage 3: cross-check binary version unavailable (log only; version.txt stays winget PackageVersion $Version)"
    }

    New-Item -ItemType Directory -Path (Join-Path $OutDir 'Data') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $OutDir 'Cache') -Force | Out-Null

    # Chrome++ branch (spike P2 PASS): version.dll next to browser.exe, else the
    # launch.bat --user-data-dir fallback (Tensionix precedent).
    $dll = Resolve-ChromePlusDll $ChromePlusUrl $work
    if ($dll) {
        Copy-Item -LiteralPath $dll -Destination (Join-Path $yandexDir 'version.dll') -Force
        Write-Host 'stage 3: version.dll placed next to browser.exe (Chrome++ portable Data/Cache)'
    }
    else {
        $launchBody = '@echo off' + "`r`n" +
            'start "" "%~dp0Yandex\browser.exe" --user-data-dir="%~dp0Data" %*' + "`r`n"
        [IO.File]::WriteAllText((Join-Path $OutDir 'launch.bat'), $launchBody)
        Write-Host 'stage 3: version.dll unavailable - wrote launch.bat fallback (--user-data-dir launcher)'
    }

    # ------------------------------------------------ stage 4: profile preseed
    # Prefs-only debloat path (review fix #10) - no admin rights needed. The
    # empty "First Run" sentinel must ship with the JSON, otherwise Yandex
    # treats hand-made profile files as corrupted and regenerates defaults.
    $preseedSrc   = Join-Path $PSScriptRoot 'preseed'
    $preseedFiles = @('Local State', 'Preferences', 'First Run')
    foreach ($pf in $preseedFiles) {
        $pfPath = Join-Path $preseedSrc $pf
        if (-not (Test-Path -LiteralPath $pfPath)) {
            Write-Error "stage 4: missing preseed file: $pfPath"
            exit 1
        }
    }
    $dataDir    = Join-Path $OutDir 'Data'
    $defaultDir = Join-Path $dataDir 'Default'
    New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $preseedSrc 'Local State') -Destination (Join-Path $dataDir 'Local State') -Force
    Copy-Item -LiteralPath (Join-Path $preseedSrc 'Preferences') -Destination (Join-Path $defaultDir 'Preferences') -Force
    Copy-Item -LiteralPath (Join-Path $preseedSrc 'First Run') -Destination (Join-Path $dataDir 'First Run') -Force
    # Ship the preseed sources next to this script at the package root so
    # update.bat-triggered rebuilds ($APP_DIR\..\build-yandex.ps1) stay self-contained.
    $preseedOut = Join-Path $OutDir 'preseed'
    New-Item -ItemType Directory -Path $preseedOut -Force | Out-Null
    foreach ($pf in $preseedFiles) {
        Copy-Item -LiteralPath (Join-Path $preseedSrc $pf) -Destination $preseedOut -Force
    }
    Write-Host 'stage 4: preseed applied -> Data\Local State, Data\Default\Preferences, Data\First Run (source preseed\ shipped at package root)'

    # -------------------------------------------------- stage 5: strip updater
    foreach ($updater in 'service_update.exe', 'yupdate-exec.exe') {
        $found = @(Get-ChildItem -LiteralPath $yandexDir -Recurse -File -Filter $updater -ErrorAction SilentlyContinue)
        foreach ($u in $found) {
            Remove-Item -LiteralPath $u.FullName -Force
            Write-Host "stage 5: stripped updater $($u.Name)"
        }
    }

    # --------------------------------------------------------- layout manifest
    $manifestLines = @(
        'build-yandex.ps1 layout manifest'
        "version=$Version"
        ''
        '[package root]'
    )
    Get-ChildItem -LiteralPath $OutDir -Force |
        Where-Object { $_.Name -ne 'layout-manifest.txt' } |
        Sort-Object Name |
        ForEach-Object {
            if ($_.PSIsContainer) { $manifestLines += "  $($_.Name)\" } else { $manifestLines += "  $($_.Name)" }
        }
    $manifestLines += '[Yandex]'
    Get-ChildItem -LiteralPath $yandexDir -Force | Sort-Object Name | ForEach-Object {
        if ($_.PSIsContainer) { $manifestLines += "  $($_.Name)\" } else { $manifestLines += "  $($_.Name)" }
    }
    if (Test-Path -LiteralPath $flatCdm) {
        $manifestLines += 'WidevineCdm=Yandex\WidevineCdm (flat, next to browser.exe)'
    }
    else {
        $manifestLines += 'WidevineCdm=ABSENT (runtime component registration only)'
    }
    $manifestLines += $trimLines
    Set-Content -Path (Join-Path $OutDir 'layout-manifest.txt') -Value ($manifestLines -join "`n")
    Write-Host "layout: manifest written: $(Join-Path $OutDir 'layout-manifest.txt')"
}
catch {
    Write-Error "build-yandex.ps1: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($exitCode -ne 0) { exit $exitCode }
Write-Host "build-yandex.ps1: done - package at $OutDir"
exit 0
