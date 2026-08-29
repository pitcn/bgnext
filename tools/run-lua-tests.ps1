$ErrorActionPreference = "Stop"

$lua = Get-Command lua5.1, lua -ErrorAction SilentlyContinue | Select-Object -First 1
if ($lua) {
    $luaPath = $lua.Source
} else {
    $knownPaths = @(
        "C:\Program Files (x86)\Lua\5.1\lua.exe",
        "C:\Program Files\Lua\5.1\lua.exe"
    )
    $luaPath = $knownPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not $luaPath) {
    throw "Lua 5.1 is required. Install rjpcomputing.luaforwindows."
}

& $luaPath tests/run.lua
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
