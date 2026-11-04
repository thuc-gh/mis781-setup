#!/bin/zsh
# MIS781 — load the Employees sample database into your local MySQL (macOS)
#
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/import-employees.sh)"
#
# Runs employees.sql through the MySQL command-line client (NOT Workbench:
# the script uses 'source', which only the command-line client understands),
# then checks the row counts. Safe to re-run; asks before reloading.

set -e
DATA="$HOME/MIS781/test_db-master"
BASE="https://github.com/thuc-gh/mis781-setup/releases/download/v2026-t3"

echo "MIS781 Employees database import"
echo "================================"

if [ "$EUID" = 0 ]; then
  echo "ERROR: do not run this with sudo. Run it again WITHOUT sudo."
  exit 1
fi

# ---- 1. Find the mysql command-line client ----------------------------------
MYSQL="${MIS781_MYSQL:-}"
for c in "$HOME/mysql/bin/mysql" /usr/local/mysql/bin/mysql /opt/homebrew/opt/mysql/bin/mysql /opt/homebrew/bin/mysql /usr/local/bin/mysql; do
  [ -n "$MYSQL" ] && break
  [ -x "$c" ] && { MYSQL="$c"; break; }
done
[ -z "$MYSQL" ] && MYSQL="$(command -v mysql 2>/dev/null || true)"
if [ -z "$MYSQL" ]; then
  echo "ERROR: the mysql command-line client was not found."
  echo "       MySQL Server does not seem to be installed yet."
  echo "       Run the installer first:"
  echo "         zsh -c \"\$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/install.sh)\""
  exit 1
fi
echo "[1/4] Using $MYSQL"
echo "      $("$MYSQL" --version | sed 's/.*Ver /Ver /')"

# ---- 2. Find the database files ---------------------------------------------
if [ ! -f "$DATA/employees.sql" ]; then
  echo "[2/4] Employees files not found at $DATA, downloading..."
  mkdir -p "$HOME/MIS781" "$HOME/Downloads"
  curl -# -fL -o "$HOME/Downloads/test_db-master.zip" "$BASE/test_db-master.zip"
  unzip -q -o "$HOME/Downloads/test_db-master.zip" -d "$HOME/MIS781"
fi
for f in employees.sql load_employees.dump load_salaries1.dump; do
  if [ ! -f "$DATA/$f" ]; then
    echo "ERROR: $DATA/$f is missing. Re-run the installer to fetch the database files."
    exit 1
  fi
done
echo "[2/4] Database files: $DATA"

# ---- 3. Connect ---------------------------------------------------------------
# The password goes in a private temp file that mysql reads, never on the
# command line, and the file is deleted when the script ends.
if [ -n "${MIS781_CNF:-}" ] && [ -r "$MIS781_CNF" ]; then
  CNF="$MIS781_CNF"      # handed over by install.sh, already checked
  echo "[3/4] Connecting to the local MySQL Server as root."
else
  CNF=$(mktemp "${TMPDIR:-/tmp}/mis781.XXXXXX")
  chmod 600 "$CNF"
  trap 'rm -f "$CNF"' EXIT
  echo "[3/4] Connecting to the local MySQL Server as root."
  printf '      MySQL root password (the one you chose when installing; typing is hidden): '
  read -rs PW < /dev/tty
  echo
  # Quote the value: unquoted, a '#' in the password would start a comment.
  # Inside quotes mysql treats backslash as an escape, so escape \ and " first.
  PW_ESC=$(printf '%s' "$PW" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '[client]\nuser=root\nhost=127.0.0.1\nport=3306\npassword="%s"\n' "$PW_ESC" > "$CNF"
  unset PW PW_ESC
fi

if ! VER=$("$MYSQL" --defaults-extra-file="$CNF" -N -s -e 'SELECT VERSION()' 2>/tmp/mis781-err); then
  ERR=$(cat /tmp/mis781-err); rm -f /tmp/mis781-err
  echo "ERROR: could not connect."
  echo "       $ERR"
  echo
  if echo "$ERR" | grep -q "Access denied"; then
    echo "       Wrong root password. Run this again and type it carefully."
    echo "       If you have forgotten it, see 'Forgot your MySQL root password' in the README."
  elif echo "$ERR" | grep -q "password has expired"; then
    echo "       Your root password has expired. Set a new one with:"
    echo "         $MYSQL -u root -p --connect-expired-password"
    echo "         ALTER USER 'root'@'localhost' IDENTIFIED BY 'YourNewPassword123!';"
  else
    echo "       MySQL Server is probably not running. Start it with:"
    if [ -f "$HOME/Library/LaunchAgents/com.mis781.mysqld.plist" ]; then
      echo "         launchctl kickstart -k gui/$(id -u)/com.mis781.mysqld"
    else
      echo "         sudo /usr/local/mysql/support-files/mysql.server start"
    fi
    echo "       then run this again. Still failing? Show the last lines of ~/mysql/mysql-error.log to your tutor."
  fi
  exit 1
fi
rm -f /tmp/mis781-err
echo "      Connected. Server version $VER"

# ---- 4. Import ----------------------------------------------------------------
EXISTING=$("$MYSQL" --defaults-extra-file="$CNF" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='employees' AND table_name='employees'" 2>/dev/null || echo 0)
if [ "$EXISTING" = 1 ]; then
  ROWS=$("$MYSQL" --defaults-extra-file="$CNF" -N -s -e "SELECT COUNT(*) FROM employees.employees" 2>/dev/null || echo 0)
  echo "[4/4] The 'employees' database already exists ($ROWS employee rows)."
  if [ "$ROWS" = 300024 ]; then
    printf '      Reload it from scratch anyway? This erases any changes you made. [y/N] '
  else
    printf '      It looks incomplete. Reload it from scratch? [Y/n] '
  fi
  if [ -n "${MIS781_IMPORT:-}" ]; then ANS="n"; [ "$ROWS" != 300024 ] && ANS="y"; echo "$ANS"; else read -r ANS < /dev/tty; fi
  case "$ROWS:$ANS" in
    300024:[Yy]*) ;;
    300024:*) echo "      Keeping the existing database. Nothing changed."; exit 0 ;;
    *:[Nn]*) echo "      Keeping the existing database. Nothing changed."; exit 0 ;;
    *) ;;
  esac
fi

echo "[4/4] Loading employees.sql (about 4 million rows; this takes a few minutes)..."
cd "$DATA"
START=$(date +%s)
# --commands=ON is required: since MySQL 9.5 the client ignores 'source' lines
# unless it is set, and employees.sql uses 'source' to pull in the .dump files.
"$MYSQL" --defaults-extra-file="$CNF" --commands=ON < employees.sql
echo "      Loaded in $(( $(date +%s) - START )) seconds."

echo
echo "Checking the result..."
OK=1
COUNT=$("$MYSQL" --defaults-extra-file="$CNF" -N -s -e "SELECT COUNT(*) FROM employees.employees")
if [ "$COUNT" = 300024 ]; then
  echo "  employees table   OK (300024 rows)"
else
  echo "  employees table   PROBLEM -> $COUNT rows (expected 300024)"
  OK=0
fi
TABLES=$("$MYSQL" --defaults-extra-file="$CNF" -N -s -e "SHOW FULL TABLES IN employees WHERE Table_type='BASE TABLE'" | awk '{print $1}' | tr '\n' ' ')
echo "  tables            $TABLES"
if [ -f test_employees_sha2.sql ]; then
  echo "  checksum test     (compares every table against the official checksums)"
  "$MYSQL" --defaults-extra-file="$CNF" --commands=ON -t < test_employees_sha2.sql | grep -E '^\| [a-z_]+ +\| (OK|not ok) ' | sed 's/^/                    /' || true
fi

echo
if [ "$OK" = 1 ]; then
  echo "Done. Open MySQL Workbench, connect as root, refresh the schemas list and run:"
  echo "  USE employees; SHOW TABLES; SELECT COUNT(*) FROM employees;"
else
  echo "SOMETHING WENT WRONG (see above). Show this output to your tutor."
  exit 1
fi
