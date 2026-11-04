# Spec: Windows Install with nothing to click and no administrator rights

**Status:** implemented 2026-11-05 on branch `feat/windows-home-folder`; Actions run and the real-machine check pending. Target: live on `main` before the week 2 seminar, no interim release.
**Vocabulary:** [GLOSSARY.md](../../GLOSSARY.md) (Our server, Legacy server, Other server, Saved password). **Decision record:** [ADR 0002](../../docs/adr/0002-windows-server-in-the-home-folder-not-an-msi-service.md).

## Why

On macOS one line installs the server, sets the password, gives Workbench a connection with the password saved, and loads the data with nothing to click. On Windows the same line opens two wizards, needs administrator approval, has the student type the password into MySQL Configurator, and the data load waits on that. The Windows path should match macOS.

## What a student sees

The same setup line as today. Install then runs end to end in the PowerShell window: scan, hidden password prompt (typed twice), download, unpack, server started, Workbench installed (one UAC "Yes"), MIS781 connection with the password saved, Employees data loaded, summary. The only other prompt is the Visual C++ runtime installer, and only on a laptop that lacks it.

## Install, new layout

1. Checks as today (64-bit, free space), plus `Unblock-File` on each download before unpacking.
2. Server: `mysql-26.10.0-winx64.zip` (mirrored unmodified, 367 MB) unpacked so that `%USERPROFILE%\mysql\bin\mysqld.exe` exists; `my.ini` with `bind-address=127.0.0.1`, `port=3306`, `datadir=%USERPROFILE%\mysql\data`, log and pid under the same folder; `mysqld --initialize-insecure`; root password set through `mysql.exe` from a temp SQL file (escaping as in the unattended code today); client option file written as on macOS for the import and the Workbench step.
3. Autostart: Task Scheduler task `MIS781 MySQL`, logon trigger for the current user only, interactive logon type, limited run level. A console program started by such a task shows a window, so the task runs `wscript.exe` on `C:\Users\<you>\mysql\start-mysqld.vbs`, which launches `mysqld --defaults-file=...` hidden (a hidden PowerShell `Start-Process` is the fallback where VBScript is absent; Microsoft lists VBScript as deprecated, enabled by default until about 2027). Install starts the server directly, not through the task, so a non-interactive session (the Actions test) works the same way, and waits for port 3306. The README gets a "start it again" line (`Start-ScheduledTask 'MIS781 MySQL'`).
4. `mysql` on the command line: `%USERPROFILE%\mysql\bin` added to the user-scope PATH; removed by Remove server.
5. Visual C++ 2019 runtime: existing registry check; when missing, download Microsoft's `vc_redist.x64.exe` and run it with one UAC prompt (unchanged).
6. Workbench: MSI as today, but `msiexec /i ... /qn /norestart` with `-Verb RunAs`, one UAC prompt, no wizard.
7. Workbench connection: `workbench-connection.ps1` with `MIS781_WB_STORE=1`, so `shell.store_credential` saves the root password in Windows Credential Manager; the Python stays identical to the macOS copy (the Actions diff check enforces it).
8. Data: `import-employees.ps1` in the same run, finding `mysql.exe` in `%USERPROFILE%\mysql\bin` first, then Program Files (legacy), then PATH.
9. Other server on 3306 (not ours, not legacy): skip the server download, ask for that server's root password, still set up Workbench and the data, as macOS does.

## Scan changes (setup.ps1)

- **Our server**: `%USERPROFILE%\mysql\bin\mysqld.exe` present; running when our `mysqld` process listens on 3306; "failing to start" when the task exists but the port stays closed.
- **Legacy server**: `C:\Program Files\MySQL\MySQL Server *\bin\mysqld.exe` present; service state as today ("Configurator never finished" case kept).
- Both present: recommend Remove server, note the port clash.
- Reset: our server resets without elevation (stop our process, start once with `--init-file`, start the task again); legacy server resets elevated as today.
- Remove server: our server = stop and delete the task, stop the process, delete `%USERPROFILE%\mysql`, drop the PATH entry, no elevation; legacy server as today, elevated.
- Remove everything: as today plus the above; Workbench MSI uninstall and the legacy service still elevate.

## Unattended mode

Unchanged variables. The Configurator command-line path in `install.ps1` is retired; interactive and unattended runs share the new layout. `MIS781_ROOT_PASSWORD` skips the password prompt.

## Test (test.yml, Windows job)

- Release assets: add the server zip to `v2026-t3` (MSIs kept for manual download and the legacy layout); `LICENSES.md` lists it.
- Install, Load, Reset, Remove server and reinstall run as a **standard local user** created on the runner (`New-LocalUser`; `.github/run-as-student.ps1` starts `.github/windows-student.ps1` with `Start-Process -Credential -LoadUserProfile`, and that script repoints `USERPROFILE`, `APPDATA`, `LOCALAPPDATA` and `TEMP` at the student's profile, since the started process inherits the administrator's environment). A green run proves no elevation is needed for the server path. Workbench's MSI is installed by the administrator beforehand and removed at the end with Remove everything, which is therefore exercised as the administrator only; its non-admin parts (profile folders, MIS781 folder, downloads, saved password) are covered by the real-machine run. The parse step also checks statically that the server part of `install.ps1` never touches a Windows service.
- Checks mirror macOS: counts, `@@bind_address`, the MIS781 connection, the saved password read back through the Windows credential helper that ships with Workbench.

## Before merging: one real-machine run

On a Windows 11 standard-user account (VM or lab PC), confirm: Workbench 26 opens the MIS781 connection without asking for the password; no firewall "allow access" prompt; no SmartScreen objection to the unpacked binaries. If Workbench ignores the store, the `store_credential` call stays and the README says "type it once and let Workbench save it".

## Out of scope

Migrating a legacy server to the new layout (Remove server then Install is the route); a per-user Workbench build (Oracle ships none); shipping the VC++ DLLs app-locally.
