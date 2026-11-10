# invite-members.ps1 - Ad Astra UC3M (owners only)
# Invites every email in a CSV to the GitHub organization.
#
#   .\invite-members.ps1 -Csv miembros.csv            # send invitations
#   .\invite-members.ps1 -Csv miembros.csv -DryRun    # show what would happen
#
# CSV format (header required, extra columns are ignored):
#   nombre,email,area
#   Ana Garcia,100512345@alumnos.uc3m.es,Hardware
#
# Requires GitHub CLI logged in as an organization owner. If gh reports a
# missing scope, run:  gh auth refresh -h github.com -s admin:org
# Never commit the CSV: it contains personal data.
#
# ASCII only on purpose: this file is run from disk by Windows PowerShell 5.1.

param(
    [Parameter(Mandatory = $true)][string]$Csv,
    [string]$Org = 'Ad-Astra-UC3M',
    [switch]$DryRun
)

if (-not (Test-Path -LiteralPath $Csv)) { Write-Host "No existe el archivo $Csv" -ForegroundColor Red; return }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host "Falta GitHub CLI (gh)." -ForegroundColor Red; return }

$rows = @(Import-Csv -LiteralPath $Csv)
if ($rows.Count -eq 0) { Write-Host "El CSV esta vacio." -ForegroundColor Yellow; return }
if (-not ($rows[0].PSObject.Properties.Name -contains 'email')) {
    Write-Host "El CSV necesita una columna llamada 'email'." -ForegroundColor Red
    return
}

# Pending invitations, to avoid sending duplicates.
$pending = @()
$raw = & gh api "orgs/$Org/invitations" --paginate --jq '.[].email' 2>$null
if ($LASTEXITCODE -eq 0 -and $raw) { $pending = @($raw | ForEach-Object { "$_".Trim().ToLower() }) }

$log = @()
$seen = @{}
foreach ($row in $rows) {
    $email = "$($row.email)".Trim().ToLower()
    if (-not $email) { continue }
    $status = ''; $detail = ''

    if ($seen.ContainsKey($email)) {
        $status = 'skipped'; $detail = 'duplicado en el CSV'
    } elseif ($email -notmatch '^[^@\s]+@([a-z0-9-]+\.)*uc3m\.es$') {
        $status = 'failed'; $detail = 'no es un correo de la UC3M'
    } elseif ($pending -contains $email) {
        $status = 'skipped'; $detail = 'ya tiene una invitacion pendiente'
    } elseif ($DryRun) {
        $status = 'dry-run'; $detail = 'se invitaria'
    } else {
        $out = & gh api -X POST "orgs/$Org/invitations" -f "email=$email" -f "role=direct_member" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $status = 'invited'
        } elseif ("$out" -match '422|already') {
            $status = 'skipped'; $detail = 'ya es miembro o ya estaba invitado'
        } else {
            $status = 'failed'; $detail = ("$out" -replace '\s+', ' ')
        }
    }
    $seen[$email] = $true

    $color = 'Green'
    if ($status -eq 'skipped' -or $status -eq 'dry-run') { $color = 'Yellow' }
    if ($status -eq 'failed') { $color = 'Red' }
    Write-Host ("{0,-10} {1}  {2}" -f $status, $email, $detail) -ForegroundColor $color
    $log += [pscustomobject]@{ email = $email; status = $status; detail = $detail }
}

$invited = @($log | Where-Object { $_.status -eq 'invited' }).Count
$skipped = @($log | Where-Object { $_.status -eq 'skipped' }).Count
$failed  = @($log | Where-Object { $_.status -eq 'failed' }).Count
Write-Host ""
Write-Host "Resumen: $invited invitados, $skipped saltados, $failed con fallo." -ForegroundColor Cyan

if (-not $DryRun) {
    $logPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Csv)) 'invite-log.csv'
    $log | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8
    Write-Host "Log guardado en $logPath"
}
