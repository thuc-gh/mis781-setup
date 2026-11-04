# MIS781: completely remove MySQL Server from Windows, for a clean reinstall.
# Leaves MySQL Workbench, its saved connections, the Employees files and your
# downloads alone unless -All is given.
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1 | iex
#
# Our server (C:\Users\<you>\mysql) comes off without administrator rights.
# The legacy server (this unit's earlier MSI install, a Windows service) and
# the Workbench MSI (-All) need an administrator window; the setup script opens
# one by itself.
#
# With options (dry run shows what would go and changes nothing; -All also
# removes Workbench, its saved connections and password, the MIS781 folder and
# the downloads; -Yes or MIS781_CONFIRM=yes skips the confirmation):
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -DryRun
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -All
#
# WARNING: this permanently deletes all MySQL databases on the PC.

param([switch]$DryRun, [switch]$Yes, [switch]$All)

function Invoke-Mis781Uninstall([bool]$DryRun, [bool]$Yes, [bool]$All) {
  $ErrorActionPreference = 'Stop'
  if ($env:MIS781_CONFIRM -eq 'yes') { $Yes = $true }
  $MysqlHome = Join-Path $env:USERPROFILE 'mysql'
  $TaskName  = 'MIS781 MySQL'

  $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  Write-Host 'Scanning for MySQL Server...'
  # Ours: the home-folder install, its logon task and its running process.
  $ourMysqld = Join-Path $MysqlHome 'bin\mysqld.exe'
  $ourFolder = if ((Test-Path $MysqlHome) -and ((Test-Path $ourMysqld) -or (Select-String -Path (Join-Path $MysqlHome 'my.ini') -Pattern 'written by install.ps1' -Quiet -ErrorAction SilentlyContinue))) { $MysqlHome }
  $ourTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  $ourProc = Get-Process -Name mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq $ourMysqld } | Select-Object -First 1
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $ourPathEntry = @($userPath -split ';' | Where-Object { $_ -ieq (Join-Path $MysqlHome 'bin') })

  # Legacy: the MSI install (service, registered program, Program Files and ProgramData folders).
  $services = @(Get-Service 'MySQL*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Router' })
  $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $products = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Server*' -and $_.PSChildName -like '{*' })
  $folders = @()
  foreach ($root in $env:ProgramFiles, $env:ProgramData) {
    $folders += @(Get-ChildItem (Join-Path $root 'MySQL\MySQL Server *') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  }
  $rules = @(Get-NetFirewallRule -DisplayName '*MySQL*' -ErrorAction SilentlyContinue)
  $legacyCount = $services.Count + $products.Count + $folders.Count + $rules.Count

  # Other servers are listed so the student knows, and left alone.
  $others = @()
  if (Test-Path 'C:\xampp\mysql\bin\mysqld.exe') { $others += 'XAMPP (C:\xampp)' }
  if (Test-Path 'C:\wamp64\bin\mysql') { $others += 'WampServer (C:\wamp64)' }

  # -All: Workbench and everything else this unit put on the PC.
  $wbProducts = @(); $allPaths = @(); $wbShell = $null
  if ($All) {
    $wbProducts = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' -and $_.PSChildName -like '{*' })
    foreach ($p in (Join-Path $env:APPDATA 'MySQL\Workbench'),
                   (Join-Path $env:APPDATA 'MySQL Workbench'),
                   (Join-Path $env:USERPROFILE 'MIS781'),
                   (Join-Path $env:USERPROFILE 'Downloads\mysql-26.10.0-winx64.zip'),
                   (Join-Path $env:USERPROFILE 'Downloads\mysql-26.10.0-winx64.msi'),
                   (Join-Path $env:USERPROFILE 'Downloads\mysql-workbench-26.10.0-winx64.msi'),
                   (Join-Path $env:USERPROFILE 'Downloads\test_db-master.zip'),
                   (Join-Path $env:USERPROFILE 'Downloads\vc_redist.x64.exe')) {
      if (Test-Path $p) { $allPaths += $p }
    }
    # The password saved for Workbench lives in Windows Credential Manager; the
    # shell Workbench ships with knows how to delete it.
    foreach ($d in @($wbProducts | ForEach-Object { $_.InstallLocation }) + @("$env:ProgramFiles\MySQL\MySQL Workbench*")) {
      if (-not $d) { continue }
      $exe = Get-ChildItem $d -Recurse -Depth 6 -Filter 'mysqlsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($exe) { $wbShell = $exe.FullName; break }
    }
  }

  $needsAdmin = ($legacyCount + $wbProducts.Count) -gt 0
  if ($needsAdmin -and -not $isAdmin) {
    throw "Removing the earlier MySQL Server install or Workbench needs an administrator window. Run the setup line (irm .../setup.ps1 | iex) and it opens one for you, or right-click Start, choose 'Terminal (Admin)', and paste the command again."
  }

  $ourCount = @($ourFolder, $ourTask, $ourProc).Where({ $_ }).Count + $ourPathEntry.Count
  if (-not ($ourCount + $legacyCount + $wbProducts.Count + $allPaths.Count)) {
    Write-Host 'No MySQL Server found. Nothing to do.'
    foreach ($o in $others) { Write-Host "  (Note: $o has its own MySQL; it is not from this unit and is left alone.)" }
    return
  }
  if ($ourCount) { Write-Host 'MySQL Server (ours):' }
  if ($ourProc)   { Write-Host "  running:  mysqld (process $($ourProc.Id))" }
  if ($ourTask)   { Write-Host "  task:     $TaskName (starts it at logon)" }
  if ($ourFolder) { Write-Host "  folder:   $ourFolder (programs and ALL its databases)" }
  if ($ourPathEntry.Count) { Write-Host "  PATH:     $($ourPathEntry[0]) (your user PATH)" }
  if ($legacyCount) { Write-Host 'MySQL Server (this unit''s earlier install):' }
  foreach ($s in $services) { Write-Host "  service:  $($s.Name)" }
  foreach ($p in $products) { Write-Host "  program:  $($p.DisplayName)" }
  foreach ($f in $folders)  { Write-Host "  folder:   $f" }
  foreach ($r in $rules)    { Write-Host "  firewall: $($r.DisplayName)" }
  if ($wbProducts.Count + $allPaths.Count) { Write-Host 'Workbench, saved connections and password, Employees files and downloads (removed with -All):' }
  foreach ($p in $wbProducts) { Write-Host "  program:  $($p.DisplayName) $($p.DisplayVersion)" }
  if ($All -and $wbShell)     { Write-Host '  password: saved for root@127.0.0.1:3306 in Windows Credential Manager' }
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

  # Ours first: stop it, drop the logon task, delete the folder, tidy the PATH.
  if ($ourTask) {
    Write-Host "Removing the logon task $TaskName..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  }
  if ($ourProc) {
    Write-Host 'Stopping MySQL Server...'
    & taskkill.exe /PID $ourProc.Id 2>$null | Out-Null
    for ($t = 0; $t -lt 30 -and -not $ourProc.HasExited; $t++) { Start-Sleep 1 }
    if (-not $ourProc.HasExited) { Stop-Process -Id $ourProc.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
  }
  if ($ourPathEntry.Count) {
    $kept = @($userPath -split ';' | Where-Object { $_ -and $_ -ine (Join-Path $MysqlHome 'bin') })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
  }

  # The saved Workbench password, while the shell that manages it is still there.
  if ($All -and $wbShell) {
    $py = Join-Path $env:TEMP ("mis781-wb-" + [guid]::NewGuid().ToString('N') + ".py")
    [IO.File]::WriteAllText($py, "try:`n    shell.delete_credential('root@127.0.0.1:3306')`nexcept Exception:`n    pass`n", [Text.UTF8Encoding]::new($false))
    $env:MYSQLSH_USER_CONFIG_HOME = Join-Path $env:APPDATA 'MySQL Workbench\mysqlsh'
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $wbShell --py -f $py 2>&1 | Out-Null } catch {}
    finally { $ErrorActionPreference = $prevEap; Remove-Item $py -Force -ErrorAction SilentlyContinue; Remove-Item Env:\MYSQLSH_USER_CONFIG_HOME -ErrorAction SilentlyContinue }
  }

  # Legacy service and MSI products (administrator window).
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
  if ($legacyCount -and $isAdmin) {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $kept = @($machinePath -split ';' | Where-Object { $_ -notmatch '\\MySQL\\MySQL Server [^\\]+\\bin\\?$' })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'Machine')
  }

  foreach ($f in @($ourFolder) + $folders + $allPaths) {
    if ($f -and (Test-Path $f)) { Write-Host "Deleting $f..."; Remove-Item $f -Recurse -Force }
  }

  Write-Host ''
  $left = @((@($ourFolder) + $folders + $allPaths) | Where-Object { $_ -and (Test-Path $_) })
  if ($left.Count) {
    throw "Some items could not be removed: $($left -join ', '). Restart Windows and run this again."
  }
  if ($All) { Write-Host 'MySQL Server, Workbench and the MIS781 files have been completely removed.' }
  else      { Write-Host 'MySQL Server has been completely removed. Workbench and the Employees files were kept.' }
}

Invoke-Mis781Uninstall ([bool]$DryRun) ([bool]$Yes) ([bool]$All)
