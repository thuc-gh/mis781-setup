# MIS781 Business Intelligence and Database - Windows setup (64-bit Windows 10/11)
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.ps1 | iex
#
# Downloads MySQL Server and MySQL Workbench, unpacks the Employees sample
# database, then opens the two installers for you to click through (they need
# administrator approval and a root password you choose, so they cannot be
# fully automated). Safe to re-run: anything already installed is skipped.

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
function Test-Workbench   { (Test-Path 'C:\Program Files\MySQL\MySQL Workbench*\MySQL Workbench.exe') -or (Test-Path 'C:\Program Files\MySQL\MySQL Workbench*\MySQLWorkbench.exe') }
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

# ---- 4. MySQL Server and Workbench installers -------------------------------
Write-Host '[4/4] Installers'
if ($serverPath) {
    Write-Host '      Opening the MySQL Server installer. Click through it with the defaults.'
    Write-Host '      At the end, leave "Run MySQL Configurator" ticked and click Finish.'
    Write-Host '      In MySQL Configurator: keep "Development Computer", port 3306, and set a root password.'
    Write-Host '      >>> WRITE DOWN THE ROOT PASSWORD YOU SET. There is no recovery. <<<'
    Write-Host '      Keep "Configure MySQL Server as a Windows Service" ticked, then Execute.'
    Start-Process msiexec.exe -ArgumentList '/i', "`"$serverPath`"" -Wait
    Write-Host '      Server installer closed (MySQL Configurator may still be open: finish it).'
} else {
    Write-Host '      MySQL Server already installed.'
}
if ($wbPath) {
    Write-Host '      Opening the MySQL Workbench installer. Click Next, choose Complete, Install, Finish.'
    Start-Process msiexec.exe -ArgumentList '/i', "`"$wbPath`"" -Wait
} else {
    Write-Host '      MySQL Workbench already installed.'
}

# ---- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host 'Checking what was installed...'
if (Test-MySqlServer) { Write-Host '  MySQL Server      OK' } else { Write-Host '  MySQL Server      not found yet (did the installer finish?)' }
if (Test-Workbench)   { Write-Host '  MySQL Workbench   OK' } else { Write-Host '  MySQL Workbench   not found yet (did the installer finish?)' }
if (Test-Path (Join-Path $Data 'test_db-master\employees.sql')) { Write-Host "  Employees files   OK ($Data\test_db-master)" } else { Write-Host '  Employees files   PROBLEM' }
$svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) { Write-Host "  MySQL service     $($svc.Name) is $($svc.Status)" } else { Write-Host '  MySQL service     not configured yet (finish MySQL Configurator)' }

Write-Host ''
Write-Host 'You still need to do these yourself:'
Write-Host '  1. If MySQL Configurator is still open, finish it (root password, Windows service, Execute).'
Write-Host '  2. Load the Employees database (takes a few minutes):'
Write-Host '       irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.ps1 | iex'
Write-Host '  3. Open MySQL Workbench, connect to the local server as root, refresh the schemas list:'
Write-Host '     you should see "employees".'
