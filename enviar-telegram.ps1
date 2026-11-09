# Uso:
#   enviar-telegram.ps1 -Archivo C:\ruta\mensaje.txt [-Html]
#   enviar-telegram.ps1 -Mensaje "texto" [-Html]
#   enviar-telegram.ps1 -FotoUrl "https://.../imagen.jpg" -Archivo C:\ruta\pie.txt -Html
#     (manda la foto con un pie de hasta 1024 caracteres; Telegram descarga la imagen de la URL)
# -Html: el texto usa formato HTML de Telegram (<b>, <i>, <u>, <s>, <code>, <a href="...">, <blockquote>).
#        Escapa &, < y > del texto normal como &amp; &lt; &gt;
#   enviar-telegram.ps1 -FotoArchivo C:\ruta\captura.png -Archivo C:\ruta\pie.txt -Html
#     (sube una imagen local, por ejemplo una captura del navegador)
param([string]$Mensaje, [string]$Archivo, [switch]$Html, [string]$FotoUrl, [string]$FotoArchivo)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "telegram-comun.ps1")
if ($Archivo) { $Mensaje = [IO.File]::ReadAllText($Archivo, [Text.Encoding]::UTF8) }
if (-not $Mensaje -and -not $FotoUrl -and -not $FotoArchivo) { throw "Falta -Mensaje, -Archivo, -FotoUrl o -FotoArchivo" }
$fChat = Join-Path $script:DirPS5 "telegram-chat.txt"
if (-not $env:TELEGRAM_CHAT -and -not (Test-Path $fChat)) { throw "No hay chat guardado." }
$chatId = if ($env:TELEGRAM_CHAT) { $env:TELEGRAM_CHAT.Trim() } else { (Get-Content $fChat -Raw).Trim() }

function Enviar-Texto([string]$texto) {
    # Telegram acepta hasta 4096 caracteres: parte por párrafos para no romper etiquetas HTML
    $partes = New-Object System.Collections.Generic.List[string]
    $actual = ""
    foreach ($p in ($texto -split "(?<=\n\n)")) {
        if (($actual.Length + $p.Length) -gt 3900 -and $actual) { $partes.Add($actual); $actual = "" }
        $actual += $p
    }
    if ($actual) { $partes.Add($actual) }
    foreach ($parte in $partes) {
        $d = @{ chat_id = $chatId; text = $parte; disable_web_page_preview = $true }
        if ($Html) { $d.parse_mode = "HTML" }
        $null = Invoke-Telegram "sendMessage" $d
    }
}

function Subir-Foto([string]$ruta, [string]$pie) {
    Add-Type -AssemblyName System.Net.Http
    $cli = New-Object System.Net.Http.HttpClient
    $form = New-Object System.Net.Http.MultipartFormDataContent
    $form.Add((New-Object System.Net.Http.StringContent($chatId)), "chat_id")
    if ($pie) {
        $form.Add((New-Object System.Net.Http.StringContent($pie, [Text.Encoding]::UTF8)), "caption")
        if ($Html) { $form.Add((New-Object System.Net.Http.StringContent("HTML")), "parse_mode") }
    }
    $bytes = New-Object System.Net.Http.ByteArrayContent(,[IO.File]::ReadAllBytes($ruta))
    $form.Add($bytes, "photo", [IO.Path]::GetFileName($ruta))
    $resp = $cli.PostAsync("https://api.telegram.org/bot$(Get-TelegramToken)/sendPhoto", $form).Result
    if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode)" }
}

if ($FotoArchivo) {
    # Telegram cuenta 1024 caracteres VISIBLES en el pie (las etiquetas y URLs de los enlaces no cuentan)
    $visible = if ($Mensaje) { [System.Net.WebUtility]::HtmlDecode(($Mensaje -replace '<[^>]+>', '')).Length } else { 0 }
    $pie = if ($Mensaje -and $visible -le 1000) { $Mensaje } else { "" }
    try { Subir-Foto $FotoArchivo $pie; if (-not $pie -and $Mensaje) { Enviar-Texto $Mensaje } }
    catch { Write-Host "No se pudo mandar la foto ($($_.Exception.Message)); mando solo el texto."; if ($Mensaje) { Enviar-Texto $Mensaje } }
} elseif ($FotoUrl) {
    $pie = if ($Mensaje) { $Mensaje } else { "" }
    $resto = ""
    if ($pie.Length -gt 1000) { $resto = $pie; $pie = "" }
    $d = @{ chat_id = $chatId; photo = $FotoUrl }
    if ($pie) { $d.caption = $pie; if ($Html) { $d.parse_mode = "HTML" } }
    try { $null = Invoke-Telegram "sendPhoto" $d }
    catch {
        # Plan B: descargar la imagen aquí y subirla como archivo (algunas tiendas no dejan que Telegram la descargue)
        try {
            $tmp = Join-Path $env:TEMP ("ps5foto_" + [guid]::NewGuid().ToString("N") + ".jpg")
            Invoke-WebRequest -Uri $FotoUrl -OutFile $tmp -UseBasicParsing -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
            try { Subir-Foto $tmp $pie } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        } catch {
            Write-Host "No se pudo mandar la foto ($($_.Exception.Message -replace 'bot[0-9]+:[A-Za-z0-9_-]+', 'bot***')); mando solo el texto."
            $resto = $Mensaje
        }
    }
    if ($resto) { Enviar-Texto $resto }
} else {
    Enviar-Texto $Mensaje
}
Write-Host "Mensaje enviado a Telegram."
