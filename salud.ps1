# Revisa que la revisión continua de los canales de Telegram esté viva; si no, la reinicia y te avisa por Telegram.
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = $env:GITHUB_REPOSITORY
$problemas = @(); $acciones = @()
$runs = @(gh run list --repo $repo --workflow ofertones.yml --limit 6 --json databaseId,status,createdAt | ConvertFrom-Json)
$activa = $runs | Where-Object { $_.status -eq 'in_progress' } | Select-Object -First 1
$espera = $runs | Where-Object { $_.status -in 'queued', 'pending', 'waiting' } | Select-Object -First 1
$c = @(gh api "repos/$repo/commits?path=ofertones-estado.json&per_page=1" | ConvertFrom-Json)
$edad = if ($c.Count) { ([DateTime]::UtcNow - ([datetime]$c[0].commit.committer.date).ToUniversalTime()).TotalMinutes } else { 9999 }
if (-not $activa -and -not $espera) {
    $problemas += "La revisión continua no estaba corriendo."
    gh workflow run ofertones.yml --repo $repo | Out-Null; $acciones += "La reinicié."
} elseif ($activa -and $edad -gt 60) {
    $problemas += "La revisión seguía abierta pero no guardaba avances desde hace $([int]$edad) min."
    gh run cancel $activa.databaseId --repo $repo | Out-Null; Start-Sleep 8
    gh workflow run ofertones.yml --repo $repo | Out-Null; $acciones += "La reinicié."
}
# ¿se pueden leer los canales y qué tan atrás va el estado?
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
$est = $null; try { $est = (Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$repo/main/ofertones-estado.json?t=$([DateTime]::UtcNow.Ticks)").Content | ConvertFrom-Json } catch { }
foreach ($ch in 'OfertonesMexico', 'ofertasimperdiblesmexico', 'MegaOfertonesMX') {
    try {
        $h = (Invoke-WebRequest "https://t.me/s/$ch" -UseBasicParsing -UserAgent $ua -TimeoutSec 30).Content
        $ids = @([regex]::Matches($h, "data-post=""$ch/(\d+)""") | ForEach-Object { [int]$_.Groups[1].Value })
        if (-not $ids.Count) { $problemas += "No pude leer el canal $ch." }
        elseif ($est -and $est.$ch -and ($ids | Measure-Object -Maximum).Maximum - [int]$est.$ch -gt 200) { $problemas += "El canal $ch va muy atrasado en el registro." }
    } catch { $problemas += "No pude abrir el canal $ch." }
}
"Salud: edad del estado $([int]$edad) min; activa=$([bool]$activa); problemas=$($problemas.Count)"
if ($problemas.Count) {
    $txt = "⚠️ Revisión de los canales de Telegram`n" + ($problemas -join "`n") + $(if ($acciones) { "`n" + ($acciones -join " ") } else { "" })
    & (Join-Path $dir "enviar-telegram.ps1") -Mensaje $txt
}