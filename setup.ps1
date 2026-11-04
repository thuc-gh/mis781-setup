# MIS781 Business Intelligence and Database - setup (64-bit Windows 10/11)
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/setup.ps1 | iex
#
# Looks at what is already on this PC (without changing anything or asking for
# a password), recommends one action, shows a short menu, and runs the action
# you choose. The actions are the other scripts in this repo:
#
#   Install            install.ps1           adds whatever is missing
#   Load data          import-employees.ps1  loads the Employees database
#   Reset password     (this script)         new root password, every database kept
#   Remove server      uninstall-mysql.ps1   MySQL Server and its databases go,
#                                            Workbench and the Employees files stay
#   Remove everything  uninstall-mysql.ps1 -All
#
# Our server lives in C:\Users\<you>\mysql and runs as you, so nothing here
# needs administrator rights. The legacy server (this unit's earlier MSI
# install, a Windows service) and the Workbench MSI do. For those the script
# first does everything that is yours in this window, then opens an
# administrator window by itself for the rest (Windows asks you to allow it).
#
# Unattended (lab PCs, the Actions test): MIS781_ACTION=scan|install|load|reset|
# remove-server|remove-all, plus MIS781_ROOT_PASSWORD, MIS781_IMPORT=y,
# MIS781_NEW_PASSWORD (reset) and MIS781_CONFIRM=yes for anything destructive.
# Without MIS781_CONFIRM a destructive action prints what it would do and stops.

$ErrorActionPreference = 'Stop'
$Raw       = 'https://raw.githubusercontent.com/thuc-gh/mis781-setup/main'
$Data      = Join-Path $env:USERPROFILE 'MIS781'
$MysqlHome = Join-Path $env:USERPROFILE 'mysql'
$TaskName  = 'MIS781 MySQL'

# Arguments arrive only when the elevated copy is run as a file:
#   -Action <x> -Elevated [-Phase admin] [-Yes] [-User <name of the caller>]
$Action = $env:MIS781_ACTION
$Elevated = $false
$Phase = 'all'          # removals: 'user' (your own items), 'admin' (the rest), 'all'
$CallerUser = $env:USERNAME
$Confirmed  = ($env:MIS781_CONFIRM -eq 'yes')
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '-Action'   { $i++; $Action = $args[$i] }
        '-Elevated' { $Elevated = $true }
        '-Phase'    { $i++; $Phase = $args[$i] }
        '-Yes'      { $Confirmed = $true }
        '-User'     { $i++; $CallerUser = $args[$i] }
    }
}
$Unattended = [bool]$env:MIS781_ACTION
$IsAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host 'MIS781 setup (Windows)'
Write-Host '======================'

# Returns the text of a worker script: a local copy when MIS781_LOCAL_SCRIPTS
# points at a checkout (the Actions test), otherwise the copy on GitHub.
function Get-Worker([string]$Name) {
    if ($env:MIS781_LOCAL_SCRIPTS -and (Test-Path (Join-Path $env:MIS781_LOCAL_SCRIPTS $Name))) {
        return Get-Content (Join-Path $env:MIS781_LOCAL_SCRIPTS $Name) -Raw
    }
    try { return (Invoke-WebRequest -Uri "$Raw/$Name" -UseBasicParsing).Content }
    catch { throw "Could not download $Name. Check your internet connection and run this again." }
}
function Invoke-Worker([string]$Name) {
    & ([scriptblock]::Create((Get-Worker $Name)))
}
function Invoke-Uninstaller([bool]$All, [bool]$Yes, [bool]$DryRun, [string]$Phase = 'all') {
    & ([scriptblock]::Create((Get-Worker 'uninstall-mysql.ps1'))) -All:$All -Yes:$Yes -DryRun:$DryRun -Phase $Phase
}
function Get-OurServerProcess {
    Get-Process -Name mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq (Join-Path $MysqlHome 'bin\mysqld.exe') } | Select-Object -First 1
}
function Start-OurServer {
    Start-Process -FilePath (Join-Path $MysqlHome 'bin\mysqld.exe') -ArgumentList "--defaults-file=`"$MysqlHome\my.ini`"" `
        -WorkingDirectory $MysqlHome -WindowStyle Hidden
}

# ---- 1. Scan (read-only) -----------------------------------------------------
# Our server: the home-folder install. Legacy server: this unit's MSI install
# from before week 2 (a Windows service under Program Files). Other: anything else.
$Ours = Test-Path (Join-Path $MysqlHome 'bin\mysqld.exe')
$OursProc = if ($Ours) { Get-OurServerProcess }
# Running means our process holds port 3306, not just that it exists.
$OursRunning = [bool]($OursProc -and (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue | Where-Object OwningProcess -eq $OursProc.Id))
$OursTask = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)

$serverExe = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server *\bin\mysqld.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Where-Object Name -notmatch 'Router' | Select-Object -First 1
$Legacy = [bool]$serverExe
$LegacyVersion = if ($serverExe) { ($serverExe.Directory.Parent.Name -replace '^MySQL Server ', '') } else { '' }
$LegacyRunning = ($Legacy -and $svc -and $svc.Status -eq 'Running')
$LegacyNoService = ($Legacy -and -not $svc)

$Other = ''; $OtherRunning = $false
# Only one process can hold port 3306: a listener is another server only when
# neither ours nor the legacy service is the one running.
$listen = if (-not $OursRunning -and -not $LegacyRunning) { Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 }
if ($listen) {
    $proc = Get-Process -Id $listen.OwningProcess -ErrorAction SilentlyContinue
    $Other = "$(if ($proc) { $proc.ProcessName } else { 'a program' }) running on port 3306"; $OtherRunning = $true
}
if (-not $Other) {
    if (Test-Path 'C:\xampp\mysql\bin\mysqld.exe') { $Other = 'XAMPP (C:\xampp)' }
    elseif (Test-Path 'C:\wamp64\bin\mysql') { $Other = 'WampServer (C:\wamp64)' }
}

function Get-WorkbenchInstall {
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
           Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' } | Select-Object -First 1
    if ($reg) { return ("$($reg.DisplayVersion) $($reg.InstallLocation)").Trim() }
    # Known locations only: a recursive search of LOCALAPPDATA\Programs took minutes.
    foreach ($pattern in "$env:ProgramFiles\MySQL\MySQL Workbench*\MySQLWorkbench.exe",
                         "$env:ProgramFiles\MySQL Workbench*\MySQLWorkbench.exe",
                         "$env:LOCALAPPDATA\Programs\MySQL*\MySQLWorkbench.exe",
                         "$env:LOCALAPPDATA\Programs\MySQL*\*\MySQLWorkbench.exe") {
        $exe = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}
$Workbench = Get-WorkbenchInstall
$Files = Test-Path (Join-Path $Data 'test_db-master\employees.sql')

Write-Host ''
Write-Host "What is on this PC ($env:PROCESSOR_ARCHITECTURE):"
if ($Ours) {
    if ($OursRunning) { Write-Host "  MySQL Server      ours, running on 127.0.0.1:3306 (files in $MysqlHome)" }
    else              { Write-Host "  MySQL Server      ours, not running (files in $MysqlHome)" }
} else {
    Write-Host '  MySQL Server      none from this unit'
}
if ($Legacy) {
    if ($LegacyNoService)   { Write-Host "  Legacy server     this unit's earlier install (MySQL Server $LegacyVersion), MySQL Configurator was never finished (no service)" }
    elseif ($LegacyRunning) { Write-Host "  Legacy server     this unit's earlier install (MySQL Server $LegacyVersion), service $($svc.Name) is running" }
    else                    { Write-Host "  Legacy server     this unit's earlier install (MySQL Server $LegacyVersion), service $($svc.Name) is $($svc.Status)" }
}
if ($Other)     { Write-Host "  Other MySQL       $Other" } else { Write-Host '  Other MySQL       none' }
if ($Workbench) { Write-Host "  MySQL Workbench   $Workbench" } else { Write-Host '  MySQL Workbench   not installed' }
if ($Files)     { Write-Host "  Employees files   present ($Data\test_db-master)" } else { Write-Host '  Employees files   not downloaded' }
Write-Host '  Employees data    (checked when you connect)'
if ($Ours) { if ($OursTask) { Write-Host "  Starts at logon   yes (task '$TaskName')" } else { Write-Host '  Starts at logon   no (Install puts the logon task back)' } }

# ---- 2. Recommendation -------------------------------------------------------
$Rec = ''; $Note = ''
if ($Ours -and $Legacy) {
    $Rec = 'remove-server'
    $Note = if ($LegacyRunning) { "Two servers from this unit want port 3306 and the earlier one (service $($svc.Name)) has it, so the one in your home folder cannot start. Remove MySQL Server takes both off; then Install puts the home-folder one back." }
            else { "Two servers from this unit are installed, and the earlier one (service $($svc.Name)) will take port 3306 whenever it starts. Remove MySQL Server takes both off; then Install puts the home-folder one back." }
} elseif ($Ours -and $OtherRunning) {
    $Rec = 'remove-server'; $Note = 'Two servers want port 3306 and the other one has it, so ours cannot start. Remove ours and use the other, or remove the other by hand and run Install again.'
} elseif (-not $Ours -and $LegacyNoService) {
    $Rec = 'quit'; $Note = 'MySQL Server (the earlier install) was never configured. Open MySQL Configurator from the Start menu, set a root password, keep "Windows Service" ticked and click Execute. Then run this again. Or choose Remove MySQL Server and then Install, which puts the server in your home folder and needs no administrator rights.'
} elseif (-not $Ours -and -not $Legacy) {
    $Rec = 'install'
    if ($OtherRunning) { $Note = "$Other is using port 3306. Install uses that server (it asks for its root password) and still sets up Workbench and the Employees data." }
    elseif ($Other) { $Note = "Install puts in the unit's own MySQL Server; $Other also has a MySQL on this PC, so do not start both at once." }
} elseif ($Ours -and -not $OursRunning) {
    $Rec = 'install'; $Note = 'MySQL Server is not running. Install starts it (and shows what is wrong if it will not start).'
} elseif (-not $Workbench -or -not $Files) {
    $Rec = 'install'
} else {
    $Rec = 'load'
}

function Get-Label([string]$a) {
    switch ($a) {
        'install'       { 'Install everything that is missing' }
        'load'          { 'Load the Employees database' }
        'reset'         { 'Reset the MySQL root password (databases are kept)' }
        'remove-server' { 'Remove MySQL Server (then reinstall; Workbench and files are kept)' }
        'remove-all'    { 'Remove everything (server, Workbench, Employees files, downloads)' }
        'quit'          { 'Quit' }
    }
}

$Menu = @('install')
if ($Ours -or $Legacy -or $Other) { $Menu += 'load' }
if ($Ours -or ($Legacy -and -not $LegacyNoService)) { $Menu += 'reset' }
if ($Ours -or $Legacy -or $Other) { $Menu += 'remove-server' }
$Menu += 'remove-all', 'quit'

Write-Host ''
if ($Note) { Write-Host "  $Note"; Write-Host '' }
Write-Host "Recommended: $(Get-Label $Rec)"

# ---- 3. Choose ---------------------------------------------------------------
if ($Action -eq 'scan') { return }
if (-not $Action) {
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
        Write-Host ''
        Write-Host "(No keyboard to ask on. Set MIS781_ACTION to one of: $($Menu -join ', ') to run an action.)"
        return
    }
    Write-Host ''
    $default = 0
    for ($i = 0; $i -lt $Menu.Count; $i++) {
        if ($Menu[$i] -eq $Rec) { $default = $i + 1 }
        Write-Host ("  {0}. {1}" -f ($i + 1), (Get-Label $Menu[$i]))
    }
    while ($true) {
        $choice = Read-Host "Choose [$default]"
        if (-not $choice) { $choice = "$default" }
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Menu.Count) { $Action = $Menu[[int]$choice - 1]; break }
        Write-Host "  Type a number between 1 and $($Menu.Count)."
    }
} elseif ($Menu -notcontains $Action) {
    throw "MIS781_ACTION=$Action is not available on this PC (choices: $($Menu -join ', '))."
}
Write-Host ''

# ---- 4. Act ------------------------------------------------------------------
# Our server runs as you, so its actions need no administrator rights. The
# legacy service and the Workbench MSI do. Interactive and not admin yet: for
# a removal, first take off everything that is yours in this window (the list
# and the confirmation cover both parts), then save this script and run it
# again in an administrator window for the rest. That window may belong to
# another account (a standard user types an administrator's password), which
# is why your own files, task, PATH and saved password are handled here first.
$WorkbenchMsi = [bool](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                       Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' -and $_.PSChildName -like '{*' })
$NeedsAdmin = switch ($Action) {
    'reset'         { -not $Ours -and $Legacy }
    'remove-server' { $Legacy }
    'remove-all'    { $Legacy -or $WorkbenchMsi }
    default         { $false }
}
if ($NeedsAdmin -and -not $IsAdmin) {
    if ($Unattended) { throw 'This action needs an administrator PowerShell when run unattended.' }
    $extra = @('-User', $env:USERNAME)
    if ($Action -in 'remove-server', 'remove-all') {
        $went = Invoke-Uninstaller -All ($Action -eq 'remove-all') -Yes $false -DryRun $false -Phase 'user'
        if (-not $went) { return }
        $extra += '-Phase', 'admin', '-Yes'
    }
    $copy = Join-Path $env:TEMP 'mis781-setup.ps1'
    [IO.File]::WriteAllText($copy, (Get-Worker 'setup.ps1'), [Text.UTF8Encoding]::new($true))
    Write-Host 'The rest needs administrator rights. Windows will ask you to allow it; it happens in the new window.'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$copy`"", '-Action', $Action, '-Elevated') + $extra
    $p = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -Wait -PassThru
    Remove-Item $copy -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { Write-Host "The administrator window finished with code $($p.ExitCode)." }
    return
}

function Read-Secret([string]$Prompt) {
    $s = Read-Host -Prompt $Prompt -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Wait-Until([scriptblock]$Test, [int]$Seconds) {
    for ($t = 0; $t -lt $Seconds; $t++) {
        if (& $Test) { return $true }
        Write-Host -NoNewline '.'; Start-Sleep 1
    }
    return $false
}

# Asks for the new password (twice, hidden) or takes MIS781_NEW_PASSWORD, shows
# what the reset does, and asks for a y. Returns the password, or $null to stop.
function Read-NewPasswordAndConfirm([string]$StopLine) {
    $newPw = $env:MIS781_NEW_PASSWORD
    if (-not $newPw) {
        if ($Unattended) { throw 'Set MIS781_NEW_PASSWORD for an unattended reset.' }
        Write-Host "Choose a NEW password for the MySQL 'root' account. >>> WRITE IT DOWN. <<<"
        while (-not $newPw) {
            $a = Read-Secret '  New root password (typing is hidden)'
            $b = Read-Secret '  Type it again'
            if (-not $a) { Write-Host '  It cannot be empty.' } elseif ($a -cne $b) { Write-Host '  They do not match, try again.' } else { $newPw = $a }
        }
    }
    Write-Host ''
    Write-Host 'This will:'
    Write-Host "  - $StopLine"
    Write-Host "  - give the 'root' account the new password; the old one stops working"
    Write-Host '  - start the server again'
    if ($Workbench) { Write-Host '  - give Workbench the new password for its connection to this server (saved in Windows Credential Manager)' }
    Write-Host '  Every database on the server is kept.'
    if (-not $Confirmed) {
        if ($Unattended) { Write-Host ''; Write-Host 'Nothing was changed. (Set MIS781_CONFIRM=yes to go ahead unattended.)'; return $null }
        $ans = Read-Host 'Continue? [y/N]'
        if ($ans -notmatch '^[Yy]') { Write-Host 'Nothing was changed.'; return $null }
    }
    Write-Host ''
    return $newPw
}

# Writes the init file (the ALTER USER) and a client option file for the new
# password; both private temp files, deleted by the caller.
function Write-PasswordFiles([string]$Password, [string]$Init, [string]$Cnf) {
    $pwSql = ($Password -replace '\\','\\') -replace "'","\'"
    [IO.File]::WriteAllText($Init, "ALTER USER 'root'@'localhost' IDENTIFIED BY '$pwSql';`nFLUSH PRIVILEGES;`n", [Text.UTF8Encoding]::new($false))
    $pwEsc = ($Password -replace '\\','\\') -replace '"','\"'
    [IO.File]::WriteAllText($Cnf, "[client]`nuser=root`nhost=127.0.0.1`nport=3306`npassword=`"$pwEsc`"`n", [Text.UTF8Encoding]::new($false))
}

# Gives Workbench the new password for its connection to this server. Returns
# whether it did; in an administrator window that belongs to another account
# the saved password is that account's, not yours, so nothing is saved.
function Update-WorkbenchPassword([string]$Cnf) {
    if (-not $Workbench) { return $false }
    Write-Host ''
    if ($Elevated -and $CallerUser -and $CallerUser -ine $env:USERNAME) {
        Write-Host "  This administrator window belongs to $env:USERNAME, so the password saved for Workbench was not updated; Workbench will ask $CallerUser for it once."
        return $false
    }
    $env:MIS781_CNF = $Cnf
    try { & ([scriptblock]::Create((Get-Worker 'workbench-connection.ps1'))); return $true }
    catch { Write-Host "  Could not update the password saved for Workbench ($($_.Exception.Message)). Workbench will ask for it."; return $false }
    finally { Remove-Item Env:\MIS781_CNF -ErrorAction SilentlyContinue }
}

function Show-OurErrorLog {
    Get-Content (Join-Path $MysqlHome 'mysql-error.log') -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "         $_" }
}

# Reset for our server: it runs as you, so no administrator rights are needed.
function Reset-OurPassword {
    $ErrorActionPreference = 'Continue'   # judge native commands by exit code
    Write-Host 'Reset the MySQL root password'
    Write-Host '-----------------------------'
    $bin = Join-Path $MysqlHome 'bin'
    $mysqld = Join-Path $bin 'mysqld.exe'; $mysql = Join-Path $bin 'mysql.exe'; $mysqladmin = Join-Path $bin 'mysqladmin.exe'
    $ini = Join-Path $MysqlHome 'my.ini'
    if (-not (Test-Path $ini)) { throw "Cannot find the server settings file ($ini). Choose 'Remove MySQL Server' and then 'Install' instead." }
    $newPw = Read-NewPasswordAndConfirm "stop MySQL Server in $MysqlHome (anything connected to it is disconnected)"
    if (-not $newPw) { return }

    $init = Join-Path $env:TEMP ("mis781-reset-" + [guid]::NewGuid().ToString('N') + ".sql")
    $cnf  = Join-Path $env:TEMP ("mis781-" + [guid]::NewGuid().ToString('N') + ".cnf")
    Write-PasswordFiles $newPw $init $cnf
    Remove-Variable newPw
    $ping = { & $mysqladmin --no-defaults -h 127.0.0.1 -P 3306 -u root ping 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
    try {
        Write-Host -NoNewline '[1/4] Stopping the server'
        $proc = Get-OurServerProcess
        if ($proc) {
            # A plain taskkill lets mysqld shut down cleanly (it closes on the console
            # close event); only if that takes too long is it ended outright.
            & taskkill.exe /PID $proc.Id 2>$null | Out-Null
            if (-not (Wait-Until { $proc.HasExited } 30)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; [void](Wait-Until { $proc.HasExited } 30) }
            if (-not $proc.HasExited) { Write-Host ''; throw 'The running server would not stop. Restart Windows and try again.' }
        }
        Write-Host ''

        Write-Host -NoNewline '[2/4] Starting it once to set the new password'
        $p = Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$ini`"", "--init-file=`"$init`"" -WorkingDirectory $MysqlHome -WindowStyle Hidden -PassThru
        $up = Wait-Until $ping 60
        Write-Host ''
        $shut = $false
        if ($up) { & $mysqladmin "--defaults-file=$cnf" shutdown 2>$null | Out-Null; $shut = ($LASTEXITCODE -eq 0) }
        if (-not $shut) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep 2
            Start-OurServer
            Write-Host "ERROR: the server did not accept the new password. Last lines of $MysqlHome\mysql-error.log:"
            Show-OurErrorLog
            throw "Choose 'Remove MySQL Server' and then 'Install' instead."
        }
        [void](Wait-Until { $p.HasExited } 60)

        Write-Host -NoNewline '[3/4] Starting the server normally'
        Start-OurServer
        $up = Wait-Until $ping 60
        Write-Host ''

        Write-Host '[4/4] Checking the new password...'
        & $mysql "--defaults-file=$cnf" -N -e 'SELECT 1' 2>$null | Out-Null
        if ($up -and $LASTEXITCODE -eq 0) {
            $n = (& $mysql "--defaults-file=$cnf" -N -e 'SELECT COUNT(*) FROM employees.employees' 2>$null | Out-String).Trim()
            Write-Host '  MySQL Server      OK  (running, new root password works)'
            if ($n -eq '300024') { Write-Host '  Employees data    OK  (300024 employees, untouched)' } else { Write-Host "  Employees data    not loaded (run this again and choose 'Load the Employees database')" }
            if (-not $OursTask) { Write-Host "  NOTE: no logon task was found; choose 'Install' once to put it back." }
            $saved = Update-WorkbenchPassword $cnf
            Write-Host ''
            if ($saved) { Write-Host 'Done. Workbench has the new password; use it too in the mysql command line.' }
            else { Write-Host 'Done. Use the new password in Workbench (host 127.0.0.1, port 3306, user root) and in the mysql command line.' }
        } else {
            throw "The server is back up but the new password does not work. Choose 'Remove MySQL Server' and then 'Install' instead."
        }
    } finally {
        Remove-Item $init, $cnf -Force -ErrorAction SilentlyContinue
    }
}

# Reset for the legacy server (the MSI install's Windows service): needs the
# administrator window this script opened.
function Reset-LegacyPassword {
    $ErrorActionPreference = 'Continue'
    Write-Host 'Reset the MySQL root password'
    Write-Host '-----------------------------'
    $bin = $serverExe.Directory.FullName
    $mysqld = $serverExe.FullName
    $mysql = Join-Path $bin 'mysql.exe'
    $mysqladmin = Join-Path $bin 'mysqladmin.exe'
    # The service's command line names the my.ini it runs with.
    $cmd = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").PathName
    $ini = if ($cmd -match '--defaults-file="([^"]+)"') { $Matches[1] } else { Join-Path $env:ProgramData "MySQL\MySQL Server $LegacyVersion\my.ini" }
    if (-not (Test-Path $ini)) { throw "Cannot find the server settings file ($ini). Choose 'Remove MySQL Server' and then 'Install' instead." }
    $newPw = Read-NewPasswordAndConfirm "stop the $($svc.Name) service (anything connected to it is disconnected)"
    if (-not $newPw) { return }

    $init = Join-Path $env:TEMP ("mis781-reset-" + [guid]::NewGuid().ToString('N') + ".sql")
    $cnf  = Join-Path $env:TEMP ("mis781-" + [guid]::NewGuid().ToString('N') + ".cnf")
    $log  = Join-Path $env:TEMP 'mis781-reset.log'
    Write-PasswordFiles $newPw $init $cnf
    Remove-Variable newPw
    $ping = { & $mysqladmin --no-defaults -h 127.0.0.1 -P 3306 -u root ping 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
    try {
        Write-Host -NoNewline "[1/4] Stopping the $($svc.Name) service"
        Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
        [void](Wait-Until { (Get-Service $svc.Name).Status -eq 'Stopped' } 60)
        Write-Host ''

        Write-Host -NoNewline '[2/4] Starting it once to set the new password'
        $p = Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$ini`"", "--init-file=`"$init`"", '--console' `
             -RedirectStandardError $log -NoNewWindow -PassThru
        $up = Wait-Until $ping 60
        Write-Host ''
        $shut = $false
        if ($up) { & $mysqladmin "--defaults-file=$cnf" shutdown 2>$null | Out-Null; $shut = ($LASTEXITCODE -eq 0) }
        if (-not $shut) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Start-Service $svc.Name -ErrorAction SilentlyContinue
            Write-Host 'ERROR: the server did not accept the new password. Last lines of its output:'
            Get-Content $log -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "         $_" }
            throw "Choose 'Remove MySQL Server' and then 'Install' instead."
        }
        [void](Wait-Until { $p.HasExited } 60)

        Write-Host -NoNewline '[3/4] Starting the service normally'
        Start-Service $svc.Name
        $up = Wait-Until $ping 60
        Write-Host ''

        Write-Host '[4/4] Checking the new password...'
        & $mysql "--defaults-file=$cnf" -N -e 'SELECT 1' 2>$null | Out-Null
        if ($up -and $LASTEXITCODE -eq 0) {
            $n = (& $mysql "--defaults-file=$cnf" -N -e 'SELECT COUNT(*) FROM employees.employees' 2>$null | Out-String).Trim()
            Write-Host "  MySQL Server      OK  ($($svc.Name) running, new root password works)"
            if ($n -eq '300024') { Write-Host '  Employees data    OK  (300024 employees, untouched)' } else { Write-Host "  Employees data    not loaded (run this again and choose 'Load the Employees database')" }
            $saved = Update-WorkbenchPassword $cnf
            Write-Host ''
            if ($saved) { Write-Host 'Done. Workbench has the new password; use it too in the mysql command line.' }
            else { Write-Host 'Done. Use the new password in Workbench (host 127.0.0.1, port 3306, user root).' }
        } else {
            throw "The service is back up but the new password does not work. Choose 'Remove MySQL Server' and then 'Install' instead."
        }
    } finally {
        Remove-Item $init, $cnf -Force -ErrorAction SilentlyContinue
    }
}

try {
    switch ($Action) {
        'install'       { Invoke-Worker 'install.ps1' }
        'load'          { Invoke-Worker 'import-employees.ps1' }
        'reset'         { if ($Ours) { Reset-OurPassword } else { Reset-LegacyPassword } }
        'remove-server' { Invoke-Uninstaller -All $false -Yes $Confirmed -DryRun ($Unattended -and -not $Confirmed) -Phase $Phase | Out-Null }
        'remove-all'    { Invoke-Uninstaller -All $true  -Yes $Confirmed -DryRun ($Unattended -and -not $Confirmed) -Phase $Phase | Out-Null }
        'quit'          { Write-Host 'Nothing was changed.' }
    }
} finally {
    if ($Elevated) { Write-Host ''; Read-Host 'Press Enter to close this window' | Out-Null }
}
