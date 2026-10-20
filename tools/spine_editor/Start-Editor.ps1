param([string]$Python = '', [int]$Port = 8876, [string]$Operator = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$main = $repo
foreach ($p in @($repo, (Join-Path $repo '..'), (Join-Path $repo '../..'), (Join-Path $repo '../../..'))) {
    if (Test-Path -LiteralPath (Join-Path $p 'build/prts_ref/_node')) {$main = (Resolve-Path $p).Path; break}
}
if ($Operator) {
    $sourceArgs = @('--operator', $Operator)
    $expected = $Operator
} else {
    $source = Join-Path $main '.worktrees/codex-art/art/incoming/cy_siege_all_actions_1020'
    $runtime = Join-Path $main 'build/prts_ref/_node/spine-canvas-3.5.51.js'
    if (-not (Test-Path -LiteralPath $source) -or -not (Test-Path -LiteralPath $runtime)) {
        throw '未找到本机的推进之王数据和 Spine 运行库。请按 README 使用 server.py 显式指定路径。'
    }
    $sourceArgs = @('--source', ('"'+$source+'"'), '--runtime', ('"'+$runtime+'"'))
    $expected = 'siege'
}
if (-not $Python) {
    $Python = if (Test-Path -LiteralPath 'D:/Anaconda/python.exe') {'D:/Anaconda/python.exe'} else {(Get-Command python).Source}
}
$url = "http://127.0.0.1:$Port/"
try {
    $existing = Invoke-RestMethod ($url + 'project.json') -TimeoutSec 2
    if ($existing.character -ne $expected) {throw "端口 $Port 已被其他编辑台（$($existing.character)）或应用占用；请关闭它或加 -Port"}
    Start-Process $url
    exit 0
} catch [System.Net.WebException] {
    # Start only if there is no editor listening yet.
}
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$log = if ($Operator) {"spine-editor-$Operator"} else {'spine-editor'}
$argsList = @('-X','utf8',('"'+(Join-Path $PSScriptRoot 'server.py')+'"')) + $sourceArgs + @('--port',"$Port")
$process = Start-Process -FilePath $Python -ArgumentList $argsList -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $build "$log-server.log") -RedirectStandardError (Join-Path $build "$log-server-errors.log")
$ready = $false
for ($i=0; $i -lt 50; $i++) {
    if ($process.HasExited) {throw "编辑器启动失败，请查看 build/$log-server-errors.log"}
    try {Invoke-RestMethod ($url + 'project.json') -TimeoutSec 1 | Out-Null; $ready=$true; break} catch {Start-Sleep -Milliseconds 200}
}
if (-not $ready) {throw '编辑器未能及时启动，请查看日志'}
Start-Process $url
