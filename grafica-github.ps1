# Con la PC apagada: dibuja y manda las gráficas por tienda usando los últimos precios que subió la PC
# + lo que el monitor de GitHub lee ahora (Elektra, Chedraui, Cyberpuerta, Liverpool). Si la PC revisó hace poco, no hace nada.
param([switch]$Forzar)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir "telegram-comun.ps1")
$edad = 99
$fU = Join-Path $dir "ultima-revision.txt"
if (Test-Path $fU) { $edad = ([DateTime]::UtcNow - [DateTime]::Parse((Get-Content $fU -Raw).Trim()).ToUniversalTime()).TotalHours }
if ($edad -lt 5 -and -not $Forzar) { "La PC revisó hace $([math]::Round($edad,1)) h: no hace falta."; return }
$filas = @([IO.File]::ReadAllText((Join-Path $dir "precios.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json)
$mon = [IO.File]::ReadAllText((Join-Path $dir "monitor-ultimo.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
$tz = [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time (Mexico)')
$hoy = [TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, [TimeZoneInfo]::Utc, $tz).ToString('yyyy-MM-dd')
$ahora = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$monOk = $mon.revisado -and (([DateTime]::UtcNow - [DateTime]::Parse($mon.revisado).ToUniversalTime()).TotalHours -lt 3)
$nuevas = @()
if ($monOk) { foreach ($x in @($mon.precios)) { $nuevas += [pscustomobject]@{ fecha = $hoy; revisado = $ahora; producto = $x.producto; condicion = $x.condicion; tienda = $x.tienda; precio = [double]$x.precio; requisito = '' } } }
$json = Join-Path $dir "combinado.json"
[IO.File]::WriteAllText($json, (@($nuevas) + @($filas) | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
foreach ($p in @(@('PS5 Slim Digital', '💿 <b>PS5 Slim Digital</b> · precio ahora por tienda'), @('PS5 Slim Disco', '📀 <b>PS5 Slim con disco</b> · precio ahora por tienda'))) {
    $png = Join-Path $dir ("graf-" + ($p[0] -replace '\W', '') + ".png")
    $frescas = @($nuevas | Where-Object { $_.producto -eq $p[0] } | ForEach-Object { $_.tienda })
    & (Join-Path $dir "grafica-tiendas.ps1") -Json $json -Producto $p[0] -Salida $png -EdadIA $edad -Frescas $frescas | Out-Null
    $txt = $p[1] + "`n<i>PC apagada: " + $(if ($frescas.Count) { ($frescas | Sort-Object -Unique) -join ', ' } else { 'ninguna tienda' }) + " con precio de ahora; las demás con su último dato (hace " + [math]::Floor($edad) + " h).</i>"
    $f = Join-Path $dir "cap.txt"; [IO.File]::WriteAllText($f, $txt, (New-Object Text.UTF8Encoding $false))
    & (Join-Path $dir "enviar-telegram.ps1") -Archivo $f -Html -FotoArchivo $png
}