# Funciones compartidas (no imprime el token nunca).
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:DirPS5 = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-TelegramToken {
    if ($env:TELEGRAM_TOKEN) { return $env:TELEGRAM_TOKEN.Trim() }
    $f = Join-Path $script:DirPS5 "telegram-token.dat"
    if (-not (Test-Path $f)) { throw "No hay token guardado. Ejecuta guardar-token.ps1" }
    $s = (Get-Content $f -Raw).Trim() | ConvertTo-SecureString -ErrorAction Stop
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Invoke-Telegram([string]$metodo, $datos) {
    $url = "https://api.telegram.org/bot$(Get-TelegramToken)/$metodo"
    $json = $datos | ConvertTo-Json -Compress -Depth 5
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    try {
        return Invoke-RestMethod -Method Post -Uri $url -Body $bytes -ContentType "application/json; charset=utf-8"
    } catch {
        # Quita el token de cualquier mensaje de error
        throw ($_.Exception.Message -replace 'bot[0-9]+:[A-Za-z0-9_-]+', 'bot***')
    }
}
