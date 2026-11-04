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
# Reset and the two Remove actions need administrator rights: the script opens
# an administrator window for them by itself (Windows asks you to allow it).
#
# Unattended (lab PCs, the Actions test): MIS781_ACTION=scan|install|load|reset|
# remove-server|remove-all, plus MIS781_ROOT_PASSWORD, MIS781_IMPORT=y,
# MIS781_NEW_PASSWORD (reset) and MIS781_CONFIRM=yes for anything destructive.
# Without MIS781_CONFIRM a destructive action prints what it would do and stops.

$ErrorActionPreference = 'Stop'
$Raw   = 'https://raw.githubusercontent.com/thuc-gh/mis781-setup/main'
$Data  = Join-Path $env:USERPROFILE 'MIS781'
$DL    = Join-Path $env:USERPROFILE 'Downloads'

# Arguments arrive only when the elevated copy is run as a file: -Action <x> -Elevated
$Action = $env:MIS781_ACTION
$Elevated = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '-Action'   { $i++; $Action = $args[$i] }
        '-Elevated' { $Elevated = $true }
    }
}
$Unattended = [bool]$env:MIS781_ACTION
$Confirmed  = ($env:MIS781_CONFIRM -eq 'yes')
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
function Invoke-Uninstaller([bool]$All, [bool]$Yes, [bool]$DryRun) {
    & ([scriptblock]::Create((Get-Worker 'uninstall-mysql.ps1'))) -All:$All -Yes:$Yes -DryRun:$DryRun
}

# ---- 1. Scan (read-only) -----------------------------------------------------
$serverExe = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server *\bin\mysqld.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Where-Object Name -notmatch 'Router' | Select-Object -First 1
$Ours = [bool]$serverExe
$OursVersion = if ($serverExe) { ($serverExe.Directory.Parent.Name -replace '^MySQL Server ', '') } else { '' }
$OursRunning = ($svc -and $svc.Status -eq 'Running')
$OursNoService = ($Ours -and -not $svc)

$Other = ''; $OtherRunning = $false
$listen = Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listen) {
    # Our service's process id, so a listener on 3306 that is not it counts as another server.
    $svcPid = if ($svc) { (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue).ProcessId } else { 0 }
    if ($listen.OwningProcess -ne $svcPid) {
        $proc = Get-Process -Id $listen.OwningProcess -ErrorAction SilentlyContinue
        $Other = "$(if ($proc) { $proc.ProcessName } else { 'a program' }) running on port 3306"; $OtherRunning = $true
    }
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
    foreach ($root in "$env:ProgramFiles\MySQL", "$env:ProgramFiles\MySQL Workbench*", "$env:LOCALAPPDATA\Programs") {
        $exe = Get-ChildItem $root -Recurse -Depth 2 -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object Name -match 'workbench' | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}
$Workbench = Get-WorkbenchInstall
$Files = Test-Path (Join-Path $Data 'test_db-master\employees.sql')

Write-Host ''
Write-Host "What is on this PC ($env:PROCESSOR_ARCHITECTURE):"
if ($Ours) {
    if ($OursRunning)        { Write-Host "  MySQL Server      ours, running on 127.0.0.1:3306 (MySQL Server $OursVersion)" }
    elseif ($OursNoService)  { Write-Host "  MySQL Server      ours, installed but MySQL Configurator was never finished (no service)" }
    else                     { Write-Host "  MySQL Server      ours, installed, service $($svc.Name) is $($svc.Status)" }
} else {
    Write-Host '  MySQL Server      none from this unit'
}
if ($Other)     { Write-Host "  Other MySQL       $Other" } else { Write-Host '  Other MySQL       none' }
if ($Workbench) { Write-Host "  MySQL Workbench   $Workbench" } else { Write-Host '  MySQL Workbench   not installed' }
if ($Files)     { Write-Host "  Employees files   present ($Data\test_db-master)" } else { Write-Host '  Employees files   not downloaded' }
Write-Host '  Employees data    (checked when you connect)'

# ---- 2. Recommendation -------------------------------------------------------
$Rec = ''; $Note = ''
if ($Ours -and $OtherRunning) {
    $Rec = 'remove-server'; $Note = 'Two servers want port 3306 and the other one has it, so ours cannot start. Remove ours and use the other, or remove the other by hand and run Install again.'
} elseif (-not $Ours -and $OtherRunning) {
    $Rec = 'quit'; $Note = "$Other is using port 3306, which MySQL Server needs. Unlike the macOS installer, the Windows installer cannot use another server. Stop or remove it (e.g. in the XAMPP control panel), then run this again and choose Install."
} elseif (-not $Ours) {
    $Rec = 'install'; if ($Other) { $Note = "Install puts in the unit's own MySQL Server; $Other also has a MySQL on this PC, so do not start both at once." }
} elseif ($OursNoService) {
    $Rec = 'quit'; $Note = 'MySQL Server is installed but was never configured. Open MySQL Configurator from the Start menu, set a root password, keep "Windows Service" ticked and click Execute. Then run this again.'
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
if ($Ours -or $Other) { $Menu += 'load' }
if ($Ours -and -not $OursNoService) { $Menu += 'reset' }
if ($Ours -or $Other) { $Menu += 'remove-server' }
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
# Reset and Remove need administrator rights. Interactive and not admin yet:
# save this script and run it again in an administrator window with the action.
$NeedsAdmin = $Action -in 'reset', 'remove-server', 'remove-all'
if ($NeedsAdmin -and -not $IsAdmin) {
    if ($Unattended) { throw 'This action needs an administrator PowerShell when run unattended.' }
    $copy = Join-Path $env:TEMP 'mis781-setup.ps1'
    [IO.File]::WriteAllText($copy, (Get-Worker 'setup.ps1'), [Text.UTF8Encoding]::new($true))
    Write-Host 'This needs administrator rights. Windows will ask you to allow it; the rest happens in the new window.'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$copy`"", '-Action', $Action, '-Elevated')
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

function Reset-RootPassword {
    # Native commands below have their stderr discarded; under 'Stop' that alone
    # would be a terminating error in Windows PowerShell, so judge by exit codes here.
    $ErrorActionPreference = 'Continue'
    Write-Host 'Reset the MySQL root password'
    Write-Host '-----------------------------'
    $bin = $serverExe.Directory.FullName
    $mysqld = $serverExe.FullName
    $mysql = Join-Path $bin 'mysql.exe'
    $mysqladmin = Join-Path $bin 'mysqladmin.exe'
    # The service's command line names the my.ini it runs with.
    $cmd = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").PathName
    $ini = if ($cmd -match '--defaults-file="([^"]+)"') { $Matches[1] } else { Join-Path $env:ProgramData "MySQL\MySQL Server $OursVersion\my.ini" }
    if (-not (Test-Path $ini)) { throw "Cannot find the server settings file ($ini). Choose 'Remove MySQL Server' and then 'Install' instead." }

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
    Write-Host "  - stop the $($svc.Name) service (anything connected to it is disconnected)"
    Write-Host "  - give the 'root' account the new password; the old one stops working"
    Write-Host '  - start the service again'
    Write-Host '  Every database on the server is kept.'
    if (-not $Confirmed) {
        if ($Unattended) { Write-Host ''; Write-Host 'Nothing was changed. (Set MIS781_CONFIRM=yes to go ahead unattended.)'; return }
        $ans = Read-Host 'Continue? [y/N]'
        if ($ans -notmatch '^[Yy]') { Write-Host 'Nothing was changed.'; return }
    }
    Write-Host ''

    $init = Join-Path $env:TEMP ("mis781-reset-" + [guid]::NewGuid().ToString('N') + ".sql")
    $log  = Join-Path $env:TEMP 'mis781-reset.log'
    $pwSql = ($newPw -replace '\\','\\') -replace "'","\'"
    [IO.File]::WriteAllText($init, "ALTER USER 'root'@'localhost' IDENTIFIED BY '$pwSql';`nFLUSH PRIVILEGES;`n", [Text.UTF8Encoding]::new($false))
    $env:MYSQL_PWD = $newPw
    Remove-Variable newPw, pwSql
    try {
        Write-Host -NoNewline "[1/4] Stopping the $($svc.Name) service"
        Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
        [void](Wait-Until { (Get-Service $svc.Name).Status -eq 'Stopped' } 60)
        Write-Host ''

        Write-Host -NoNewline '[2/4] Starting it once to set the new password'
        $p = Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$ini`"", "--init-file=`"$init`"", '--console' `
             -RedirectStandardError $log -NoNewWindow -PassThru
        $up = Wait-Until { & $mysqladmin -h 127.0.0.1 -u root ping 2>$null; $LASTEXITCODE -eq 0 } 60
        Write-Host ''
        $shut = $false
        if ($up) { & $mysqladmin -h 127.0.0.1 -u root shutdown 2>$null; $shut = ($LASTEXITCODE -eq 0) }
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
        $up = Wait-Until { & $mysqladmin -h 127.0.0.1 -u root ping 2>$null; $LASTEXITCODE -eq 0 } 60
        Write-Host ''

        Write-Host '[4/4] Checking the new password...'
        & $mysql -h 127.0.0.1 -u root -N -e 'SELECT 1' 2>$null | Out-Null
        if ($up -and $LASTEXITCODE -eq 0) {
            $n = (& $mysql -h 127.0.0.1 -u root -N -e 'SELECT COUNT(*) FROM employees.employees' 2>$null | Out-String).Trim()
            Write-Host "  MySQL Server      OK  ($($svc.Name) running, new root password works)"
            if ($n -eq '300024') { Write-Host '  Employees data    OK  (300024 employees, untouched)' } else { Write-Host "  Employees data    not loaded (run this again and choose 'Load the Employees database')" }
            Write-Host ''
            Write-Host 'Done. Use the new password in Workbench (host 127.0.0.1, port 3306, user root).'
        } else {
            throw "The service is back up but the new password does not work. Choose 'Remove MySQL Server' and then 'Install' instead."
        }
    } finally {
        Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
        Remove-Item $init -Force -ErrorAction SilentlyContinue
    }
}

try {
    switch ($Action) {
        'install'       { Invoke-Worker 'install.ps1' }
        'load'          { Invoke-Worker 'import-employees.ps1' }
        'reset'         { Reset-RootPassword }
        'remove-server' { Invoke-Uninstaller -All $false -Yes $Confirmed -DryRun ($Unattended -and -not $Confirmed) }
        'remove-all'    { Invoke-Uninstaller -All $true  -Yes $Confirmed -DryRun ($Unattended -and -not $Confirmed) }
        'quit'          { Write-Host 'Nothing was changed.' }
    }
} finally {
    if ($Elevated) { Write-Host ''; Read-Host 'Press Enter to close this window' | Out-Null }
}
