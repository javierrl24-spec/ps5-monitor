# Vigila el canal público de Telegram @OfertonesMexico (sin IA, sin tokens) y, cuando publique una consola
# PS5 Slim Digital o con disco, te manda una copia idéntica (misma foto, texto, enlaces y cupones) + enlace al post original.
# Uso: monitor-ofertones.ps1            (normal, lo corre el Programador de tareas cada 5 min)
#      monitor-ofertones.ps1 -Probar N  (manda una copia del post N del canal, para ver cómo se ve)
param([int]$Probar = 0, [string]$De = "OfertonesMexico", [int]$Bucle = 0, [int]$Cada = 30)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir "telegram-comun.ps1")
$canales = @(@{ u = "OfertonesMexico"; n = "Ofertones México" }, @{ u = "ofertasimperdiblesmexico"; n = "Ofertas Imperdibles México" }, @{ u = "MegaOfertonesMX"; n = "Mega Ofertones MX" })
$canal = "OfertonesMexico"; $nombreCanal = "Ofertones México"
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
$fEstado = Join-Path $dir "ofertones-ultimo.txt"
$log = Join-Path $dir "monitor-log.txt"
function Log($m) { Add-Content -Path $log -Value ("{0} [Ofertones] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m) -Encoding UTF8 }
$chatId = if ($env:TELEGRAM_CHAT) { $env:TELEGRAM_CHAT.Trim() } else { (Get-Content (Join-Path $dir "telegram-chat.txt") -Raw).Trim() }

function Leer-Pagina([string]$extra) {
    $html = (Invoke-WebRequest -Uri ("https://t.me/s/$canal" + $extra) -UseBasicParsing -UserAgent $ua -TimeoutSec 30).Content
    $posts = @()
    $bloques = [regex]::Split($html, '(?=<div class="tgme_widget_message_wrap)')
    foreach ($b in $bloques) {
        $m = [regex]::Match($b, 'data-post="[^/]+/(\d+)"'); if (-not $m.Success) { continue }
        $id = [int]$m.Groups[1].Value
        $t = [regex]::Match($b, '(?s)<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>\s*(?:<div class="tgme_widget_message_footer|<div class="tgme_widget_message_reply_markup|</div>)')
        $foto = [regex]::Match($b, "tgme_widget_message_photo_wrap[^>]*background-image:url\('([^']+)'\)").Groups[1].Value
        $fecha = [regex]::Match($b, '<time[^>]*datetime="([^"]+)"').Groups[1].Value
        $posts += [pscustomobject]@{ id = $id; html = $t.Groups[1].Value; foto = $foto; fecha = $fecha }
    }
    return $posts
}

# Convierte el HTML del canal al HTML que acepta Telegram (b, i, u, s, code, a href), conservando enlaces y emojis
function A-HtmlTelegram([string]$h) {
    $h = $h -replace '<br\s*/?>', "`n"
    $h = [regex]::Replace($h, '<i class="emoji"[^>]*>(.*?)</i>', '$1')
    $h = [regex]::Replace($h, '<tg-emoji[^>]*>(.*?)</tg-emoji>', '$1')
    $h = [regex]::Replace($h, '<a [^>]*href="([^"]+)"[^>]*>', '<a href="$1">')
    $h = [regex]::Replace($h, '<(b|strong)(\s[^>]*)?>', '<b>'); $h = $h -replace '</strong>', '</b>'
    $h = [regex]::Replace($h, '<(i|em)(\s[^>]*)?>', '<i>'); $h = $h -replace '</em>', '</i>'
    $h = [regex]::Replace($h, '<(?!/?(b|i|u|s|code|a)(>|\s))[^>]+>', '')   # quita cualquier otra etiqueta
    # --- Limpieza para que se lea bien ---
    $h = [regex]::Replace($h, '<b>\s*([^<a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]{1,8}?)\s*</b>\s*', '$1 ')   # emojis sueltos en negritas -> emoji + espacio
    $h = [regex]::Replace($h, '<a href="(https?://[^"]+)">\s*https?://[^<]+</a>', '<a href="$1">abrir oferta</a>')  # URL larga -> "abrir oferta"
    $h = [regex]::Replace($h, '(?i)(ver oferta|compra aqu[ií]|link|enlace|ver aqu[ií])\s*:\s*<a href="([^"]+)">abrir oferta</a>', '<a href="$2"><b>$1</b></a>')
    $lineas = $h -split "`n" | Where-Object {
        $_ -notmatch '(?i)[uú]nete a nuestros|ofertonesmexico\.com|href="\?q=|#\w+@\w+|^\s*(<b>)?[^\w<]{1,4}(</b>)?\s*\d+[KkMm]?\s*$'
    } | ForEach-Object { $_.Trim() }
    $h = ($lineas -join "`n")
    $h = [regex]::Replace($h, "(`n\s*){3,}", "`n`n")                           # sin renglones vacíos de más
    $h = [regex]::Replace($h.Trim(), '^([^\n<]+)', '<b>$1</b>')               # primera línea (tienda + producto) en negritas
    $h = [regex]::Replace($h, '(?im)^(.*precio final.*?:\s*)((?:&#036;|\$)\s?[\d,\.]+)', '$1<b>$2</b>')  # precio final en negritas
    return $h.Trim()
}
function Texto-Plano([string]$h) { [System.Net.WebUtility]::HtmlDecode(([regex]::Replace(($h -replace '<br\s*/?>', ' '), '<[^>]+>', ' ') -replace '\s+', ' ')) }

# ¿Es una consola PS5 Slim Digital o con disco? (no Pro, no juegos, no accesorios)
function Es-PS5([string]$t) {
    if ($t -match '(?i)ps4|ps3|playstation ?4|playstation ?3|vita|\bpsp\b') { return $false }
    $esPS5 = $t -match '(?i)\bps ?5\b|playstation\s?5|playstation®\s?5|play ?station ?5'
    if (-not $esPS5 -and $t -match '(?i)play ?station' -and $t -match '(?i)slim|825 ?gb|1 ?tb|astro bot|gran turismo 7') { $esPS5 = $true }
    if (-not $esPS5) { return $false }
    if ($t -notmatch '(?i)consola|console|bundle|paquete|slim|edici[oó]n digital|digital edition|est[aá]ndar|standard') { return $false }
    if ($t -match '(?i)\bps5 pro\b|playstation\s?5 pro|\bpro\b.{0,12}(2 ?tb|consola)') { return $false }
    if ($t -match '(?i)control(?!\s?inal[aá]mbrico dualsense incluido)|dualsense|juego para|videojuego|portal|aud[ií]fonos|headset|soporte|funda|base de carga|cargador|unidad de disco|lector de disco para|skin|volante|tarjeta de regalo|playstation plus|ps plus|cubierta|carcasa|tapas|faceplate|auriculares|teclado|monitor|switch hdmi') { return $false }
    return $true
}

function Mandar-Copia($p) {
    $cuerpo = A-HtmlTelegram $p.html
    $cuando = ""
    if ($p.fecha) {
        try {
            $utc = [datetimeoffset]::Parse($p.fecha).UtcDateTime
            $mx = [TimeZoneInfo]::ConvertTimeFromUtc($utc, [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time (Mexico)'))
            $cuando = "🕒 " + $mx.ToString("d MMM yyyy, HH:mm", [Globalization.CultureInfo]::GetCultureInfo('es-MX')) + " (CDMX)`n"
        } catch { }
    }
    $pie = "📢 <b>" + $nombreCanal + "</b>`n" + $cuando + "`n" + $cuerpo + "`n`n🔗 <a href=""https://t.me/$canal/$($p.id)"">Ver en Telegram</a>"
    try {
        # enviar-telegram.ps1 ya sabe: foto por URL → si falla, la descarga y la sube → si falla, solo texto
        $tmp = Join-Path $env:TEMP ("ofertones_" + $p.id + ".txt")
        [IO.File]::WriteAllText($tmp, $pie, (New-Object Text.UTF8Encoding $false))
        $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dir 'enviar-telegram.ps1'), '-Archivo', $tmp, '-Html')
        if ($p.foto) { $args2 += @('-FotoUrl', $p.foto) }
        $salida = & powershell.exe @args2 2>&1 | Out-String
        Remove-Item $tmp -ErrorAction SilentlyContinue
        if ($salida -notmatch 'Mensaje enviado') { throw "enviar-telegram: $salida" }
        if ($salida -match 'No se pudo mandar la foto') { Log "Post $($p.id): sin foto ($($salida.Trim()))" }
    } catch {
        Log "Formato rechazado en post $($p.id): $($_.Exception.Message); se manda en texto plano"
        # Si el formato falla, manda el texto plano con el enlace al post (Telegram muestra la vista previa del original)
        $null = Invoke-Telegram "sendMessage" @{ chat_id = $chatId; text = ("📢 " + $nombreCanal + "`n`n" + (Texto-Plano $p.html) + "`n`nhttps://t.me/$canal/$($p.id)") }
    }
}

if ($Probar -gt 0) {
    $x = $canales | Where-Object { $_.u -eq $De } | Select-Object -First 1; $canal = $x.u; $nombreCanal = $x.n
    $ps = Leer-Pagina ("?before=" + ($Probar + 1))
    $p = $ps | Where-Object { $_.id -eq $Probar } | Select-Object -First 1
    if (-not $p) { throw "No encontré el post $Probar" }
    Mandar-Copia $p; Write-Host "Copia del post $Probar enviada."; return
}

$script:hashes = @{}
function Guardar-Estado {
    # Sube el estado con la API de GitHub (sin git pull/rebase, que se atoraba con los otros commits)
    $ErrorActionPreference = 'Continue'
    $lista = @('ofertones-ultimo.txt', 'ofertones-estado.json', 'ofertones-enviados.json')
    if (-not $script:ultLatido -or ((Get-Date) - $script:ultLatido).TotalMinutes -ge 15) { $lista += 'latido.txt'; $script:ultLatido = Get-Date }
    foreach ($f in $lista) {
        try {
            $ruta = Join-Path $dir $f
            if (-not (Test-Path $ruta)) { continue }
            $h = (Get-FileHash $ruta -Algorithm SHA1).Hash
            if ($script:hashes[$f] -eq $h) { continue }
            $sha = & gh api "repos/$env:GITHUB_REPOSITORY/contents/$f" --jq '.sha' 2>$null
            $o = @{ message = "estado ofertones"; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ruta)) }
            if ($sha) { $o.sha = "$sha".Trim() }
            $tmp = Join-Path $env:TEMP 'gh-est.json'
            [IO.File]::WriteAllText($tmp, ($o | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            & gh api -X PUT "repos/$env:GITHUB_REPOSITORY/contents/$f" --input $tmp 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $script:hashes[$f] = $h } else { Log "No se pudo guardar $f" }
        } catch { Log "Error guardando ${f}: $($_.Exception.Message)" }
    }
}
function Pasada {
# --- Normal: revisa los 3 canales; estado por canal y sin repetir la misma oferta publicada en dos canales ---
$fEst = Join-Path $dir "ofertones-estado.json"
$est = @{}
if (Test-Path $fEst) { (Get-Content $fEst -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $est[$_.Name] = [int]$_.Value } }
elseif (Test-Path $fEstado) { $est["OfertonesMexico"] = [int](Get-Content $fEstado -Raw).Trim() }   # migración del estado viejo
$fVistos = Join-Path $dir "ofertones-enviados.json"
$vistos = @{}
if (Test-Path $fVistos) { (Get-Content $fVistos -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $vistos[$_.Name] = $_.Value } }
$limite = (Get-Date).ToUniversalTime().AddHours(-12).ToString('s')
foreach ($k in @($vistos.Keys)) { if ($vistos[$k] -lt $limite) { $vistos.Remove($k) } }
function Clave-Oferta([string]$s) {
    $s = $s -replace '(?i)^.*?(amazon|mercado ?libre|walmart|bodega aurrera|soriana|liverpool|coppel|costco|sam.s club|elektra|chedraui)\s*:\s*', ''
    $s = ($s.ToLower() -replace '[^a-z0-9áéíóúñ ]', ' ' -replace '\s+', ' ').Trim()
    return (($s -split ' ' | Select-Object -First 6) -join ' ')
}
foreach ($c in $canales) {
    $canal = $c.u; $nombreCanal = $c.n
    try {
        $ultimo = if ($est.ContainsKey($canal)) { [int]$est[$canal] } else { 0 }
        $todos = @(); $pag = Leer-Pagina ""; $todos += $pag
        $vueltas = 0
        while ($ultimo -gt 0 -and $pag.Count -gt 0 -and (($pag | Measure-Object id -Minimum).Minimum -gt $ultimo + 1) -and $vueltas -lt 4) {
            $pag = Leer-Pagina ("?before=" + ($pag | Measure-Object id -Minimum).Minimum); $todos += $pag; $vueltas++
        }
        if ($todos.Count -eq 0) { Log "No se pudo leer $canal"; continue }
        $max = ($todos | Measure-Object id -Maximum).Maximum
        if ($ultimo -eq 0) { $est[$canal] = $max; Log "Inicio ${canal}: último post $max"; continue }
        $nuevos = $todos | Where-Object { $_.id -gt $ultimo } | Sort-Object id -Unique
        $enviados = 0
        foreach ($p in $nuevos) {
            $plano = Texto-Plano $p.html
            if (-not (Es-PS5 $plano)) { continue }
            $clave = Clave-Oferta $plano
            if ($clave.Length -gt 10 -and $vistos.ContainsKey($clave)) { Log "Repetido (ya enviado): $canal/$($p.id)"; continue }
            Mandar-Copia $p; $enviados++; Log "Copiado $canal/$($p.id)"
            if ($clave.Length -gt 10) { $vistos[$clave] = (Get-Date).ToUniversalTime().ToString('s') }
        }
        $est[$canal] = $max
        if ($enviados -eq 0) { Log "Sin PS5 en $(@($nuevos).Count) posts nuevos de $canal" }
    } catch { Log "FALLA ${canal}: $($_.Exception.Message)" }
}
($est | ConvertTo-Json -Compress) | Set-Content $fEst -Encoding UTF8
($vistos | ConvertTo-Json -Compress) | Set-Content $fVistos -Encoding UTF8
}
if ($Bucle -le 0) { Pasada; return }
# Modo continuo: revisa cada $Cada segundos durante $Bucle minutos. Escribe latido.txt en cada vuelta para que el vigilante sepa que sigue vivo.
$fin = (Get-Date).AddMinutes($Bucle); $ultGuardado = Get-Date
$fLat = Join-Path $dir 'latido.txt'
while ((Get-Date) -lt $fin) {
    try { Pasada } catch { Log "FALLA pasada: $($_.Exception.Message)" }
    Set-Content -Path $fLat -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    if (((Get-Date) - $ultGuardado).TotalMinutes -ge 4) { Guardar-Estado; $ultGuardado = Get-Date }
    Start-Sleep -Seconds $Cada
}
Guardar-Estado