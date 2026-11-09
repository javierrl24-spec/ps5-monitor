# Vigila el canal público de Telegram @OfertonesMexico (sin IA, sin tokens) y, cuando publique una consola
# PS5 Slim Digital o con disco, te manda una copia idéntica (misma foto, texto, enlaces y cupones) + enlace al post original.
# Uso: monitor-ofertones.ps1            (normal, lo corre el Programador de tareas cada 5 min)
#      monitor-ofertones.ps1 -Probar N  (manda una copia del post N del canal, para ver cómo se ve)
param([int]$Probar = 0)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir "telegram-comun.ps1")
$canal = "OfertonesMexico"
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
    if ($t -notmatch '(?i)ps5|playstation\s?5|playstation®\s?5|play station 5') { return $false }
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
    $pie = "📢 <b>Ofertones México</b>`n" + $cuando + "`n" + $cuerpo + "`n`n🔗 <a href=""https://t.me/$canal/$($p.id)"">Ver en Telegram</a>"
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
        $null = Invoke-Telegram "sendMessage" @{ chat_id = $chatId; text = ("📢 Ofertones México`n`n" + (Texto-Plano $p.html) + "`n`nhttps://t.me/$canal/$($p.id)") }
    }
}

if ($Probar -gt 0) {
    $ps = Leer-Pagina ("?before=" + ($Probar + 1))
    $p = $ps | Where-Object { $_.id -eq $Probar } | Select-Object -First 1
    if (-not $p) { throw "No encontré el post $Probar" }
    Mandar-Copia $p; Write-Host "Copia del post $Probar enviada."; return
}

$ultimo = if (Test-Path $fEstado) { [int](Get-Content $fEstado -Raw).Trim() } else { 0 }
$todos = @(); $pag = Leer-Pagina ""; $todos += $pag
# Si hubo muchos posts desde la última vez, lee hasta 4 páginas hacia atrás
$vueltas = 0
while ($ultimo -gt 0 -and $pag.Count -gt 0 -and (($pag | Measure-Object id -Minimum).Minimum -gt $ultimo + 1) -and $vueltas -lt 4) {
    $pag = Leer-Pagina ("?before=" + ($pag | Measure-Object id -Minimum).Minimum); $todos += $pag; $vueltas++
}
if ($todos.Count -eq 0) { Log "No se pudo leer el canal"; return }
$max = ($todos | Measure-Object id -Maximum).Maximum
if ($ultimo -eq 0) { Set-Content $fEstado $max; Log "Inicio: último post $max"; return }

$nuevos = $todos | Where-Object { $_.id -gt $ultimo } | Sort-Object id -Unique
$enviados = 0
foreach ($p in $nuevos) {
    if (Es-PS5 (Texto-Plano $p.html)) { Mandar-Copia $p; $enviados++; Log "Copiado post $($p.id)" }
}
Set-Content $fEstado $max
if ($enviados -eq 0) { Log "Sin PS5 en $(@($nuevos).Count) posts nuevos" }
