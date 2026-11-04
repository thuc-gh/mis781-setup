# Actions test helper (Windows): the student side. Runs one named step of the
# test as a standard local user, the way a student with no administrator
# rights would, and checks the result. Started by run-as-student.ps1 from the
# workflow; never run by students.
#
# The process gets the student's own environment, so the runner's values
# (workspace, test passwords) arrive in the JSON file named by -Config; the
# profile folders are set from the profile itself in case any were inherited.

param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)][string]$Config)

$ErrorActionPreference = 'Stop'
$cfg = Get-Content $Config -Raw | ConvertFrom-Json
$env:GITHUB_WORKSPACE = $cfg.Workspace
$env:TEST_PASSWORD    = $cfg.TestPassword
$env:SECOND_PASSWORD  = $cfg.SecondPassword
$env:USERPROFILE  = [Environment]::GetFolderPath('UserProfile')
$env:APPDATA      = [Environment]::GetFolderPath('ApplicationData')
$env:LOCALAPPDATA = [Environment]::GetFolderPath('LocalApplicationData')
$env:USERNAME     = [Environment]::UserName
$env:HOMEDRIVE    = Split-Path $env:USERPROFILE -Qualifier
$env:HOMEPATH     = Split-Path $env:USERPROFILE -NoQualifier
$env:TEMP = $env:TMP = Join-Path $env:LOCALAPPDATA 'Temp'
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$env:MIS781_LOCAL_SCRIPTS = $env:GITHUB_WORKSPACE
foreach ($v in 'MIS781_ACTION', 'MIS781_ROOT_PASSWORD', 'MIS781_IMPORT', 'MIS781_NEW_PASSWORD', 'MIS781_CONFIRM', 'MIS781_CNF') {
    Remove-Item "Env:\$v" -ErrorAction SilentlyContinue
}
$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "== student step: $Step  (user $env:USERNAME, admin: $isAdmin, profile $env:USERPROFILE, workspace $env:GITHUB_WORKSPACE)"
if ($isAdmin) { throw 'this step must run as a standard user, not an administrator' }

$MysqlHome = Join-Path $env:USERPROFILE 'mysql'
$M = Join-Path $MysqlHome 'bin\mysql.exe'
$TaskName = 'MIS781 MySQL'

function Invoke-Setup([hashtable]$Vars) {
    foreach ($k in $Vars.Keys) { Set-Item "Env:\$k" $Vars[$k] }
    try {
        $out = Get-Content (Join-Path $env:GITHUB_WORKSPACE 'setup.ps1') -Raw | Invoke-Expression *>&1 | Out-String
        Write-Host $out
        return $out
    } finally { foreach ($k in $Vars.Keys) { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue } }
}
function Write-Cnf([string]$Password, [string]$Path) {
    $esc = ($Password -replace '\\','\\') -replace '"','\"'
    [IO.File]::WriteAllText($Path, "[client]`nuser=root`nhost=127.0.0.1`nport=3306`npassword=`"$esc`"`n", [Text.UTF8Encoding]::new($false))
}
function Query([string]$Cnf, [string]$Sql) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = (& $M "--defaults-file=$Cnf" -N -e $Sql 2>$null | Out-String).Trim(); if ($LASTEXITCODE -ne 0) { return $null }; return $out }
    finally { $ErrorActionPreference = $prev }
}
function Assert([bool]$Cond, [string]$What) { if (-not $Cond) { throw "FAILED: $What" }; Write-Host "  ok: $What" }
function Get-WorkbenchShell {
    foreach ($d in (Get-Item "$env:ProgramFiles\MySQL\MySQL Workbench*", "$env:ProgramFiles\MySQL Workbench*" -ErrorAction SilentlyContinue)) {
        $sh = Get-ChildItem $d.FullName -Recurse -Depth 6 -Filter mysqlsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sh) { return $sh.FullName }
    }
    throw 'the mysqlsh.exe that Workbench ships with was not found'
}
function Test-WorkbenchConnection {
    $sh = Get-WorkbenchShell
    $env:MYSQLSH_USER_CONFIG_HOME = Join-Path $env:APPDATA 'MySQL Workbench\mysqlsh'
    $py = Join-Path $env:TEMP 'wbcheck.py'
    @'
import json
from gui_plugin.core.Db import BackendDatabase
from gui_plugin.users import backend as users
with BackendDatabase() as db:
    user_id = users.get_user_id(db, users.LOCAL_USERNAME)
    profile = users.get_default_profile(db, user_id)["id"]
    rows = db.select("""SELECT dc.caption, dc.options FROM profile_has_db_connection p
        JOIN db_connection dc ON dc.id = p.db_connection_id WHERE p.profile_id = ?""", (profile,))
found = [r for r in rows if r["caption"] == "MIS781"]
assert len(found) == 1, rows
o = found[0]["options"]; o = json.loads(o) if isinstance(o, str) else o
assert (o["host"], int(o["port"]), o["user"]) == ("127.0.0.1", 3306, "root"), o
print("MIS781 connection:", o)
'@ | Set-Content $py -Encoding Ascii
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $sh --py -f $py 2>&1 | ForEach-Object { Write-Host "  $_" }
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Assert ($rc -eq 0) 'Workbench has the MIS781 connection (127.0.0.1, 3306, root)'
}
function Get-SavedWorkbenchPassword {
    # Read back through the same credential helper Workbench's shell uses.
    $sh = Get-WorkbenchShell
    $helper = Get-ChildItem (Split-Path $sh) -Filter 'mysql-secret-store-windows*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $helper) { throw "no Windows credential helper next to $sh" }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $json = '{"ServerURL":"root@127.0.0.1:3306","SecretType":"password"}' | & $helper.FullName get 2>$null | Out-String
        if ($LASTEXITCODE -ne 0 -or -not $json.Trim()) { return $null }
        return ($json | ConvertFrom-Json).Secret
    } finally { $ErrorActionPreference = $prev }
}

$cnf1 = Join-Path $env:TEMP 't1.cnf'; Write-Cnf $env:TEST_PASSWORD $cnf1
$cnf2 = Join-Path $env:TEMP 't2.cnf'; Write-Cnf $env:SECOND_PASSWORD $cnf2

switch ($Step) {
    'scan-clean' {
        $out = Invoke-Setup @{ MIS781_ACTION = 'scan' }
        Assert ($out -match 'MySQL Server      none') 'scan: no server from this unit'
        Assert ($out -match 'Recommended: Install') 'scan: recommends Install'
    }
    'install' {
        Invoke-Setup @{ MIS781_ACTION = 'install'; MIS781_ROOT_PASSWORD = $env:TEST_PASSWORD; MIS781_IMPORT = 'y' } | Out-Null
    }
    'check-install' {
        & $M --version
        Assert ((Query $cnf1 'SELECT COUNT(*) FROM employees.employees') -eq '300024') 'employees count'
        Assert ((Query $cnf1 'SELECT COUNT(*) FROM employees.salaries') -eq '2844047') 'salaries count'
        Assert ((Query $cnf1 "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='employees'") -eq '8') 'eight objects'
        Assert ((Query $cnf1 'SELECT @@bind_address') -eq '127.0.0.1') 'bound to 127.0.0.1 only'
        Assert ((Query $cnf1 'SELECT @@mysqlx_bind_address') -eq '127.0.0.1') 'X plugin bound to 127.0.0.1 only'
        $proc = Get-Process mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq (Join-Path $MysqlHome 'bin\mysqld.exe') }
        Assert ([bool]$proc) 'our mysqld is the running one'
        Assert ([bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) "logon task '$TaskName' registered"
        $t = Get-ScheduledTask -TaskName $TaskName
        Assert ($t.Principal.LogonType -eq 'Interactive' -and $t.Principal.RunLevel -eq 'Limited') 'task runs as the user, limited'
        Assert ((([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';') -contains (Join-Path $MysqlHome 'bin')) 'mysql\bin on the user PATH'
        Assert (Test-Path (Join-Path $MysqlHome 'my.ini')) 'my.ini written'
        Assert (-not (Get-ChildItem (Join-Path $MysqlHome 'bin\mysqld.exe') -Stream Zone.Identifier -ErrorAction SilentlyContinue)) 'mysqld.exe carries no mark of the web'
    }
    'check-workbench' {
        Test-WorkbenchConnection
        $saved = Get-SavedWorkbenchPassword
        Assert ($saved -ceq $env:TEST_PASSWORD) 'saved Workbench password reads back'
    }
    'scan-complete' {
        $out = Invoke-Setup @{ MIS781_ACTION = 'scan' }
        Assert ($out -match 'MySQL Server      ours, running') 'scan: ours, running'
        Assert ($out -match 'Recommended: Load') 'scan: recommends Load'
    }
    'reset-dry' {
        $out = Invoke-Setup @{ MIS781_ACTION = 'reset'; MIS781_NEW_PASSWORD = $env:SECOND_PASSWORD }
        Assert ($out -match 'Nothing was changed') 'reset without confirmation stops'
        Assert ((Query $cnf1 'SELECT 1') -eq '1') 'old password still works'
    }
    'reset' {
        Invoke-Setup @{ MIS781_ACTION = 'reset'; MIS781_NEW_PASSWORD = $env:SECOND_PASSWORD; MIS781_CONFIRM = 'yes' } | Out-Null
        Assert ($null -eq (Query $cnf1 'SELECT 1')) 'old password no longer works'
        Assert ((Query $cnf2 'SELECT COUNT(*) FROM employees.employees') -eq '300024') 'data survived the reset'
        $proc = Get-Process mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq (Join-Path $MysqlHome 'bin\mysqld.exe') }
        Assert ([bool]$proc) 'our mysqld running again'
        Assert ((Get-SavedWorkbenchPassword) -ceq $env:SECOND_PASSWORD) 'reset updated the saved Workbench password'
    }
    'rerun' {
        $out = Invoke-Setup @{ MIS781_ACTION = 'install'; MIS781_ROOT_PASSWORD = $env:SECOND_PASSWORD; MIS781_IMPORT = 'y' }
        Assert ($out -match 'already loaded') 're-run finds the data already loaded'
        Assert ($out -match 'already has a connection') 're-run keeps the MIS781 connection'
    }
    'import-reload' {
        Assert ((Query $cnf2 'DROP DATABASE employees') -ne $null) 'dropped employees'
        $env:MIS781_CNF = $cnf2; $env:MIS781_IMPORT = 'y'
        try { Get-Content (Join-Path $env:GITHUB_WORKSPACE 'import-employees.ps1') -Raw | Invoke-Expression }
        finally { Remove-Item Env:\MIS781_CNF, Env:\MIS781_IMPORT -ErrorAction SilentlyContinue }
        Assert ((Query $cnf2 'SELECT COUNT(*) FROM employees.salaries') -eq '2844047') 'standalone import reloaded cleanly'
    }
    'remove-server-dry' {
        $out = Invoke-Setup @{ MIS781_ACTION = 'remove-server' }
        Assert ($out -match 'MySQL Server \(ours\)') 'removal lists our server'
        Assert ($out -match 'Nothing was changed') 'removal without confirmation stops'
        Assert (Test-Path $MysqlHome) 'folder still there'
    }
    'remove-server' {
        Invoke-Setup @{ MIS781_ACTION = 'remove-server'; MIS781_CONFIRM = 'yes' } | Out-Null
        Assert (-not (Test-Path $MysqlHome)) 'mysql folder gone'
        Assert (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) 'logon task gone'
        Assert (-not (Get-Process mysqld -ErrorAction SilentlyContinue)) 'no mysqld running'
        Assert (-not ((([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';') -contains (Join-Path $MysqlHome 'bin'))) 'PATH entry gone'
        Assert (Test-Path (Join-Path $env:USERPROFILE 'MIS781\test_db-master\employees.sql')) 'Employees files kept'
        Test-WorkbenchConnection
        Assert ($null -ne (Get-SavedWorkbenchPassword)) 'saved Workbench password kept by Remove server'
    }
    'reinstall' {
        $out = Invoke-Setup @{ MIS781_ACTION = 'install'; MIS781_ROOT_PASSWORD = $env:TEST_PASSWORD; MIS781_IMPORT = 'n' }
        Assert ($out -match 'Workbench already installed') 'Workbench reused'
        Assert ($out -match 'already has a connection') 'MIS781 connection kept'
        Assert ((Query $cnf1 'SELECT 1') -eq '1') 'fresh server accepts the password'
        Assert ((Get-SavedWorkbenchPassword) -ceq $env:TEST_PASSWORD) 'saved Workbench password updated on reinstall'
    }
    'remove-server-final' {
        Invoke-Setup @{ MIS781_ACTION = 'remove-server'; MIS781_CONFIRM = 'yes' } | Out-Null
        Assert (-not (Test-Path $MysqlHome)) 'mysql folder gone'
        Assert (-not (Get-Process mysqld -ErrorAction SilentlyContinue)) 'no mysqld running'
    }
    'diagnostics' {
        Get-ChildItem $env:USERPROFILE -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        Get-Content (Join-Path $MysqlHome 'mysql-error.log') -Tail 40 -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Format-List TaskName, State
        Get-Process mysqld -ErrorAction SilentlyContinue | Format-Table Id, Path
        Get-NetTCPConnection -LocalPort 3306 -ErrorAction SilentlyContinue | Format-Table
    }
    default { throw "unknown step $Step" }
}
Write-Host "== student step $Step passed"
