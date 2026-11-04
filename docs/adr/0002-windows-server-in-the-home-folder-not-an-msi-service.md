---
status: accepted
date: 2026-11-04
---

# On Windows the server lives in the student's home folder and is started by a logon task, not installed from the MSI as a service

The first Windows installer ran Oracle's MSI and MySQL Configurator, which need administrator approval, two click-through wizards and a password typed into Configurator's window, so the Windows path could never be "one line, nothing to click" the way the macOS path is. We decided that Install on Windows unpacks Oracle's no-install archive (`mysql-26.10.0-winx64.zip`, mirrored unmodified) into `C:\Users\<you>\mysql`, initialises it, sets the root password through `mysql.exe`, and registers a Task Scheduler logon task that runs `mysqld` as the student, bound to 127.0.0.1. No step needs administrator rights, and Reset password and Remove server stop needing them too. Workbench stays an MSI (Oracle ships no other build) and takes one UAC prompt; the Visual C++ 2019 runtime is installed only when the registry check says it is missing, and that is the only other prompt.

## Considered options

- **Keep the MSI and drive it silently** (one UAC prompt, `msiexec /qn`, Configurator from its command line): reuses the unattended code, but every action still needs elevation, Configurator's command line mangles passwords, and the student-facing flow stays different from macOS.
- **Repack a trimmed archive** to cut the 367 MB download: breaks the "unmodified vendor files" statement in `LICENSES.md` and the checksum match with Oracle. The full archive is mirrored as is.
- **Ship the Visual C++ runtime DLLs beside `mysqld.exe`** for zero prompts: permitted by Microsoft for local deployment, but adds Microsoft files to the release under terms written for Visual Studio licensees. Detection plus Microsoft's own installer was chosen instead.

## Consequences

- The server runs only while the student is logged in and does not appear in Settings > Apps; removal is through the setup script, as on macOS.
- Students who installed from the MSI in week 1 have a **Legacy server**: the scan recognises it, Load, Reset and the removals keep working on it (Reset and removal elevated), and Install never migrates it. Remove server then Install is the route to the new layout.
- ADR 0001's Windows line no longer applies to our server; it applies to the legacy server only.
- Whether Workbench 26 on Windows reads the MySQL Shell credential store, whether a loopback-only `mysqld` raises a firewall prompt, and whether SmartScreen objects to the unpacked binaries are undocumented; one run on a standard-user Windows 11 account settles them before week 2.
