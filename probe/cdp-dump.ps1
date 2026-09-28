# Extracts page HTML over the Chrome DevTools Protocol.
# Used as a fallback when --dump-dom never terminates (Yandex 26.8 / Chromium 150 on CI).
param(
  [Parameter(Mandatory = $true)][string]$App,
  [Parameter(Mandatory = $true)][string]$Url,
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string[]]$Base = @(),
  [string]$Profile = '',
  [int]$Port = 9444,
  [int]$ReadyMs = 30000,
  [string]$AwaitExpr = '',
  [int]$AwaitMs = 0,
  [int]$PollMs = 1000,
  [switch]$NoLaunch,
  [switch]$DriveNav
)
$ErrorActionPreference = 'Stop'
function Log([string]$m) { Write-Host "detail: cdp-dump: $m" }

$proc = $null
$ws = $null
$ok = $false
try {
  $exe = Join-Path $App 'browser.exe'
  if (-not (Test-Path $exe)) { Log "browser.exe missing in $App"; exit 2 }
  if (-not $Profile) { $Profile = Join-Path ([IO.Path]::GetTempPath()) ('cdp-' + [Guid]::NewGuid().ToString('N')) }

  if (-not $NoLaunch) {
    $argList = $Base + @("--user-data-dir=$Profile", "--remote-debugging-port=$Port", '--remote-allow-origins=*', $Url)
    Log "launch browser.exe port=$Port url=$Url"
    $proc = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -NoNewWindow -WorkingDirectory $App `
      -RedirectStandardOutput "$OutFile.out" -RedirectStandardError "$OutFile.err"
  }

  function Find-Target {
    $dl = [DateTime]::UtcNow.AddMilliseconds($ReadyMs)
    $last = ''
    while ([DateTime]::UtcNow -lt $dl) {
      Start-Sleep -Milliseconds $PollMs
      try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing -TimeoutSec 3
        $list = @($r.Content | ConvertFrom-Json)
        $pages = @($list | Where-Object { $_.type -eq 'page' })
        if ($pages.Count -gt 0) {
          $prefix = $Url.TrimEnd('/')
          $withUrl = @($pages | Where-Object { $_.url })
          $exact = @($withUrl | Where-Object { $_.url -eq $Url -or $_.url -like ($prefix + '*') })
          if ($exact.Count -gt 0) { Log "matched target url=$($exact[0].url)"; return $exact[0] }
          if (($withUrl.Count -eq 1) -and ([DateTime]::UtcNow -gt $dl.AddMilliseconds(-4000))) {
            Log "late single-page fallback url=$($withUrl[0].url)"
            return $withUrl[0]
          }
          $last = "page urls=[$(($pages | ForEach-Object { $_.url }) -join ', ')]"
        } else { $last = 'no page targets' }
      } catch { $last = $_.Exception.Message }
    }
    Log "no url-matched target within ${ReadyMs}ms (last=$last)"
    return $null
  }
  function Get-AnyPage([int]$timeoutMs) {
    $dl = [DateTime]::UtcNow.AddMilliseconds($timeoutMs)
    $last = ''
    while ([DateTime]::UtcNow -lt $dl) {
      Start-Sleep -Milliseconds $PollMs
      try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing -TimeoutSec 3
        $list = @($r.Content | ConvertFrom-Json)
        $pages = @($list | Where-Object { $_.type -eq 'page' })
        if ($pages.Count -gt 0) { return $pages[0] }
        $last = 'no page targets'
      } catch { $last = $_.Exception.Message }
    }
    Log "no page target within ${timeoutMs}ms (last=$last)"
    return $null
  }
  $driveNav = $false
  if ($DriveNav) {
    $target = Get-AnyPage 8000
    if ($null -eq $target) { exit 3 }
    $driveNav = $true
    Log 'DriveNav: attaching to first page target; navigation will be driven over CDP'
  } else {
    $target = Find-Target
    if ($null -eq $target) { exit 3 }
  }
  Log "target url=$($target.url)"

  function Send-Json([string]$json) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $seg = [ArraySegment[byte]]::new($bytes)
    $sendTask = $ws.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct)
    if (-not $sendTask.Wait(15000)) { throw 'ws send timeout (15s)' }
  }
  function Receive-Json {
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 262144
    do {
      $seg = [ArraySegment[byte]]::new($buf)
      $recvTask = $ws.ReceiveAsync($seg, $ct)
      if (-not $recvTask.Wait(15000)) { throw 'ws receive timeout (15s)' }
      $res = $recvTask.Result
      if ($res.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'ws closed by peer' }
      $ms.Write($buf, 0, $res.Count)
    } while (-not $res.EndOfMessage)
    [Text.Encoding]::UTF8.GetString($ms.ToArray())
  }
  function Invoke-Cdp([string]$method, $params) {
    $script:cdpSeq++
    $id = $script:cdpSeq
    $obj = @{ id = $id; method = $method }
    if ($null -ne $params) { $obj['params'] = $params }
    Send-Json ($obj | ConvertTo-Json -Compress -Depth 8)
    $limit = [DateTime]::UtcNow.AddSeconds(45)
    while ([DateTime]::UtcNow -lt $limit) {
      $msg = Receive-Json | ConvertFrom-Json
      if (($null -ne $msg.PSObject.Properties['id']) -and $msg.id -eq $id) { return $msg }
    }
    throw "no CDP response for $method"
  }
  $script:cdpSeq = 0

  $enabled = $false
  for ($attempt = 1; ($attempt -le 2) -and (-not $enabled); $attempt++) {
    if ($null -ne $ws) { try { $ws.Dispose() } catch { Log "ws dispose: $($_.Exception.Message)" }; $ws = $null }
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(5)
    $ct = [Threading.CancellationToken]::None
    $connTask = $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $ct)
    if (-not $connTask.Wait(15000)) { throw 'ws connect timeout (15s)' }
    Log "ws connected (attempt $attempt)"
    try { $null = Invoke-Cdp 'Runtime.enable' @{}; $enabled = $true }
    catch { Log "Runtime.enable attempt ${attempt}: $($_.Exception.Message)"; if ($attempt -lt 2) { Start-Sleep -Seconds 3 } }
  }
  if (-not $enabled) { throw 'Runtime.enable failed after 2 attempts' }

  if ($driveNav) {
    $null = Invoke-Cdp 'Page.enable' @{}
    $null = Invoke-Cdp 'Page.navigate' @{ url = $Url }
    Log "Page.navigate issued for $Url"
    $loc = ''
    $prefix = $Url.TrimEnd('/')
    $locLimit = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $locLimit) {
      Start-Sleep -Milliseconds $PollMs
      try {
        $r = Invoke-Cdp 'Runtime.evaluate' @{ expression = 'location.href'; returnByValue = $true }
        if ($null -ne $r.result -and $null -ne $r.result.result -and $null -ne $r.result.result.PSObject.Properties['value']) {
          $loc = [string]$r.result.result.value
        }
        if (($loc -eq $Url) -or $loc.StartsWith($prefix)) { break }
      } catch { Log "loc poll: $($_.Exception.Message)" }
    }
    Log "navigated location.href=[$loc]"
    if (($loc -ne $Url) -and (-not $loc.StartsWith($prefix))) { throw "navigation to $Url did not commit (location.href=$loc)" }
  }

  try { $null = Invoke-Cdp 'Runtime.enable' @{} } catch { Log "Runtime.enable: $($_.Exception.Message)" }

  if ($AwaitExpr) {
    $val = ''
    $limit = [DateTime]::UtcNow.AddMilliseconds($AwaitMs)
    while ([DateTime]::UtcNow -lt $limit) {
      Start-Sleep -Milliseconds $PollMs
      try {
        $r = Invoke-Cdp 'Runtime.evaluate' @{ expression = $AwaitExpr; returnByValue = $true }
        if ($null -ne $r.result -and $null -ne $r.result.result -and $null -ne $r.result.result.PSObject.Properties['value']) {
          $val = [string]$r.result.result.value
        }
      } catch { Log "await eval: $($_.Exception.Message)" }
      if ($val -and $val -ne 'pending') { break }
    }
    Log "await value=[$val]"
  }

  $r = Invoke-Cdp 'Runtime.evaluate' @{ expression = 'document.documentElement.outerHTML'; returnByValue = $true }
  $html = ''
  if ($null -ne $r.result -and $null -ne $r.result.result -and $null -ne $r.result.result.PSObject.Properties['value']) {
    $html = [string]$r.result.result.value
  }
  Set-Content -Path $OutFile -Value $html -Encoding utf8
  Log "dom bytes=$($html.Length)"
  $ok = $true
  exit 0
} catch {
  Log "error: $($_.Exception.Message)"
  exit 1
} finally {
  if ($null -ne $ws) {
    try { $ws.Dispose() } catch { Log "ws dispose: $($_.Exception.Message)" }
  }
  if ($null -ne $proc) {
    try { if (-not $proc.HasExited) { $proc.Kill($true) } } catch { Log "kill: $($_.Exception.Message)" }
  }
  Stop-Process -Name browser, browser_proxy -Force -ErrorAction SilentlyContinue
  if (-not $ok) { Log 'cdp extraction did not produce a DOM' }
}
