# MIS781 — MySQL setup (macOS and Windows)

Everything you need for MIS781 Business Intelligence and Database: MySQL Server, MySQL Workbench and the Employees sample database, with the versions pinned and the downloads hosted here so the links keep working all trimester.

| Component | Version |
|---|---|
| MySQL Community Server | 26.10.0 |
| MySQL Workbench | 26.10.0 |
| Employees sample database | `test_db` (April 2026 commit), 300,024 employees and 2.8 million salary rows |

## macOS (Apple Silicon)

> **Apple Silicon only** (M1 to M5). Check with `uname -m` in Terminal: it must say `arm64`. If it says `x86_64` you have an Intel Mac; see [Intel Macs](#intel-macs).

Open **Terminal** and paste this one line. It needs no admin password and nothing to click through:

```bash
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.sh)"
```

It asks you for two things: a **new MySQL root password** (write it down) and whether to load the Employees database now (say yes). About five minutes on a normal connection.

What it does:

1. Unpacks MySQL Server into `~/mysql`, creates the database folder, sets your root password and starts the server. The server starts again by itself every time you log in. It only listens on this Mac (127.0.0.1), so nothing is exposed on wifi.
2. Puts MySQL Workbench into your Applications folder.
3. Unpacks the Employees files into `~/MIS781/test_db-master` and loads them into MySQL (about four million rows, a few minutes).

Then open **MySQL Workbench** from Applications, add a connection with host `127.0.0.1`, port `3306`, user `root` and your password, and refresh the SCHEMAS list. You should see `employees`.

The `mysql` command also works directly in any **new** Terminal window.

## Windows (64-bit Windows 10 or 11)

Open **PowerShell** (Start menu, type PowerShell) and paste this one line:

```powershell
irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.ps1 | iex
```

It downloads everything, unpacks the Employees files into `C:\Users\<you>\MIS781\test_db-master`, then opens the two Oracle installers for you to click through (Windows needs you to approve them, so this part cannot be automated):

1. **MySQL Server**: accept the defaults. On the last page leave **Run MySQL Configurator** ticked. In MySQL Configurator keep *Development Computer* and port 3306, set a **root password** (write it down), keep *Configure MySQL Server as a Windows Service* ticked, then **Execute**.
2. **MySQL Workbench**: Next, Complete, Install, Finish.

Then load the Employees database with this second one-liner (it asks for your root password):

```powershell
irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.ps1 | iex
```

Open **MySQL Workbench**, double-click the local connection, enter your root password and refresh the SCHEMAS list. You should see `employees`.

**Lab PCs or unattended installs (Windows):** set `MIS781_ROOT_PASSWORD` (and `MIS781_IMPORT=y` to load the data) before running the script, and it installs silently with no clicking. On macOS the same two variables skip the prompts.

## Check it worked

In a Workbench query tab:

```sql
USE employees;
SHOW TABLES;
SELECT COUNT(*) FROM employees;
```

`SHOW TABLES` lists eight objects (six tables plus the views `current_dept_emp` and `dept_emp_latest_date`). The count is **300024**.

## If something goes wrong

**Forgot your MySQL root password.** There is no recovery. On macOS run the [uninstaller](#uninstalling-mysql) and then the installer again. On Windows uninstall *MySQL Server 26.10* from Settings → Apps, delete `C:\ProgramData\MySQL`, and run the installer again.

**macOS: "something is already using MySQL's port 3306".** You already have a MySQL from Homebrew, MAMP, XAMPP, Docker or an earlier Oracle installer. Either use that one (point Workbench at it) or remove it with the [uninstaller](#uninstalling-mysql) and run the installer again.

**macOS: `permission denied: .zshrc`.** The installer adds one line to `~/.zshrc` and that file is not writable by you, almost always because something was run with `sudo` earlier. Run this (it asks for your Mac password), then run the installer again:

```bash
sudo chown $(whoami) ~/.zshrc && chmod u+w ~/.zshrc
```

**Never run the installer with `sudo`.** It does not need it, and `sudo` creates files your normal account cannot edit afterwards. The installer refuses to run that way.

**macOS: Workbench "cannot be opened" or "is damaged".** System Settings → Privacy & Security → scroll down → **Open Anyway**. If that does not appear, run `xattr -dr com.apple.quarantine "/Applications/MySQL Workbench.app"` in Terminal and open it again.

**macOS: MySQL Server not running** (Workbench says "Can't connect"). Start it with:

```bash
launchctl kickstart -k gui/$(id -u)/com.mis781.mysqld
```

If it still will not connect, the reason is at the end of `~/mysql/mysql-error.log`. Show it to your tutor.

**Windows: "mysql.exe is not recognised".** The import script finds `mysql.exe` by itself, so use it rather than typing the tutorial's command. If you do type it, use the full path: `"C:\Program Files\MySQL\MySQL Server 26.10\bin\mysql.exe"`.

**Windows: MySQL Configurator did not appear.** Open it from the Start menu (MySQL → MySQL Configurator) and finish it. The server does not start until it has been configured.

**Import says `source` failed or loads nothing.** You ran `employees.sql` inside Workbench, or with the plain `mysql < employees.sql` command. The script uses `source` lines, which only the command-line client understands, and since MySQL 9.5 the client needs `--commands=ON` to follow them. The import scripts here do that for you.

**Intel Macs.** Oracle builds MySQL 26.10 for Apple Silicon only. Use MySQL Server 9.7 LTS and the last Intel Workbench instead, both from Oracle: [mysql-9.7.4-macos15-x86_64.dmg](https://cdn.mysql.com/Downloads/MySQL-9.7/mysql-9.7.4-macos15-x86_64.dmg) and [mysql-workbench-community-8.0.47-macos-x86_64.dmg](https://cdn.mysql.com/archives/mysql-workbench/mysql-workbench-community-8.0.47-macos-x86_64.dmg). Install both by double-clicking, then follow the unit's Mac tutorial PDF, which uses `/usr/local/mysql/bin/mysql`. The import script here also works with that layout.

## Manual downloads

If you would rather not run a script, every file is on the [Releases page](../../releases/latest), with SHA-256 checksums in the release notes.

- macOS: unpack `mysql-26.10.0-macos15-arm64.tar.gz`, follow Oracle's [tar.gz instructions](https://dev.mysql.com/doc/refman/26.10/en/macos-installation-notes.html); unzip `mysql-workbench-26.10.0-macos-arm64.zip` and drag *MySQL Workbench* into Applications.
- Windows: run `mysql-26.10.0-winx64.msi` then `mysql-workbench-26.10.0-winx64.msi`.
- Employees database: unzip `test_db-master.zip`, open a terminal in that folder and run `mysql --commands=ON -u root -p < employees.sql` (on Windows, with the full path to `mysql.exe`).

## Uninstalling MySQL

### macOS

Removes every MySQL on your Mac: the `~/mysql` install from this unit, Homebrew installs and Oracle `.pkg` installs. It shows what it found and only deletes after you type `yes`:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.sh)"
```

To see what it would remove without deleting anything:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.sh)" -- --dry-run
```

### Windows

Open **Terminal (Admin)** (right-click the Start button) and paste:

```powershell
irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1 | iex
```

It removes MySQL Server, its service and its data folder, and leaves Workbench alone.

> **Both uninstallers permanently delete all MySQL databases on the computer.** If you have coursework in MySQL you want to keep, export it first: `mysqldump -u root -p --all-databases > backup.sql`.

## What's in this repo

| File | Purpose |
|---|---|
| `install.sh` | macOS: MySQL Server, Workbench and Employees data, one command |
| `import-employees.sh` | macOS: load (or reload) the Employees database on its own |
| `uninstall-mysql.sh` | macOS: complete MySQL removal |
| `install.ps1` | Windows: downloads, unpacks the data, opens the two installers |
| `import-employees.ps1` | Windows: load (or reload) the Employees database |
| `uninstall-mysql.ps1` | Windows: complete MySQL Server removal |
| `.github/workflows/test.yml` | Installs, loads and removes everything on clean macOS and Windows runners; run by hand before each trimester |
| `LICENSES.md` | Licences and source availability for everything distributed here |

---

*Unit mirror for Deakin MIS781. Files are hosted here so the versions stay pinned and the links keep working: vendor download URLs move when versions are superseded. See [LICENSES.md](LICENSES.md) for licensing and source.*
