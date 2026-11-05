# MIS781 - load the Employees sample database into your local MySQL (Windows)
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.ps1 | iex
#
# Runs employees.sql through the MySQL command-line client (NOT Workbench:
# the script uses 'source', which only the command-line client understands),
# then checks the row counts. Safe to re-run; asks before reloading.

$ErrorActionPreference = 'Stop'
$Data = Join-Path $env:USERPROFILE 'MIS781\test_db-master'
$Base = 'https://github.com/thuc-gh/mis781-setup/releases/download/v2026-t3'
$MysqlHome = Join-Path $env:USERPROFILE 'mysql'

Write-Host 'MIS781 Employees database import'
Write-Host '================================'

# ---- 1. Find the mysql command-line client ----------------------------------
# Ours (C:\Users\<you>\mysql) first, then the legacy MSI install, then the PATH.
# install.ps1 hands over the one it used in MIS781_MYSQL.
$mysql = $env:MIS781_MYSQL
if (-not $mysql -and (Test-Path (Join-Path $MysqlHome 'bin\mysql.exe'))) { $mysql = Join-Path $MysqlHome 'bin\mysql.exe' }
if (-not $mysql) {
    $mysql = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server *\bin\mysql.exe' -ErrorAction SilentlyContinue |
             Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $mysql) { $mysql = (Get-Command mysql.exe -ErrorAction SilentlyContinue).Source }
if (-not $mysql) {
    Write-Host 'ERROR: mysql.exe was not found. MySQL Server does not seem to be installed yet.'
    Write-Host '       Run the setup line and choose Install:'
    Write-Host '         irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/setup.ps1 | iex'
    return
}
Write-Host "[1/4] Using $mysql"
Write-Host "      $(((& $mysql --version) | Out-String).Trim() -creplace '^.*? Ver ', 'Ver ')"

# ---- 2. Find the database files ---------------------------------------------
if (-not (Test-Path (Join-Path $Data 'employees.sql'))) {
    Write-Host "[2/4] Employees files not found at $Data, downloading..."
    $zip = Join-Path $env:USERPROFILE 'Downloads\test_db-master.zip'
    New-Item -ItemType Directory -Force -Path (Split-Path $Data), (Split-Path $zip) | Out-Null
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) { & curl.exe -# -fL -o $zip "$Base/test_db-master.zip" }
    else { Invoke-WebRequest -Uri "$Base/test_db-master.zip" -OutFile $zip -UseBasicParsing }
    Expand-Archive -Path $zip -DestinationPath (Split-Path $Data) -Force
}
foreach ($f in 'employees.sql', 'load_employees.dump', 'load_salaries1.dump') {
    if (-not (Test-Path (Join-Path $Data $f))) {
        Write-Host "ERROR: $Data\$f is missing. Re-run the installer to fetch the database files."
        return
    }
}
Write-Host "[2/4] Database files: $Data"

# ---- 3. Connect ---------------------------------------------------------------
# Our server not running? Start it (it runs as you, no admin). A legacy service
# that is stopped needs Windows to allow a start.
$ourMysqld = Join-Path $MysqlHome 'bin\mysqld.exe'
$ourRunning = [bool](Get-Process -Name mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -ieq $ourMysqld })
$portBusy = [bool](Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue)
if ($mysql -ieq (Join-Path $MysqlHome 'bin\mysql.exe') -and -not $ourRunning -and -not $portBusy -and (Test-Path $ourMysqld)) {
    Write-Host -NoNewline '      MySQL Server is not running. Starting it'
    Start-Process -FilePath $ourMysqld -ArgumentList "--defaults-file=`"$MysqlHome\my.ini`"" -WorkingDirectory $MysqlHome -WindowStyle Hidden
    $admin = Join-Path $MysqlHome 'bin\mysqladmin.exe'
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    for ($t = 0; $t -lt 60; $t++) {
        & $admin --no-defaults -h 127.0.0.1 -P 3306 -u root ping 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host -NoNewline '.'; Start-Sleep 1
    }
    $ErrorActionPreference = $prev
    Write-Host ''
} elseif ($mysql -notlike "$MysqlHome\*") {
    $svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Where-Object Name -notmatch 'Router' | Select-Object -First 1
    if ($svc -and $svc.Status -ne 'Running') {
        Write-Host "      The $($svc.Name) service is $($svc.Status). Trying to start it (Windows may ask you to allow this)..."
        try { Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', "Start-Service '$($svc.Name)'" -Verb RunAs -Wait } catch {}
    }
}

# The password goes in a private temp file that mysql reads, never on the
# command line, and the file is deleted when the script ends. install.ps1
# hands over the file it already checked in MIS781_CNF.
$ownCnf = -not ($env:MIS781_CNF -and (Test-Path $env:MIS781_CNF))
$cnf = if ($ownCnf) { Join-Path $env:TEMP ("mis781-" + [guid]::NewGuid().ToString('N') + ".cnf") } else { $env:MIS781_CNF }
Write-Host '[3/4] Connecting to the local MySQL Server as root.'
if ($ownCnf) {
    if ($env:MIS781_ROOT_PASSWORD) {
        $pw = $env:MIS781_ROOT_PASSWORD     # unattended use (lab PCs, the Actions test)
    } else {
        $secure = Read-Host -Prompt '      MySQL root password (typing is hidden)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    # Write ASCII with no BOM: mysql cannot read a UTF-16 or BOM-prefixed option file.
    # Quoted so a '#' in the password is not read as a comment; inside quotes mysql treats
    # backslash as an escape, so escape \ and " first.
    $pwEsc = ($pw -replace '\\','\\') -replace '"','\"'
    [IO.File]::WriteAllText($cnf, "[client]`nuser=root`nhost=127.0.0.1`nport=3306`npassword=`"$pwEsc`"`n", [Text.UTF8Encoding]::new($false))
    Remove-Variable pw, pwEsc -ErrorAction SilentlyContinue; Remove-Variable secure -ErrorAction SilentlyContinue
}

function Invoke-Sql([string]$Sql) {
    $out = & $mysql "--defaults-extra-file=$cnf" -N -s -e $Sql 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($out | Out-String).Trim() }
    return ($out | Out-String).Trim()
}

try {
    try {
        $ver = Invoke-Sql 'SELECT VERSION()'
    } catch {
        $err = "$_"
        Write-Host 'ERROR: could not connect.'
        Write-Host "       $err"
        Write-Host ''
        if ($err -match 'Access denied') {
            Write-Host '       Wrong root password. Run this again and type it carefully.'
            Write-Host '       If you have forgotten it, see "Forgot your MySQL root password" in the README.'
        } elseif ($err -match 'password has expired') {
            Write-Host '       Your root password has expired. Set a new one with:'
            Write-Host "         & '$mysql' -u root -p --connect-expired-password"
            Write-Host "         ALTER USER 'root'@'localhost' IDENTIFIED BY 'YourNewPassword123!';"
        } else {
            Write-Host '       MySQL Server is probably not running. Run the setup line and choose Install,'
            Write-Host '       which starts it (and puts it back if it is broken), then Load the data again.'
        }
        return
    }
    Write-Host "      Connected. Server version $ver"

    # ---- 4. Import ------------------------------------------------------------
    $existing = Invoke-Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='employees' AND table_name='employees'"
    if ($existing -eq '1') {
        $rows = Invoke-Sql 'SELECT COUNT(*) FROM employees.employees'
        Write-Host "[4/4] The 'employees' database already exists ($rows employee rows)."
        if ($rows -eq '300024') {
            $ans = if ($env:MIS781_IMPORT) { 'n' } else { Read-Host '      Reload it from scratch anyway? This erases any changes you made. [y/N]' }
            if ($ans -notmatch '^[Yy]') { Write-Host '      Keeping the existing database. Nothing changed.'; return }
        } else {
            $ans = if ($env:MIS781_IMPORT) { 'y' } else { Read-Host '      It looks incomplete. Reload it from scratch? [Y/n]' }
            if ($ans -match '^[Nn]') { Write-Host '      Keeping the existing database. Nothing changed.'; return }
        }
    }

    Write-Host '[4/4] Loading employees.sql (about 4 million rows; this takes a few minutes)...'
    Push-Location $Data
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # --commands=ON is required: since MySQL 9.5 the client ignores 'source' lines
        # unless it is set, and employees.sql uses 'source' to pull in the .dump files.
        $p = Start-Process -FilePath $mysql -ArgumentList "--defaults-extra-file=`"$cnf`"", '--commands=ON' `
             -RedirectStandardInput (Join-Path $Data 'employees.sql') -NoNewWindow -Wait -PassThru
        $sw.Stop()
        if ($p.ExitCode -ne 0) { Write-Host "ERROR: the import stopped with exit code $($p.ExitCode). Show this output to your tutor."; return }
        Write-Host "      Loaded in $([int]$sw.Elapsed.TotalSeconds) seconds."

        Write-Host ''
        Write-Host 'Checking the result...'
        $ok = $true
        $count = Invoke-Sql 'SELECT COUNT(*) FROM employees.employees'
        if ($count -eq '300024') { Write-Host '  employees table   OK (300024 rows)' }
        else { Write-Host "  employees table   PROBLEM -> $count rows (expected 300024)"; $ok = $false }
        $tables = (Invoke-Sql "SHOW FULL TABLES IN employees WHERE Table_type='BASE TABLE'") -split "`r?`n" | ForEach-Object { ($_ -split "`t")[0] }
        Write-Host "  tables            $($tables -join ' ')"
        if (Test-Path 'test_employees_sha2.sql') {
            Write-Host '  checksum test     (compares every table against the official checksums)'
            $log = Join-Path $env:TEMP 'mis781-sha2.txt'
            Start-Process -FilePath $mysql -ArgumentList "--defaults-extra-file=`"$cnf`"", '--commands=ON', '-t' `
                -RedirectStandardInput (Join-Path $Data 'test_employees_sha2.sql') -RedirectStandardOutput $log -NoNewWindow -Wait | Out-Null
            Get-Content $log | Where-Object { $_ -match '^\| [a-z_]+ +\| (OK|not ok) ' } | ForEach-Object { Write-Host "                    $_" }
            Remove-Item $log -ErrorAction SilentlyContinue
        }
        Write-Host ''
        if ($ok) {
            Write-Host 'Done. Open MySQL Workbench, connect as root, refresh the schemas list and run:'
            Write-Host '  USE employees; SHOW TABLES; SELECT COUNT(*) FROM employees;'
        } else {
            Write-Host 'SOMETHING WENT WRONG (see above). Show this output to your tutor.'
        }
    } finally { Pop-Location }
} finally {
    if ($ownCnf) { Remove-Item $cnf -Force -ErrorAction SilentlyContinue }
}
