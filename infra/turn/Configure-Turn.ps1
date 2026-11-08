param(
  [Parameter(Mandatory=$true)][string]$PublicIP,
  [string]$TurnHost,
  [switch]$EnableTLS,
  [switch]$Production
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$taskAddress = $null
if (-not [Net.IPAddress]::TryParse($PublicIP, [ref]$taskAddress) -or $taskAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'PublicIP harus alamat IPv4 yang bisa dijangkau peserta.' }
if (-not $TurnHost) { $TurnHost = $PublicIP }
if ($TurnHost -notmatch '^[a-zA-Z0-9.-]+$') { throw 'TurnHost harus hostname atau IPv4, tanpa protokol atau port.' }
if ($EnableTLS -and (-not (Test-Path (Join-Path $PSScriptRoot 'certs/fullchain.pem')) -or -not (Test-Path (Join-Path $PSScriptRoot 'certs/privkey.pem')))) { throw 'Tambahkan certs/fullchain.pem dan certs/privkey.pem sebelum mengaktifkan TLS.' }
$taskEnvPath = Join-Path $taskRoot '.env'
if (-not (Test-Path $taskEnvPath)) { throw 'Buat .env project terlebih dahulu dari .env.example.' }
$taskText = [IO.File]::ReadAllText($taskEnvPath)
$taskExisting = [regex]::Match($taskText, '(?m)^TURN_SHARED_SECRET=([^\r\n]*)')
$taskSecret = $taskExisting.Groups[1].Value.Trim().Trim('"').Trim("'")
if (-not $taskSecret) {
  $taskBytes = New-Object byte[] 32
  $taskRng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $taskRng.GetBytes($taskBytes) } finally { $taskRng.Dispose() }
  $taskSecret = ([BitConverter]::ToString($taskBytes)).Replace('-', '').ToLowerInvariant()
}
if ($taskSecret -notmatch '^[a-zA-Z0-9_-]{32,}$') { throw 'TURN_SHARED_SECRET harus minimal 32 karakter hex/URL-safe.' }
$taskUrls = "turn:${TurnHost}:3478?transport=udp,turn:${TurnHost}:3478?transport=tcp"
if ($EnableTLS) { $taskUrls += ",turns:${TurnHost}:5349?transport=tcp" }
$taskValues = @{ TURN_EXTERNAL_IP=$PublicIP; TURN_REALM=$TurnHost; TURN_SHARED_SECRET=$taskSecret; TURN_URLS=$taskUrls; TURN_TLS_ENABLED=([bool]$EnableTLS).ToString().ToLowerInvariant() }
foreach ($taskEntry in $taskValues.GetEnumerator()) {
  $taskPattern = '(?m)^' + [regex]::Escape($taskEntry.Key) + '=[^\r\n]*'
  $taskReplacement = $taskEntry.Key + '=' + $taskEntry.Value
  if ([regex]::IsMatch($taskText, $taskPattern)) { $taskText = [regex]::Replace($taskText, $taskPattern, $taskReplacement) }
  else { $taskText += "`n" + $taskReplacement }
}
[IO.File]::WriteAllText($taskEnvPath, $taskText, [Text.UTF8Encoding]::new($false))
Push-Location $taskRoot
try {
  $taskArgs = @('compose')
  if ($Production) { $taskArgs += @('-f', 'docker-compose.prod.yml') }
  $taskArgs += @('--profile','turn','up','-d','turn','api')
  & docker @taskArgs
  if ($LASTEXITCODE -ne 0) { throw 'Docker gagal menjalankan TURN/API. Periksa docker compose logs turn api.' }
} finally { Pop-Location }
Write-Host 'TURN dan API dikonfigurasi. Pastikan firewall/port forwarding sudah membuka 3478 TCP+UDP serta rentang relay UDP di .env. Peserta perlu keluar dan gabung call ulang.'
