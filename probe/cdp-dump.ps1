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
  [switch]$NoLaunch
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

  $target = $null
  $deadline = [DateTime]::UtcNow.AddMilliseconds($ReadyMs)
  $lastErr = ''
  while ([DateTime]::UtcNow -lt $deadline -and $null -eq $target) {
    Start-Sleep -Milliseconds $PollMs
    try {
      $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing -TimeoutSec 3
      $list = @($r.Content | ConvertFrom-Json)
      $pages = @($list | Where-Object { $_.type -eq 'page' })
      if ($pages.Count -gt 0) {
        $prefix = $Url.TrimEnd('/')
        $exact = @($pages | Where-Object { $_.url -eq $Url -or $_.url -like ($prefix + '*') })
        if ($exact.Count -gt 0) { $target = $exact[0] }
        elseif ($pages.Count -eq 1) { $target = $pages[0]; Log "single page target accepted: $($pages[0].url)" }
        else { Log "no url match yet; page count=$($pages.Count)" }
      } else {
        $lastErr = 'no page targets'
      }
    } catch {
      $lastErr = $_.Exception.Message
    }
  }
  if ($null -eq $target) { Log "no debug target within ${ReadyMs}ms (last=$lastErr)"; exit 3 }
  Log "target url=$($target.url)"

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(5)
  $ct = [Threading.CancellationToken]::None
  $connTask = $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $ct)
  if (-not $connTask.Wait(15000)) { throw 'ws connect timeout (15s)' }
  Log 'ws connected'


  function Send-Json([string]$json) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $seg = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult() | Out-Null
  }
  function Receive-Json {
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 262144
    do {
      $seg = [ArraySegment[byte]]::new($buf)
      $recvTask = $ws.ReceiveAsync($seg, $ct)
      if (-not $recvTask.Wait(10000)) { throw 'ws receive timeout (10s)' }
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
