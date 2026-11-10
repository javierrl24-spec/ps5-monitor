# Monitor rápido de PS5 SIN IA (no gasta tokens). Corre cada 15 min con el Programador de tareas de Windows.
# Revisa las tiendas que dejan leer sus precios con una consulta simple: Elektra, Chedraui, Cyberpuerta y Liverpool.
# Avisa por Telegram solo si: baja un precio, una PS5 vuelve a tener existencias / aparece nueva, o llega al precio objetivo.
# Guarda el último estado en monitor-estado.json y una foto rápida en monitor-ultimo.json (la revisión con IA la lee).
param([switch]$Prueba, [switch]$Ver)   # -Prueba: manda un resumen aunque no haya cambios · -Ver: solo muestra lo leído, no guarda ni manda nada
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir "telegram-comun.ps1")
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
$CP = "33000"
# Precios objetivo (nuevas). La revisión con IA puede actualizarlos en monitor-objetivos.json
$objetivos = @{ "PS5 Slim Digital" = 7300; "PS5 Slim Disco" = 8800; "PS5 Pro" = 15500 }
$fObj = Join-Path $dir "monitor-objetivos.json"
if (Test-Path $fObj) { (Get-Content $fObj -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $objetivos[$_.Name] = [double]$_.Value } }
$log = Join-Path $dir "monitor-log.txt"
function Log($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m) -Encoding UTF8 }

# Modo noche: de 23:00 a 06:00 (hora de Delicias) este monitor no revisa ni avisa; solo siguen los canales de Telegram
$horaMX = [TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, [TimeZoneInfo]::Utc, [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time (Mexico)')).Hour
if (-not $Prueba -and -not $Ver -and ($horaMX -ge 23 -or $horaMX -lt 6)) { Log "Modo noche (23-6 h): sin revisión de tiendas"; return }
function Get-Web($url) { (Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $ua -TimeoutSec 30 -Headers @{ "Accept-Language" = "es-MX" }).Content }

function Clasificar([string]$n, [double]$precio) {
    if ($precio -lt 6000 -or $precio -gt 45000) { return $null }
    if ($n -match '(?i)portal|control|dualsense|unidad de disco|lector de disco para|juego para|videojuego|soporte|funda|base |cargador|reproductor|aud[ií]fono|cable|disco duro|ssd ') { return $null }
    if ($n -notmatch '(?i)ps5|playstation ?5|play station ?5|playstation®5') { return $null }
    if ($n -match '(?i)nintendo|switch|xbox|ps4|playstation 4') { return $null }
    $c = if ($n -match '(?i)\bpro\b|2 ?tb') { "PS5 Pro" }
         elseif ($n -match '(?i)digital') { "PS5 Slim Digital" }
         elseif ($n -match '(?i)lector|disco|est[aá]ndar|standard|1 ?tb|f[ií]sic') { "PS5 Slim Disco" }
         elseif ($n -match '825') { "PS5 Slim Digital" }
         else { "PS5 Slim Disco" }   # PS5 sin "digital" ni "pro" = con lector
    $cond = if ($n -match '(?i)recertific|reacondic|renovad|refurb|open box|caja abierta') { "Reacondicionado" } else { "Nuevo" }
    $intl = $n -match '(?i)internacional|jap[oó]n|versi[oó]n us|importad'
    return @{ consola = $c; condicion = $cond; internacional = $intl }
}

$items = New-Object System.Collections.Generic.List[object]
function Add-Item($tienda, $id, $nombre, $precio, $antes, $disp, $url, $extra) {
    $k = Clasificar $nombre $precio
    if (-not $k) { return }
    $items.Add([pscustomobject]@{ tienda = $tienda; id = "$tienda|$id"; nombre = $nombre; consola = $k.consola; condicion = $k.condicion;
        internacional = $k.internacional; precio = [double]$precio; antes = [double]$antes; disponible = [bool]$disp; url = $url; extra = $extra })
}

$fallas = @()
# --- Tiendas VTEX (JSON público): Elektra y Chedraui ---
$vtex = @(
    @{ t = "Elektra";  base = "https://www.elektra.mx";       q = "consola ps5" },
    @{ t = "Chedraui"; base = "https://www.chedraui.com.mx";  q = "consola playstation 5" }
)
foreach ($v in $vtex) {
    try {
        $json = Get-Web ("{0}/api/catalog_system/pub/products/search?ft={1}&_from=0&_to=49" -f $v.base, [uri]::EscapeDataString($v.q))
        $prods = $json | ConvertFrom-Json
        foreach ($p in $prods) {
            foreach ($it in $p.items) {
                $s = $it.sellers | Select-Object -First 1
                $o = $s.commertialOffer
                Add-Item $v.t $it.itemId $p.productName $o.Price $o.ListPrice ($o.AvailableQuantity -gt 0) $p.link @{ base = $v.base; itemId = $it.itemId; seller = $s.sellerId; vendedor = $s.sellerName }
            }
        }
    } catch { $fallas += $v.t; Log "FALLA $($v.t): $($_.Exception.Message)" }
}

# --- Cyberpuerta (datos estructurados JSON-LD de la página de categoría) ---
try {
    $h = Get-Web "https://www.cyberpuerta.mx/Audio-y-Video/Consolas-y-Juegos/PlayStation-5-PS5/Consolas-PlayStation-5/"
    $m = [regex]::Match($h, '(?s)<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>')
    $ld = $m.Groups[1].Value | ConvertFrom-Json
    $lista = @($ld) | ForEach-Object { if ($_.itemListElement) { $_.itemListElement } elseif ($_.'@graph') { $_.'@graph' | Where-Object { $_.itemListElement } | ForEach-Object { $_.itemListElement } } }
    foreach ($e in $lista) {
        $pr = $e.item; if (-not $pr -or -not $pr.offers) { continue }
        Add-Item "Cyberpuerta" $pr.sku $pr.name $pr.offers.price 0 ($pr.offers.availability -match 'InStock') $pr.url $null
    }
} catch { $fallas += "Cyberpuerta"; Log "FALLA Cyberpuerta: $($_.Exception.Message)" }

# --- Liverpool (tarjetas del buscador) ---
try {
    $h = Get-Web "https://www.liverpool.com.mx/tienda?s=consola+ps5"
    foreach ($c in [regex]::Matches($h, '(?s)data-testid="(\d+)-card"(.*?)(?=data-testid="\d+-card"|</main>)')) {
        $id = $c.Groups[1].Value; $html = $c.Groups[2].Value
        $alt = [regex]::Match($html, 'alt="([^"]+)"').Groups[1].Value
        $href = [regex]::Match($html, 'href="(/tienda/pdp/[^"]+)"').Groups[1].Value
        if (-not $href) { $href = [regex]::Match($h, 'href="(/tienda/pdp/[^"]+/' + $id + ')"').Groups[1].Value }
        $txt = ([regex]::Replace($html, '<[^>]+>', ' ') -replace '\s+', ' ')
        $precios = [regex]::Matches($txt, '\$ ?([\d,]+) ?\. ?(\d\d)') | ForEach-Object { [double](($_.Groups[1].Value -replace ',', '') + '.' + $_.Groups[2].Value) }
        if (-not $precios) { continue }
        $url = if ($href) { "https://www.liverpool.com.mx" + [System.Net.WebUtility]::HtmlDecode($href) } else { "https://www.liverpool.com.mx/tienda?s=consola+ps5" }
        Add-Item "Liverpool" $id ([System.Net.WebUtility]::HtmlDecode($alt)) @($precios)[0] (@($precios) | Measure-Object -Maximum).Maximum $true $url $null
    }
} catch { $fallas += "Liverpool"; Log "FALLA Liverpool: $($_.Exception.Message)" }

if ($Ver) {
    $items | Sort-Object consola, condicion, precio | Format-Table tienda, consola, condicion, precio, disponible, internacional, @{ n = 'nombre'; e = { $_.nombre.Substring(0, [Math]::Min(60, $_.nombre.Length)) } } -AutoSize | Out-String -Width 220
    "Fallas: $($fallas -join ', ')"
    return
}

# --- ¿Llega a Delicias? (simulación de envío VTEX para CP 33000) ---
function Llega-A-Delicias($it) {
    if (-not $it.extra -or -not $it.extra.base) { return $null }
    try {
        $body = @{ items = @(@{ id = "$($it.extra.itemId)"; quantity = 1; seller = "$($it.extra.seller)" }); postalCode = $CP; country = "MEX" } | ConvertTo-Json -Depth 4 -Compress
        $r = Invoke-RestMethod -Method Post -Uri ($it.extra.base + "/api/checkout/pub/orderForms/simulation?sc=1") -Body $body -ContentType "application/json" -UserAgent $ua -TimeoutSec 30
        $slas = @($r.logisticsInfo | ForEach-Object { $_.slas }) | Where-Object { $_ }
        # Solo cuenta envío a domicilio; "Recoger en tienda" aparece aunque no haya existencias en Delicias
        $envio = @($slas | Where-Object { $_.deliveryChannel -eq 'delivery' })
        if ($envio.Count -gt 0) { return $true }
        if ($slas.Count -eq 0) { return $false }
        return $null
    } catch { return $null }
}

# --- Comparar con el estado anterior ---
$fEstado = Join-Path $dir "monitor-estado.json"
$antes = @{}
$primera = -not (Test-Path $fEstado)
if (-not $primera) { (Get-Content $fEstado -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $antes[$_.Name] = $_.Value } }

$fmt = { param($v) '$' + ([math]::Round($v)).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('en-US')) }
$esc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
$avisos = @()
$nuevoEstado = @{}
# Productos que la revisión con IA confirmó que NO llegan a Delicias (lista de nombres "Tienda|nombre" en monitor-no-llega.txt)
$noLlega = @()
$fNo = Join-Path $dir "monitor-no-llega.txt"
if (Test-Path $fNo) { $nombresNo = Get-Content $fNo -Encoding UTF8 | Where-Object { $_.Trim() } ; $noLlega = @($items | Where-Object { $nombresNo -contains ($_.tienda + '|' + $_.nombre) -or $nombresNo -contains ($_.tienda + '|' + $_.precio) } | ForEach-Object { $_.id }) }
foreach ($it in $items) {
    $nuevoEstado[$it.id] = @{ precio = $it.precio; disponible = $it.disponible; visto = (Get-Date -Format 's'); avisado = $(if ($antes[$it.id] -and $antes[$it.id].avisado -and $it.precio -le 10000) { [double]$antes[$it.id].avisado } else { $null }) }
    if ($primera -or -not $it.disponible) { continue }
    $prev = $antes[$it.id]
    $motivo = $null
    if (-not $prev) { $motivo = "🆕 <b>Nueva en la tienda</b>" }
    elseif (-not $prev.disponible) { $motivo = "🟢 <b>Volvió a haber existencias</b>" }
    elseif ($it.precio -lt [double]$prev.precio - 1) { $motivo = "🔻 <b>Bajó</b> de " + (& $fmt $prev.precio) }
    # Solo consolas NUEVAS: avisa únicamente al llegar a $10,000 o menos, y otra vez si baja de $9,000 (no cada $100)
    if ($it.condicion -eq 'Nuevo') {
        if ($it.precio -le 10000) {
            $av = $nuevoEstado[$it.id].avisado
            $nivelAntes = if ($null -eq $av) { 0 } elseif ([double]$av -lt 9000) { 2 } else { 1 }
            $nivel = if ($it.precio -lt 9000) { 2 } else { 1 }
            if ($nivel -gt $nivelAntes) {
                $motivo = $(if ($nivel -eq 2) { "🔥🔥 <b>Bajo `$9,000</b>" } else { "🔥 <b>A `$10,000 o menos</b>" })
                $nuevoEstado[$it.id].avisado = $it.precio
            } else { $motivo = $null }
        } else { $motivo = $null }   # arriba de $10,000 no avisa
    }    $obj = $objetivos[$it.consola]
    $enObjetivo = ($it.condicion -eq 'Nuevo' -and $obj -and $it.precio -le $obj)
    if (-not $motivo) { continue }
    # La simulación de envío de VTEX no es confiable (Elektra marca "Recoger en tienda" aunque no haya en Delicias)
    # y consultarla seguido provoca bloqueos; la disponibilidad la confirma la revisión con IA.
    $llega = $null
    if ($noLlega -contains $it.id) { Log "Descartada (no llega a $CP): $($it.tienda) $($it.nombre)"; continue }
    if ($llega -eq $false) { Log "Descartada (no llega a $CP): $($it.tienda) $($it.nombre) $($it.precio)"; continue }
    $linea = @()
    if ($enObjetivo) { $linea += "🔔 <b>PRECIO BAJO</b> (objetivo " + (& $fmt $obj) + ")" }
    $linea += "<b>" + (& $esc $it.tienda) + ": " + (& $esc $it.nombre) + "</b>"
    $linea += "💰 <b>" + (& $fmt $it.precio) + "</b>" + $(if ($it.antes -gt $it.precio + 1) { " <i>(antes " + (& $fmt $it.antes) + ")</i>" } else { "" })
    $linea += $motivo
    if ($it.condicion -ne 'Nuevo') { $linea += "♻️ Reacondicionada" }
    if ($it.internacional) { $linea += "🌎 Versión internacional" }
    if ($it.extra -and $it.extra.vendedor -and $it.extra.vendedor -notmatch '(?i)elektra|chedraui') { $linea += "🏪 Vendedor: " + (& $esc $it.extra.vendedor) }
    $linea += $(if ($llega -eq $true) { "🚚 Llega a CP $CP" } else { "⚠️ Verifica disponibilidad para Delicias" })
    $linea += "👉 <a href=""" + (& $esc $it.url) + """>abrir oferta</a>"
    $avisos += [pscustomobject]@{ orden = $(if ($enObjetivo) { 0 } else { 1 }); precio = $it.precio; texto = ($linea -join "`n") }
}
# Lo que no se vio esta vez se conserva marcado como no disponible (para detectar cuando vuelva)
foreach ($k in $antes.Keys) { if (-not $nuevoEstado.ContainsKey($k)) { $nuevoEstado[$k] = @{ precio = $antes[$k].precio; disponible = $false; visto = $antes[$k].visto; avisado = $antes[$k].avisado } } }
# Si una tienda falló, no la marques como agotada
foreach ($t in $fallas) { foreach ($k in $antes.Keys) { if ($k -like "$t|*") { $nuevoEstado[$k] = $antes[$k] } } }
$nuevoEstado | ConvertTo-Json -Depth 4 | Set-Content -Path $fEstado -Encoding UTF8

# Foto rápida para la revisión con IA: más barata disponible por tienda + consola + condición
$ultimo = $items | Where-Object { $_.disponible } | Group-Object tienda, consola, condicion | ForEach-Object {
    $b = $_.Group | Sort-Object precio | Select-Object -First 1
    [pscustomobject][ordered]@{ tienda = $b.tienda; producto = $b.consola; condicion = $b.condicion; precio = $b.precio; nombre = $b.nombre; internacional = $b.internacional; url = $b.url }
}
[pscustomobject]@{ revisado = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"); fallas = $fallas; precios = @($ultimo) } | ConvertTo-Json -Depth 4 |
    Set-Content -Path (Join-Path $dir "monitor-ultimo.json") -Encoding UTF8

$chatId = if ($env:TELEGRAM_CHAT) { $env:TELEGRAM_CHAT.Trim() } else { (Get-Content (Join-Path $dir "telegram-chat.txt") -Raw).Trim() }
function Mandar($texto) { $null = Invoke-Telegram "sendMessage" @{ chat_id = $chatId; text = $texto; parse_mode = "HTML"; disable_web_page_preview = $true } }

if ($avisos.Count -gt 0) {
    $cab = "⚡ <b>MONITOR PS5</b> · " + (Get-Date -Format 'HH:mm') + "`n━━━━━━━━━━━━━━━`n"
    $bloques = $avisos | Sort-Object orden, precio | Select-Object -First 8 | ForEach-Object { $_.texto }
    Mandar ($cab + ($bloques -join "`n━━━━━━━━━━━━━━━`n"))
    Log "Avisos enviados: $($avisos.Count)"
} elseif ($primera -or $Prueba) {
    $res = $items | Where-Object { $_.disponible -and $_.condicion -eq 'Nuevo' -and $noLlega -notcontains $_.id } | Group-Object consola | Sort-Object Name | ForEach-Object {
        $b = $_.Group | Sort-Object precio | Select-Object -First 1
        "• <b>" + $_.Name + "</b>: " + (& $fmt $b.precio) + " en " + $b.tienda
    }
    $t = "⚡ <b>MONITOR PS5 activo</b>`nRevisa cada 15 min Elektra, Chedraui, Cyberpuerta y Liverpool sin gastar tokens. Solo te escribe si algo baja, vuelve a haber o llega a tu precio objetivo.`n`nLo más barato que ve ahora:`n" + ($res -join "`n") + "`n`n" + ("{0} productos leídos" -f $items.Count) + $(if ($fallas) { "`n⚠️ No respondieron: " + ($fallas -join ", ") } else { "" })
    Mandar $t
    Log "Resumen enviado (primera vez o prueba). Productos: $($items.Count)"
} else {
    Log "Sin cambios. Productos: $($items.Count). Fallas: $($fallas -join ',')"
}
