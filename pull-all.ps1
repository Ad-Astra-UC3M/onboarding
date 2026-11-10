# pull-all.ps1 - Ad Astra UC3M
# Downloads the latest changes from GitHub for every repository inside this
# folder (and one level of subfolders). It only runs "git pull --ff-only":
# it never pushes and never touches local changes. Repositories with
# uncommitted work are skipped and reported.
#
# ASCII only on purpose: this file is run from disk by Windows PowerShell 5.1.

param(
    [string]$Root = $PSScriptRoot,
    [switch]$NoPause
)

if (-not $Root) { $Root = (Get-Location).Path }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git no esta instalado. Ejecuta primero el setup de Ad Astra." -ForegroundColor Red
    if (-not $NoPause) { [void](Read-Host "Pulsa Enter para cerrar") }
    return
}

# Collect repositories: Root\<repo> and Root\<folder>\<repo>
$repos = @()
foreach ($dir in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) {
        $repos += $dir
    } else {
        foreach ($sub in @(Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath (Join-Path $sub.FullName '.git')) { $repos += $sub }
        }
    }
}

if ($repos.Count -eq 0) {
    Write-Host "No hay repositorios en $Root" -ForegroundColor Yellow
    if (-not $NoPause) { [void](Read-Host "Pulsa Enter para cerrar") }
    return
}

$updated = 0; $skipped = 0; $failed = 0
foreach ($repo in $repos) {
    $path = $repo.FullName
    Write-Host ""
    Write-Host "== $($repo.Name)" -ForegroundColor Cyan

    $dirty = & git -C $path status --porcelain 2>$null
    if ($dirty) {
        Write-Host "   Saltado: tienes cambios sin commit. Haz commit (o descartalos) y vuelve a ejecutar." -ForegroundColor Yellow
        $skipped++
        continue
    }

    & git -C $path rev-parse --verify --quiet HEAD 2>$null | Out-Null
    $hasCommits = ($LASTEXITCODE -eq 0)

    & git -C $path pull --ff-only
    if ($LASTEXITCODE -eq 0) {
        $updated++
    } elseif (-not $hasCommits) {
        Write-Host "   Repositorio vacio todavia, nada que descargar." -ForegroundColor Yellow
        $skipped++
    } else {
        Write-Host "   Fallo: no se pudo actualizar (rama sin remoto, conflicto o sin conexion)." -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Resumen: $updated actualizados, $skipped saltados, $failed con fallo." -ForegroundColor Green
if (-not $NoPause) { [void](Read-Host "Pulsa Enter para cerrar") }
