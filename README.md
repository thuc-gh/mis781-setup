# MIS781 — MySQL setup (macOS and Windows)

Everything you need for MIS781 Business Intelligence and Database: MySQL Server, MySQL Workbench and the Employees sample database, with the versions pinned and the downloads hosted here so the links keep working all trimester.

| Component | Version |
|---|---|
| MySQL Community Server | 26.10.0 |
| MySQL Workbench | 26.10.0 |
| Employees sample database | `test_db` (April 2026 commit), 300,024 employees and 2.8 million salary rows |

## One line, whatever state your computer is in

The setup script first looks at what is already on your computer (it changes nothing and asks for no password), tells you what it found, recommends one action and lets you pick from a short menu. Run it on a brand-new laptop, run it again later to load the data, run it when you have forgotten your password: it works out what to do.

**macOS (Apple Silicon, M1 to M5).** Open **Terminal** and paste:

```bash
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/setup.sh)"
```

**Windows (64-bit Windows 10 or 11).** Open **PowerShell** (Start menu, type PowerShell) and paste:

```powershell
irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/setup.ps1 | iex
```

You will see something like this, then a menu. Press **Enter** to take the recommendation.

```
What is on this Mac (arm64):
  MySQL Server      none from this unit
  Other MySQL       none
  MySQL Workbench   not installed
  Employees files   not downloaded
  Employees data    (checked when you connect)

Recommended: Install everything that is missing

  1. Install everything that is missing
  2. Remove everything (server, Workbench, Employees files, downloads)
  3. Quit
Choose [1]:
```

The menu only shows actions that make sense for your computer:

| Action | What it does |
|---|---|
| **Install everything that is missing** | MySQL Server, MySQL Workbench, the Employees files and the Employees data. Whatever is already there is kept. Asks you for a **new MySQL root password** (write it down). Gives Workbench a ready-made **MIS781** connection; on macOS the password is saved too, so Workbench connects without asking. On Windows it opens the two Oracle installers for you to click through, then loads the data once you have finished MySQL Configurator. |
| **Load the Employees database** | Loads the Employees data into your server (a few minutes). Asks for your root password. |
| **Reset the MySQL root password** | For when you have forgotten it. Gives `root` a new password and keeps every database. On macOS the password saved for Workbench is updated too. |
| **Remove MySQL Server** | Takes the server and all its databases off, keeps Workbench and the Employees files, so a fresh Install is quick. |
| **Remove everything** | Also removes Workbench, its saved connections and saved password, the `MIS781` folder and the downloaded installers. |

Anything that deletes something shows you the exact list first and only goes ahead after you type `yes`. Reset and a reload ask for a `y`. On Windows, Reset and the two Remove actions open an administrator window by themselves (Windows asks you to allow it).

### What Install does

**macOS.** Unpacks MySQL Server into `~/mysql`, creates the database folder, sets your root password and starts the server. The server starts again by itself every time you log in and only listens on this Mac (127.0.0.1). Puts MySQL Workbench into Applications, gives it a connection called **MIS781** and saves your root password in the keychain, so Workbench connects without asking. Unpacks the Employees files into `~/MIS781/test_db-master` and loads them. No admin password, nothing to click through, about five minutes.

**Windows.** Downloads everything, unpacks the Employees files into `C:\Users\<you>\MIS781\test_db-master`, then opens the two Oracle installers (Windows needs you to approve them):

1. **MySQL Server**: accept the defaults. On the last page leave **Run MySQL Configurator** ticked. In MySQL Configurator keep *Development Computer* and port 3306, set a **root password** (write it down), keep *Configure MySQL Server as a Windows Service* ticked, then **Execute**.
2. **MySQL Workbench**: Next, Complete, Install, Finish.

Leave the PowerShell window open. When you click **Finish** in MySQL Configurator the script notices, asks for the root password you just set and loads the Employees data (a few minutes). If you closed the window or the load reported a problem, run the setup line again and choose **Load the Employees database**. Workbench also gets a ready-made connection called **MIS781**; it asks for your root password the first time you connect and can save it.

## Check it worked

Open **MySQL Workbench** and click the **MIS781** connection (on Windows, type your root password the first time and let Workbench save it; on macOS it opens straight away). If there is no MIS781 tile, add a connection with host `127.0.0.1`, port `3306`, user `root` and your password. Refresh the SCHEMAS list and run:

```sql
USE employees;
SHOW TABLES;
SELECT COUNT(*) FROM employees;
```

`SHOW TABLES` lists eight objects (six tables plus the views `current_dept_emp` and `dept_emp_latest_date`). The count is **300024**.

On macOS the `mysql` command also works directly in any **new** Terminal window.

## If something goes wrong

**Forgot your MySQL root password.** Run the setup line again and choose **Reset the MySQL root password**. Your databases are kept. If the reset fails, choose **Remove MySQL Server** and then **Install**. (If your MySQL is from Homebrew, MAMP or the Oracle installer rather than from this unit, Reset is not offered; follow Oracle's [reset instructions](https://dev.mysql.com/doc/refman/26.10/en/resetting-permissions.html) instead.)

**macOS: you already have MySQL.** If a MySQL server is already installed or running (Homebrew, MAMP, XAMPP, Docker, an earlier Oracle installer), the scan lists it under "Other MySQL" and Install leaves it alone and uses it: it asks for that server's root password, skips the server download, and still sets up Workbench and the data. If you would rather start clean, **Remove MySQL Server** lists every server it found, marked *ours* or *other*, and removes them all after you type `yes`.

**macOS: `permission denied: .zshrc`.** The installer adds one line to `~/.zshrc` and that file is not writable by you, almost always because something was run with `sudo` earlier. Run this (it asks for your Mac password), then run the setup line again:

```bash
sudo chown $(whoami) ~/.zshrc && chmod u+w ~/.zshrc
```

**Never run the scripts with `sudo`.** They do not need it, and `sudo` creates files your normal account cannot edit afterwards. They refuse to run that way.

**macOS: Workbench "cannot be opened" or "is damaged".** System Settings → Privacy & Security → scroll down → **Open Anyway**. If that does not appear, run `xattr -dr com.apple.quarantine "/Applications/MySQL Workbench.app"` in Terminal and open it again.

**macOS: MySQL Server not running** (Workbench says "Can't connect"). Start it with:

```bash
launchctl kickstart -k gui/$(id -u)/com.mis781.mysqld
```

If it still will not connect, the scan will say "failing to start" and recommend Remove MySQL Server, then Install. The reason is at the end of `~/mysql/mysql-error.log`; show it to your tutor if it keeps happening.

**Windows: MySQL Configurator did not appear.** The scan says "MySQL Configurator was never finished". Open it from the Start menu (MySQL → MySQL Configurator) and finish it. The server does not start until it has been configured.

**Windows: "mysql.exe is not recognised".** The scripts find `mysql.exe` by themselves, so use them rather than typing the tutorial's command. If you do type it, use the full path: `"C:\Program Files\MySQL\MySQL Server 26.10\bin\mysql.exe"`.

**Import says `source` failed or loads nothing.** You ran `employees.sql` inside Workbench, or with the plain `mysql < employees.sql` command. The script uses `source` lines, which only the command-line client understands, and since MySQL 9.5 the client needs `--commands=ON` to follow them. The scripts here do that for you.

**Intel Macs.** Oracle builds MySQL 26.10 for Apple Silicon only. Use MySQL Server 9.7 LTS and the last Intel Workbench instead, both from Oracle: [mysql-9.7.4-macos15-x86_64.dmg](https://cdn.mysql.com/Downloads/MySQL-9.7/mysql-9.7.4-macos15-x86_64.dmg) and [mysql-workbench-community-8.0.47-macos-x86_64.dmg](https://cdn.mysql.com/archives/mysql-workbench/mysql-workbench-community-8.0.47-macos-x86_64.dmg). Install both by double-clicking, then run the setup line: on an Intel Mac it offers **Load the Employees database**, which works with that layout.

## Running one step directly

The setup script calls these; tutors can run them on their own.

| | macOS | Windows |
|---|---|---|
| Install | `zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.sh)"` | `irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.ps1 \| iex` |
| Load data | `zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.sh)"` | `irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.ps1 \| iex` |
| Workbench connection | `zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/workbench-connection.sh)"` | `irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/workbench-connection.ps1 \| iex` |
| Remove server | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.sh)"` | in Terminal (Admin): `irm https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.ps1 \| iex` |

The removal scripts take `--dry-run` / `-DryRun` (show the list, change nothing) and `--all` / `-All` (remove everything). On Windows pass options as `& ([scriptblock]::Create((irm <url>))) -DryRun`.

**Lab PCs and the Actions test (unattended).** Set `MIS781_ACTION` to `install`, `load`, `reset`, `remove-server` or `remove-all` and the setup script runs that action with no menu (`scan` prints the scan and stops). Supply `MIS781_ROOT_PASSWORD` (and `MIS781_IMPORT=y` to load the data) for Install, `MIS781_NEW_PASSWORD` for Reset, and `MIS781_CONFIRM=yes` for Reset and the two Remove actions; without it they print what they would do and stop.

## Manual downloads

If you would rather not run a script, every file is on the [Releases page](../../releases/latest), with SHA-256 checksums in the release notes.

- macOS: unpack `mysql-26.10.0-macos15-arm64.tar.gz`, follow Oracle's [tar.gz instructions](https://dev.mysql.com/doc/refman/26.10/en/macos-installation-notes.html); unzip `mysql-workbench-26.10.0-macos-arm64.zip` and drag *MySQL Workbench* into Applications.
- Windows: run `mysql-26.10.0-winx64.msi` then `mysql-workbench-26.10.0-winx64.msi`.
- Employees database: unzip `test_db-master.zip`, open a terminal in that folder and run `mysql --commands=ON -u root -p < employees.sql` (on Windows, with the full path to `mysql.exe`).

## What's in this repo

| File | Purpose |
|---|---|
| `setup.sh` / `setup.ps1` | The one line students run: scans, recommends, runs the chosen action (Reset password lives here) |
| `install.sh` / `install.ps1` | Install: MySQL Server, Workbench and Employees data; re-running adds only what is missing |
| `import-employees.sh` / `import-employees.ps1` | Load (or reload) the Employees database |
| `workbench-connection.sh` / `workbench-connection.ps1` | Give Workbench the ready-made MIS781 connection (and on macOS the saved password); run by Install and, on macOS, Reset |
| `uninstall-mysql.sh` / `uninstall-mysql.ps1` | Remove MySQL Server; with `--all` / `-All`, remove everything |
| `.github/workflows/test.yml` | Installs, loads, resets, reinstalls and removes everything on clean macOS and Windows runners through the setup script; run by hand before each trimester |
| `GLOSSARY.md`, `docs/adr/` | The words the scripts and this README use, and the decisions behind them |
| `LICENSES.md` | Licences and source availability for everything distributed here |

---

*Unit mirror for Deakin MIS781. Files are hosted here so the versions stay pinned and the links keep working: vendor download URLs move when versions are superseded. See [LICENSES.md](LICENSES.md) for licensing and source.*
