# Dibuja "Precio ahora por tienda (nuevas)" de una consola como PNG, igual que el tablero.
# Uso: grafica-tiendas.ps1 -Json C:\ruta\precios.json -Producto "PS5 Slim Digital" -Salida C:\ruta\digital.png
# Toma, por tienda, el último precio de consola NUEVA de los últimos 60 días; la más barata va en verde
# y una línea punteada marca el promedio.
param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][string]$Producto, [Parameter(Mandatory)][string]$Salida, [int]$Ventana = 60, [double]$EdadIA = 0, [string[]]$Frescas = @())
Add-Type -AssemblyName System.Drawing

$filas = [IO.File]::ReadAllText($Json, [Text.Encoding]::UTF8) | ConvertFrom-Json
$tzMX = [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time (Mexico)')
$ahoraMX = [TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, [TimeZoneInfo]::Utc, $tzMX)
$hoy = $ahoraMX.Date
# Tiendas que Javier quitó de la revisión (9 nov 2026): no salen en la gráfica
$quitadas = @('Sears', 'El Palacio de Hierro', 'Suburbia', 'Game Planet', 'Telcel', 'Zegucom', 'PCEL')
# "Tienda|precio" que no llegan a Delicias: se muestran en gris y no cuentan como la más barata ni en el promedio
$noLlega = @()
$fNo = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "monitor-no-llega.txt"
if (Test-Path $fNo) { $noLlega = @(Get-Content $fNo -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) }
$vistas = @{}
$datos = @()
$filas | Where-Object { $_.producto -eq $Producto -and $_.condicion -eq 'Nuevo' -and -not $_.tienda.StartsWith('Apple') -and $quitadas -notcontains $_.tienda } |
    Sort-Object @{e = { $_.fecha }; Descending = $true }, @{e = { $_.revisado }; Descending = $true } |
    ForEach-Object {
        $f = [datetime]::ParseExact($_.fecha.Substring(0, 10), 'yyyy-MM-dd', $null)
        if (($hoy - $f).TotalDays -le $Ventana -and -not $vistas.ContainsKey($_.tienda)) {
            $vistas[$_.tienda] = $true
            $nl = ($noLlega -contains ($_.tienda + '|' + ([double]$_.precio))) -or ($_.requisito -match '(?i)no disponible para CP')
            $vieja = ($EdadIA -gt 4 -and $Frescas -notcontains $_.tienda)
            $datos += [pscustomobject]@{ tienda = $_.tienda; precio = [double]$_.precio; noLlega = $nl; vieja = $vieja }
        }
    }
$datos = @($datos | Sort-Object precio)
if ($datos.Count -eq 0) { throw "No hay precios recientes de $Producto" }

$fmt = { param($v) '$' + ([math]::Round($v)).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('en-US')) }
$validos = @($datos | Where-Object { -not $_.noLlega })
if ($validos.Count -eq 0) { $validos = $datos }
$prom = ($validos | Measure-Object precio -Average).Average
$max = ($datos | Measure-Object precio -Maximum).Maximum * 1.02

# Lienzo (doble resolución para que se vea nítido en el celular)
$s = 2
$W = 1100 * $s; $rowH = 40 * $s; $top = 120 * $s; $bottom = 40 * $s
$H = $top + $datos.Count * $rowH + $bottom
$bmp = New-Object Drawing.Bitmap $W, $H
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'

$cFondo = [Drawing.Color]::FromArgb(32, 32, 32)
$cTexto = [Drawing.Color]::FromArgb(236, 236, 236)
$cGris = [Drawing.Color]::FromArgb(150, 150, 150)
$cAzul = [Drawing.Color]::FromArgb(59, 140, 235)
$cVerde = [Drawing.Color]::FromArgb(84, 196, 92)
$cProm = [Drawing.Color]::FromArgb(230, 160, 30)
$cAcento = [Drawing.Color]::FromArgb(36, 168, 148)
$g.Clear($cFondo)

$fTit = New-Object Drawing.Font 'Segoe UI Semibold', (17 * $s), ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
$fSub = New-Object Drawing.Font 'Segoe UI', (13 * $s), ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
$fTienda = New-Object Drawing.Font 'Segoe UI', (14 * $s), ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
$fVal = New-Object Drawing.Font 'Segoe UI Semibold', (14 * $s), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
$bTexto = New-Object Drawing.SolidBrush $cTexto
$bGris = New-Object Drawing.SolidBrush $cGris

# Título y leyenda
$g.FillRectangle((New-Object Drawing.SolidBrush $cAcento), 16 * $s, 22 * $s, 7 * $s, 20 * $s)
$g.DrawString("Precio ahora por tienda (nuevas):  $Producto", $fTit, $bTexto, 34 * $s, 19 * $s)
$g.DrawString("Actualizado " + $ahoraMX.ToString('d MMM yyyy, HH:mm', [Globalization.CultureInfo]::GetCultureInfo('es-MX')) + " · solo consolas nuevas", $fSub, $bGris, 16 * $s, 54 * $s)
$lx = 16 * $s; $ly = 84 * $s
$g.FillEllipse((New-Object Drawing.SolidBrush $cVerde), $lx, $ly, 12 * $s, 12 * $s); $g.DrawString("La más barata", $fSub, $bGris, $lx + 17 * $s, $ly - 3 * $s)
$lx += 130 * $s
$g.FillEllipse((New-Object Drawing.SolidBrush $cAzul), $lx, $ly, 12 * $s, 12 * $s); $g.DrawString("Nuevo", $fSub, $bGris, $lx + 17 * $s, $ly - 3 * $s)
$lx += 80 * $s
$pPromLey = New-Object Drawing.Pen $cProm, (2 * $s); $pPromLey.DashStyle = 'Dash'
$g.DrawLine($pPromLey, $lx + 5 * $s, $ly - 2 * $s, $lx + 5 * $s, $ly + 14 * $s); $g.DrawString("Promedio", $fSub, $bGris, $lx + 13 * $s, $ly - 3 * $s)

# Márgenes según el texto más largo
$etq = { param($d) $e = if ($d.noLlega) { $d.tienda + " (no llega a Delicias)" } else { $d.tienda }; if ($d.vieja) { $e += " · hace " + [math]::Floor($EdadIA) + " h" }; $e }
$wL = ($datos | ForEach-Object { $g.MeasureString((& $etq $_), $fTienda).Width } | Measure-Object -Maximum).Maximum
$wR = ($datos | ForEach-Object { $g.MeasureString((& $fmt $_.precio), $fVal).Width } | Measure-Object -Maximum).Maximum
$mL = [math]::Min($wL + 24 * $s, $W * 0.4); $mR = $wR + 24 * $s
$x = { param($v) $mL + ($W - $mL - $mR) * ($v / $max) }

$minP = $validos[0].precio
$cNo = [Drawing.Color]::FromArgb(90, 90, 90)
$bNo = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(140, 140, 140))
$fmtD = New-Object Drawing.StringFormat; $fmtD.Alignment = 'Far'; $fmtD.LineAlignment = 'Center'
$fmtI = New-Object Drawing.StringFormat; $fmtI.LineAlignment = 'Center'
for ($i = 0; $i -lt $datos.Count; $i++) {
    $d = $datos[$i]
    $y = $top + $i * $rowH
    $cy = $y + $rowH / 2
    $g.DrawString((& $etq $d), $fTienda, $(if ($d.noLlega) { $bNo } else { $bTexto }), (New-Object Drawing.RectangleF 0, $y, ($mL - 10 * $s), $rowH), $fmtD)
    $col = if ($d.noLlega) { $cNo } elseif ($d.precio -eq $minP) { $cVerde } else { $cAzul }
    $bw = [math]::Max(2 * $s, (& $x $d.precio) - $mL)
    $bh = $rowH - 18 * $s
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $r = 4 * $s; $bx = $mL; $by = $cy - $bh / 2
    $path.AddArc($bx, $by, $r * 2, $r * 2, 180, 90); $path.AddArc($bx + $bw - $r * 2, $by, $r * 2, $r * 2, 270, 90)
    $path.AddArc($bx + $bw - $r * 2, $by + $bh - $r * 2, $r * 2, $r * 2, 0, 90); $path.AddArc($bx, $by + $bh - $r * 2, $r * 2, $r * 2, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush $col), $path)
    $g.DrawString((& $fmt $d.precio), $fVal, $bTexto, (New-Object Drawing.RectangleF ((& $x $d.precio) + 8 * $s), $y, $mR, $rowH), $fmtI)
}

if ($datos.Count -gt 1) {
    $ax = & $x $prom
    $pProm = New-Object Drawing.Pen $cProm, (2 * $s); $pProm.DashStyle = 'Dash'
    $g.DrawLine($pProm, $ax, $top - 6 * $s, $ax, $H - $bottom + 6 * $s)
    $tProm = "Promedio " + (& $fmt $prom)
    $fProm = New-Object Drawing.Font 'Segoe UI Semibold', (13 * $s), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $tw = $g.MeasureString($tProm, $fProm).Width
    $g.DrawString($tProm, $fProm, (New-Object Drawing.SolidBrush $cProm), [math]::Min($ax - $tw / 2, $W - $tw - 4 * $s), $top - 30 * $s)
}

$g.Dispose()
$bmp.Save($Salida, [Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("Gráfica guardada: {0} ({1} tiendas; más barata {2} en {3})" -f $Salida, $datos.Count, (& $fmt $minP), $validos[0].tienda)
