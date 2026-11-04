# MIS781: completely remove MySQL Server from Windows, for a clean install.
# Leaves MySQL Workbench, its saved connections, the Employees files and your
# downloads alone unless -All is given.
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1 | iex
#
# Our server (C:\Users\<you>\mysql) comes off without administrator rights.
# The legacy server (this unit's earlier MSI install, a Windows service) and
# the Workbench MSI (-All) need an administrator window; the setup script does
# your own part in your window first and then opens one for the rest, through
# -Phase user and -Phase admin. Run on its own, this script does both at once
# and needs the administrator window only when those are present.
#
# With options (dry run shows what would go and changes nothing; -All also
# removes Workbench, its saved connections and password, the MIS781 folder and
# the downloads; -Yes or MIS781_CONFIRM=yes skips the confirmation):
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -DryRun
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1))) -All
#
# WARNING: this permanently deletes all MySQL databases on the PC.

param([switch]$DryRun, [switch]$Yes, [switch]$All, [ValidateSet('all', 'user', 'admin')][string]$Phase = 'all')

function Invoke-Mis781Uninstall([bool]$DryRun, [bool]$Yes, [bool]$All, [string]$Phase) {
  $ErrorActionPreference = 'Stop'
  if ($env:MIS781_CONFIRM -eq 'yes') { $Yes = $true }
  $MysqlHome = Join-Path $env:USERPROFILE 'mysql'
  $TaskName  = 'MIS781 MySQL'
  $DoUser  = $Phase -ne 'admin'
  $DoAdmin = $Phase -ne 'user'

  $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  Write-Host 'Scanning for MySQL Server...'
  # Ours: the home-folder install (its my.ini marker, or an unpacked server that
  # never got as far as the my.ini), its logon task and its running process.
  $ourMysqld = Join-Path $MysqlHome 'bin\mysqld.exe'
  $ourIni = Join-Path $MysqlHome 'my.ini'
  $ourFolder = $null
  if ((Test-Path $MysqlHome) -and ((Select-String -Path $ourIni -Pattern 'written by install.ps1' -Quiet -ErrorAction SilentlyContinue) -or
                                   ((Test-Path $ourMysqld) -and -not (Test-Path $ourIni)))) { $ourFolder = $MysqlHome }
  $ourTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  $ourProc = Get-Process -Name mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq $ourMysqld } | Select-Object -First 1
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $ourPathEntry = @($userPath -split ';' | Where-Object { $_ -ieq (Join-Path $MysqlHome 'bin') })

  # Legacy: the MSI install (service, registered program, Program Files and
  # ProgramData folders, and the firewall rule its installer added).
  $services = @(Get-Service 'MySQL*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Router' })
  $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $products = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Server*' -and $_.PSChildName -like '{*' })
  $folders = @()
  foreach ($root in $env:ProgramFiles, $env:ProgramData) {
    $folders += @(Get-ChildItem (Join-Path $root 'MySQL\MySQL Server *') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  }
  $rules = @()
  if ($services.Count + $products.Count + $folders.Count) { $rules = @(Get-NetFirewallRule -DisplayName '*MySQL*' -ErrorAction SilentlyContinue) }
  $legacyCount = $services.Count + $products.Count + $folders.Count + $rules.Count

  # Other servers are listed so the student knows, and left alone.
  $others = @()
  if (Test-Path 'C:\xampp\mysql\bin\mysqld.exe') { $others += 'XAMPP (C:\xampp)' }
  if (Test-Path 'C:\wamp64\bin\mysql') { $others += 'WampServer (C:\wamp64)' }

  # -All: Workbench and everything else this unit put on the PC.
  $wbProducts = @(); $allPaths = @(); $wbShell = $null; $savedTargets = @()
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
    # The password saved for Workbench lives in Windows Credential Manager. The
    # shell Workbench ships with deletes it; failing that, cmdkey finds the entry.
    foreach ($d in @($wbProducts | ForEach-Object { $_.InstallLocation }) + @("$env:ProgramFiles\MySQL\MySQL Workbench*")) {
      if (-not $d) { continue }
      $exe = Get-ChildItem $d -Recurse -Depth 6 -Filter 'mysqlsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($exe) { $wbShell = $exe.FullName; break }
    }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $savedTargets = @(& cmdkey.exe /list 2>$null | Where-Object { $_ -match 'root@127\.0\.0\.1:3306' } | ForEach-Object { if ($_ -match 'Target:\s*(?:\w+:target=)?(.+?)\s*$') { $Matches[1] } })
    $ErrorActionPreference = $prev
  }

  $userCount  = if ($DoUser) { @($ourFolder, $ourTask, $ourProc).Where({ $_ }).Count + $ourPathEntry.Count + $allPaths.Count + $savedTargets.Count } else { 0 }
  $adminCount = if ($DoAdmin) { $legacyCount + $wbProducts.Count } else { 0 }
  if (-not ($userCount + $adminCount)) {
    if ($Phase -eq 'admin') { Write-Host 'Nothing left that needs administrator rights.' } else { Write-Host 'No MySQL Server found. Nothing to do.' }
    foreach ($o in $others) { Write-Host "  (Note: $o has its own MySQL; it is not from this unit and is left alone.)" }
    return
  }
  # The list. In the user phase the administrator items are shown too, so one
  # confirmation covers both windows.
  $showAdmin = $DoAdmin -or $Phase -eq 'user'
  $tag = if ($Phase -eq 'user') { ' (administrator window)' } else { '' }
  if ($DoUser) {
    if (@($ourFolder, $ourTask, $ourProc).Where({ $_ }).Count + $ourPathEntry.Count) { Write-Host 'MySQL Server (ours):' }
    if ($ourProc)   { Write-Host "  running:  mysqld (process $($ourProc.Id))" }
    if ($ourTask)   { Write-Host "  task:     $TaskName (starts it at logon)" }
    if ($ourFolder) { Write-Host "  folder:   $ourFolder (programs and ALL its databases)" }
    if ($ourPathEntry.Count) { Write-Host "  PATH:     $($ourPathEntry[0]) (your user PATH)" }
  }
  if ($showAdmin -and $legacyCount) { Write-Host "MySQL Server (this unit's earlier install)${tag}:" }
  if ($showAdmin) {
    foreach ($s in $services) { Write-Host "  service:  $($s.Name)" }
    foreach ($p in $products) { Write-Host "  program:  $($p.DisplayName)" }
    foreach ($f in $folders)  { Write-Host "  folder:   $f" }
    foreach ($r in $rules)    { Write-Host "  firewall: $($r.DisplayName)" }
  }
  if (($showAdmin -and $wbProducts.Count) -or ($DoUser -and ($allPaths.Count + $savedTargets.Count))) { Write-Host 'Workbench, saved connections and password, Employees files and downloads (removed with -All):' }
  if ($showAdmin) { foreach ($p in $wbProducts) { Write-Host "  program:  $($p.DisplayName) $($p.DisplayVersion)$tag" } }
  if ($DoUser) {
    foreach ($t in $savedTargets) { Write-Host "  password: saved for root@127.0.0.1:3306 in Windows Credential Manager ($t)" }
    foreach ($p in $allPaths)     { Write-Host "  path:     $p" }
  }
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
  if ($DoAdmin -and $adminCount -and -not $isAdmin) {
    throw "Removing the earlier MySQL Server install or Workbench needs an administrator window. Run the setup line (see the README) and choose the removal there, and it opens one for you; or right-click Start, choose 'Terminal (Admin)' and paste this command again."
  }
  if (-not $Yes) {
    $answer = Read-Host 'Type "yes" to uninstall everything listed above'
    if ($answer -cne 'yes') {
      Write-Host 'Aborted. Nothing was changed.'
      return
    }
  }

  if ($DoUser) {
    # Ours first: stop it, drop the logon task, delete the folder, tidy the PATH.
    if ($ourTask) {
      Write-Host "Removing the logon task $TaskName..."
      Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($ourProc) {
      Write-Host 'Stopping MySQL Server...'
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      & taskkill.exe /PID $ourProc.Id 2>$null | Out-Null    # a plain taskkill asks it to close; its databases are deleted next anyway
      $ErrorActionPreference = $prev
      for ($t = 0; $t -lt 15 -and -not $ourProc.HasExited; $t++) { Start-Sleep 1 }
      if (-not $ourProc.HasExited) { Stop-Process -Id $ourProc.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
    }
    if ($ourPathEntry.Count) {
      $kept = @($userPath -split ';' | Where-Object { $_ -and $_ -ine (Join-Path $MysqlHome 'bin') })
      [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    }
    # The saved Workbench password, while the shell that manages it is still there.
    if ($savedTargets.Count) {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      try {
        if ($wbShell) {
          $py = Join-Path $env:TEMP ("mis781-wb-" + [guid]::NewGuid().ToString('N') + ".py")
          [IO.File]::WriteAllText($py, "try:`n    shell.delete_credential('root@127.0.0.1:3306')`nexcept Exception:`n    pass`n", [Text.UTF8Encoding]::new($false))
          $env:MYSQLSH_USER_CONFIG_HOME = Join-Path $env:APPDATA 'MySQL Workbench\mysqlsh'
          try { & $wbShell --py -f $py 2>&1 | Out-Null } catch {}
          finally { Remove-Item $py -Force -ErrorAction SilentlyContinue; Remove-Item Env:\MYSQLSH_USER_CONFIG_HOME -ErrorAction SilentlyContinue }
        }
        foreach ($t in $savedTargets) { & cmdkey.exe /delete:$t 2>$null | Out-Null }
      } finally { $ErrorActionPreference = $prev }
    }
  }

  if ($DoAdmin) {
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
  }

  $toDelete = @()
  if ($DoUser)  { $toDelete += @($ourFolder) + $allPaths }
  if ($DoAdmin) { $toDelete += $folders }
  foreach ($f in $toDelete) {
    if ($f -and (Test-Path $f)) { Write-Host "Deleting $f..."; Remove-Item $f -Recurse -Force }
  }

  Write-Host ''
  $left = @($toDelete | Where-Object { $_ -and (Test-Path $_) })
  if ($left.Count) {
    throw "Some items could not be removed: $($left -join ', '). Restart Windows and run this again."
  }
  if ($Phase -eq 'user') {
    if ($adminCount -or $legacyCount + $wbProducts.Count) { Write-Host 'Your own part is done. The items marked (administrator window) come off next.' }
    else { Write-Host 'Done.' }
    Write-Output $true    # tells the setup script the student confirmed and the admin part may follow
    return
  }
  if ($All) { Write-Host 'MySQL Server, Workbench and the MIS781 files have been completely removed.' }
  else      { Write-Host 'MySQL Server has been completely removed. Workbench and the Employees files were kept.' }
}

Invoke-Mis781Uninstall ([bool]$DryRun) ([bool]$Yes) ([bool]$All) $Phase
