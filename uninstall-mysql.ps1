# MIS781: completely remove MySQL Server from Windows, for a clean reinstall.
# Leaves MySQL Workbench and your downloads alone.
#
# In Terminal (Admin) or PowerShell (Admin):
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1 | iex
#
# To see what it would remove without deleting anything:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -DryRun
#
# WARNING: this permanently deletes all MySQL databases on the PC.

param([switch]$DryRun, [switch]$Yes)

function Invoke-Mis781Uninstall([bool]$DryRun, [bool]$Yes) {
  $ErrorActionPreference = 'Stop'

  $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This window is not running as Administrator. Right-click the Start button, choose 'Terminal (Admin)' or 'PowerShell (Admin)', and paste the command again."
  }

  Write-Host 'Scanning for MySQL Server...'
  $services = @(Get-Service 'MySQL*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Router' })
  $products = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Server*' -and $_.PSChildName -like '{*' })
  $folders = @()
  foreach ($root in $env:ProgramFiles, $env:ProgramData) {
    $folders += @(Get-ChildItem (Join-Path $root 'MySQL\MySQL Server *') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  }
  $rules = @(Get-NetFirewallRule -DisplayName '*MySQL*' -ErrorAction SilentlyContinue)

  if (-not ($services.Count + $products.Count + $folders.Count + $rules.Count)) {
    Write-Host 'No MySQL Server found. Nothing to do.'
    return
  }
  foreach ($s in $services) { Write-Host "  service:  $($s.Name)" }
  foreach ($p in $products) { Write-Host "  program:  $($p.DisplayName)" }
  foreach ($f in $folders)  { Write-Host "  folder:   $f" }
  foreach ($r in $rules)    { Write-Host "  firewall: $($r.DisplayName)" }

  Write-Host ''
  Write-Host 'WARNING: this will permanently delete ALL MySQL databases on this PC.' -ForegroundColor Yellow
  Write-Host '         Back up first if needed: Workbench > Server > Data Export.'
  Write-Host ''
  if ($DryRun) {
    Write-Host 'Dry run: nothing was changed.'
    return
  }
  if (-not $Yes) {
    $answer = Read-Host 'Type "yes" to uninstall everything listed above'
    if ($answer -cne 'yes') {
      Write-Host 'Aborted. Nothing was changed.'
      return
    }
  }

  foreach ($s in $services) {
    Write-Host "Removing service $($s.Name)..."
    Stop-Service $s.Name -Force -ErrorAction SilentlyContinue
    & sc.exe delete $s.Name | Out-Null
  }
  foreach ($p in $products) {
    Write-Host "Uninstalling $($p.DisplayName)..."
    $r = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @('/x', $p.PSChildName, '/qn', '/norestart')
    if ($r.ExitCode -notin 0, 1605, 3010) { Write-Host "  msiexec returned $($r.ExitCode); carrying on." }
  }
  foreach ($r in $rules) { Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
  foreach ($f in $folders) {
    if (Test-Path $f) { Remove-Item $f -Recurse -Force }
  }

  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $kept = @($machinePath -split ';' | Where-Object { $_ -notmatch '\\MySQL\\MySQL Server [^\\]+\\bin\\?$' })
  [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'Machine')

  Write-Host ''
  $left = @($folders | Where-Object { Test-Path $_ })
  if ($left.Count) {
    throw "Some folders could not be removed: $($left -join ', '). Restart Windows and run this again."
  }
  Write-Host 'MySQL Server has been completely removed.'
}

Invoke-Mis781Uninstall ([bool]$DryRun) ([bool]$Yes)
