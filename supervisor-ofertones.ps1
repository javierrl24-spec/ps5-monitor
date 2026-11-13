# Vigilante: corre el copiador como trabajo en segundo plano. Si se congela (sin latido 4 min) o se cae, lo reinicia.
# 6 min antes de terminar, encola la siguiente corrida para que no haya huecos.
param([int]$Minutos = 175)
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$fin = (Get-Date).AddMinutes($Minutos)
$lat = Join-Path $dir 'latido.txt'
$encadenado = $false; $reinicios = 0
function Lanzar {
    $m = [math]::Max(1, [int][math]::Floor(($fin - (Get-Date)).TotalMinutes))
    Set-Content -Path $lat -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    Start-Job -ScriptBlock { param($d, $m) Set-Location $d; & (Join-Path $d 'monitor-ofertones.ps1') -Bucle $m -Cada 30 } -ArgumentList $dir, $m
}
$job = Lanzar
while ((Get-Date) -lt $fin) {
    Start-Sleep -Seconds 30
    Receive-Job $job -ErrorAction SilentlyContinue | Out-Host
    if (-not $encadenado -and (Get-Date) -gt $fin.AddMinutes(-6)) { & gh workflow run ofertones.yml 2>&1 | Out-Host; $encadenado = $true; "Siguiente corrida encolada" }
    $edad = ((Get-Date) - (Get-Item $lat).LastWriteTime).TotalMinutes
    $vivo = $job.State -eq 'Running'
    if ((-not $vivo -or $edad -gt 4) -and (Get-Date) -lt $fin.AddMinutes(-1)) {
        $reinicios++
        "$(Get-Date -Format 'HH:mm:ss') Reiniciando copiador (estado $($job.State), latido hace $([int]$edad) min)"
        Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
        $job = Lanzar
    }
}
Stop-Job $job -ErrorAction SilentlyContinue; Receive-Job $job -ErrorAction SilentlyContinue | Out-Host; Remove-Job $job -Force -ErrorAction SilentlyContinue
"Fin del vigilante. Reinicios: $reinicios"