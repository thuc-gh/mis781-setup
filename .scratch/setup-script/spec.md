# Spec: one setup script per platform that scans, recommends, then acts

**Status:** implemented and verified 2026-11-04 (Actions run 41826816809 green on macOS and Windows)
**Vocabulary:** [GLOSSARY.md](../../GLOSSARY.md). **Decision record:** [ADR 0001](../../docs/adr/0001-forgotten-root-password-is-reset-not-reinstall.md).

## Why

Students currently choose between three one-liners per platform and must diagnose their own machine first. A forgotten root password is documented as unrecoverable, which costs coursework databases. Removals already ask before deleting; the rest of the scripts have no single place that explains what is on the machine.

## What a student sees

One line per platform, the only ones in the README's opening:

- macOS: `zsh -c "$(curl -fsSL .../setup.sh)"`
- Windows: `irm .../setup.ps1 | iex`

The setup script:

1. Runs the **scan** (read-only, no password) and prints a short table: MySQL Server (none / ours / other, named, running or not on 3306), Workbench (version, location), Employees files (present or not), Windows service state.
2. Prints the **recommendation** and a numbered menu with the recommended action as the Enter default.
3. Runs the chosen action by calling the existing worker scripts (`install`, `import-employees`, `uninstall-mysql`), fetched from `RAW` or from `MIS781_LOCAL_SCRIPTS` as today.

Menu text:

```
  1. Install everything that is missing
  2. Load the Employees database
  3. Reset the MySQL root password
  4. Remove MySQL Server (then reinstall)
  5. Remove everything
  6. Quit
Choose [N]:
```

Items that do not apply are not shown (Reset when no "our server"; Install on an Intel Mac).

## Recommendation table

| Scan finds | Recommendation |
|---|---|
| No server, no Workbench | Install |
| Our server present, Workbench or files missing | Install |
| Our server present, everything present | Load data |
| Our server present, not running and will not start | Remove server |
| Other server present, ours absent | Install (uses the other server) |
| Other server and our server both present (port clash) | Remove server, note that the other wins |
| Intel Mac, a server found | Load data |
| Intel Mac, no server | Print the Intel instructions, no Install offered |

Reset password is never recommended; it is a standing menu item whenever our server is present.

## Actions

**Install**: existing `install.sh` / `install.ps1` behaviour (adds what is missing, re-run changes nothing).

**Load data**: existing `import-employees.*`. Confirmation (`y`) when an `employees` database already exists.

**Reset password** (our server only): ask for the new password twice (hidden); stop the server; start it once with an init file that runs `ALTER USER 'root'@'localhost' IDENTIFIED BY ...`; stop it; start normally (launchd kickstart on macOS, Windows service); log in with the new password and count `employees.employees` if present; report. On failure say so and recommend Remove server. Confirmation (`y`) stating that the old password stops working and the server restarts. Other servers: menu item hidden, README links to Oracle's reset page.

**Remove server**: existing uninstallers, extended so the pre-removal list marks each server "ours" or "other". Leaves Workbench, Workbench profiles and Employees files. Confirmation: type `yes`.

**Remove everything**: Remove server plus Workbench (app bundle or MSI product), Workbench profile folder (`~/Library/Application Support/MySQL/Workbench`, `%APPDATA%\MySQL\Workbench`), `~/MIS781` or `%USERPROFILE%\MIS781`, and the downloaded installers in Downloads. Confirmation: type `yes`.

## Confirmation rule

- Destructive actions: Remove server, Remove everything, Load data over existing data, Reset password.
- The list shown is produced by the action itself immediately before it acts, with concrete paths, service names, app bundle and profile folder, and the line "ALL MySQL databases on this computer" for removals.
- Removals require the literal word `yes`; reload and reset accept `y` with decline as default. Anything else prints "Nothing was changed." and exits 0.
- One list, one answer; no per-item prompts.

## Windows elevation

Install runs unelevated (MSIs raise their own UAC). Reset, Remove server and Remove everything need admin: the setup script writes itself to `%TEMP%`, relaunches `powershell -File <copy> -Action <x>` with `-Verb RunAs`, and the elevated copy performs the scan again, the confirmation and the action. The README instruction to open Terminal (Admin) goes.

## Unattended mode

| Variable | Values | Notes |
|---|---|---|
| `MIS781_ACTION` | `install`, `load`, `reset`, `remove-server`, `remove-all` | anything else prints the menu |
| `MIS781_ROOT_PASSWORD` | current password | as today |
| `MIS781_NEW_PASSWORD` | new password | reset only |
| `MIS781_IMPORT` | `y` | as today |
| `MIS781_CONFIRM` | `yes` | required for any destructive action unattended; without it the list is printed and the script stops |

## README changes

- Open with the two setup lines and a paragraph on what the script asks for.
- "Check it worked" unchanged.
- Troubleshooting: forgot password becomes "run the setup line again and choose Reset password"; Terminal (Admin) instruction removed; sudo, quarantine, Intel and `source` entries stay.
- New short section "Running one step directly" with the three worker one-liners per platform, for tutors.
- Uninstalling section describes the two removal levels and the confirmation.

## Actions test

Per platform, unattended, in order: scan output checked for "none" lines; Install; checks as today; Reset with a second awkward password, then prove the new password logs in and the 300024 count survives; Remove server with `MIS781_CONFIRM=yes`, check server gone and Workbench present; Install again (fast path, Workbench reused); Remove everything, check Workbench, profiles and `MIS781` folder gone. Also check that a removal without `MIS781_CONFIRM` changes nothing.

## Out of scope

Intel Mac install automation; MAMP/XAMPP/Docker removal; Windows on ARM special-casing beyond the current note.

## Files to change

- New: `setup.sh`, `setup.ps1`
- Changed: `uninstall-mysql.sh`, `uninstall-mysql.ps1` (ours/other marking, remove-everything level, `MIS781_CONFIRM`), `README.md`, `.github/workflows/test.yml`
- Unchanged unless a defect appears: `install.sh`, `install.ps1`, `import-employees.sh`, `import-employees.ps1`
