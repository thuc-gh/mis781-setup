# MIS781 Business Intelligence and Database - Workbench connection (Windows)
#
#   irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/workbench-connection.ps1 | iex
#
# Gives MySQL Workbench a ready-made connection called "MIS781" (host 127.0.0.1,
# port 3306, user root) and saves the root password in Windows Credential
# Manager, so Workbench connects without asking. install.ps1 runs this at the
# end of Install and setup.ps1 at the end of Reset password. If Workbench
# already has a connection to that server it is kept as it is; a student's
# other connections are never touched.
#
# The password comes from the option file named by MIS781_CNF (written by the
# calling script) or from MIS781_ROOT_PASSWORD. With -NoPassword, or with
# neither set, only the connection is added. Workbench 26 keeps its connections
# through the MySQL Shell it ships with, so that shell does the work here;
# nothing is written by hand. It never fails the calling script; when it
# cannot help it says what to do by hand.

param([switch]$NoPassword)

$ErrorActionPreference = 'Stop'
Write-Host 'Workbench connection'

function Find-WorkbenchShell {
    # The Workbench folder (registered location first, then the usual places),
    # then the shell it ships with somewhere under it.
    $dirs = @()
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
           Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'MySQL Workbench*' -and $_.InstallLocation } | Select-Object -First 1
    if ($reg) { $dirs += $reg.InstallLocation }
    $dirs += @(Get-Item "$env:ProgramFiles\MySQL\MySQL Workbench*", "$env:ProgramFiles\MySQL Workbench*", "$env:LOCALAPPDATA\Programs\MySQL*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    foreach ($d in $dirs) {
        $exe = Get-ChildItem $d -Recurse -Depth 6 -Filter 'mysqlsh.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

$mysqlsh = Find-WorkbenchShell
if (-not $mysqlsh) {
    Write-Host '  MySQL Workbench 26 was not found, so no connection was added. In Workbench, add one'
    Write-Host '  by hand with host 127.0.0.1, port 3306, user root.'
    return
}
# Workbench holds its connection database while it runs, so the connection is
# only added when it is closed.
$running = [bool](Get-Process | Where-Object { $_.ProcessName -like '*Workbench*' })

$shellHome = Join-Path $env:APPDATA 'MySQL Workbench\mysqlsh'
New-Item -ItemType Directory -Force -Path $shellHome | Out-Null
$scriptFile = Join-Path $env:TEMP ("mis781-wb-" + [guid]::NewGuid().ToString('N') + ".py")
# Keep this script the same as the one in workbench-connection.sh.
$python = @'
import json, os
from gui_plugin.core.Db import BackendDatabase
from gui_plugin.users import backend as users

HOST, PORT, USER = "127.0.0.1", 3306, "root"
BY_HAND = "You can add one by hand in Workbench: host 127.0.0.1, port 3306, user root."
store = os.environ.get("MIS781_WB_STORE") == "1"
running = os.environ.get("MIS781_WB_RUNNING") == "1"


def password_from_cnf(path):
    # The option file has password="..." with \ and " escaped by the writer.
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("password="):
                continue
            value = line[len("password="):]
            if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
                raw, out, i = value[1:-1], [], 0
                while i < len(raw):
                    if raw[i] == "\\" and i + 1 < len(raw):
                        i += 1
                    out.append(raw[i])
                    i += 1
                return "".join(out)
            return value
    return None


def is_this_server(options):
    try:
        port = int(options.get("port") or 3306)
    except (TypeError, ValueError):
        return False
    host = str(options.get("host", "")).lower()
    return host in ("127.0.0.1", "localhost") and port == 3306 and not options.get("socket")


try:
    with BackendDatabase() as db:
        users.create_local_user(db)
        user_id = users.get_user_id(db, users.LOCAL_USERNAME)
        profile_id = users.get_default_profile(db, user_id)["id"]
        rows = db.select(
            """SELECT dc.caption, dc.db_type, dc.options
            FROM profile_has_db_connection p
            JOIN db_connection dc ON dc.id = p.db_connection_id
            WHERE p.profile_id = ?""",
            (profile_id,),
        )
    existing = None
    for row in rows:
        options = row.get("options") or {}
        if isinstance(options, str):
            try:
                options = json.loads(options)
            except ValueError:
                options = {}
        if str(row.get("db_type", "")).lower() == "mysql" and is_this_server(options):
            existing = (row.get("caption") or "?", options)
            break

    if existing:
        caption, options = existing
        print(f"  Workbench already has a connection to this server ('{caption}'); it was kept as it is.")
    elif running:
        print("  MySQL Workbench is open, so no connection was added. Quit Workbench and run the")
        print(f"  setup line again (Install) to get the ready-made 'MIS781' connection. {BY_HAND}")
        raise SystemExit(0)
    else:
        gui.db_connections.add_db_connection(profile_id, {
            "db_type": "MySQL",
            "caption": "MIS781",
            "description": "MySQL Server for MIS781 on this computer",
            "options": {"scheme": "mysql", "host": HOST, "port": PORT, "user": USER},
        })
        options = {"host": HOST, "port": PORT, "user": USER}
        print("  Added a connection called 'MIS781' (host 127.0.0.1, port 3306, user root) to MySQL Workbench.")

    if not store:
        print("  Workbench asks for the root password the first time you connect and can save it.")
    else:
        password = None
        cnf = os.environ.get("MIS781_CNF")
        if cnf and os.path.isfile(cnf):
            password = password_from_cnf(cnf)
        if not password:
            password = os.environ.get("MIS781_ROOT_PASSWORD")
        user = options.get("user") or ""
        if not password:
            print("  No password was given, so Workbench asks for it the first time and can save it.")
        elif user != USER:
            print(f"  That connection logs in as '{user}', not root, so no password was saved for it.")
        else:
            url = f"{USER}@{options.get('host')}:{int(options.get('port') or PORT)}"
            shell.store_credential(url, password)
            print("  Saved the root password in your keychain, so Workbench connects without asking.")
except Exception as exc:  # never fail the install over a convenience
    print(f"  Could not set up the Workbench connection ({exc}). {BY_HAND}")
'@
[IO.File]::WriteAllText($scriptFile, $python, [Text.UTF8Encoding]::new($false))
$env:MYSQLSH_USER_CONFIG_HOME = $shellHome
$env:MIS781_WB_STORE = if ($NoPassword) { '0' } else { '1' }
$env:MIS781_WB_RUNNING = if ($running) { '1' } else { '0' }
try {
    # A warning on stderr must not count as a failure (Windows PowerShell throws on it under Stop).
    $ErrorActionPreference = 'Continue'
    & $mysqlsh --py -f $scriptFile 2>&1 | ForEach-Object { Write-Host "$_" }
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { Write-Host '  Could not set up the Workbench connection. Add one by hand in Workbench: host 127.0.0.1, port 3306, user root.' }
} catch {
    Write-Host "  Could not set up the Workbench connection ($($_.Exception.Message)). Add one by hand in Workbench: host 127.0.0.1, port 3306, user root."
} finally {
    Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\MYSQLSH_USER_CONFIG_HOME, Env:\MIS781_WB_STORE, Env:\MIS781_WB_RUNNING -ErrorAction SilentlyContinue
}
