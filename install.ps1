# MIS781 Business Intelligence and Database - Windows setup (64-bit Windows 10/11)
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.ps1 | iex
#
# Downloads MySQL Server and MySQL Workbench, unpacks the Employees sample
# database, then opens the two installers for you to click through (they need
# administrator approval and a root password you choose, so they cannot be
# fully automated). Once MySQL Configurator is finished it asks for that
# password and loads the Employees data. Safe to re-run: anything already
# installed is skipped.

$ErrorActionPreference = 'Stop'
$Base    = 'https://github.com/thuc-gh/mis781-setup/releases/download/v2026-t3'
$DL      = Join-Path $env:USERPROFILE 'Downloads'
$Data    = Join-Path $env:USERPROFILE 'MIS781'
$ServerMsi = 'mysql-26.10.0-winx64.msi'
$WbMsi     = 'mysql-workbench-26.10.0-winx64.msi'
$DbZip     = 'test_db-master.zip'
$VcRedist  = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'

Write-Host 'MIS781 Windows setup'
Write-Host '===================='

# ---- Checks before we download a gigabyte ------------------------------------
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
if ($freeGB -lt 4) {
    Write-Host "ERROR: not enough free disk space. This needs about 4GB free on ${drive}:, you have ${freeGB}GB."
    return
}
New-Item -ItemType Directory -Force -Path $DL, $Data | Out-Null

# Download helper: curl.exe (built into Windows 10/11) is far faster than
# Invoke-WebRequest and shows progress; fall back to Invoke-WebRequest if absent.
function Get-Asset {
    param([string]$Name, [string]$Size)
    $target = Join-Path $DL $Name
    if ((Test-Path $target) -and (Get-Item $target).Length -gt 1MB) {
        Write-Host "      $Name already in Downloads, re-using it."
        return $target
    }
    Write-Host "      Downloading $Name ($Size)..."
    $part = "$target.part"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -# -fL -o $part "$Base/$Name"
        if ($LASTEXITCODE -ne 0) { throw "Download of $Name failed (curl exit code $LASTEXITCODE). Check your internet connection and run this again." }
    } else {
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri "$Base/$Name" -OutFile $part -UseBasicParsing
        $ProgressPreference = $old
    }
    Move-Item -Force $part $target
    return $target
}

function Test-MySqlServer { Test-Path 'C:\Program Files\MySQL\MySQL Server *\bin\mysqld.exe' }
function Get-WorkbenchInstall {
    # Registered program first (any install location), then the usual folders.
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
           Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' } | Select-Object -First 1
    if ($reg) { return ("$($reg.DisplayName) $($reg.DisplayVersion) $($reg.InstallLocation)").Trim() }
    foreach ($root in "$env:ProgramFiles\MySQL", "$env:ProgramFiles\MySQL Workbench*", "$env:LOCALAPPDATA\Programs") {
        $exe = Get-ChildItem $root -Recurse -Depth 2 -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object Name -match 'workbench' | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}
function Test-Workbench { [bool](Get-WorkbenchInstall) }
function Test-VcRedist {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
    return ($k -and $k.Installed -eq 1 -and $k.Major -ge 14 -and $k.Minor -ge 20)   # 14.20+ = VC++ 2019 or newer
}

# ---- 1. Download everything first -------------------------------------------
Write-Host '[1/4] Downloading'
$serverPath = $null; $wbPath = $null
if (-not (Test-MySqlServer)) { $serverPath = Get-Asset $ServerMsi '~180MB' }
if (-not (Test-Workbench))   { $wbPath     = Get-Asset $WbMsi     '~260MB' }
$dbPath = $null
if (-not (Test-Path (Join-Path $Data 'test_db-master\employees.sql'))) { $dbPath = Get-Asset $DbZip '~35MB' }

# ---- 2. Employees sample database -------------------------------------------
if ($dbPath) {
    Write-Host "[2/4] Unpacking the Employees database files into $Data..."
    Expand-Archive -Path $dbPath -DestinationPath $Data -Force
} else {
    Write-Host "[2/4] Employees database files already at $Data\test_db-master"
}

# ---- 3. Visual C++ runtime (MySQL Server needs it) ---------------------------
if ((Test-MySqlServer) -or (Test-VcRedist)) {
    Write-Host '[3/4] Visual C++ runtime already present.'
} else {
    Write-Host '[3/4] Installing the Microsoft Visual C++ runtime (MySQL Server needs it).'
    Write-Host '      Windows will ask you to allow it (click Yes).'
    $vc = Join-Path $DL 'vc_redist.x64.exe'
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) { & curl.exe -# -fL -o $vc $VcRedist }
    else { Invoke-WebRequest -Uri $VcRedist -OutFile $vc -UseBasicParsing }
    $p = Start-Process -FilePath $vc -ArgumentList '/install', '/quiet', '/norestart' -Verb RunAs -Wait -PassThru
    if ($p.ExitCode -notin 0, 1638, 3010) { Write-Host "      WARNING: the runtime installer returned code $($p.ExitCode). Continuing anyway." }
}

# Runs import-employees.ps1 in this window (local copy for the Actions test,
# otherwise the published one). It asks for the root password itself.
function Invoke-ImportScript {
    $importScript = if ($env:MIS781_LOCAL_SCRIPTS -and (Test-Path (Join-Path $env:MIS781_LOCAL_SCRIPTS 'import-employees.ps1'))) {
        Get-Content (Join-Path $env:MIS781_LOCAL_SCRIPTS 'import-employees.ps1') -Raw
    } else {
        (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.ps1' -UseBasicParsing).Content
    }
    & ([scriptblock]::Create($importScript))
}
function Get-MySqlService {
    Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Where-Object Name -notmatch 'Router' | Select-Object -First 1
}

# ---- 4. MySQL Server and Workbench installers -------------------------------
# Normal use: the installers open and the student clicks through them.
# Unattended use (lab PCs, the Actions test): set MIS781_ROOT_PASSWORD and the
# MSIs run silently and MySQL Configurator is driven from its command line.
$Unattended = [bool]$env:MIS781_ROOT_PASSWORD
Write-Host '[4/4] Installers'
if ($serverPath) {
    if ($Unattended) {
        Write-Host '      Installing MySQL Server silently...'
        $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$serverPath`"", '/qn', '/norestart' -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "MySQL Server MSI failed with exit code $($p.ExitCode)" }
        $cfg = Get-ChildItem 'C:\Program Files\MySQL' -Recurse -Filter 'mysql_configurator.exe' -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
        if (-not $cfg) { throw 'mysql_configurator.exe not found after installing MySQL Server' }
        Write-Host "      Configuring the server with $cfg ..."
        # Configurator's command line mangles quotes, backslashes and # in the password
        # (tested: a " makes it abort with "Illegal characters in path"), so configure
        # with a throwaway random password and set the real one through mysql.exe.
        $tmpPw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        $env:MYSQL_PWD = $tmpPw
        try {
            $p = Start-Process -FilePath $cfg -ArgumentList '--console', '--action=configure', '--server-type=Developer', `
                 '--port=3306', '--configure-as-windows-service=true', '--windows-service-auto-start=true', `
                 '--install-sample-databases=None' -NoNewWindow -Wait -PassThru
        } finally { Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue }
        if ($p.ExitCode -ne 0) { throw "MySQL Configurator failed with exit code $($p.ExitCode)" }
        # Configurator can print an error and still exit 0, so check for the service it should have made.
        $svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Where-Object Name -notmatch 'Router' | Select-Object -First 1
        if (-not $svc) { throw 'MySQL Configurator did not create the MySQL service (see its output above).' }
        if ($svc.Status -ne 'Running') { Start-Service $svc.Name }
        # Now the real root password. SQL string literal: escape \ and ' so any password works.
        $m = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server *\bin\mysql.exe' | Select-Object -First 1 -ExpandProperty FullName
        $pwSql = ($env:MIS781_ROOT_PASSWORD -replace '\\','\\') -replace "'","\'"
        $sqlFile = Join-Path $env:TEMP ("mis781-" + [guid]::NewGuid().ToString('N') + ".sql")
        [IO.File]::WriteAllText($sqlFile, "ALTER USER 'root'@'localhost' IDENTIFIED BY '$pwSql';`nFLUSH PRIVILEGES;`n", [Text.UTF8Encoding]::new($false))
        $env:MYSQL_PWD = $tmpPw
        try {
            $p = Start-Process -FilePath $m -ArgumentList '-h', '127.0.0.1', '-u', 'root' -RedirectStandardInput $sqlFile -NoNewWindow -Wait -PassThru
        } finally { Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue; Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue; Remove-Variable tmpPw, pwSql }
        if ($p.ExitCode -ne 0) { throw "Could not set the root password (mysql.exe exit code $($p.ExitCode))" }
        Write-Host '      Root password set.'
        Write-Host "      Service $($svc.Name) is $((Get-Service $svc.Name).Status)."
    } else {
        Write-Host '      Opening the MySQL Server installer. Click through it with the defaults.'
        Write-Host '      At the end, leave "Run MySQL Configurator" ticked and click Finish.'
        Write-Host '      In MySQL Configurator: keep "Development Computer", port 3306, and set a root password.'
        Write-Host '      >>> WRITE DOWN THE ROOT PASSWORD YOU SET. There is no recovery. <<<'
        Write-Host '      Keep "Configure MySQL Server as a Windows Service" ticked, then Execute, Next, Finish.'
        Write-Host '      Leave this window open: it loads the Employees data once Configurator is finished.'
        Start-Process msiexec.exe -ArgumentList '/i', "`"$serverPath`"" -Wait
        Write-Host '      Server installer closed (MySQL Configurator may still be open: finish it).'
    }
} else {
    Write-Host '      MySQL Server already installed.'
}
if ($wbPath) {
    if ($Unattended) {
        Write-Host '      Installing MySQL Workbench silently...'
        $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$wbPath`"", '/qn', '/norestart' -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "MySQL Workbench MSI failed with exit code $($p.ExitCode)" }
    } else {
        Write-Host '      Opening the MySQL Workbench installer. Click Next, choose Complete, Install, Finish.'
        Start-Process msiexec.exe -ArgumentList '/i', "`"$wbPath`"" -Wait
    }
} else {
    Write-Host '      MySQL Workbench already installed.'
}

# ---- Load the Employees data, like the macOS installer does -----------------
# Unattended runs load it when MIS781_IMPORT is set. Interactive runs wait for
# the student to finish MySQL Configurator (the service appears when they click
# Execute and the root password is applied just after it; Configurator closes
# on Finish), then run the import, which asks for that password.
$Imported = $false
if ($Unattended) {
    if ($env:MIS781_IMPORT) { Invoke-ImportScript; $Imported = $true }
} else {
    $svc = Get-MySqlService
    if ($serverPath -and -not ($svc -and $svc.Status -eq 'Running' -and -not (Get-Process -Name 'mysql_configurator' -ErrorAction SilentlyContinue))) {
        Write-Host ''
        Write-Host '      Waiting for you to finish MySQL Configurator (Execute, Next, Finish).'
        Write-Host -NoNewline '      Press Ctrl+C to stop waiting; the data can be loaded later from the setup menu'
        $deadline = (Get-Date).AddMinutes(20)
        while ((Get-Date) -lt $deadline) {
            $svc = Get-MySqlService
            if ($svc -and $svc.Status -eq 'Running' -and -not (Get-Process -Name 'mysql_configurator' -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Seconds 5
            Write-Host -NoNewline '.'
        }
        Write-Host ''
        Start-Sleep -Seconds 3   # let the server finish starting up
    }
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host ''
        Write-Host '      MySQL Server is running. Loading the Employees database now.'
        Write-Host ''
        Invoke-ImportScript
        $Imported = $true
    }
}

# ---- Workbench connection ---------------------------------------------------
# A ready-made "MIS781" connection in Workbench; Workbench asks for the root
# password the first time and can save it.
if (Test-Workbench) {
    Write-Host ''
    try {
        $wbScript = if ($env:MIS781_LOCAL_SCRIPTS -and (Test-Path (Join-Path $env:MIS781_LOCAL_SCRIPTS 'workbench-connection.ps1'))) {
            Get-Content (Join-Path $env:MIS781_LOCAL_SCRIPTS 'workbench-connection.ps1') -Raw
        } else {
            (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/workbench-connection.ps1' -UseBasicParsing).Content
        }
        & ([scriptblock]::Create($wbScript))
    } catch { Write-Host "  Could not set up the Workbench connection ($($_.Exception.Message)). Add one by hand in Workbench: host 127.0.0.1, port 3306, user root." }
}

# ---- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host 'Checking what was installed...'
if (Test-MySqlServer) { Write-Host '  MySQL Server      OK' } else { Write-Host '  MySQL Server      not found yet (did the installer finish?)' }
if (Test-Workbench)   { Write-Host "  MySQL Workbench   OK ($(Get-WorkbenchInstall))" } else { Write-Host '  MySQL Workbench   not found yet (did the installer finish?)' }
if (Test-Path (Join-Path $Data 'test_db-master\employees.sql')) { Write-Host "  Employees files   OK ($Data\test_db-master)" } else { Write-Host '  Employees files   PROBLEM' }
$svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) { Write-Host "  MySQL service     $($svc.Name) is $($svc.Status)" } else { Write-Host '  MySQL service     not configured yet (finish MySQL Configurator)' }

if ($Unattended) {
    $problems = @()
    if (-not (Test-MySqlServer)) { $problems += 'MySQL Server missing' }
    if (-not (Test-Workbench))   { $problems += 'MySQL Workbench missing' }
    if (-not $svc -or $svc.Status -ne 'Running') { $problems += 'MySQL service not running' }
    if ($env:MIS781_IMPORT) {
        $m = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server *\bin\mysql.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        $env:MYSQL_PWD = $env:MIS781_ROOT_PASSWORD
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $n = (& $m -h 127.0.0.1 -u root -N -e 'SELECT COUNT(*) FROM employees.employees' 2>&1 | Where-Object { $_ -is [string] } | Out-String).Trim() }
        finally { $ErrorActionPreference = $prevEap; Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue }
        if ($n -ne '300024') { $problems += "employees table has '$n' rows, expected 300024" }
    }
    if ($problems) { throw "Unattended install incomplete: $($problems -join '; ')" }
    Write-Host 'Unattended install complete.'
    return
}

Write-Host ''
if ($Imported) {
    Write-Host 'Next: open MySQL Workbench, click the "MIS781" connection, type your root password and let it'
    Write-Host 'save it. Refresh the schemas list and you should see "employees".'
    Write-Host 'If the load above reported a problem, run the setup line again and choose "Load the Employees database".'
} else {
    Write-Host 'You still need to do these yourself:'
    Write-Host '  1. If MySQL Configurator is still open, finish it (root password, Windows service, Execute, Finish).'
    Write-Host '  2. Run the setup line again and choose "Load the Employees database" (takes a few minutes):'
    Write-Host '       irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/setup.ps1 | iex'
    Write-Host '  3. Open MySQL Workbench, click the "MIS781" connection, type your root password and let it'
    Write-Host '     save it. Refresh the schemas list: you should see "employees".'
}
