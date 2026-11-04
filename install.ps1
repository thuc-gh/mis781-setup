# MIS781 Business Intelligence and Database - Windows setup (64-bit Windows 10/11)
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.ps1 | iex
#
# Unpacks MySQL Server into C:\Users\<you>\mysql (no administrator rights
# needed), starts it and keeps it starting at every logon, installs MySQL
# Workbench (the one step Windows asks you to allow), gives Workbench a
# ready-made connection with the password saved, then loads the Employees
# sample database. One command, nothing to click through. Safe to re-run:
# anything already done is skipped.

$ErrorActionPreference = 'Stop'
$Base      = 'https://github.com/thuc-gh/mis781-setup/releases/download/v2026-t3'
$Raw       = 'https://raw.githubusercontent.com/thuc-gh/mis781-setup/main'
$DL        = Join-Path $env:USERPROFILE 'Downloads'
$Data      = Join-Path $env:USERPROFILE 'MIS781'
$MysqlHome = Join-Path $env:USERPROFILE 'mysql'
$ServerZip = 'mysql-26.10.0-winx64.zip'
$ServerDir = 'mysql-26.10.0-winx64'
$WbMsi     = 'mysql-workbench-26.10.0-winx64.msi'
$DbZip     = 'test_db-master.zip'
$VcRedist  = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
$TaskName  = 'MIS781 MySQL'
# Unattended (lab PCs, the Actions test): no prompts at all.
$Unattended = [bool]$env:MIS781_ACTION -or [bool]$env:MIS781_ROOT_PASSWORD

Write-Host 'MIS781 Windows setup'
Write-Host '===================='

# ---- Checks before we download anything -------------------------------------
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host 'ERROR: MySQL 26.10 needs 64-bit Windows. This PC is 32-bit. Ask your tutor.'
    return
}
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    Write-Host 'NOTE: this is a Windows on ARM PC. MySQL ships x64 builds only; they run'
    Write-Host '      through emulation, which works but is slower.'
}
$drive = (Get-Item $env:USERPROFILE).PSDrive.Name
$freeGB = [math]::Floor((Get-PSDrive $drive).Free / 1GB)
if ($freeGB -lt 5) {
    Write-Host "ERROR: not enough free disk space. This needs about 5GB free on ${drive}:, you have ${freeGB}GB."
    return
}
New-Item -ItemType Directory -Force -Path $DL, $Data | Out-Null

# ---- Helpers ----------------------------------------------------------------
# Runs a native command whose stderr must not count as an error (curl's progress
# bar, tar's warnings): Windows PowerShell 5.1 would otherwise stop the script.
function Invoke-Native([scriptblock]$Command) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Command; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
}
function Read-Secret([string]$Prompt) {
    $s = Read-Host -Prompt $Prompt -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
# Download helper: curl.exe (built into Windows 10/11) is far faster than
# Invoke-WebRequest and shows progress; fall back to Invoke-WebRequest if absent.
function Get-Asset {
    param([string]$Name, [string]$Size)
    $target = Join-Path $DL $Name
    if ((Test-Path $target) -and (Get-Item $target).Length -gt 1MB) {
        Write-Host "      $Name already in Downloads, re-using it."
    } else {
        Write-Host "      Downloading $Name ($Size)..."
        $part = "$target.part"
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $rc = Invoke-Native { & curl.exe -# -fL -o $part "$Base/$Name" }
            if ($rc -ne 0) { throw "Download of $Name failed (curl exit code $rc). Check your internet connection and run this again." }
        } else {
            $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri "$Base/$Name" -OutFile $part -UseBasicParsing
            $ProgressPreference = $old
        }
        Move-Item -Force $part $target
    }
    # A file saved from the internet carries a mark that makes Windows warn about
    # (or block) what comes out of it; our files come from this unit's release.
    Unblock-File $target -ErrorAction SilentlyContinue
    return $target
}
# Unpacks a zip; tar.exe (built into Windows 10 1803+) is many times faster than Expand-Archive.
function Expand-Zip([string]$Zip, [string]$Into) {
    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        if ((Invoke-Native { & tar.exe -xf $Zip -C $Into }) -eq 0) { return }
        Write-Host '      (tar.exe could not unpack it; trying Expand-Archive instead)'
    }
    Expand-Archive -Path $Zip -DestinationPath $Into -Force
}
function Get-WorkbenchInstall {
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
           Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' } | Select-Object -First 1
    if ($reg) { return ("$($reg.DisplayName) $($reg.DisplayVersion) $($reg.InstallLocation)").Trim() }
    foreach ($pattern in "$env:ProgramFiles\MySQL\MySQL Workbench*\MySQLWorkbench.exe",
                         "$env:ProgramFiles\MySQL Workbench*\MySQLWorkbench.exe",
                         "$env:LOCALAPPDATA\Programs\MySQL*\MySQLWorkbench.exe",
                         "$env:LOCALAPPDATA\Programs\MySQL*\*\MySQLWorkbench.exe") {
        $exe = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}
function Test-Workbench { [bool](Get-WorkbenchInstall) }
function Test-VcRedist {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
    return ($k -and $k.Installed -eq 1 -and $k.Major -ge 14 -and $k.Minor -ge 20)   # 14.20+ = VC++ 2019 or newer
}
# Our mysqld, if it is running (the one started from C:\Users\<you>\mysql).
function Get-OurServerProcess {
    Get-Process -Name mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq (Join-Path $MysqlHome 'bin\mysqld.exe') } | Select-Object -First 1
}
# Starts our server in a hidden window. It outlives this PowerShell window.
function Start-OurServer {
    Start-Process -FilePath (Join-Path $MysqlHome 'bin\mysqld.exe') -ArgumentList "--defaults-file=`"$MysqlHome\my.ini`"" `
        -WorkingDirectory $MysqlHome -WindowStyle Hidden
}
function Test-Port3306 {
    [bool](Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue)
}
function Wait-ForServer([string]$Mysqladmin, [int]$Seconds) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        for ($t = 0; $t -lt $Seconds; $t++) {
            & $Mysqladmin --no-defaults -h 127.0.0.1 -P 3306 -u root ping 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
            Write-Host -NoNewline '.'; Start-Sleep 1
        }
        return $false
    } finally { $ErrorActionPreference = $prev }
}
function Show-ErrorLog {
    Write-Host "       Last lines of $MysqlHome\mysql-error.log:"
    Get-Content (Join-Path $MysqlHome 'mysql-error.log') -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "         $_" }
    Write-Host '       Show this to your tutor.'
}
# Returns the text of a worker script: the local copy when MIS781_LOCAL_SCRIPTS
# points at a checkout (the Actions test), otherwise the published one.
function Get-Worker([string]$Name) {
    if ($env:MIS781_LOCAL_SCRIPTS -and (Test-Path (Join-Path $env:MIS781_LOCAL_SCRIPTS $Name))) {
        return Get-Content (Join-Path $env:MIS781_LOCAL_SCRIPTS $Name) -Raw
    }
    return (Invoke-WebRequest -Uri "$Raw/$Name" -UseBasicParsing).Content
}

# ---- Is MySQL already here? -------------------------------------------------
# Ours (C:\Users\<you>\mysql), the legacy one (this unit's MSI, a Windows
# service under Program Files, from before week 2), or another one (XAMPP,
# WAMP, Oracle's installer, Docker...). An existing one is used, not replaced.
$Ours = Test-Path (Join-Path $MysqlHome 'bin\mysqld.exe')
$legacyExe = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server *\bin\mysqld.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$legacySvc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Where-Object Name -notmatch 'Router' | Select-Object -First 1
$Existing = ''        # the legacy server or an other server, when Install uses it instead of ours
$ExistingClient = $null
$StorePassword = $true
if (-not $Ours -and $legacyExe -and $legacySvc) {
    $Existing = "this unit's earlier MySQL Server (service $($legacySvc.Name), under Program Files)"
    $ExistingClient = Join-Path $legacyExe.Directory.FullName 'mysql.exe'
    if ($legacySvc.Status -ne 'Running') {
        Write-Host "      The $($legacySvc.Name) service is $($legacySvc.Status). Trying to start it (Windows may ask you to allow this)..."
        try { Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', "Start-Service '$($legacySvc.Name)'" -Verb RunAs -Wait } catch {}
    }
} elseif (-not (Get-OurServerProcess) -and (Test-Port3306)) {
    $listen = Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    $proc = Get-Process -Id $listen.OwningProcess -ErrorAction SilentlyContinue
    $who = if ($proc) { $proc.ProcessName } else { 'a program' }
    if ($Ours) {
        Write-Host "ERROR: $MysqlHome is installed, but $who is using port 3306, so ours cannot start."
        Write-Host "       Stop or remove the other one (see 'Other MySQL' in the README), then run this again."
        return
    }
    $Existing = "a MySQL server already running on port 3306 ($who)"
    $StorePassword = $false
    foreach ($c in 'C:\xampp\mysql\bin\mysql.exe', 'C:\wamp64\bin\mysql\*\bin\mysql.exe', 'C:\Program Files\MySQL\MySQL Server *\bin\mysql.exe', 'C:\Program Files\MariaDB*\bin\mysql.exe') {
        $found = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $ExistingClient = $found.FullName; break }
    }
    if (-not $ExistingClient) { $ExistingClient = (Get-Command mysql.exe -ErrorAction SilentlyContinue).Source }
}

# ---- 1. MySQL Server: unpack into C:\Users\<you>\mysql ------------------------
$MysqlClient = Join-Path $MysqlHome 'bin\mysql.exe'
$Mysqladmin  = Join-Path $MysqlHome 'bin\mysqladmin.exe'
if ($Existing) {
    Write-Host "[1/5] MySQL Server already on this PC: $Existing. Using it, nothing downloaded."
    $MysqlClient = $ExistingClient
    if ($MysqlClient) { Write-Host "      Command-line client: $MysqlClient" }
    else { Write-Host '      No mysql command-line client was found next to it, so this script cannot load the Employees data. Show this to your tutor.' }
} elseif ($Ours) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $verOut = & (Join-Path $MysqlHome 'bin\mysqld.exe') --version 2>&1 | Out-String
    $ErrorActionPreference = $prev
    $ver = if ($verOut -match 'Ver \S+') { $Matches[0] } else { 'version unknown' }
    Write-Host "[1/5] MySQL Server already unpacked in $MysqlHome ($ver)."
} else {
    Write-Host '[1/5] MySQL Server 26.10.0'
    # Visual C++ runtime: mysqld.exe will not start without it. Most PCs already
    # have it; when it is missing Microsoft's installer needs one UAC prompt.
    if (Test-VcRedist) {
        Write-Host '      Visual C++ runtime already present.'
    } else {
        Write-Host '      Installing the Microsoft Visual C++ runtime (MySQL Server needs it).'
        Write-Host '      Windows will ask you to allow it (click Yes).'
        $vc = Join-Path $DL 'vc_redist.x64.exe'
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $rc = Invoke-Native { & curl.exe -# -fL -o $vc $VcRedist }
            if ($rc -ne 0) { throw "Download of the Visual C++ runtime failed (curl exit code $rc). Check your internet connection and run this again." }
        } else { Invoke-WebRequest -Uri $VcRedist -OutFile $vc -UseBasicParsing }
        Unblock-File $vc -ErrorAction SilentlyContinue
        try {
            $p = Start-Process -FilePath $vc -ArgumentList '/install', '/quiet', '/norestart' -Verb RunAs -Wait -PassThru
            if ($p.ExitCode -notin 0, 1638, 3010) { Write-Host "      WARNING: the runtime installer returned code $($p.ExitCode). Continuing anyway." }
        } catch {
            Write-Host 'ERROR: the Visual C++ runtime was not installed (the prompt was declined), and MySQL Server cannot run without it.'
            Write-Host "       Run this again and click Yes, or double-click $vc yourself first."
            return
        }
    }
    $zip = Get-Asset $ServerZip '~370MB'
    Write-Host "      Unpacking into $MysqlHome (about 1.5GB, a minute or two)..."
    $unpacked = Join-Path $env:USERPROFILE $ServerDir
    if (Test-Path $unpacked) { Remove-Item $unpacked -Recurse -Force }
    Expand-Zip $zip $env:USERPROFILE
    if (-not (Test-Path (Join-Path $unpacked 'bin\mysqld.exe'))) { throw "The server zip did not unpack as expected ($unpacked\bin\mysqld.exe is missing). Delete $zip and run this again." }
    if (Test-Path (Join-Path $MysqlHome 'data\mysql')) {
        # Program files missing but a database folder exists: keep it, add the programs.
        Copy-Item (Join-Path $unpacked '*') $MysqlHome -Recurse -Force
        Remove-Item $unpacked -Recurse -Force
    } elseif ((Test-Path $MysqlHome) -and (Get-ChildItem $MysqlHome -Force | Select-Object -First 1) -and
              -not (Select-String -Path (Join-Path $MysqlHome 'my.ini') -Pattern 'written by install.ps1' -Quiet -ErrorAction SilentlyContinue) -and
              -not ((Test-Path (Join-Path $MysqlHome 'bin\mysqld.exe')) -and -not (Test-Path (Join-Path $MysqlHome 'my.ini')))) {
        # A C:\Users\<you>\mysql folder that is not ours (someone's own files): never delete it.
        Remove-Item $unpacked -Recurse -Force
        Write-Host "ERROR: a folder called $MysqlHome already exists and was not made by this installer."
        Write-Host '       Move or rename it (for example to mysql-old), then run this again.'
        return
    } else {
        if (Test-Path $MysqlHome) { Remove-Item $MysqlHome -Recurse -Force }
        Rename-Item $unpacked $MysqlHome
    }
    Get-ChildItem (Join-Path $MysqlHome 'bin\*.exe') | Unblock-File -ErrorAction SilentlyContinue
    Write-Host '      Done.'
}

# Server settings. Only this PC can connect (bind-address), data lives in
# C:\Users\<you>\mysql\data, errors go to mysql-error.log in the same folder.
# Forward slashes: in a MySQL option file a backslash is an escape character.
$iniHome = $MysqlHome -replace '\\', '/'
if (-not $Existing -and -not (Test-Path (Join-Path $MysqlHome 'my.ini'))) {
    $ini = @"
# MySQL Server settings for MIS781 (written by install.ps1)
[mysqld]
basedir="$iniHome"
datadir="$iniHome/data"
port=3306
bind-address=127.0.0.1
mysqlx-bind-address=127.0.0.1
log-error="$iniHome/mysql-error.log"
pid-file="$iniHome/mysqld.pid"

[client]
port=3306
"@
    [IO.File]::WriteAllText((Join-Path $MysqlHome 'my.ini'), $ini, [Text.UTF8Encoding]::new($false))
}

# ---- 2. First-time setup: create the data folder ----------------------------
$NewServer = $false
if ($Existing) {
    Write-Host '[2/5] Skipped (using the server already on this PC).'
} elseif (Test-Path (Join-Path $MysqlHome 'data\mysql')) {
    Write-Host "[2/5] Database folder already set up ($MysqlHome\data)."
} else {
    Write-Host '[2/5] Creating the database folder...'
    if (Test-Path (Join-Path $MysqlHome 'data')) { Remove-Item (Join-Path $MysqlHome 'data') -Recurse -Force }
    $p = Start-Process -FilePath (Join-Path $MysqlHome 'bin\mysqld.exe') -ArgumentList "--defaults-file=`"$MysqlHome\my.ini`"", '--initialize-insecure' `
         -WorkingDirectory $MysqlHome -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0 -or -not (Test-Path (Join-Path $MysqlHome 'data\mysql'))) {
        Write-Host "ERROR: could not create the database folder (mysqld exit code $($p.ExitCode))."
        if ($p.ExitCode -eq -1073741515) { Write-Host '       That code means a DLL is missing: the Visual C++ runtime is probably not installed.' }
        Show-ErrorLog
        return
    }
    $NewServer = $true
}

# ---- 3. Start the server now and at every logon (Task Scheduler) ------------
if ($Existing) {
    Write-Host '[3/5] Skipped (the server already on this PC manages itself).'
} else {
    Write-Host '[3/5] Starting MySQL Server (it will also start automatically when you log in).'
    # A logon task that runs as you, no administrator rights involved. The task
    # launches mysqld through a tiny script so no console window appears; where
    # VBScript is not available a hidden PowerShell does the same.
    $launcher = Join-Path $MysqlHome 'start-mysqld.vbs'
    $vbs = "Set sh = CreateObject(`"WScript.Shell`")`r`n" +
           "sh.Run `"`"`"$MysqlHome\bin\mysqld.exe`"`" --defaults-file=`"`"$MysqlHome\my.ini`"`"`", 0, False`r`n"
    [IO.File]::WriteAllText($launcher, $vbs, [Text.Encoding]::Unicode)   # wscript reads UTF-16 with a BOM, so any profile path works
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    if (Test-Path $wscript) {
        $action = New-ScheduledTaskAction -Execute $wscript -Argument "//B //Nologo `"$launcher`"" -WorkingDirectory $MysqlHome
    } else {
        $q = $MysqlHome -replace "'", "''"
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $MysqlHome `
                  -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"Start-Process -FilePath '$q\bin\mysqld.exe' -ArgumentList '--defaults-file=\`"$q\my.ini\`"' -WindowStyle Hidden`""
    }
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $me
    $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    } catch {
        Write-Host "      WARNING: could not create the logon task ($($_.Exception.Message))."
        Write-Host '      The server is started now, but after a restart you will need to run the setup line again (Install) to start it.'
    }
    if (Get-OurServerProcess) {
        Write-Host '      Already running.'
    } elseif (Test-Port3306) {
        Write-Host 'ERROR: something else is using port 3306, so MySQL Server cannot start. Close it and run this again.'
        return
    } else {
        Start-OurServer
        Write-Host -NoNewline '      Waiting for the server'
        $ready = Wait-ForServer $Mysqladmin 60
        Write-Host ''
        if (-not $ready) {
            Write-Host 'ERROR: MySQL Server did not start.'
            Show-ErrorLog
            return
        }
    }
    Write-Host '      Server is running on 127.0.0.1 port 3306.'
    # An earlier run that stopped before the password was set leaves root with no
    # password. Detect that and treat the server as new, so a password gets set now.
    if (-not $NewServer) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $MysqlClient --no-defaults -h 127.0.0.1 -P 3306 -u root --skip-password -N -e 'SELECT 1' 2>$null | Out-Null
        $noPassword = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        if ($noPassword) { Write-Host '      The root account has no password yet (an earlier run was interrupted).'; $NewServer = $true }
        else { Write-Host '      Keeping your existing root password.' }
    }
}

# ---- Root password ----------------------------------------------------------
# New server: choose one (hidden prompt, or MIS781_ROOT_PASSWORD when set) and
# set it through mysql.exe. Existing server: ask for it, for the checks below.
$cnf = Join-Path $env:TEMP ("mis781-" + [guid]::NewGuid().ToString('N') + ".cnf")
$pw = $env:MIS781_ROOT_PASSWORD
try {
if ($NewServer) {
    if (-not $pw) {
        if ($Unattended) { throw 'Set MIS781_ROOT_PASSWORD for an unattended install.' }
        Write-Host ''
        Write-Host "      Choose a password for the MySQL 'root' account. Workbench will have it saved,"
        Write-Host '      but you will need it in the mysql command line and if you ever install again.'
        Write-Host "      >>> WRITE IT DOWN. If you forget it, the setup menu can reset it. <<<"
        while (-not $pw) {
            $a = Read-Secret '      New root password (typing is hidden)'
            $b = Read-Secret '      Type it again'
            if (-not $a) { Write-Host '      It cannot be empty.' } elseif ($a -cne $b) { Write-Host '      They do not match, try again.' } else { $pw = $a }
        }
    }
    # SQL string literal: escape \ and ' so any password works. The statement goes
    # through a private temp file, never the command line.
    $pwSql = ($pw -replace '\\','\\') -replace "'","\'"
    $sqlFile = Join-Path $env:TEMP ("mis781-" + [guid]::NewGuid().ToString('N') + ".sql")
    [IO.File]::WriteAllText($sqlFile, "ALTER USER 'root'@'localhost' IDENTIFIED BY '$pwSql';`nFLUSH PRIVILEGES;`n", [Text.UTF8Encoding]::new($false))
    try {
        $p = Start-Process -FilePath $MysqlClient -ArgumentList '--no-defaults', '-h', '127.0.0.1', '-P', '3306', '-u', 'root', '--skip-password' `
             -RedirectStandardInput $sqlFile -NoNewWindow -Wait -PassThru
    } finally { Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue; Remove-Variable pwSql }
    if ($p.ExitCode -ne 0) { Write-Host "ERROR: could not set the root password (mysql.exe exit code $($p.ExitCode)). Show this to your tutor."; return }
    Write-Host '      Root password set.'
} elseif (-not $pw -and $MysqlClient -and -not $Unattended) {
    $pw = Read-Secret '      Your existing MySQL root password, for the checks below (typing is hidden)'
}
# Option file for the rest of this script and the workers: quoted, \ and " escaped,
# written without a BOM (mysql cannot read a BOM-prefixed option file).
$pwEsc = ($pw -replace '\\','\\') -replace '"','\"'
[IO.File]::WriteAllText($cnf, "[client]`nuser=root`nhost=127.0.0.1`nport=3306`npassword=`"$pwEsc`"`n", [Text.UTF8Encoding]::new($false))
Remove-Variable pw, pwEsc -ErrorAction SilentlyContinue
function Invoke-Sql([string]$Sql) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $MysqlClient "--defaults-file=$cnf" -N -s -e $Sql 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($out | Where-Object { $_ -is [string] } | Out-String).Trim()
    } finally { $ErrorActionPreference = $prev }
}
$ServerOk = $false
if ($MysqlClient -and (Invoke-Sql 'SELECT 1') -eq '1') {
    $ServerOk = $true
} elseif (-not $Existing) {
    Write-Host 'ERROR: that root password did not work. Run the setup line again and type it carefully.'
    Write-Host "       Forgotten it? Run the setup line again and choose 'Reset the MySQL root password'."
    return
} else {
    if ($MysqlClient) { Write-Host '      WARNING: could not log in to that server as root with that password.' }
    Write-Host '      Workbench and the data files are still set up below; load the data later from the setup menu.'
}

# Put mysql on the PATH so 'mysql' works in a new PowerShell window (user-scope, no admin).
if (-not $Existing) {
    $bin = Join-Path $MysqlHome 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($userPath -split ';') -contains $bin)) {
        [Environment]::SetEnvironmentVariable('Path', (@($bin) + @($userPath -split ';' | Where-Object { $_ }) -join ';'), 'User')
        Write-Host "      Added $bin to your PATH (takes effect in new PowerShell windows)."
    }
}

# ---- 4. MySQL Workbench -----------------------------------------------------
# Oracle ships Workbench for Windows as an MSI only, so this is the one step
# Windows asks you to allow. No wizard: the installer runs silently.
$wbExisting = Get-WorkbenchInstall
if ($wbExisting) {
    Write-Host "[4/5] MySQL Workbench already installed ($wbExisting)."
} else {
    Write-Host '[4/5] MySQL Workbench 26.10.0'
    $msi = Get-Asset $WbMsi '~260MB'
    Write-Host '      Installing. Windows will ask you to allow it (click Yes); nothing else to click.'
    try {
        $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Verb RunAs -Wait -PassThru
        if ($p.ExitCode -in 0, 3010) { Write-Host "      Installed ($(Get-WorkbenchInstall))." }
        elseif ($p.ExitCode -eq 1602) { Write-Host '      Skipped because the installer was cancelled. Run the setup line again (Install) to retry.' }
        else { Write-Host "      WARNING: the Workbench installer returned code $($p.ExitCode). Try double-clicking $msi; if that fails too, show this to your tutor." }
    } catch {
        Write-Host '      Skipped: Windows did not allow it. Workbench can be installed later by double-clicking'
        Write-Host "      $msi, or run the setup line again (Install)."
    }
}

# ---- 5. Employees sample database -------------------------------------------
if (Test-Path (Join-Path $Data 'test_db-master\employees.sql')) {
    Write-Host "[5/5] Employees database files already at $Data\test_db-master."
} else {
    Write-Host '[5/5] Employees files'
    $dbZipPath = Get-Asset $DbZip '~35MB'
    Expand-Zip $dbZipPath $Data
    Write-Host "      Files at $Data\test_db-master (employees.sql and the .dump files)."
}

# Loaded means every table is complete, not just employees (salaries loads last).
function Test-EmployeesComplete {
    $r = Invoke-Sql "SELECT (SELECT COUNT(*) FROM employees.employees), (SELECT COUNT(*) FROM employees.salaries), (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='employees')"
    return (($r -replace '\s+', ' ') -eq '300024 2844047 8')
}
$Imported = $false
if (-not $ServerOk) {
    Write-Host '      Employees data not loaded (no working connection to the server, see above).'
} elseif (Test-EmployeesComplete) {
    Write-Host "      The 'employees' database is already loaded (300024 employees)."
    $Imported = $true
} else {
    $ans = $env:MIS781_IMPORT
    if (-not $ans) {
        if ($Unattended) { $ans = 'n' }
        else { $ans = Read-Host '      Load the Employees database into MySQL now? It takes a few minutes. [Y/n]' }
    }
    if ($ans -match '^[Nn]') {
        Write-Host "      Skipped. Load it later from the setup menu ('Load the Employees database')."
    } else {
        $importWasSet = [bool]$env:MIS781_IMPORT
        $env:MIS781_CNF = $cnf; $env:MIS781_MYSQL = $MysqlClient; $env:MIS781_IMPORT = 'y'
        try { & ([scriptblock]::Create((Get-Worker 'import-employees.ps1'))) }
        finally {
            Remove-Item Env:\MIS781_CNF, Env:\MIS781_MYSQL -ErrorAction SilentlyContinue
            if (-not $importWasSet) { Remove-Item Env:\MIS781_IMPORT -ErrorAction SilentlyContinue }
        }
        $Imported = Test-EmployeesComplete
    }
}

# ---- Workbench connection ---------------------------------------------------
# A ready-made "MIS781" connection in Workbench and, for our server, the root
# password saved in Windows Credential Manager, so Workbench connects without asking.
if (Test-Workbench) {
    Write-Host ''
    $env:MIS781_CNF = $cnf
    try {
        & ([scriptblock]::Create((Get-Worker 'workbench-connection.ps1'))) -NoPassword:(-not $StorePassword -or -not $ServerOk)
    } catch { Write-Host "  Could not set up the Workbench connection ($($_.Exception.Message)). Add one by hand in Workbench: host 127.0.0.1, port 3306, user root." }
    finally { Remove-Item Env:\MIS781_CNF -ErrorAction SilentlyContinue }
}

# ---- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host 'Checking what was installed...'
$ok = $true
if ($Existing) {
    if ($ServerOk) { Write-Host "  MySQL Server      OK  (already on this PC: $Existing)" } else { Write-Host "  MySQL Server      already on this PC ($Existing), but root login failed" }
} elseif (Get-OurServerProcess) {
    Write-Host "  MySQL Server      OK  (running, 127.0.0.1:3306, files in $MysqlHome)"
} else {
    Write-Host '  MySQL Server      PROBLEM -> not running'; $ok = $false
}
$wb = Get-WorkbenchInstall
if ($wb) { Write-Host "  MySQL Workbench   OK  ($wb)" } else { Write-Host '  MySQL Workbench   not installed (run the setup line again and allow the installer)'; $ok = $false }
if ($Imported) { Write-Host '  Employees data    OK  (300024 employees, 2844047 salary rows)' } else { Write-Host '  Employees data    not loaded yet' }
if (-not $Existing) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Write-Host "  Starts at logon   OK  (task '$TaskName')" }
    else { Write-Host '  Starts at logon   PROBLEM -> no logon task (see the warning above)' }
}

if ($Unattended) {
    $problems = @()
    if (-not $ok) { $problems += 'server or Workbench missing' }
    if ($env:MIS781_IMPORT -match '^[Yy]' -and -not $Imported) { $problems += 'Employees data incomplete' }
    if ($problems) { throw "Unattended install incomplete: $($problems -join '; ')" }
    Write-Host 'Unattended install complete.'
    return
}
Write-Host ''
if ($ok) {
    Write-Host 'Done. Next:'
    Write-Host "  1. Open MySQL Workbench (Start menu) and click the 'MIS781' connection."
    Write-Host '     If it asks for a password, use your MySQL root password and let it save it.'
    Write-Host "  2. Refresh the SCHEMAS list and you should see 'employees'. Try:"
    Write-Host '       USE employees; SHOW TABLES; SELECT COUNT(*) FROM employees;'
    if (-not $Existing) { Write-Host "  3. Open a NEW PowerShell window if you want to use the 'mysql' command directly." }
} else {
    Write-Host 'SOMETHING WENT WRONG (see above). Show this output to your tutor.'
}
} finally {
    Remove-Item $cnf -Force -ErrorAction SilentlyContinue
}
