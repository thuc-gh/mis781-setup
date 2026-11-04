# MIS781: completely remove MySQL Server from Windows, for a clean reinstall.
# Leaves MySQL Workbench, its saved connections, the Employees files and your
# downloads alone unless -All is given.
#
# In Terminal (Admin) or PowerShell (Admin):
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1 | iex
#
# With options (dry run shows what would go and changes nothing; -All also
# removes Workbench, its saved connections, the MIS781 folder and the downloads;
# -Yes or MIS781_CONFIRM=yes skips the confirmation):
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -DryRun
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -All
#
# WARNING: this permanently deletes all MySQL databases on the PC.

param([switch]$DryRun, [switch]$Yes, [switch]$All)

function Invoke-Mis781Uninstall([bool]$DryRun, [bool]$Yes, [bool]$All) {
  $ErrorActionPreference = 'Stop'
  if ($env:MIS781_CONFIRM -eq 'yes') { $Yes = $true }

  $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This window is not running as Administrator. Right-click the Start button, choose 'Terminal (Admin)' or 'PowerShell (Admin)', and paste the command again."
  }

  Write-Host 'Scanning for MySQL Server...'
  $services = @(Get-Service 'MySQL*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Router' })
  $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $products = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Server*' -and $_.PSChildName -like '{*' })
  $folders = @()
  foreach ($root in $env:ProgramFiles, $env:ProgramData) {
    $folders += @(Get-ChildItem (Join-Path $root 'MySQL\MySQL Server *') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  }
  $rules = @(Get-NetFirewallRule -DisplayName '*MySQL*' -ErrorAction SilentlyContinue)

  # Other servers are listed so the student knows, and left alone.
  $others = @()
  if (Test-Path 'C:\xampp\mysql\bin\mysqld.exe') { $others += 'XAMPP (C:\xampp)' }
  if (Test-Path 'C:\wamp64\bin\mysql') { $others += 'WampServer (C:\wamp64)' }

  # -All: Workbench and everything else this unit put on the PC.
  $wbProducts = @(); $allPaths = @()
  if ($All) {
    $wbProducts = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' -and $_.PSChildName -like '{*' })
    foreach ($p in (Join-Path $env:APPDATA 'MySQL\Workbench'),
                   (Join-Path $env:USERPROFILE 'MIS781'),
                   (Join-Path $env:USERPROFILE 'Downloads\mysql-26.10.0-winx64.msi'),
                   (Join-Path $env:USERPROFILE 'Downloads\mysql-workbench-26.10.0-winx64.msi'),
                   (Join-Path $env:USERPROFILE 'Downloads\test_db-master.zip'),
                   (Join-Path $env:USERPROFILE 'Downloads\vc_redist.x64.exe')) {
      if (Test-Path $p) { $allPaths += $p }
    }
  }

  if (-not ($services.Count + $products.Count + $folders.Count + $rules.Count + $wbProducts.Count + $allPaths.Count)) {
    Write-Host 'No MySQL Server found. Nothing to do.'
    foreach ($o in $others) { Write-Host "  (Note: $o has its own MySQL; it is not from this unit and is left alone.)" }
    return
  }
  if ($services.Count + $products.Count + $folders.Count) { Write-Host 'MySQL Server (ours):' }
  foreach ($s in $services) { Write-Host "  service:  $($s.Name)" }
  foreach ($p in $products) { Write-Host "  program:  $($p.DisplayName)" }
  foreach ($f in $folders)  { Write-Host "  folder:   $f" }
  foreach ($r in $rules)    { Write-Host "  firewall: $($r.DisplayName)" }
  if ($wbProducts.Count + $allPaths.Count) { Write-Host 'Workbench, saved connections, Employees files and downloads (removed with -All):' }
  foreach ($p in $wbProducts) { Write-Host "  program:  $($p.DisplayName) $($p.DisplayVersion)" }
  foreach ($p in $allPaths)   { Write-Host "  path:     $p" }
  foreach ($o in $others) { Write-Host "  (Note: $o has its own MySQL; it is not from this unit and is left alone.)" }

  Write-Host ''
  Write-Host 'WARNING: this will permanently delete ALL MySQL databases on this PC,' -ForegroundColor Yellow
  Write-Host '         plus everything listed above.' -ForegroundColor Yellow
  Write-Host '         Back up first if needed: Workbench > Server > Data Export.'
  Write-Host ''
  if ($DryRun) {
    if ($env:MIS781_ACTION -and $env:MIS781_CONFIRM -ne 'yes') {
      Write-Host 'Nothing was changed. Set MIS781_CONFIRM=yes to remove the items above unattended.'
    } else {
      Write-Host 'Dry run: nothing was changed.'
    }
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
  foreach ($p in $products + $wbProducts) {
    Write-Host "Uninstalling $($p.DisplayName)..."
    $r = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @('/x', $p.PSChildName, '/qn', '/norestart')
    if ($r.ExitCode -notin 0, 1605, 3010) { Write-Host "  msiexec returned $($r.ExitCode); carrying on." }
  }
  foreach ($r in $rules) { Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
  foreach ($f in $folders + $allPaths) {
    if (Test-Path $f) { Remove-Item $f -Recurse -Force }
  }

  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $kept = @($machinePath -split ';' | Where-Object { $_ -notmatch '\\MySQL\\MySQL Server [^\\]+\\bin\\?$' })
  [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'Machine')

  Write-Host ''
  $left = @(($folders + $allPaths) | Where-Object { Test-Path $_ })
  if ($left.Count) {
    throw "Some items could not be removed: $($left -join ', '). Restart Windows and run this again."
  }
  if ($All) { Write-Host 'MySQL Server, Workbench and the MIS781 files have been completely removed.' }
  else      { Write-Host 'MySQL Server has been completely removed. Workbench and the Employees files were kept.' }
}

Invoke-Mis781Uninstall ([bool]$DryRun) ([bool]$Yes) ([bool]$All)
