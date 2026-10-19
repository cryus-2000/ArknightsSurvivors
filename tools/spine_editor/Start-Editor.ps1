param([string]$Python = '', [int]$Port = 8876)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$main = (Resolve-Path (Join-Path $repo '../..')).Path
$source = Join-Path $main '.worktrees/codex-art/art/incoming/cy_siege_all_actions_1020'
$runtime = Join-Path $main 'build/prts_ref/_node/spine-canvas-3.5.51.js'
if (-not (Test-Path -LiteralPath $source) -or -not (Test-Path -LiteralPath $runtime)) {
    throw '未找到本机的推进之王数据和 Spine 运行库。请按 README 使用 server.py 显式指定路径。'
}
if (-not $Python) {
    $Python = if (Test-Path -LiteralPath 'D:/Anaconda/python.exe') {'D:/Anaconda/python.exe'} else {(Get-Command python).Source}
}
$url = "http://127.0.0.1:$Port/"
try {
    $existing = Invoke-RestMethod ($url + 'project.json') -TimeoutSec 2
    if ($existing.title -ne '推进之王 · 扛锤跑步') {throw '端口已被其他应用占用'}
    Start-Process $url
    exit 0
} catch [System.Net.WebException] {
    # Start only if there is no editor listening yet.
}
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$argsList = @('-X','utf8',('"'+(Join-Path $PSScriptRoot 'server.py')+'"'),'--source',('"'+$source+'"'),'--runtime',('"'+$runtime+'"'),'--port',"$Port")
$process = Start-Process -FilePath $Python -ArgumentList $argsList -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $build 'spine-editor-server.log') -RedirectStandardError (Join-Path $build 'spine-editor-server-errors.log')
$ready = $false
for ($i=0; $i -lt 30; $i++) {
    if ($process.HasExited) {throw '编辑器启动失败，请查看 build/spine-editor-server-errors.log'}
    try {Invoke-RestMethod ($url + 'project.json') -TimeoutSec 1 | Out-Null; $ready=$true; break} catch {Start-Sleep -Milliseconds 200}
}
if (-not $ready) {throw '编辑器未能及时启动，请查看日志'}
Start-Process $url
