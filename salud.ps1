# Salud del copiador de canales (sin IA). Corre cada hora: si la revisión continua no está viva, la reinicia.
# Solo avisa por Telegram de 6 a 23 h (hora de Delicias); de noche solo lo arregla.
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = $env:GITHUB_REPOSITORY
$problemas = @(); $acciones = @()
$runs = @(gh run list --repo $repo --workflow ofertones.yml --limit 8 --json databaseId,status,createdAt | ConvertFrom-Json | ForEach-Object { $_ })
$activa = $runs | Where-Object { $_.status -eq 'in_progress' } | Select-Object -First 1
$espera = $runs | Where-Object { $_.status -in 'queued', 'pending', 'waiting', 'requested' } | Select-Object -First 1
$lat = $null; try { $lat = (Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$repo/main/latido.txt?t=$([DateTime]::UtcNow.Ticks)").Content.Trim() } catch { }
$edad = if ($lat) { ([DateTime]::UtcNow - [DateTime]::Parse($lat).ToUniversalTime()).TotalMinutes } else { 9999 }
if (-not $activa -and -not $espera) {
    $problemas += "La revisión de canales no estaba corriendo."
    gh workflow run ofertones.yml --repo $repo | Out-Null; $acciones += "La reinicié."
} elseif ($activa -and $edad -gt 35) {
    $problemas += "La revisión de canales no daba señales desde hace $([int]$edad) min."
    gh run cancel $activa.databaseId --repo $repo | Out-Null; Start-Sleep 10
    gh workflow run ofertones.yml --repo $repo | Out-Null; $acciones += "La reinicié."
}
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
foreach ($ch in 'OfertonesMexico', 'ofertasimperdiblesmexico', 'MegaOfertonesMX') {
    try {
        $h = (Invoke-WebRequest "https://t.me/s/$ch" -UseBasicParsing -UserAgent $ua -TimeoutSec 30).Content
        if (-not [regex]::IsMatch($h, "data-post=""$ch/\d+""")) { $problemas += "No pude leer el canal $ch." }
    } catch { $problemas += "No pude abrir el canal $ch." }
}
$hora = [TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, [TimeZoneInfo]::Utc, [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time (Mexico)')).Hour
"Salud: latido hace $([int]$edad) min; activa=$([bool]$activa); en espera=$([bool]$espera); problemas=$($problemas.Count); hora MX=$hora"
$problemas | ForEach-Object { "  - $_" }
if ($false) {   # 12 nov: Javier solo quiere mensajes de ofertas bajo $10k; la salud solo arregla, no escribe
    $txt = "⚠️ Revisión automática de los canales de Telegram`n" + ($problemas -join "`n") + $(if ($acciones) { "`n" + ($acciones -join " ") } else { "" })
    & (Join-Path $dir "enviar-telegram.ps1") -Mensaje $txt
}