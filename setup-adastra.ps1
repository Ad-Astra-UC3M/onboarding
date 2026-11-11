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
$script:DeferredManual = @()
$script:BlockingAntivirus = $null
$script:InstalledRecord = $null
$DefaultRawBase = 'https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main'

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------
function Write-Log([string]$Text) {
    if ($script:LogPath) {
        try { Add-Content -LiteralPath $script:LogPath -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -Encoding UTF8 -ErrorAction Stop }
        catch {
            # Seen with Avast's ransomware shield: it blocks PowerShell from
            # changing files on the Desktop. Warn once and carry on.
            if (-not $script:LogWarned) {
                $script:LogWarned = $true
                Write-Host "   [!]  No puedo escribir en setup-log.txt. Si tu antivirus protege el Escritorio (Avast, AVG...), puede estar bloqueando a PowerShell. El setup sigue igualmente." -ForegroundColor Yellow
            }
        }
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
    # Options marked "hidden" are never listed, but can still be chosen with a preset.
    if ($Preset) {
        $match = @($Options | Where-Object { $_.key -eq $Preset })
        if ($match.Count -gt 0) { return $match[0] }
    }
    $Options = @($Options | Where-Object { -not $_.hidden })
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
    $leafs = @(@($App.exe) | Where-Object { $_ } | ForEach-Object { (Split-Path -Leaf $_).ToLower() })
    if ($leafs.Count -eq 0) { return $null }
    # Installed somewhere else: ask the uninstall entry in the registry (only
    # trusted when the file name matches; MSI icons are also called *.exe).
    $entry = Find-UninstallEntry $App
    if ($entry) {
        $candidates = @()
        if ($entry.InstallLocation) { foreach ($leaf in $leafs) { $candidates += (Join-Path "$($entry.InstallLocation)".Trim('"') $leaf) } }
        if ($entry.DisplayIcon) { $candidates += ("$($entry.DisplayIcon)" -replace ',\s*-?\d+$', '').Trim('"') }
        foreach ($candidate in $candidates) {
            if (($leafs -contains (Split-Path -Leaf $candidate).ToLower()) -and (Test-Path -LiteralPath $candidate)) { return $candidate }
        }
    }
    # Last resort: a Start Menu shortcut that points to the same program file.
    foreach ($target in @(Get-StartMenuTargets)) {
        if ($leafs -contains (Split-Path -Leaf $target).ToLower()) { return $target }
    }
    return $null
}

function Get-StartMenuTargets {
    # Existing .exe targets of every Start Menu shortcut (read once per run).
    if ($null -ne $script:StartMenuTargets) { return $script:StartMenuTargets }
    $script:StartMenuTargets = @()
    if (-not $script:OnWindows) { return $script:StartMenuTargets }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $menus = @((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
        foreach ($link in @(Get-ChildItem -Path $menus -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
            $target = $shell.CreateShortcut($link.FullName).TargetPath
            if ($target -and $target.ToLower().EndsWith('.exe') -and (Test-Path -LiteralPath $target)) { $script:StartMenuTargets += $target }
        }
    } catch { }
    return $script:StartMenuTargets
}

function Get-UninstallEntries {
    # Programs listed in "Apps & features" (machine, 32-bit and per-user), read once per run.
    if ($null -ne $script:UninstallEntries) { return $script:UninstallEntries }
    $script:UninstallEntries = @()
    if (-not $script:OnWindows) { return $script:UninstallEntries }
    $keys = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $script:UninstallEntries = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    return $script:UninstallEntries
}

function Find-UninstallEntry($App) {
    if (-not $App.uninstallName) { return $null }
    $pattern = "$($App.uninstallName)*"
    $match = @(Get-UninstallEntries | Where-Object { $_.DisplayName -like $pattern })
    if ($match.Count -gt 0) { return $match[0] }
    return $null
}

function Reset-AppCache {
    # Call after installing something, so the next checks see it.
    $script:StartMenuTargets = $null
    $script:UninstallEntries = $null
    Update-SessionPath
}

function Get-StatePath {
    return (Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AdAstraSetup') 'installed.json')
}

function Get-InstalledRecord {
    # Names of the apps (and VS Code extension ids) this setup installed on this
    # computer. Only these are ever uninstalled when the profile changes.
    if ($null -ne $script:InstalledRecord) { return $script:InstalledRecord }
    $script:InstalledRecord = @()
    $path = Get-StatePath
    if (Test-Path -LiteralPath $path) {
        try { $script:InstalledRecord = @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).installed | Where-Object { $_ }) } catch { }
    }
    return $script:InstalledRecord
}

function Save-InstalledRecord([string[]]$Names) {
    $script:InstalledRecord = @($Names | Where-Object { $_ } | Select-Object -Unique)
    if ($DryRun) { return }
    $path = Get-StatePath
    try {
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force -ErrorAction Stop)
        $json = ConvertTo-Json -InputObject @{ installed = @($script:InstalledRecord) }
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Add-InstalledRecord([string]$Name) {
    $current = @(Get-InstalledRecord)
    if ($current -notcontains $Name) { Save-InstalledRecord (@($current) + $Name) }
}

function Remove-InstalledRecord([string]$Name) {
    Save-InstalledRecord @(@(Get-InstalledRecord) | Where-Object { $_ -ne $Name })
}

function Test-NetFx3 {
    # .NET Framework 3.5 (needed by RASAero II); not enabled by default on Windows 10/11.
    $key = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction SilentlyContinue
    return ($key -and $key.Install -eq 1)
}

function Test-AppInstalled($App) {
    if ($App.command -and (Test-Command $App.command)) { return $true }
    if (Find-Exe $App) { return $true }
    if (Find-UninstallEntry $App) { return $true }
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

    # The project comes first: some projects (Jet Engine) fix the profile and have no areas.
    $chosenProject = Read-Choice '¿En qué proyecto estás?' @($Config.projects) $Project
    $chosenProfile = $null
    if ($chosenProject.installProfile) {
        $chosenProfile = @($Config.profiles | Where-Object { $_.key -eq $chosenProject.installProfile })[0]
    }
    if (-not $chosenProfile) { $chosenProfile = Read-Choice '¿Qué quieres instalar?' @($Config.profiles) $InstallProfile }
    $chosenArea = $null
    if ($chosenProject.noArea) {
        Write-Info "$($chosenProject.label): instalo lo básico y todos los repositorios van a '$($Config.teamReposFolder)'."
    } else {
        $chosenArea = Read-Choice '¿Cuál es tu área principal?' @($Config.areas) $Area
        Write-Info "(Proyecto y área solo ordenan tus carpetas: tendrás todos los repositorios igualmente.)"
    }
    $where = $chosenProject.label
    if ($chosenArea) { $where = "$where / $($chosenArea.label)" }

    Write-Ok "$memberName <$memberEmail> | $($chosenProfile.label) | $where"
    Add-Result 'Datos' 'OK' $where
    return [pscustomobject]@{ Name = $memberName; Email = $memberEmail; Profile = $chosenProfile; Project = $chosenProject; Area = $chosenArea }
}

# ----------------------------------------------------------------------------
# Step 3 - automatic installs (winget)
# ----------------------------------------------------------------------------
function Install-Apps($Config, $Member, [string]$Root) {
    Write-Step "3/8 Instalación de aplicaciones"
    $profileKey = $Member.Profile.key
    $selected = @($Config.apps | Where-Object { $_.profiles -contains $profileKey })
    $names = @($selected | ForEach-Object { $_.name })
    $names += @($Config.vscodeExtensions | Where-Object { $_.profiles -contains $profileKey } | ForEach-Object { "$($_.name) (VS Code)" })
    Write-Info "Perfil '$profileKey': $($names -join ', ')"
    if ($SkipInstall) { Write-Info "Saltado (-SkipInstall)."; Add-Result 'Apps' 'Saltado' '-SkipInstall'; return }

    # Changed profile (e.g. avionics -> vehicle)? Offer to remove what this
    # setup installed for the old one.
    Remove-OldApps $Config $Member $Root

    $apps = @($selected | Where-Object { $_.wingetId })
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
            Add-InstalledRecord $app.name
        } else {
            Write-Err "No se pudo instalar $($app.name) (código $code)."
            $failed += $app.name
        }
    }
    # Apps with an official installer that is not in winget (OpenRocket,
    # RASAero II): downloaded and installed silently. If that is not possible
    # (antivirus, no internet, UAC refused...), step 8 opens the download in
    # the browser, the member installs it and the setup checks the result.
    foreach ($app in @($selected | Where-Object { $_.download })) {
        if (-not (Install-DownloadedApp $Config $app)) { $script:DeferredManual += $app }
    }
    $failed += @(Install-PortableApps $Config $Member $Root)
    $failed += @(Install-CodeExtensions $Config $Member)
    if ($failed.Count -gt 0) { Add-Result 'Apps' 'Fallo' ($failed -join ', ') } else { Add-Result 'Apps' 'OK' '' }
}

function Get-RawBase($Config) {
    if ($Config.rawBase) { return $Config.rawBase }
    return $DefaultRawBase
}

function Save-Url([string]$Url, [string]$Path) {
    # Downloads to "<file>.part" first, so an interrupted download never looks finished.
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $partial = "$Path.part"
    $oldProgress = $ProgressPreference
    # The progress bar makes Invoke-WebRequest many times slower in 5.1.
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing -ErrorAction Stop
        Move-Item -LiteralPath $partial -Destination $Path -Force -ErrorAction Stop
    } finally {
        $ProgressPreference = $oldProgress
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
}

function Get-DownloadUrl($Download) {
    # "githubRepo" + "assetPattern": newest release on GitHub; "url" is the fallback.
    if ($Download.githubRepo -and $Download.assetPattern) {
        try {
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Download.githubRepo)/releases/latest" -UseBasicParsing -Headers @{ 'User-Agent' = 'AdAstraSetup' } -ErrorAction Stop
            $asset = @($release.assets | Where-Object { $_.name -match $Download.assetPattern })
            if ($asset.Count -gt 0) { return $asset[0].browser_download_url }
        } catch { }
    }
    return $Download.url
}

function Get-BrowserDownloadUrl($Config, $Download) {
    # The link the browser opens. If the official site does not answer and there
    # is a copy in this repository ("mirror"), use the copy. Only checks the
    # link (HEAD request); nothing is downloaded or run here.
    $url = Get-DownloadUrl $Download
    if (-not $Download.mirror) { return $url }
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ($response.StatusCode -lt 400) { return $url }
    } catch { }
    return "$(Get-RawBase $Config)/$($Download.mirror)"
}

function Get-BlockingAntivirus($Config) {
    # Antivirus programs known to kill this setup when it runs a downloaded
    # installer (Avast/AVG: detection IDP.HELU.PSD11). Returns the name of the
    # first one that is active, or ''. Read once per run.
    if ($null -ne $script:BlockingAntivirus) { return $script:BlockingAntivirus }
    $script:BlockingAntivirus = ''
    $names = @($Config.antivirusNoDirectInstall | Where-Object { $_ })
    if (-not $script:OnWindows -or $names.Count -eq 0) { return $script:BlockingAntivirus }
    try {
        foreach ($product in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntivirusProduct' -ErrorAction Stop)) {
            # productState: bits 12-15 = 1 when real-time protection is on.
            $enabled = ((([int]$product.productState) -shr 12) -band 0xF) -eq 1
            foreach ($name in $names) {
                if ($enabled -and "$($product.displayName)" -like "*$name*") { $script:BlockingAntivirus = "$($product.displayName)"; return $script:BlockingAntivirus }
            }
        }
    } catch { }
    return $script:BlockingAntivirus
}

function Get-AttemptMarker($App) {
    # Written just before running an installer and removed when it returns. If
    # it is still there on the next run, the previous run was cut off in the
    # middle of the install (usually by an antivirus): do not try again.
    $dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AdAstraSetup'
    return (Join-Path $dir ('install-' + ($App.name -replace '[^A-Za-z0-9]', '') + '.txt'))
}

function Install-DownloadedApp($Config, $App) {
    # Downloads the official installer (optionally inside a .zip; "mirror" is a
    # copy in this repository) and runs it silently. Only the installer itself
    # is elevated (one UAC prompt). Returns $true when the app is installed.
    $marker = Get-AttemptMarker $App
    if (Test-AppInstalled $App) {
        Write-Ok "$($App.name) ya está instalado"
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        return $true
    }
    $url = Get-DownloadUrl $App.download
    $antivirus = Get-BlockingAntivirus $Config
    $interrupted = Test-Path -LiteralPath $marker
    if ($DryRun) {
        if ($antivirus) { Write-Info "(dry-run) $antivirus está activo: pediría instalar $($App.name) a mano desde $url" }
        elseif ($interrupted) { Write-Info "(dry-run) la última instalación de $($App.name) se cortó: pediría instalarlo a mano" }
        else { Write-Info "(dry-run) descargaría e instalaría $($App.name) desde $url" }
        return $true
    }
    if ($antivirus -or $interrupted) {
        if ($antivirus) { Write-Warn "Tu antivirus ($antivirus) suele cortar este setup cuando instala programas descargados." }
        else { Write-Warn "La última vez que intenté instalar $($App.name) el setup se cortó (casi siempre es el antivirus)." }
        Write-Info "$($App.name): lo instalas tú en el último paso; te abro la descarga en el navegador."
        return $false
    }
    if (-not $url) { return $false }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('AdAstraSetup-' + ($App.name -replace '[^A-Za-z0-9]', ''))
    $code = $null
    $log = $null
    try {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        [void](New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop)
        $file = Join-Path $work ([Uri]::UnescapeDataString((Split-Path -Leaf ([Uri]$url).AbsolutePath)))
        Write-Info "Descargando $($App.name)..."
        try { Save-Url $url $file }
        catch {
            if (-not $App.download.mirror) { throw }
            Write-Info "La web oficial no responde; uso la copia del repositorio onboarding."
            $file = Join-Path $work (Split-Path -Leaf $App.download.mirror)
            Save-Url "$(Get-RawBase $Config)/$($App.download.mirror)" $file
        }
        $installer = Get-Item -LiteralPath $file
        if ($installer.Extension -eq '.zip') {
            $unzipped = Join-Path $work 'unzipped'
            Expand-Archive -LiteralPath $file -DestinationPath $unzipped -Force -ErrorAction Stop
            $installer = @(Get-ChildItem -LiteralPath $unzipped -Recurse -File | Where-Object { $_.Extension -eq '.msi' -or $_.Extension -eq '.exe' } | Sort-Object Extension -Descending)[0]
            if (-not $installer) { throw "el zip no contiene ningún instalador" }
        }
        Unblock-File -LiteralPath $installer.FullName -ErrorAction SilentlyContinue
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $marker) -Force -ErrorAction SilentlyContinue)
        Set-Content -LiteralPath $marker -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ErrorAction SilentlyContinue
        Write-Info "Instalando $($App.name)... (acepta el aviso de Windows que pide permiso)"
        if ($installer.Extension -eq '.msi') {
            $log = Join-Path $work 'install.log'
            # One string, so the paths keep their quotes in Windows PowerShell 5.1.
            $argLine = '/i "{0}" /qn /norestart ALLUSERS=1 /l*v "{1}"' -f $installer.FullName, $log
            if ($App.download.needsNetFx3 -and -not (Test-NetFx3)) {
                # Enable .NET 3.5 and install in the same elevated process, so the
                # member sees one UAC prompt. -EncodedCommand keeps any accent in
                # the user's folder name intact.
                Write-Info "$($App.name) necesita .NET Framework 3.5: lo activo antes (lo descarga Windows Update, 1-3 minutos)."
                $inner = "dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart /Quiet | Out-Null`r`n" +
                         "`$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList '$($argLine -replace "'", "''")' -Wait -PassThru`r`n" +
                         "exit `$p.ExitCode"
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
                $process = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded" -Verb RunAs -Wait -PassThru -ErrorAction Stop
            } else {
                $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argLine -Verb RunAs -Wait -PassThru -ErrorAction Stop
            }
        } else {
            $params = @{ FilePath = $installer.FullName; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
            $argLine = (@($App.download.args) | Where-Object { $_ }) -join ' '
            if ($argLine) { $params['ArgumentList'] = $argLine }
            if ($App.download.elevate) { $params['Verb'] = 'RunAs' }
            $process = Start-Process @params
        }
        $code = $process.ExitCode
    } catch {
        # Includes "No" on the UAC prompt and download errors.
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        Write-Warn "No pude instalar $($App.name) automáticamente: $($_.Exception.Message)"
        return $false
    }
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    # 3010 / 1641: installed, Windows wants a restart.
    $succeeded = ($code -eq 0 -or $code -eq 3010 -or $code -eq 1641)
    Reset-AppCache
    for ($i = 0; $succeeded -and $i -lt 12 -and -not (Test-AppInstalled $App); $i++) { Start-Sleep -Seconds 5; Reset-AppCache }
    if (Test-AppInstalled $App) {
        Write-Ok "$($App.name) instalado"
        Add-InstalledRecord $App.name
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }
    Write-Warn "El instalador de $($App.name) terminó (código $code), pero no encuentro el programa: lo instalas tú en el último paso."
    if ($log) { Write-Info "Detalle de la instalación: $log" }
    return $false
}

function Test-PortableApp($App, [string]$Root) {
    $dest = Join-Path (Join-Path $Root 'Apps') $App.portable.dest
    foreach ($fileName in @($App.portable.files)) {
        if (-not (Test-Path -LiteralPath (Join-Path $dest $fileName))) { return $false }
    }
    return $true
}

function Install-PortableApps($Config, $Member, [string]$Root) {
    # Programs that are not installed, only copied: their files live in this
    # repository ("portable.repoPath") and go to Apps\<portable.dest>.
    # Existing files are never replaced. If the copy fails or an antivirus
    # removes the file, step 8 asks the member to download it by hand.
    $base = Get-RawBase $Config
    foreach ($app in @($Config.apps | Where-Object { $_.portable -and ($_.profiles -contains $Member.Profile.key) })) {
        $dest = Join-Path (Join-Path $Root 'Apps') $app.portable.dest
        $missing = @(@($app.portable.files) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dest $_)) })
        if ($missing.Count -eq 0) { Write-Ok "$($app.name) ya está en Apps\$($app.portable.dest)"; continue }
        if ($DryRun) { Write-Info "(dry-run) copiaría $($app.name) ($($missing -join ', ')) a $dest"; continue }
        try {
            [void](New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop)
            foreach ($fileName in $missing) {
                $target = Join-Path $dest $fileName
                $local = $null
                if ($script:ScriptDir) { $local = Join-Path (Join-Path $script:ScriptDir $app.portable.repoPath) $fileName }
                if ($local -and (Test-Path -LiteralPath $local)) {
                    Copy-Item -LiteralPath $local -Destination $target -ErrorAction Stop
                } else {
                    Save-Url "$base/$($app.portable.repoPath)/$fileName" $target
                }
                # Downloaded files are marked as "from the internet"; without this
                # Windows warns every time the program is opened.
                Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warn "No pude copiar $($app.name): $($_.Exception.Message)"
        }
        # An antivirus may delete the file a moment after it is written.
        Start-Sleep -Seconds 2
        if (Test-PortableApp $app $Root) {
            Write-Ok "$($app.name) copiado en Apps\$($app.portable.dest)"
            Add-InstalledRecord $app.name
        } else {
            Write-Warn "$($app.name) no ha quedado copiado (puede que tu antivirus lo haya bloqueado): lo descargas tú en el último paso."
            $script:DeferredManual += $app
        }
    }
}

function Get-CodeCli($Config) {
    # VS Code's command line. Right after installing, "code" may not be on PATH
    # yet, so fall back to bin\code.cmd next to the executable.
    $command = Get-Command 'code.cmd' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $exe = Find-Exe (@($Config.apps | Where-Object { $_.name -eq 'VS Code' })[0])
    if ($exe) {
        $cli = Join-Path (Join-Path (Split-Path -Parent $exe) 'bin') 'code.cmd'
        if (Test-Path -LiteralPath $cli) { return $cli }
    }
    return $null
}

function Install-CodeExtensions($Config, $Member) {
    # Installs the VS Code extensions listed in config.json ("vscodeExtensions").
    # Returns the names of the ones that failed.
    $failedNames = @()
    $extensions = @($Config.vscodeExtensions | Where-Object { $_.id -and ($_.profiles -contains $Member.Profile.key) })
    if ($extensions.Count -eq 0) { return $failedNames }
    $code = Get-CodeCli $Config
    if (-not $code) {
        foreach ($ext in $extensions) {
            if ($DryRun) { Write-Info "(dry-run) instalaría la extensión de VS Code $($ext.name) [$($ext.id)]" }
            else { Write-Err "No encuentro VS Code para instalar la extensión $($ext.name)."; $failedNames += $ext.name }
        }
        return $failedNames
    }
    $installed = @(& $code --list-extensions 2>$null)
    foreach ($ext in $extensions) {
        if ($installed -contains $ext.id) { Write-Ok "Extensión $($ext.name) ya está instalada"; continue }
        if ($DryRun) { Write-Info "(dry-run) instalaría la extensión de VS Code $($ext.name) [$($ext.id)]"; continue }
        Write-Info "Instalando la extensión $($ext.name) en VS Code..."
        & $code --install-extension $ext.id 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Extensión $($ext.name) instalada"
            Add-InstalledRecord $ext.id
        } else {
            Write-Err "No se pudo instalar la extensión $($ext.name) (código $LASTEXITCODE)."
            $failedNames += $ext.name
        }
    }
    return $failedNames
}

function Split-CommandLine([string]$CommandLine) {
    # "C:\x\uninstall.exe" /S  ->  exe + arguments (quoted or not).
    $line = $CommandLine.Trim()
    if ($line.StartsWith('"')) {
        $end = $line.IndexOf('"', 1)
        if ($end -gt 0) { return @($line.Substring(1, $end - 1), $line.Substring($end + 1).Trim()) }
    }
    $index = $line.ToLower().IndexOf('.exe')
    if ($index -gt 0) { return @($line.Substring(0, $index + 4), $line.Substring($index + 4).Trim()) }
    return @($line, '')
}

function Uninstall-SetupApp($Config, $App, [string]$Root) {
    # Removes one app installed by this setup. Returns $true when it is gone.
    if ($App.portable) {
        $dest = Join-Path (Join-Path $Root 'Apps') $App.portable.dest
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($entry in @($App.shortcuts)) { Remove-Item -LiteralPath (Join-Path (Join-Path $Root 'Apps') "$($entry.name).lnk") -Force -ErrorAction SilentlyContinue }
        return -not (Test-Path -LiteralPath $dest)
    }
    if (-not (Test-AppInstalled $App)) { return $true }
    try {
        if ($App.wingetId) {
            & winget uninstall --id $App.wingetId -e --source winget --silent --accept-source-agreements | Out-Host
        } else {
            $entry = Find-UninstallEntry $App
            if (-not $entry) { return $false }
            $exe = $null; $arguments = ''
            if ($entry.QuietUninstallString) {
                $parts = Split-CommandLine "$($entry.QuietUninstallString)"; $exe = $parts[0]; $arguments = $parts[1]
            } elseif ("$($entry.UninstallString)" -match '(?i)msiexec' -and "$($entry.UninstallString)" -match '(\{[0-9A-Fa-f-]{36}\})') {
                $exe = 'msiexec.exe'; $arguments = "/x $($Matches[1]) /qn /norestart"
            } else {
                $parts = Split-CommandLine "$($entry.UninstallString)"; $exe = $parts[0]
                $arguments = (@($parts[1]) + @($App.download.uninstallArgs) | Where-Object { $_ }) -join ' '
            }
            $params = @{ FilePath = $exe; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
            if ($arguments) { $params['ArgumentList'] = $arguments }
            # Programs installed for all users need administrator rights (one UAC prompt).
            if ("$($entry.PSPath)" -notmatch 'HKEY_CURRENT_USER') { $params['Verb'] = 'RunAs' }
            [void](Start-Process @params)
        }
    } catch {
        return $false
    }
    # Some uninstallers finish in the background: wait up to a minute.
    for ($i = 0; $i -lt 12; $i++) {
        Reset-AppCache
        if (-not (Test-AppInstalled $App)) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Remove-OldApps($Config, $Member, [string]$Root) {
    # When the member changes profile, removes what this setup installed for
    # the old one. Never touches the base tools (Git, GitHub CLI, SourceTree,
    # VS Code, MATLAB), nor anything that was already on the computer. Apps the
    # member installed by hand (STM32CubeIDE, STM32CubeMX) are not removed
    # automatically: the setup opens Windows' app list instead.
    $profileKey = $Member.Profile.key
    $automatic = @(); $byHand = @(); $extensions = @()
    foreach ($name in @(Get-InstalledRecord)) {
        $app = @($Config.apps | Where-Object { $_.name -eq $name })[0]
        if ($app) {
            if (($app.profiles -contains $profileKey) -or ($app.profiles -contains 'base')) { continue }
            if ($app.manual) { $byHand += $app } else { $automatic += $app }
            continue
        }
        $ext = @($Config.vscodeExtensions | Where-Object { $_.id -eq $name })[0]
        if ($ext -and -not ($ext.profiles -contains $profileKey)) { $extensions += $ext }
    }
    $all = @($automatic | ForEach-Object { $_.name }) + @($byHand | ForEach-Object { $_.name }) + @($extensions | ForEach-Object { "$($_.name) (VS Code)" })
    if ($all.Count -eq 0) { return }

    Write-Warn "Tu perfil ahora es '$profileKey'. Estas herramientas las instaló el setup para tu perfil anterior y ya no las necesitas:"
    Write-Info "  $($all -join ', ')"
    if ($DryRun) { Write-Info "(dry-run) preguntaría si desinstalarlas"; return }
    if (-not (Read-YesNo '¿Las desinstalo? (s = sí; Enter o n = no, las dejo)' $false)) {
        Write-Info "Las dejo instaladas. Si cambias de idea, vuelve a ejecutar el setup."
        return
    }
    $openSettings = $false
    foreach ($app in $automatic) {
        Write-Info "Desinstalando $($app.name)... (acepta el aviso de Windows si aparece)"
        if (Uninstall-SetupApp $Config $app $Root) {
            Write-Ok "$($app.name) desinstalado"
            Remove-InstalledRecord $app.name
        } else {
            Write-Warn "No pude desinstalar $($app.name): quítalo tú desde Configuración > Aplicaciones (te la abro)."
            $openSettings = $true
        }
    }
    if ($extensions.Count -gt 0) {
        $code = Get-CodeCli $Config
        foreach ($ext in $extensions) {
            if ($code) { & $code --uninstall-extension $ext.id 2>$null | Out-Null }
            if ($code -and $LASTEXITCODE -eq 0) { Write-Ok "Extensión $($ext.name) desinstalada"; Remove-InstalledRecord $ext.id }
            else { Write-Warn "No pude desinstalar la extensión $($ext.name): quítala desde VS Code (Extensiones)." }
        }
    }
    foreach ($app in $byHand) {
        Write-Info "$($app.name) lo instalaste tú: desinstálalo desde Configuración > Aplicaciones (te la abro). Yo quito su acceso directo."
        Remove-InstalledRecord $app.name
        $openSettings = $true
    }
    if ($openSettings) { Open-Url 'ms-settings:appsfeatures' }
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
    $script:GitHubLogin = "$login".Trim()
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

    # The member's own repository: <project prefix><area suffix>, e.g. rocket-a4-simulation.
    # If it does not exist (e.g. model-satellite-simulation), everything goes to Team.
    $mine = ''
    if ($Member.Area -and $Member.Area.repoSuffix -and $Member.Project.repoPrefix) { $mine = "$($Member.Project.repoPrefix)$($Member.Area.repoSuffix)" }
    if ($mine -and -not @($repos | Where-Object { $_.name -eq $mine })) { $mine = '' }

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
                    catch { Write-Warn "No pude mover $repoName (¿está abierto en algún programa o lo bloquea tu antivirus?). Lo dejo donde está."; $target = $other }
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
    if (-not $mine) { Write-Info "Tu proyecto o área no tiene repositorio propio en GitHub: tienes todos en '$($Config.teamReposFolder)'." }
    $detail = "$cloned clonados, $updated actualizados, $skipped sin tocar, $failed con fallo"
    if ($DryRun) { Add-Result 'Repositorios' 'Saltado' "dry-run ($($repos.Count) repos)" }
    elseif ($failed -gt 0) { Add-Result 'Repositorios' 'Fallo' $detail }
    else { Add-Result 'Repositorios' 'OK' $detail }
}

function Install-PullAll($Config, [string]$Root) {
    # A plain .cmd so anyone can run it with a double-click (a .ps1 opens in
    # Notepad and depends on the execution policy).
    $name = 'Update all repositories.cmd'
    if ($DryRun) { Write-Info "(dry-run) copiaría '$name' a $Root"; return }
    $dest = Join-Path $Root $name
    try {
        if ($script:ScriptDir -and (Test-Path -LiteralPath (Join-Path $script:ScriptDir 'pull-all.cmd'))) {
            Copy-Item -LiteralPath (Join-Path $script:ScriptDir 'pull-all.cmd') -Destination $dest -Force -ErrorAction Stop
        } else {
            $base = $Config.rawBase
            if (-not $base) { $base = $DefaultRawBase }
            Invoke-WebRequest -Uri "$base/pull-all.cmd" -OutFile $dest -UseBasicParsing -ErrorAction Stop
        }
        Write-Ok "'$name' copiado: doble clic para actualizar todos los repositorios"
    } catch {
        Write-Warn "No pude copiar '$name': $($_.Exception.Message)"
    }
}

function New-BookmarkNode($Doc, [bool]$IsFolder, [int]$Level, [string]$NodeName, [string]$RepoPath) {
    # One entry of SourceTree's bookmarks.xml. The element order matters:
    # SourceTree reads the file with XmlSerializer.
    $node = $Doc.CreateElement('TreeViewNode')
    $attr = $Doc.CreateAttribute('xsi', 'type', 'http://www.w3.org/2001/XMLSchema-instance')
    if ($IsFolder) { $attr.Value = 'BookmarkFolderNode' } else { $attr.Value = 'BookmarkNode' }
    [void]$node.Attributes.Append($attr)
    $fields = @(
        @('Level', "$Level"),
        @('IsExpanded', "$IsFolder".ToLower()),
        @('IsLeaf', "$(-not $IsFolder)".ToLower()),
        @('Name', $NodeName),
        @('Children', $null)
    )
    if (-not $IsFolder) { $fields += , @('Path', $RepoPath); $fields += , @('RepoType', 'Git') }
    foreach ($field in $fields) {
        $element = $Doc.CreateElement($field[0])
        if ($null -ne $field[1]) { $element.InnerText = $field[1] }
        [void]$node.AppendChild($element)
    }
    return $node
}

function Set-SourceTreeBookmarks($Config, [string]$Root) {
    # Adds the cloned repositories to SourceTree's sidebar, grouped like the
    # folders on disk. Only adds what is missing; existing bookmarks are kept.
    # (The format is not documented by Atlassian; verified with SourceTree 3.4.)
    if (-not $script:OnWindows -or -not $env:LOCALAPPDATA) { return }
    if (-not (Find-Exe (@($Config.apps | Where-Object { $_.name -eq 'SourceTree' })[0]))) { return }

    $groups = @()
    foreach ($folderName in @($Config.myReposFolder, $Config.teamReposFolder)) {
        $dir = Join-Path $Root $folderName
        $repoDirs = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } | Sort-Object Name)
        if ($repoDirs.Count -gt 0) { $groups += , @($folderName, $repoDirs) }
    }
    if ($groups.Count -eq 0) { return }
    if ($DryRun) { Write-Info "(dry-run) añadiría los repositorios a SourceTree"; return }
    if (Get-Process -Name 'SourceTree' -ErrorAction SilentlyContinue) {
        # SourceTree rewrites the file when it closes, so our changes would be lost.
        Write-Warn "SourceTree está abierto: ciérralo y vuelve a ejecutar el setup para añadirle los repositorios."
        return
    }

    $bookmarkDir = Join-Path (Join-Path $env:LOCALAPPDATA 'Atlassian') 'SourceTree'
    $file = Join-Path $bookmarkDir 'bookmarks.xml'
    try {
        $doc = New-Object System.Xml.XmlDocument
        if (Test-Path -LiteralPath $file) {
            $doc.Load($file)
        } else {
            New-FolderIfMissing $bookmarkDir
            $doc.LoadXml('<?xml version="1.0" encoding="utf-8"?><ArrayOfTreeViewNode xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" />')
        }
        if ($doc.DocumentElement.Name -ne 'ArrayOfTreeViewNode') { throw "formato inesperado en bookmarks.xml" }

        # Drop bookmarks of repositories under this folder that are gone (moved to the other group).
        $changed = $false
        $prefix = ($Root.TrimEnd('\') + '\').ToLower()
        $known = @{}
        foreach ($pathNode in @($doc.SelectNodes('//TreeViewNode/Path'))) {
            $bookmarked = $pathNode.InnerText.TrimEnd('\')
            if ($bookmarked.ToLower().StartsWith($prefix) -and -not (Test-Path -LiteralPath $bookmarked)) {
                $stale = $pathNode.ParentNode
                [void]$stale.ParentNode.RemoveChild($stale)
                $changed = $true
                continue
            }
            $known[$bookmarked.ToLower()] = $true
        }

        $added = 0
        foreach ($group in $groups) {
            $missing = @($group[1] | Where-Object { -not $known.ContainsKey($_.FullName.TrimEnd('\').ToLower()) })
            if ($missing.Count -eq 0) { continue }
            $folderNode = $null
            foreach ($candidate in @($doc.DocumentElement.SelectNodes('TreeViewNode'))) {
                $nameNode = $candidate.SelectSingleNode('Name')
                $isLeaf = $candidate.SelectSingleNode('IsLeaf')
                if ($nameNode -and $nameNode.InnerText -eq $group[0] -and $isLeaf -and $isLeaf.InnerText -eq 'false') { $folderNode = $candidate; break }
            }
            if (-not $folderNode) {
                $folderNode = New-BookmarkNode $doc $true 0 $group[0] ''
                [void]$doc.DocumentElement.AppendChild($folderNode)
            }
            $children = $folderNode.SelectSingleNode('Children')
            foreach ($repoDir in $missing) {
                [void]$children.AppendChild((New-BookmarkNode $doc $false 1 $repoDir.Name $repoDir.FullName))
                $added++
            }
        }
        if ($added -gt 0 -or $changed) { $doc.Save($file) }
        if ($added -gt 0) { Write-Ok "$added repositorios añadidos a SourceTree" }
        else { Write-Ok "SourceTree ya tiene todos los repositorios" }
        Write-Info "Aviso: la primera vez que abras SourceTree verás un asistente de bienvenida. Puedes saltarte"
        Write-Info "el inicio de sesión de Bitbucket; tu nombre, tu correo y el acceso a GitHub ya están configurados."
        Write-Info "Si en algún momento te pide iniciar sesión en GitHub, hazlo con tu cuenta en el navegador."
    } catch {
        Write-Warn "No pude añadir los repositorios a SourceTree (puedes arrastrar las carpetas a su ventana): $($_.Exception.Message)"
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
            # The Apps folder only shows the tools of the member's profile: the
            # shortcuts of other profiles' apps are removed (the apps are not).
            $profileKey = $Member.Profile.key
            foreach ($app in @($Config.apps | Where-Object { -not ($_.profiles -contains $profileKey) })) {
                $names = @("$($app.name)") + @($app.shortcuts | ForEach-Object { $_.name })
                foreach ($name in $names) { Remove-Item -LiteralPath (Join-Path $appsDir "$name.lnk") -Force -ErrorAction SilentlyContinue }
            }
            foreach ($app in @($Config.apps | Where-Object { $_.profiles -contains $profileKey })) {
                $exe = Find-Exe $app
                if (-not $exe) { continue }
                $shortcut = $shell.CreateShortcut((Join-Path $appsDir "$($app.name).lnk"))
                $shortcut.TargetPath = $exe
                $shortcut.WorkingDirectory = (Split-Path -Parent $exe)
                $shortcut.Save()
                $made++
            }
            # Copied programs (OSCALC): one shortcut per listed file. Existing
            # shortcuts are left as they are.
            foreach ($app in @($Config.apps | Where-Object { $_.portable -and ($_.profiles -contains $profileKey) })) {
                $dir = Join-Path $appsDir $app.portable.dest
                foreach ($entry in @($app.shortcuts)) {
                    $target = Join-Path $dir $entry.file
                    $lnk = Join-Path $appsDir "$($entry.name).lnk"
                    if (-not (Test-Path -LiteralPath $target)) { continue }
                    if (-not (Test-Path -LiteralPath $lnk)) {
                        $shortcut = $shell.CreateShortcut($lnk)
                        $shortcut.TargetPath = $target
                        $shortcut.WorkingDirectory = $dir
                        $shortcut.Save()
                    }
                    $made++
                }
            }
            $pull = Join-Path $Root 'Update all repositories.cmd'
            if (Test-Path -LiteralPath $pull) {
                $shortcut = $shell.CreateShortcut((Join-Path $appsDir 'Update all repos.lnk'))
                $shortcut.TargetPath = $pull
                $shortcut.Arguments = ''
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
function Invoke-ManualApps($Config, $Member, [string]$Root) {
    Write-Step "8/8 Últimos pasos"
    $pending = @()
    if ($SkipInstall) { return $pending }
    # Manual apps of the profile, plus the ones step 3 left for the member:
    # official installers (opened in the browser) and copies that failed.
    $todo = @($Config.apps | Where-Object { $_.manual -and ($_.profiles -contains $Member.Profile.key) })
    $todo += @($script:DeferredManual)
    foreach ($app in $todo) {
        if ($app.portable) {
            if (Test-PortableApp $app $Root) { Write-Ok "$($app.name) ya está en Apps\$($app.portable.dest)"; continue }
        } elseif (Test-AppInstalled $app) { Write-Ok "$($app.name) ya está instalado"; continue }
        if ($DryRun) { Write-Info "(dry-run) pediría instalar $($app.name) desde $($app.url)"; continue }
        Write-Host ""
        $dest = $null
        if ($app.manual) {
            Write-Warn "$($app.name) no se puede instalar automáticamente."
            Write-Info $app.hint
            Open-Url $app.url
        } elseif ($app.portable) {
            # The copy failed or an antivirus removed it: the browser can still
            # download the files from GitHub.
            $dest = Join-Path (Join-Path $Root 'Apps') $app.portable.dest
            [void](New-Item -ItemType Directory -Path $dest -Force -ErrorAction SilentlyContinue)
            Write-Warn "$($app.name): descárgalo tú. Te abro su página en GitHub y la carpeta donde tiene que ir."
            Write-Info "Descarga estos archivos (botón 'Download raw file') y guárdalos en $dest :"
            Write-Info "  $(@($app.portable.files) -join ', ')"
            Write-Info "Si tu antivirus los bloquea, márcalos como seguros: vienen del repositorio del equipo."
            Open-Url "https://github.com/$($Config.org)/onboarding/tree/main/$($app.portable.repoPath)"
            try { Start-Process 'explorer.exe' -ArgumentList "`"$dest`"" -ErrorAction Stop } catch { }
        } else {
            # Official installer: the browser downloads it (antivirus programs
            # trust browser downloads, not scripts that run installers).
            Write-Warn "$($app.name) no se ha podido instalar solo: instálalo tú (descárgalo en tu carpeta Descargas)."
            if ($app.download.needsNetFx3 -and -not (Test-NetFx3)) {
                Write-Info "Primero: $($app.name) necesita .NET Framework 3.5. Te abro 'Características de Windows':"
                Write-Info "marca '.NET Framework 3.5', pulsa Aceptar y deja que Windows lo descargue."
                try { Start-Process 'optionalfeatures.exe' -ErrorAction Stop } catch { Write-Info "Ábrelo tú: menú Inicio, escribe 'Activar o desactivar las características de Windows'." }
            }
            Write-Info "Te abro la descarga en el navegador. Cuando termine, ábrela desde Descargas."
            Write-Info $app.hint
            Write-Info "Si la descarga no empieza, entra en $($app.url)"
            $direct = Get-BrowserDownloadUrl $Config $app.download
            if ($direct) { Open-Url $direct } else { Open-Url $app.url }
        }
        $done = $false
        for ($try = 0; -not $done -and $try -lt 4; $try++) {
            $answer = "$(Read-Host "   Pulsa Enter cuando $($app.name) esté instalado (o escribe S para dejarlo para luego)")".Trim().ToLower()
            if ($answer -eq 's') { break }
            Reset-AppCache
            if ($app.portable) {
                $done = Test-PortableApp $app $Root
                if ($done) { foreach ($fileName in @($app.portable.files)) { Unblock-File -LiteralPath (Join-Path $dest $fileName) -ErrorAction SilentlyContinue } }
            } else { $done = Test-AppInstalled $app }
            if (-not $done) { Write-Warn "No lo encuentro todavía. Termina y pulsa Enter." }
        }
        if ($done) { Write-Ok "$($app.name) instalado"; Add-InstalledRecord $app.name } else { $pending += $app.name }
    }
    if ($pending.Count -gt 0) { Add-Result 'Apps manuales' 'Pendiente' ($pending -join ', ') }
    elseif (-not $DryRun) { Add-Result 'Apps manuales' 'OK' '' }
    return $pending
}

function Confirm-Cadlab($Config) {
    if ($DryRun) { Write-Info "(dry-run) abriría CADLAB y preguntaría si has iniciado sesión"; return }
    Write-Host ""
    # CADLAB can only add people by their CADLAB username, which exists once
    # they have signed in. So: sign in now, the contact adds them afterwards.
    $contact = $Config.cadlabContact
    if (-not $contact) { $contact = 'tu lead' }
    $who = 'tu usuario de GitHub'
    if ($script:GitHubLogin) { $who = "tu usuario de GitHub ($script:GitHubLogin)" }
    Write-Info "CADLAB es donde se revisan los cambios de las PCBs."
    Open-Url $Config.cadlabUrl
    Write-Info "Inicia sesión en CADLAB ahora, con tu cuenta de GitHub (no crees una cuenta aparte)."
    Write-Info "No hay invitación por correo: $contact te añade al equipo después de que entres."
    if (Read-YesNo '¿Has iniciado sesión en CADLAB con GitHub?' $false) {
        Add-Result 'CADLAB' 'OK' "Pide a $contact que te añada"
        Write-Ok "Sesión de CADLAB iniciada"
    } else {
        Add-Result 'CADLAB' 'Pendiente' 'Iniciar sesión en CADLAB con GitHub'
        Write-Warn "Queda pendiente: entra en $($Config.cadlabUrl) con tu cuenta de GitHub cuando puedas."
    }
    Write-Info "Siguiente paso: escribe a $contact y dile $who para que te añada a CADLAB."
}

function Write-AiHelp($Config, $Member, [string]$Root, [bool]$Final) {
    # "Ayuda para la IA.txt": a ready-to-paste message for the member's AI
    # assistant (ChatGPT, Claude...), with links to the script and its docs, the
    # computer's details and what happened. Written at the start (in case an
    # antivirus kills the setup) and again at the end. Returns its path.
    if ($DryRun -or -not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    $base = Get-RawBase $Config
    $os = ''
    try { $os = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption } catch { $os = "Windows $([Environment]::OSVersion.Version)" }
    $antivirus = @()
    try { $antivirus = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntivirusProduct' -ErrorAction Stop | ForEach-Object { $_.displayName }) } catch { }
    if ($antivirus.Count -eq 0) { $antivirus = @('no lo sé') }

    $lines = @(
        'Hola. Estoy instalando en mi ordenador el entorno de trabajo del equipo Ad Astra UC3M con un script',
        'de PowerShell y algo no ha ido bien (puede que mi antivirus lo haya bloqueado). No soy experto:',
        'ayúdame paso a paso, con instrucciones muy sencillas, a terminar la instalación.',
        '',
        "- Script del setup: $base/setup-adastra.ps1",
        "- Instrucciones y problemas frecuentes: $base/README.md",
        "- Cómo trabaja el equipo: $base/WORKFLOW.md",
        "- Se ejecuta en PowerShell con: irm $base/setup-adastra.ps1 | iex",
        "- Mi ordenador: $os, PowerShell $($PSVersionTable.PSVersion), antivirus: $($antivirus -join ', ')",
        "- Mi perfil: $($Member.Profile.key), proyecto: $($Member.Project.key)",
        "- Mi carpeta del equipo: $Root",
        ''
    )
    if ($Final) {
        $lines += 'Resumen del setup:'
        foreach ($result in $script:Results) { $lines += ("  {0}: {1} {2}" -f $result.Step, $result.Status, $result.Detail) }
    } else {
        $lines += 'El setup ha empezado pero puede que se haya cortado a mitad (por ejemplo, por el antivirus).'
    }
    if ($script:LogPath -and (Test-Path -LiteralPath $script:LogPath)) {
        $lines += ''
        $lines += 'Últimas líneas del registro (setup-log.txt):'
        $tail = @(Get-Content -LiteralPath $script:LogPath -Encoding UTF8 -Tail 60 -ErrorAction SilentlyContinue)
        # Keep the member's email out of what they paste.
        if ($Member.Email) { $tail = @($tail | ForEach-Object { "$_".Replace($Member.Email, '<mi correo UC3M>') }) }
        $lines += $tail
    }
    $path = Join-Path $Root 'Ayuda para la IA.txt'
    try {
        [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
        return $path
    } catch { return $null }
}

function Show-AiHelp($Config, $Member, [string]$Root) {
    # When something failed: copy the message for the AI to the clipboard and
    # open it, so the member only has to paste it.
    $path = Write-AiHelp $Config $Member $Root $true
    if (-not $path) { return }
    Write-Host "  ¿Atascado? Te he preparado un mensaje para tu IA de confianza (ChatGPT, Claude...):" -ForegroundColor Yellow
    try {
        Set-Clipboard -Value (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -ErrorAction Stop
        Write-Host "  ya está copiado: abre tu IA, pega con Ctrl+V y envíalo. Te guiará paso a paso." -ForegroundColor Yellow
    } catch {
        Write-Host "  copia el texto que te abro en el Bloc de notas, pégalo en tu IA y envíalo." -ForegroundColor Yellow
    }
    Write-Host "  (Está guardado en $path)" -ForegroundColor Yellow
    try { Start-Process 'notepad.exe' -ArgumentList "`"$path`"" -ErrorAction Stop } catch { }
    Write-Host ""
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
        $helpFile = Write-AiHelp $config $member $root $false
        if ($helpFile) {
            Write-Info "Si el setup se corta o algo falla, abre '$helpFile',"
            Write-Info "copia todo el texto, pégalo en tu IA de confianza (ChatGPT, Claude...) y te ayudará."
        }
    }

    Install-Apps $config $member $root
    Connect-GitHub $member
    Confirm-Membership $config $member $script:LoggedIn
    Set-GitConfiguration $config $member
    Sync-Repositories $config $member $root
    Install-PullAll $config $root
    [void](Invoke-ManualApps $config $member $root)
    Set-MatlabMerge $config
    Set-SourceTreeBookmarks $config $root
    New-Shortcuts $config $member $root
    Confirm-Cadlab $config
    Show-Summary $root
    # CADLAB "Pendiente" is normal (Jorge adds the member later): not a problem.
    if (@($script:Results | Where-Object { $_.Step -ne 'CADLAB' -and ($_.Status -eq 'Fallo' -or $_.Status -eq 'Pendiente') }).Count -gt 0) {
        Show-AiHelp $config $member $root
    } else {
        [void](Write-AiHelp $config $member $root $true)
    }
}

Invoke-AdAstraSetup
