# Spec: a ready-made Workbench connection from the setup script

**Status:** implemented 2026-11-04 (Actions run to confirm)
**Vocabulary:** [GLOSSARY.md](../../GLOSSARY.md) (Workbench connection, saved password). **Builds on:** [setup-script spec](../setup-script/spec.md).

## Why

After Install the README still asked students to open Workbench and add a connection by hand (127.0.0.1, 3306, root, password). That step is where the first support requests come from. The setup script already knows every value, so it should do it.

## Decisions (approved in the grilling of 2026-11-04)

1. Install ends by giving Workbench a connection called **MIS781** (host 127.0.0.1, port 3306, user root, no default schema), only when Workbench has no connection to 127.0.0.1:3306 or localhost:3306 yet. A student's other connections are never touched. If Workbench is open at that moment, no connection is added and a note says what to do.
2. macOS also saves the root password in the keychain, so Workbench connects with no prompt; Reset password updates it. The saved password belongs to whichever root connection to this server Workbench has (the MIS781 one, or a student's own), because it is the verified password for that server; the connection itself is not changed. Windows gets the connection only; Workbench asks for the password once and can save it.
3. Hooks: end of Install on both platforms (inside `install.sh` / `install.ps1`, so the tutor one-liner gets it too) and end of Reset on macOS (`setup.sh`). Remove server leaves connection and saved password alone; Remove everything deletes them.
4. When macOS Install uses an other server (Homebrew, Oracle package) the connection is still added, but no password is saved.
5. The Actions test checks the stored connection holds 127.0.0.1 / 3306 / root, and on macOS that the saved password reads back through Workbench's own keychain helper after Install, Reset and the second Install, and is gone after Remove everything. The tile appearing and connecting without a prompt is checked once by hand.
6. Host stays `127.0.0.1`, not `localhost` (socket versus TCP on macOS, `::1` on Windows).
7. Adding a connection is not destructive and needs no confirmation; an existing connection is never overwritten.

## How (Workbench 26)

Workbench 26 is an Electron app around the MySQL Shell it ships with; connections live in the shell's `gui_plugin` SQLite database under the app's user-data folder (`~/Library/Application Support/MySQL Workbench/mysqlsh` on macOS, `%APPDATA%\MySQL Workbench\mysqlsh` on Windows) and passwords in the shell's credential store (macOS keychain, account `root`, service `host:port`). The worker reads the profile's connections with one query over `profile_has_db_connection` rather than `list_db_connections`, which lists only the top-level folder. The workers `workbench-connection.sh` / `.ps1` run that bundled `mysqlsh` with `MYSQLSH_USER_CONFIG_HOME` set and a short Python script that creates the local user and default profile when missing, lists the profile's connections, calls `gui.db_connections.add_db_connection` when none points at this server, and on macOS `shell.store_credential`. Nothing is written by hand. The password reaches the script through the option file in `MIS781_CNF` (or `MIS781_ROOT_PASSWORD`), never the command line.

## Files

- New: `workbench-connection.sh`, `workbench-connection.ps1`
- Changed: `install.sh` (calls the worker, closing instructions), `install.ps1` (same), `setup.sh` (Reset calls the worker), `uninstall-mysql.sh` and `uninstall-mysql.ps1` (Workbench 26 profile folder; macOS keychain entry), `.github/workflows/test.yml`, `README.md`, `GLOSSARY.md`
