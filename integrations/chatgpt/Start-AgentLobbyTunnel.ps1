param(
    [Parameter(Mandatory)]
    [ValidatePattern('^tunnel_(?:[a-z0-9]{4}_)?[a-z0-9]{32}$')]
    [string]$TunnelId,

    [string]$TunnelClient = 'tunnel-client.exe',

    [string]$Python = (Join-Path $PSScriptRoot '.venv/Scripts/python.exe'),

    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$client = (Get-Command $TunnelClient -CommandType Application).Source
$pythonPath = (Get-Item -LiteralPath $Python).FullName.Replace('\', '/')
$bridgePath = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'lobby_bridge.py')).FullName.Replace('\', '/')
$bridgeCommand = '"{0}" -X utf8 "{1}"' -f $pythonPath, $bridgePath
$healthFile = Join-Path ([IO.Path]::GetTempPath()) ('agent-lobby-tunnel-{0}.url' -f [guid]::NewGuid())
$settings = @(
    '--control-plane.tunnel-id', $TunnelId,
    '--mcp.command', $bridgeCommand,
    '--health.listen-addr', '127.0.0.1:0'
)

$previousKey = $env:CONTROL_PLANE_API_KEY
$previousToken = $env:AGENT_LOBBY_TOKEN
$runtimeKey = $null
$lobbyToken = $null
try {
    if ([string]::IsNullOrWhiteSpace($previousKey)) {
        $runtimeKey = Read-Host 'Tunnel runtime API key' -AsSecureString
        if ($runtimeKey.Length -eq 0) { throw 'A Tunnel runtime API key is required.' }
        $env:CONTROL_PLANE_API_KEY = [Net.NetworkCredential]::new('', $runtimeKey).Password
    }
    if ([string]::IsNullOrWhiteSpace($previousToken)) {
        $lobbyToken = Read-Host 'Agent Lobby token' -AsSecureString
        if ($lobbyToken.Length -eq 0) { throw 'An Agent Lobby token is required.' }
        $env:AGENT_LOBBY_TOKEN = [Net.NetworkCredential]::new('', $lobbyToken).Password
    }

    & $client doctor @settings --explain
    if ($LASTEXITCODE -ne 0) { throw 'Tunnel diagnostics did not pass.' }
    if ($CheckOnly) { return }

    Write-Host "Tunnel health URL file: $healthFile"
    & $client run @settings --health.url-file $healthFile --mcp.stdio-send-initialized-notification
    if ($LASTEXITCODE -ne 0) { throw 'The tunnel client exited with an error.' }
}
finally {
    $env:CONTROL_PLANE_API_KEY = $previousKey
    $env:AGENT_LOBBY_TOKEN = $previousToken
    if ($null -ne $runtimeKey) { $runtimeKey.Dispose() }
    if ($null -ne $lobbyToken) { $lobbyToken.Dispose() }
    if (Test-Path -LiteralPath $healthFile) { Remove-Item -LiteralPath $healthFile }
}
