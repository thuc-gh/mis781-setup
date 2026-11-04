#!/bin/zsh
# MIS781 Business Intelligence and Database — macOS setup (Apple Silicon)
#
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.sh)"
#
# Installs MySQL Server into ~/mysql (no admin password needed), starts it and
# keeps it running at login, installs MySQL Workbench into Applications, then
# loads the Employees sample database. One command, nothing to click through.
# Safe to re-run: anything already done is skipped.

set -e
BASE="https://github.com/thuc-gh/mis781-setup/releases/download/v2026-t3"
RAW="https://raw.githubusercontent.com/thuc-gh/mis781-setup/main"
DL="$HOME/Downloads"
DATA="$HOME/MIS781"
MYSQL_HOME="$HOME/mysql"
RC="$HOME/.zshrc"
APPS="${MIS781_APPS:-/Applications}"
SERVER_TGZ="mysql-26.10.0-macos15-arm64.tar.gz"
SERVER_DIR="mysql-26.10.0-macos15-arm64"
WB_ZIP="mysql-workbench-26.10.0-macos-arm64.zip"
DB_ZIP="test_db-master.zip"
WB_APP="MySQL Workbench.app"
LABEL="com.mis781.mysqld"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SOCK="/tmp/mysql.sock"

echo "MIS781 macOS setup"
echo "=================="

# ---- Checks before we download anything -------------------------------------
if [ "$(uname -m)" != arm64 ]; then
  echo "ERROR: this installer is for Apple Silicon Macs (M1/M2/M3/M4/M5) only."
  echo "       Your Mac reports: $(uname -m) (Intel)."
  echo "       See the 'Intel Macs' section of the README for what to do instead."
  exit 1
fi

# Never run as root: sudo writes root-owned files into your home folder, which
# is the usual reason ~/.zshrc later becomes unwritable.
if [ "$EUID" = 0 ]; then
  echo "ERROR: do not run this with sudo."
  echo "       It does not need it, and sudo would create root-owned files in your home folder."
  echo "       Run it again WITHOUT sudo."
  exit 1
fi

FREE_GB=$(df -g "$HOME" | tail -1 | awk '{print $4}')
if [ "${FREE_GB:-99}" -lt 4 ]; then
  echo "ERROR: not enough free disk space."
  echo "       This needs about 4GB free; you have ${FREE_GB}GB."
  echo "       Empty the Trash, free some space and run this again."
  exit 1
fi

# Another MySQL already listening on 3306 (Homebrew, Docker, MAMP, an Oracle
# installer) would stop ours from starting. Ours is fine.
LISTENER=$(lsof -nP -iTCP:3306 -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -1 || true)
LISTENER_PID=$(printf '%s' "$LISTENER" | awk '{print $2}')
if [ -n "$LISTENER_PID" ] && ! ps -o command= -p "$LISTENER_PID" 2>/dev/null | grep -q "^$MYSQL_HOME/bin/mysqld"; then
  echo "ERROR: something is already using MySQL's port 3306:"
  echo "       $LISTENER"
  echo
  echo "       You already have a MySQL (or compatible) server running. Either use it, or"
  echo "       remove it first with the uninstall script in the README, then run this again."
  exit 1
fi

# Check we can write ~/.zshrc before downloading anything.
if [ ! -e "$RC" ]; then
  touch "$RC" 2>/dev/null || { echo "ERROR: cannot create $RC — home folder not writable. Contact IT support."; exit 1; }
fi
if [ ! -w "$RC" ]; then
  RC_OWNER=$(stat -f%Su "$RC" 2>/dev/null || echo "?")
  ME=$(whoami)
  [ "$RC_OWNER" = "$ME" ] && chmod u+w "$RC" 2>/dev/null || true
  if [ ! -w "$RC" ]; then
    echo "ERROR: cannot write to ~/.zshrc — permission denied."
    echo
    if [ "$RC_OWNER" != "$ME" ]; then
      echo "       The file is owned by '$RC_OWNER', but you are '$ME'."
      echo "       This normally happens when something was run with sudo earlier."
      echo
      echo "       Fix it by running this one line (it will ask for your Mac password):"
      echo
      echo "         sudo chown $ME ~/.zshrc && chmod u+w ~/.zshrc"
    else
      echo "       You own the file, but it is still locked. Try these two lines:"
      echo
      echo "         chflags nouchg ~/.zshrc"
      echo "         chmod u+w ~/.zshrc"
    fi
    echo
    echo "       Then run this installer again. If that does not work, show this message to your tutor."
    exit 1
  fi
  echo "      NOTE: ~/.zshrc was read-only; made it writable."
fi

mkdir -p "$DL" "$DATA" "$HOME/Library/LaunchAgents"

# Download helper: re-uses a file already in Downloads, resumes a partial one.
fetch() {  # fetch <filename> <human size>
  local f="$1" size="$2"
  if [ -s "$DL/$f" ]; then
    echo "      $f already in Downloads, re-using it."
    return 0
  fi
  echo "      Downloading $f ($size)..."
  curl -# -fL -C - -o "$DL/$f.part" "$BASE/$f" || curl -# -fL -o "$DL/$f.part" "$BASE/$f"
  mv "$DL/$f.part" "$DL/$f"
}

# ---- 1. MySQL Server: unpack into ~/mysql -------------------------------------
if [ -x "$MYSQL_HOME/bin/mysqld" ]; then
  echo "[1/5] MySQL Server already unpacked in ~/mysql ($("$MYSQL_HOME/bin/mysqld" --version 2>/dev/null | sed 's/.*Ver /Ver /' | cut -d' ' -f1-2))."
else
  echo "[1/5] MySQL Server 26.10.0"
  fetch "$SERVER_TGZ" "~185MB"
  echo "      Unpacking into ~/mysql (about 750MB)..."
  rm -rf "${HOME:?}/${SERVER_DIR:?}"
  tar -xzf "$DL/$SERVER_TGZ" -C "$HOME"
  if [ -d "$MYSQL_HOME/data/mysql" ]; then
    # Program files missing but a database folder exists: keep it, add the programs.
    cp -R "$HOME/$SERVER_DIR/." "$MYSQL_HOME/"
    rm -rf "${HOME:?}/${SERVER_DIR:?}"
  else
    rm -rf "${MYSQL_HOME:?}"
    mv "$HOME/$SERVER_DIR" "$MYSQL_HOME"
  fi
  xattr -r -d com.apple.quarantine "$MYSQL_HOME" 2>/dev/null || true
  echo "      Done."
fi

# Server settings. Only this Mac can connect (bind-address), data lives in
# ~/mysql/data, errors go to ~/mysql/mysql-error.log.
if [ ! -f "$MYSQL_HOME/my.cnf" ]; then
  cat > "$MYSQL_HOME/my.cnf" <<CNF
# MySQL Server settings for MIS781 (written by install.sh)
[mysqld]
basedir=$MYSQL_HOME
datadir=$MYSQL_HOME/data
socket=$SOCK
port=3306
bind-address=127.0.0.1
mysqlx-bind-address=127.0.0.1
log-error=$MYSQL_HOME/mysql-error.log
pid-file=$MYSQL_HOME/mysqld.pid

[client]
socket=$SOCK
port=3306
CNF
fi

# ---- 2. First-time setup: create the data folder --------------------------------
NEW_SERVER=0
if [ -d "$MYSQL_HOME/data/mysql" ]; then
  echo "[2/5] Database folder already set up (~/mysql/data). Keeping your existing root password."
else
  echo "[2/5] Creating the database folder..."
  rm -rf "${MYSQL_HOME:?}/data"
  "$MYSQL_HOME/bin/mysqld" --defaults-file="$MYSQL_HOME/my.cnf" --initialize-insecure >/dev/null 2>&1 || {
    echo "ERROR: could not create the database folder. Last lines of the log:"
    tail -20 "$MYSQL_HOME/mysql-error.log" 2>/dev/null | sed 's/^/         /'
    echo "       Show this to your tutor."
    exit 1
  }
  NEW_SERVER=1
fi

# ---- 3. Start the server now and at every login (launchd) ---------------------
echo "[3/5] Starting MySQL Server (it will also start automatically when you log in)."
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$MYSQL_HOME/bin/mysqld</string>
    <string>--defaults-file=$MYSQL_HOME/my.cnf</string>
  </array>
  <key>WorkingDirectory</key><string>$MYSQL_HOME</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardErrorPath</key><string>$MYSQL_HOME/launchd.log</string>
  <key>StandardOutPath</key><string>$MYSQL_HOME/launchd.log</string>
</dict>
</plist>
PL
UID_=$(id -u)
if launchctl print "gui/$UID_/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart "gui/$UID_/$LABEL" >/dev/null 2>&1 || true
else
  launchctl bootstrap "gui/$UID_" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"
fi

printf '      Waiting for the server'
READY=0
for i in $(seq 1 60); do
  if "$MYSQL_HOME/bin/mysqladmin" --defaults-file="$MYSQL_HOME/my.cnf" --socket="$SOCK" ping >/dev/null 2>&1; then READY=1; break; fi
  printf '.'; sleep 1
done
echo
if [ "$READY" != 1 ]; then
  echo "ERROR: MySQL Server did not start. Last lines of ~/mysql/mysql-error.log:"
  tail -20 "$MYSQL_HOME/mysql-error.log" 2>/dev/null | sed 's/^/         /'
  echo "       Show this to your tutor."
  exit 1
fi
echo "      Server is running on 127.0.0.1 port 3306."

# Root password: prompt (hidden), or take it from MIS781_ROOT_PASSWORD when set.
CNF=$(mktemp "${TMPDIR:-/tmp}/mis781.XXXXXX"); chmod 600 "$CNF"
trap 'rm -f "$CNF"' EXIT
trap 'echo; echo "Interrupted. Run the installer again to continue."; exit 130' INT
if [ "$NEW_SERVER" = 1 ]; then
  echo
  echo "      Choose a password for the MySQL 'root' account. You will type it into"
  echo "      Workbench every time you connect, so pick one you can remember."
  echo "      >>> WRITE IT DOWN. If you forget it, the only fix is a reinstall. <<<"
  PW="${MIS781_ROOT_PASSWORD:-}"
  while [ -z "$PW" ]; do
    printf '      New root password (typing is hidden): '; read -rs PW < /dev/tty; echo
    printf '      Type it again: '; read -rs PW2 < /dev/tty; echo
    if [ -z "$PW" ]; then echo "      It cannot be empty."; elif [ "$PW" != "$PW2" ]; then echo "      They do not match, try again."; PW=""; fi
  done
  # SQL string literal: escape \ and ' so any password works (sed, because zsh's
  # ${var//} replacement mangles backslashes).
  PW_SQL=$(printf '%s' "$PW" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
  printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\nFLUSH PRIVILEGES;\n" "$PW_SQL" | \
    "$MYSQL_HOME/bin/mysql" --defaults-file="$MYSQL_HOME/my.cnf" --socket="$SOCK" -u root --skip-password 2>&1 | grep -v 'Using a password' || true
  echo "      Root password set."
else
  PW="${MIS781_ROOT_PASSWORD:-}"
  if [ -z "$PW" ]; then
    printf '      Your existing MySQL root password, for the checks below (typing is hidden): '; read -rs PW < /dev/tty; echo
  fi
fi
# Option file for the rest of this script: quoted, with \ and " escaped.
PW_ESC=$(printf '%s' "$PW" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
printf '[client]\nuser=root\nhost=127.0.0.1\nport=3306\npassword="%s"\n' "$PW_ESC" > "$CNF"
unset PW PW2 PW_SQL PW_ESC
if ! "$MYSQL_HOME/bin/mysql" --defaults-extra-file="$CNF" -N -s -e 'SELECT 1' >/dev/null 2>&1; then
  echo "ERROR: that root password did not work. Run the installer again and type it carefully."
  echo "       Forgotten it? See 'Forgot your MySQL root password' in the README."
  exit 1
fi

# Put ~/mysql/bin on the PATH so 'mysql' works in a new Terminal window.
if ! grep -q 'MIS781' "$RC" 2>/dev/null; then
  cat >> "$RC" <<'ZRC'

# MySQL command-line tools for MIS781 (installed in ~/mysql by install.sh)
export PATH="$HOME/mysql/bin:$PATH"
ZRC
  echo "      Added ~/mysql/bin to your PATH (takes effect in new Terminal windows)."
fi

# ---- 4. MySQL Workbench -------------------------------------------------------
# Workbench 26 ships as a zip of the .app, so this part is fully automatic.
wb_version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null || true; }
WB_DEST=""
for d in "$APPS" "$HOME/Applications"; do
  if [ -d "$d/$WB_APP" ]; then WB_DEST="$d"; break; fi
done
if [ -n "$WB_DEST" ]; then
  echo "[4/5] MySQL Workbench already installed ($(wb_version "$WB_DEST/$WB_APP")) in $WB_DEST."
else
  echo "[4/5] MySQL Workbench 26.10.0"
  fetch "$WB_ZIP" "~295MB"
  if [ -w "$APPS" ]; then WB_DEST="$APPS"; else WB_DEST="$HOME/Applications"; mkdir -p "$WB_DEST"; fi
  echo "      Unpacking into $WB_DEST..."
  ditto -x -k "$DL/$WB_ZIP" "$WB_DEST"
  if [ -d "$WB_DEST/$WB_APP" ]; then
    # A zip saved by a browser carries a quarantine flag that would block the app.
    xattr -r -d com.apple.quarantine "$WB_DEST/$WB_APP" 2>/dev/null || true
    echo "      Installed ($(wb_version "$WB_DEST/$WB_APP"))."
  else
    echo "ERROR: Workbench did not unpack as expected. Show this to your tutor."
    exit 1
  fi
fi

# ---- 5. Employees sample database ---------------------------------------------
if [ -f "$DATA/test_db-master/employees.sql" ]; then
  echo "[5/5] Employees database files already at ~/MIS781/test_db-master."
else
  echo "[5/5] Employees sample database"
  fetch "$DB_ZIP" "~35MB"
  unzip -q -o "$DL/$DB_ZIP" -d "$DATA"
  echo "      Files at ~/MIS781/test_db-master (employees.sql and the .dump files)."
fi

ROWS=$("$MYSQL_HOME/bin/mysql" --defaults-extra-file="$CNF" -N -s -e "SELECT COUNT(*) FROM employees.employees" 2>/dev/null || echo 0)
if [ "$ROWS" = 300024 ]; then
  echo "      The 'employees' database is already loaded (300024 employees)."
else
  ANS="${MIS781_IMPORT:-}"
  if [ -z "$ANS" ]; then
    printf '      Load the Employees database into MySQL now? It takes a few minutes. [Y/n] '
    read -r ANS < /dev/tty
  fi
  case "$ANS" in
    [Nn]*) echo "      Skipped. Load it later with:"
           echo "        zsh -c \"\$(curl -fsSL $RAW/import-employees.sh)\"" ;;
    *)     export MIS781_CNF="$CNF" MIS781_MYSQL="$MYSQL_HOME/bin/mysql" MIS781_IMPORT=y
           if [ -n "${MIS781_LOCAL_SCRIPTS:-}" ] && [ -f "$MIS781_LOCAL_SCRIPTS/import-employees.sh" ]; then
             zsh "$MIS781_LOCAL_SCRIPTS/import-employees.sh"
           else
             zsh -c "$(curl -fsSL "$RAW/import-employees.sh")"
           fi ;;
  esac
fi

# ---- Summary ------------------------------------------------------------------
echo
echo "Checking what was installed..."
OK=1
if "$MYSQL_HOME/bin/mysqladmin" --defaults-file="$MYSQL_HOME/my.cnf" --socket="$SOCK" ping >/dev/null 2>&1; then
  echo "  MySQL Server      OK  (running, 127.0.0.1:3306, files in ~/mysql)"
else
  echo "  MySQL Server      PROBLEM -> not responding"; OK=0
fi
[ -d "$WB_DEST/$WB_APP" ] && echo "  MySQL Workbench   OK  ($WB_DEST)" || { echo "  MySQL Workbench   PROBLEM"; OK=0; }
ROWS=$("$MYSQL_HOME/bin/mysql" --defaults-extra-file="$CNF" -N -s -e "SELECT COUNT(*) FROM employees.employees" 2>/dev/null || echo 0)
if [ "$ROWS" = 300024 ]; then echo "  Employees data    OK  (300024 employees)"; else echo "  Employees data    not loaded yet"; fi

echo
if [ "$OK" = 1 ]; then
  echo "Done. Next:"
  echo "  1. Open MySQL Workbench (Applications). Add a connection: host 127.0.0.1, port 3306,"
  echo "     user root, and the password you just chose."
  echo "  2. Refresh the SCHEMAS list: you should see 'employees'. Try:"
  echo "       USE employees; SHOW TABLES; SELECT COUNT(*) FROM employees;"
  echo "  3. Open a NEW Terminal window if you want to use the 'mysql' command directly."
else
  echo "SOMETHING WENT WRONG (see above). Show this output to your tutor."
  exit 1
fi
