# setup-adastra.ps1 - Ad Astra UC3M
# One-command setup for team members (Windows 10/11):
#
#   irm https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main/setup-adastra.ps1 | iex
#
# With parameters:
#   & ([scriptblock]::Create((irm <same url>))) -Folder "AdAstra-test" -DryRun
#
# Installs the tools, signs the member in to GitHub (in the browser), checks
# membership of the organization, configures Git, clones every repository into
# Desktop\Ad Astra and creates shortcuts. Safe to run again at any time.
#
# Compatibility notes for maintainers:
# - Must run on Windows PowerShell 5.1: no ternary, no ??, no &&, no $IsWindows.
# - Keep $ErrorActionPreference at 'Continue': in 5.1, native stderr under
#   'Stop' turns git's progress output into terminating errors.
# - Accents are fine in messages, but never use curly quotes or uppercase
#   accented O: read as ANSI they contain a byte that 5.1 parses as a quote.

param(
    [string]$Folder,
    [string]$ConfigPath,
    [string]$Name,
    [string]$Email,
    [string]$InstallProfile,
    [string]$Project,
    [string]$Area,
    [switch]$SkipInstall,
    [switch]$DryRun,
    [switch]$Force
)

# Windows PowerShell 5.1 reads a BOM-less file from disk as ANSI, which garbles
# every accent below (and adding a BOM would break "irm | iex"). So when this
# runs from a file on 5.1, re-read the file as UTF-8 and run that copy instead.
# Keep everything above and inside this block ASCII.
$script:ScriptDir = $PSScriptRoot
if ($AdAstraScriptDir) {
    $script:ScriptDir = $AdAstraScriptDir
} elseif ($PSCommandPath -and $PSVersionTable.PSVersion.Major -lt 6) {
    $AdAstraScriptDir = $PSScriptRoot
    $utf8Source = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
    & ([scriptblock]::Create($utf8Source)) @PSBoundParameters
    return
}

$ErrorActionPreference = 'Continue'
$script:OnWindows = ($env:OS -eq 'Windows_NT')
$script:Results = New-Object System.Collections.ArrayList
$script:LogPath = $null
$script:LoggedIn = $false
$DefaultRawBase = 'https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main'

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------
function Write-Log([string]$Text) {
    if ($script:LogPath) {
        try { Add-Content -LiteralPath $script:LogPath -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -Encoding UTF8 -ErrorAction Stop } catch { }
    }
}
function Write-Step([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan; Write-Log "== $Text" }
function Write-Ok([string]$Text)   { Write-Host "   [OK] $Text" -ForegroundColor Green;  Write-Log "[OK] $Text" }
function Write-Warn([string]$Text) { Write-Host "   [!]  $Text" -ForegroundColor Yellow; Write-Log "[!] $Text" }
function Write-Err([string]$Text)  { Write-Host "   [X]  $Text" -ForegroundColor Red;    Write-Log "[X] $Text" }
function Write-Info([string]$Text) { Write-Host "   $Text"; Write-Log $Text }

function Add-Result([string]$Step, [string]$Status, [string]$Detail) {
    [void]$script:Results.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $hint = '(s/n)'
    for ($i = 0; $i -lt 5; $i++) {
        $answer = (Read-Host "   $Question $hint")
        if ($null -eq $answer) { return $Default }
        $answer = $answer.Trim().ToLower()
        if ($answer -eq '') { return $Default }
        if ($answer -in @('s', 'si', 'y', 'yes')) { return $true }
        if ($answer -in @('n', 'no')) { return $false }
    }
    return $Default
}

function Read-Choice([string]$Title, $Options, [string]$Preset) {
    # $Options: objects with .key and .label. Returns the chosen object.
    if ($Preset) {
        $match = @($Options | Where-Object { $_.key -eq $Preset })
        if ($match.Count -gt 0) { return $match[0] }
    }
    Write-Host ""
    Write-Host "   $Title"
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host ("     {0}) {1}" -f ($i + 1), $Options[$i].label) }
    for ($i = 0; $i -lt 5; $i++) {
        $answer = (Read-Host "   Elige un número (Enter = 1)")
        if ($null -eq $answer -or $answer.Trim() -eq '') { return $Options[0] }
        $n = 0
        if ([int]::TryParse($answer.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $Options[$n - 1] }
    }
    return $Options[0]
}

function Open-Url([string]$Url) {
    if ($DryRun) { Write-Info "(dry-run) abriría $Url"; return }
    try { Start-Process $Url -ErrorAction Stop } catch { Write-Info "Abre esta página en tu navegador: $Url" }
}

function Test-Command([string]$CommandName) {
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    if (-not $script:OnWindows) { return }
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Find-Exe($App) {
    # First existing path among the app's "exe" globs (newest version last wins).
    foreach ($pattern in @($App.exe)) {
        if (-not $pattern) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($pattern)
        $found = @(Get-Item -Path $expanded -ErrorAction SilentlyContinue | Sort-Object FullName)
        if ($found.Count -gt 0) { return $found[$found.Count - 1].FullName }
    }
    return $null
}

function Test-AppInstalled($App) {
    if ($App.command -and (Test-Command $App.command)) { return $true }
    if (Find-Exe $App) { return $true }
    if ($App.wingetId -and (Test-Command 'winget')) {
        & winget list --id $App.wingetId -e --source winget --accept-source-agreements 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

# ----------------------------------------------------------------------------
# Step 0 - configuration
# ----------------------------------------------------------------------------
function Get-SetupConfig {
    $path = $ConfigPath
    if (-not $path -and $script:ScriptDir) {
        $local = Join-Path $script:ScriptDir 'config.json'
        if (Test-Path -LiteralPath $local) { $path = $local }
    }
    if ($path) {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $data = Invoke-RestMethod -Uri "$DefaultRawBase/config.json" -UseBasicParsing -ErrorAction Stop
    if ($data -is [string]) { $data = $data | ConvertFrom-Json }
    return $data
}

# ----------------------------------------------------------------------------
# Step 1 - welcome and checks
# ----------------------------------------------------------------------------
function Invoke-Welcome {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "     Ad Astra UC3M - Setup del equipo" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Voy a instalar las herramientas, conectar tu cuenta de GitHub"
    Write-Host "  y dejarte todos los repositorios en una carpeta de tu escritorio."
    Write-Host "  Tarda entre 15 y 30 minutos. Puedes ejecutarlo las veces que quieras."
    Write-Host ""
    Write-Host "  IMPORTANTE: este script NUNCA te pedirá contraseñas ni tokens." -ForegroundColor Yellow
    Write-Host "  Todos los inicios de sesión se hacen en tu navegador. Si algo te" -ForegroundColor Yellow
    Write-Host "  pide una contraseña en esta ventana, cancela y avisa a tu lead." -ForegroundColor Yellow
    if ($DryRun) { Write-Host ""; Write-Host "  MODO DRY-RUN: solo muestro lo que haría, no cambio nada." -ForegroundColor Magenta }

    Write-Step "1/8 Comprobaciones"
    if (-not $script:OnWindows) {
        if (-not $Force) {
            Write-Err "Este setup es solo para Windows 10/11."
            Add-Result 'Comprobaciones' 'Fallo' 'No es Windows'
            return $false
        }
        Write-Warn "No es Windows: continúo porque has usado -Force (modo pruebas)."
    }
    if ($SkipInstall) {
        Write-Info "Instalación de apps desactivada (-SkipInstall)."
    } elseif (-not (Test-Command 'winget')) {
        Write-Warn "No encuentro 'winget' (el instalador de apps de Windows)."
        Write-Info "Abro Microsoft Store: instala o actualiza 'Instalador de aplicación' (App Installer)."
        Open-Url 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
        if (-not $DryRun) { [void](Read-Host "   Pulsa Enter cuando esté instalado") }
        Update-SessionPath
        if (-not (Test-Command 'winget')) {
            Write-Err "Sigo sin encontrar winget. Cierra esta ventana, abre PowerShell de nuevo y repite el comando."
            Add-Result 'Comprobaciones' 'Fallo' 'Falta winget'
            return $false
        }
    }
    Write-Ok "Todo listo para empezar"
    Add-Result 'Comprobaciones' 'OK' ''
    return $true
}

# ----------------------------------------------------------------------------
# Step 2 - member data
# ----------------------------------------------------------------------------
function Get-MemberData($Config) {
    Write-Step "2/8 Tus datos"
    # Bounded loops: never spin forever if input is closed or keeps being invalid.
    $memberName = $Name
    for ($i = 0; -not $memberName -and $i -lt 5; $i++) {
        $memberName = "$(Read-Host '   Nombre y apellidos')".Trim()
    }
    $memberEmail = $Email
    $emailOk = $false
    for ($i = 0; $i -lt 6; $i++) {
        if ($memberEmail -and ($memberEmail.Trim().ToLower() -match '^[^@\s]+@([a-z0-9-]+\.)*uc3m\.es$')) { $emailOk = $true; break }
        if ($memberEmail) { Write-Warn "Tiene que ser tu correo de la UC3M (por ejemplo 100xxxxxx@alumnos.uc3m.es)." }
        if ($i -lt 5) { $memberEmail = "$(Read-Host '   Correo de la UC3M')" }
    }
    if (-not $memberName -or -not $emailOk) {
        Write-Err "Necesito tu nombre y tu correo de la UC3M para continuar. Vuelve a ejecutar el setup."
        Add-Result 'Datos' 'Fallo' 'Faltan nombre o correo'
        return $null
    }
    $memberEmail = $memberEmail.Trim().ToLower()

    $chosenProfile = Read-Choice '¿Qué quieres instalar?' @($Config.profiles) $InstallProfile
    $chosenProject = Read-Choice '¿En qué proyecto estás?' @($Config.projects) $Project
    $chosenArea = Read-Choice '¿Cuál es tu área principal?' @($Config.areas) $Area
    Write-Info "(Proyecto y área solo ordenan tus carpetas: tendrás todos los repositorios igualmente.)"

    Write-Ok "$memberName <$memberEmail> | $($chosenProfile.label) | $($chosenProject.label) / $($chosenArea.label)"
    Add-Result 'Datos' 'OK' "$($chosenProject.label) / $($chosenArea.label)"
    return [pscustomobject]@{ Name = $memberName; Email = $memberEmail; Profile = $chosenProfile; Project = $chosenProject; Area = $chosenArea }
}

# ----------------------------------------------------------------------------
# Step 3 - automatic installs (winget)
# ----------------------------------------------------------------------------
function Install-Apps($Config, $Member) {
    Write-Step "3/8 Instalación de aplicaciones"
    if ($SkipInstall) { Write-Info "Saltado (-SkipInstall)."; Add-Result 'Apps' 'Saltado' '-SkipInstall'; return }

    $apps = @($Config.apps | Where-Object { $_.wingetId -and ($_.profiles -contains $Member.Profile.key) })
    $failed = @()
    foreach ($app in $apps) {
        if (Test-AppInstalled $app) { Write-Ok "$($app.name) ya está instalado"; continue }
        if ($DryRun) { Write-Info "(dry-run) instalaría $($app.name) [$($app.wingetId)]"; continue }
        Write-Info "Instalando $($app.name)... (puede tardar unos minutos; acepta si Windows pide permiso)"
        # --source winget: without it, a broken msstore source (certificate
        # errors are common) makes winget refuse to pick a package at all.
        & winget install --id $app.wingetId -e --source winget --silent --accept-package-agreements --accept-source-agreements
        $code = $LASTEXITCODE
        Update-SessionPath
        if ($code -eq 0 -or (Test-AppInstalled $app)) {
            Write-Ok "$($app.name) instalado"
        } else {
            Write-Err "No se pudo instalar $($app.name) (código $code)."
            $failed += $app.name
        }
    }
    if ($failed.Count -gt 0) { Add-Result 'Apps' 'Fallo' ($failed -join ', ') } else { Add-Result 'Apps' 'OK' '' }
}

# ----------------------------------------------------------------------------
# Step 4 - GitHub account and login
# ----------------------------------------------------------------------------
function Connect-GitHub($Member) {
    # Sets $script:LoggedIn instead of returning a value: capturing this function's
    # output would also swallow the one-time code that "gh auth login" prints.
    Write-Step "4/8 Cuenta de GitHub"
    if (-not (Test-Command 'gh') -or -not (Test-Command 'git')) {
        if ($DryRun) { Write-Info "(dry-run) Git/GitHub CLI no están instalados todavía; aquí iniciaría sesión."; Add-Result 'GitHub' 'Saltado' 'dry-run'; $script:LoggedIn = $false; return }
        Write-Err "Falta Git o GitHub CLI. Cierra esta ventana, abre PowerShell de nuevo y repite el comando."
        Add-Result 'GitHub' 'Fallo' 'Falta git o gh'
        $script:LoggedIn = $false; return
    }
    & gh auth status --hostname github.com 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $login = (& gh api user --jq .login 2>$null)
        Write-Ok "Ya has iniciado sesión en GitHub como $login"
    } else {
        if ($DryRun) { Write-Info "(dry-run) iniciaría sesión en GitHub por el navegador"; Add-Result 'GitHub' 'Saltado' 'dry-run'; $script:LoggedIn = $false; return }
        if (-not (Read-YesNo '¿Tienes ya una cuenta de GitHub?' $true)) {
            Write-Info "Abro la página de registro. Crea la cuenta con tu correo de la UC3M: $($Member.Email)"
            Write-Info "(Tiene que ser ese correo: es al que llega la invitación del equipo.)"
            Open-Url 'https://github.com/signup'
            [void](Read-Host "   Pulsa Enter cuando hayas creado y verificado la cuenta")
        }
        Write-Info "Ahora inicia sesión: copia el código que aparece abajo, pulsa Enter y pégalo en el navegador."
        & gh auth login --hostname github.com --web --git-protocol https
        & gh auth status --hostname github.com 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Err "No se completó el inicio de sesión en GitHub. Vuelve a ejecutar el setup para reintentarlo."
            Add-Result 'GitHub' 'Fallo' 'Login no completado'
            $script:LoggedIn = $false; return
        }
        $login = (& gh api user --jq .login 2>$null)
        Write-Ok "Sesión iniciada como $login"
    }
    if (-not $DryRun) { & gh auth setup-git 2>$null | Out-Null }
    Add-Result 'GitHub' 'OK' "$login"
    $script:LoggedIn = $true
}

# ----------------------------------------------------------------------------
# Step 5 - organization membership
# ----------------------------------------------------------------------------
function Get-MembershipState([string]$Org) {
    $state = (& gh api "user/memberships/orgs/$Org" --jq .state 2>$null)
    if ($LASTEXITCODE -ne 0) { return 'none' }
    return "$state".Trim()
}

function Confirm-Membership($Config, $Member, [bool]$LoggedIn) {
    Write-Step "5/8 Acceso a la organización $($Config.org)"
    if (-not $LoggedIn) { Write-Info "Saltado: no hay sesión de GitHub."; Add-Result 'Organización' 'Saltado' 'Sin sesión'; return }
    $org = $Config.org
    $state = Get-MembershipState $org
    if ($state -eq 'pending' -and -not $DryRun) {
        & gh api -X PATCH "user/memberships/orgs/$org" -f state=active 2>$null | Out-Null
        $state = Get-MembershipState $org
        if ($state -eq 'active') { Write-Ok "Invitación aceptada automáticamente" }
    }
    $tries = 0
    while ($state -ne 'active' -and -not $DryRun -and $tries -lt 6) {
        $tries++
        if ($tries -eq 1) {
            Write-Warn "Todavía no eres miembro de $org."
            Write-Info "Abro la página de la invitación. Si aparece, pulsa 'Join'."
            Write-Info "Si no aparece: busca el correo de GitHub en tu Outlook de la UC3M ($($Member.Email))"
            Write-Info "o pide a tu lead que te invite a ese correo."
            Open-Url "https://github.com/orgs/$org/invitation"
        }
        $answer = "$(Read-Host '   Pulsa Enter para volver a comprobar (o escribe S para saltar este paso)')".Trim().ToLower()
        if ($answer -eq 's') { break }
        $state = Get-MembershipState $org
        if ($state -eq 'pending') {
            & gh api -X PATCH "user/memberships/orgs/$org" -f state=active 2>$null | Out-Null
            $state = Get-MembershipState $org
        }
        if ($state -ne 'active') { Write-Warn "Aún no apareces como miembro." }
    }
    if ($state -eq 'active') {
        Write-Ok "Eres miembro de $org"
        Add-Result 'Organización' 'OK' ''
        return
    }
    if ($DryRun) { Write-Info "(dry-run) estado actual: $state"; Add-Result 'Organización' 'Saltado' "dry-run ($state)"; return }
    Write-Warn "Sigo sin acceso: solo podrás descargar los repositorios públicos. Vuelve a ejecutar el setup cuando te inviten."
    Add-Result 'Organización' 'Pendiente' 'Falta aceptar la invitación'
    return
}

# ----------------------------------------------------------------------------
# Step 6 - Git configuration
# ----------------------------------------------------------------------------
function Set-GitConfiguration($Config, $Member) {
    Write-Step "6/8 Configuración de Git"
    if (-not (Test-Command 'git')) { Write-Info "Saltado: Git no está instalado."; Add-Result 'Git' 'Saltado' 'Falta git'; return }
    $settings = @(
        @('user.name', $Member.Name),
        @('user.email', $Member.Email),
        @('core.longpaths', 'true'),
        @('init.defaultBranch', 'main'),
        @('pull.rebase', 'false')
    )
    foreach ($pair in $settings) {
        if ($DryRun) { Write-Info "(dry-run) git config --global $($pair[0]) `"$($pair[1])`""; continue }
        & git config --global $pair[0] $pair[1]
    }
    if (-not $DryRun) { Write-Ok "Git configurado" }
    Set-MatlabMerge $Config
    Add-Result 'Git' 'OK' ''
}

function Set-MatlabMerge($Config) {
    # Lets MATLAB merge Simulink models (.slx). Needs MATLAB, so it is called
    # again after the manual installs.
    if (-not (Test-Command 'git')) { return }
    $matlab = Find-Exe (@($Config.apps | Where-Object { $_.name -eq 'MATLAB' })[0])
    if (-not $matlab) { return }
    $driver = Join-Path (Join-Path (Split-Path -Parent $matlab) 'win64') 'mlAutoMerge.bat'
    $value = ('"{0}" %O %A %B %P' -f ($driver -replace '\\', '/'))
    if ($DryRun) { Write-Info "(dry-run) configuraría el merge de MATLAB/Simulink"; return }
    # Before PowerShell 7.3 (and always in 5.1) embedded double quotes are lost
    # when passed to a native program unless they are backslash-escaped; the
    # driver was being saved as just "C:/Program".
    $legacyArgs = ($PSVersionTable.PSVersion -lt [version]'7.3') -or ("$PSNativeCommandArgumentPassing" -eq 'Legacy')
    if ($legacyArgs) { $value = $value -replace '"', '\"' }
    & git config --global --replace-all merge.mlAutoMerge.name 'MATLAB Auto Merge'
    & git config --global --replace-all merge.mlAutoMerge.driver $value
    Write-Ok "Merge de MATLAB/Simulink configurado"
}

# ----------------------------------------------------------------------------
# Step 7 - folder, repositories and shortcuts
# ----------------------------------------------------------------------------
function Get-RootFolder($Config) {
    $leaf = $Config.folderName
    if ($Folder) {
        if ([System.IO.Path]::IsPathRooted($Folder)) { return $Folder }
        $leaf = $Folder
    }
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { $desktop = Join-Path $HOME 'Desktop' }
    return (Join-Path $desktop $leaf)
}

function New-FolderIfMissing([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return }
    if ($DryRun) { Write-Info "(dry-run) crearía la carpeta $Path"; return }
    [void](New-Item -ItemType Directory -Path $Path -Force)
}

function Sync-Repositories($Config, $Member, [string]$Root) {
    Write-Step "7/8 Repositorios en $Root"
    $myDir = Join-Path $Root $Config.myReposFolder
    $teamDir = Join-Path $Root $Config.teamReposFolder
    New-FolderIfMissing $Root
    New-FolderIfMissing $myDir
    New-FolderIfMissing $teamDir

    if (-not (Test-Command 'git') -or -not (Test-Command 'gh')) {
        Write-Info "Saltado: falta Git o GitHub CLI."
        Add-Result 'Repositorios' 'Saltado' 'Falta git o gh'
        return
    }
    $json = (& gh repo list $Config.org --limit 200 --no-archived --json name,isEmpty 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Write-Err "No pude leer la lista de repositorios de $($Config.org)."
        Add-Result 'Repositorios' 'Fallo' 'gh repo list falló'
        return
    }
    $repos = @(("$json" | ConvertFrom-Json) | Sort-Object name)

    $mine = ''
    if ($Member.Area.repoSuffix) { $mine = "$($Member.Project.repoPrefix)$($Member.Area.repoSuffix)" }

    $cloned = 0; $updated = 0; $skipped = 0; $failed = 0
    foreach ($repo in $repos) {
        $repoName = $repo.name
        $targetDir = $teamDir
        if ($mine -and $repoName -eq $mine) { $targetDir = $myDir }
        $target = Join-Path $targetDir $repoName

        # Already cloned somewhere else under the root (old layout or changed area)? Move it.
        if (-not (Test-Path -LiteralPath $target)) {
            foreach ($other in @((Join-Path $Root $repoName), (Join-Path $myDir $repoName), (Join-Path $teamDir $repoName))) {
                if ($other -ne $target -and (Test-Path -LiteralPath (Join-Path $other '.git'))) {
                    if ($DryRun) { Write-Info "(dry-run) movería $other -> $target"; break }
                    try { Move-Item -LiteralPath $other -Destination $target -ErrorAction Stop; Write-Info "$repoName movido a $(Split-Path -Leaf $targetDir)" }
                    catch { Write-Warn "No pude mover $repoName (¿está abierto en algún programa?). Lo dejo donde está."; $target = $other }
                    break
                }
            }
        }

        if (Test-Path -LiteralPath (Join-Path $target '.git')) {
            if ($DryRun) { Write-Info "(dry-run) actualizaría $repoName"; continue }
            $dirty = (& git -C $target status --porcelain 2>$null)
            if ($dirty) { Write-Warn "$repoName tiene cambios sin commit: no lo toco."; $skipped++; continue }
            & git -C $target pull --ff-only --quiet 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok "$repoName actualizado"; $updated++ }
            elseif ($repo.isEmpty) { Write-Ok "$repoName (vacío todavía)"; $updated++ }
            else { Write-Warn "$repoName no se pudo actualizar (rama sin remoto o cambios locales): revísalo en SourceTree."; $skipped++ }
        } elseif (Test-Path -LiteralPath $target) {
            Write-Warn "$target existe pero no es un repositorio: no lo toco."; $skipped++
        } else {
            if ($DryRun) { Write-Info "(dry-run) clonaría $repoName en $(Split-Path -Leaf $targetDir)"; continue }
            & git clone --quiet "https://github.com/$($Config.org)/$repoName.git" $target 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok "$repoName clonado en $(Split-Path -Leaf $targetDir)"; $cloned++ }
            else { Write-Err "No se pudo clonar $repoName"; $failed++ }
        }
    }
    if (-not $mine) { Write-Info "Tu área no tiene repositorio propio en GitHub: tienes todos en '$($Config.teamReposFolder)'." }
    $detail = "$cloned clonados, $updated actualizados, $skipped sin tocar, $failed con fallo"
    if ($DryRun) { Add-Result 'Repositorios' 'Saltado' "dry-run ($($repos.Count) repos)" }
    elseif ($failed -gt 0) { Add-Result 'Repositorios' 'Fallo' $detail }
    else { Add-Result 'Repositorios' 'OK' $detail }
}

function Install-PullAll($Config, [string]$Root) {
    if ($DryRun) { Write-Info "(dry-run) copiaría pull-all.ps1 a $Root"; return }
    $dest = Join-Path $Root 'pull-all.ps1'
    try {
        if ($script:ScriptDir -and (Test-Path -LiteralPath (Join-Path $script:ScriptDir 'pull-all.ps1'))) {
            Copy-Item -LiteralPath (Join-Path $script:ScriptDir 'pull-all.ps1') -Destination $dest -Force -ErrorAction Stop
        } else {
            $base = $Config.rawBase
            if (-not $base) { $base = $DefaultRawBase }
            Invoke-WebRequest -Uri "$base/pull-all.ps1" -OutFile $dest -UseBasicParsing -ErrorAction Stop
        }
        Write-Ok "pull-all.ps1 copiado (actualiza todos los repositorios de golpe)"
    } catch {
        Write-Warn "No pude copiar pull-all.ps1: $($_.Exception.Message)"
    }
}

function New-Shortcuts($Config, $Member, [string]$Root) {
    $appsDir = Join-Path $Root 'Apps'
    New-FolderIfMissing $appsDir
    if ($DryRun) { Write-Info "(dry-run) crearía los accesos directos en $appsDir"; return }

    foreach ($link in @($Config.links)) {
        $file = Join-Path $appsDir "$($link.name).url"
        Set-Content -LiteralPath $file -Value @('[InternetShortcut]', "URL=$($link.url)") -Encoding ASCII
    }
    $made = @($Config.links).Count
    if ($script:OnWindows) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            foreach ($app in @($Config.apps)) {
                $exe = Find-Exe $app
                if (-not $exe) { continue }
                $shortcut = $shell.CreateShortcut((Join-Path $appsDir "$($app.name).lnk"))
                $shortcut.TargetPath = $exe
                $shortcut.WorkingDirectory = (Split-Path -Parent $exe)
                $shortcut.Save()
                $made++
            }
            $pull = Join-Path $Root 'pull-all.ps1'
            if (Test-Path -LiteralPath $pull) {
                $shortcut = $shell.CreateShortcut((Join-Path $appsDir 'Update all repositories.lnk'))
                $shortcut.TargetPath = 'powershell.exe'
                $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$pull`""
                $shortcut.WorkingDirectory = $Root
                $shortcut.Save()
                $made++
            }
        } catch {
            Write-Warn "No pude crear algunos accesos directos: $($_.Exception.Message)"
        }
    }
    Write-Ok "$made accesos directos en la carpeta Apps"
}

# ----------------------------------------------------------------------------
# Step 8 - manual apps, CADLAB and summary
# ----------------------------------------------------------------------------
function Invoke-ManualApps($Config, $Member) {
    Write-Step "8/8 Últimos pasos"
    $pending = @()
    if ($SkipInstall) { return $pending }
    foreach ($app in @($Config.apps | Where-Object { $_.manual -and ($_.profiles -contains $Member.Profile.key) })) {
        if (Find-Exe $app) { Write-Ok "$($app.name) ya está instalado"; continue }
        if ($DryRun) { Write-Info "(dry-run) pediría instalar $($app.name) desde $($app.url)"; continue }
        Write-Host ""
        Write-Warn "$($app.name) no se puede instalar automáticamente."
        Write-Info $app.hint
        Open-Url $app.url
        $done = $false
        for ($try = 0; -not $done -and $try -lt 4; $try++) {
            $answer = "$(Read-Host "   Pulsa Enter cuando $($app.name) esté instalado (o escribe S para dejarlo para luego)")".Trim().ToLower()
            if ($answer -eq 's') { break }
            if (Find-Exe $app) { $done = $true } else { Write-Warn "No lo encuentro todavía. Termina la instalación y pulsa Enter." }
        }
        if ($done) { Write-Ok "$($app.name) instalado" } else { $pending += $app.name }
    }
    if ($pending.Count -gt 0) { Add-Result 'Apps manuales' 'Pendiente' ($pending -join ', ') }
    elseif (-not $DryRun) { Add-Result 'Apps manuales' 'OK' '' }
    return $pending
}

function Confirm-Cadlab($Config) {
    if ($DryRun) { Write-Info "(dry-run) abriría CADLAB y preguntaría por la invitación"; return }
    Write-Host ""
    Write-Info "CADLAB es donde se revisan los cambios de las PCBs. Tu lead te ha enviado una invitación por correo."
    Open-Url $Config.cadlabUrl
    Write-Info "Inicia sesión en CADLAB con tu cuenta de GitHub y acepta la invitación del correo."
    if (Read-YesNo '¿Has aceptado la invitación de CADLAB?' $false) { Add-Result 'CADLAB' 'OK' ''; Write-Ok "CADLAB listo"; return }
    Write-Info "Búscala en tu Outlook de la UC3M (remitente CADLAB.io; mira también en correo no deseado)."
    Write-Info "Si no te ha llegado, pide a tu lead que te invite."
    if (Read-YesNo '¿Has aceptado ya la invitación de CADLAB?' $false) { Add-Result 'CADLAB' 'OK' ''; Write-Ok "CADLAB listo" }
    else { Add-Result 'CADLAB' 'Pendiente' 'Aceptar la invitación de CADLAB'; Write-Warn "Queda pendiente: acéptala en cuanto te llegue." }
}

function Show-Summary([string]$Root) {
    Write-Host ""
    Write-Host "  ================= RESUMEN =================" -ForegroundColor Cyan
    foreach ($result in $script:Results) {
        $color = 'Green'
        if ($result.Status -eq 'Saltado' -or $result.Status -eq 'Pendiente') { $color = 'Yellow' }
        if ($result.Status -eq 'Fallo') { $color = 'Red' }
        Write-Host ("  {0,-16} {1,-10} {2}" -f $result.Step, $result.Status, $result.Detail) -ForegroundColor $color
        Write-Log ("RESUMEN {0} | {1} | {2}" -f $result.Step, $result.Status, $result.Detail)
    }
    Write-Host ""
    $problems = @($script:Results | Where-Object { $_.Status -eq 'Fallo' -or $_.Status -eq 'Pendiente' })
    if ($DryRun) { Write-Host "  Dry-run terminado: no se ha cambiado nada." -ForegroundColor Magenta }
    elseif ($problems.Count -eq 0) { Write-Host "  Todo listo. Tu carpeta: $Root" -ForegroundColor Green }
    else { Write-Host "  Casi listo: revisa lo marcado arriba y vuelve a ejecutar el setup cuando quieras." -ForegroundColor Yellow }
    if ($script:LogPath) { Write-Host "  Log: $script:LogPath" }
    Write-Host ""
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Invoke-AdAstraSetup {
    try { $config = Get-SetupConfig }
    catch {
        Write-Host "No pude descargar la configuración del setup. Revisa tu conexión a internet y vuelve a intentarlo." -ForegroundColor Red
        Write-Host "Detalle: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    $root = Get-RootFolder $config

    if (-not (Invoke-Welcome)) { Show-Summary $root; return }
    $member = Get-MemberData $config
    if (-not $member) { Show-Summary $root; return }

    if (-not $DryRun) {
        New-FolderIfMissing $root
        $script:LogPath = Join-Path $root 'setup-log.txt'
        Write-Log "---- Setup iniciado ($($member.Profile.key), $($member.Project.key)/$($member.Area.key)) ----"
    }

    Install-Apps $config $member
    Connect-GitHub $member
    Confirm-Membership $config $member $script:LoggedIn
    Set-GitConfiguration $config $member
    Sync-Repositories $config $member $root
    Install-PullAll $config $root
    [void](Invoke-ManualApps $config $member)
    Set-MatlabMerge $config
    New-Shortcuts $config $member $root
    Confirm-Cadlab $config
    Show-Summary $root
}

Invoke-AdAstraSetup
