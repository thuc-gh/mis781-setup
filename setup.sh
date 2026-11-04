#!/bin/zsh
# MIS781 Business Intelligence and Database — setup (macOS)
#
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/setup.sh)"
#
# Looks at what is already on this Mac (without changing anything or asking for
# a password), recommends one action, shows a short menu, and runs the action
# you choose. The actions are the other scripts in this repo:
#
#   Install            install.sh          adds whatever is missing
#   Load data          import-employees.sh loads the Employees database
#   Reset password     (this script)       new root password, every database kept
#   Remove server      uninstall-mysql.sh  MySQL Server and its databases go,
#                                          Workbench and the Employees files stay
#   Remove everything  uninstall-mysql.sh --all
#
# Unattended (lab PCs, the Actions test): MIS781_ACTION=scan|install|load|reset|
# remove-server|remove-all, plus MIS781_ROOT_PASSWORD, MIS781_IMPORT=y,
# MIS781_NEW_PASSWORD (reset) and MIS781_CONFIRM=yes for anything destructive.
# Without MIS781_CONFIRM a destructive action prints what it would do and stops.

set -e
RAW="https://raw.githubusercontent.com/thuc-gh/mis781-setup/main"
MYSQL_HOME="$HOME/mysql"
LABEL="com.mis781.mysqld"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SOCK="/tmp/mysql.sock"
DATA="$HOME/MIS781"
APPS="${MIS781_APPS:-/Applications}"
WB_APP="MySQL Workbench.app"
UID_=$(id -u)

echo "MIS781 setup (macOS)"
echo "===================="

if [ "$EUID" = 0 ]; then
  echo "ERROR: do not run this with sudo. Run it again WITHOUT sudo."
  exit 1
fi

# /dev/tty exists even with no terminal attached (the Actions runner), so try to open it.
HAVE_TTY=0; { : < /dev/tty; } 2>/dev/null && HAVE_TTY=1
ACTION="${MIS781_ACTION:-}"
CONFIRMED=0; [ "${MIS781_CONFIRM:-}" = yes ] && CONFIRMED=1

# Runs one of the worker scripts: a local copy when MIS781_LOCAL_SCRIPTS points
# at a checkout (the Actions test), otherwise the copy on GitHub.
worker() {  # worker <shell> <file> [args...]
  local sh="$1" f="$2"; shift 2
  if [ -n "${MIS781_LOCAL_SCRIPTS:-}" ] && [ -f "$MIS781_LOCAL_SCRIPTS/$f" ]; then
    "$sh" "$MIS781_LOCAL_SCRIPTS/$f" "$@"
  else
    local t; t=$(mktemp "${TMPDIR:-/tmp}/mis781-worker.XXXXXX")
    curl -fsSL "$RAW/$f" -o "$t" || { rm -f "$t"; echo "ERROR: could not download $f. Check your internet connection."; exit 1; }
    local rc=0
    "$sh" "$t" "$@" || rc=$?
    rm -f "$t"; return $rc
  fi
}

# ---- 1. Scan (read-only) -----------------------------------------------------
ARCH=$(uname -m)
INTEL=0; [ "$ARCH" != arm64 ] && INTEL=1

OURS=0; [ -x "$MYSQL_HOME/bin/mysqld" ] && OURS=1
OURS_RUNNING=0; OURS_FAILING=0
if [ "$OURS" = 1 ]; then
  "$MYSQL_HOME/bin/mysqladmin" --no-defaults --socket="$SOCK" ping >/dev/null 2>&1 && OURS_RUNNING=1
  if [ "$OURS_RUNNING" = 0 ]; then
    # launchd remembers the last exit code; a non-zero one means it keeps failing.
    LAST=$(launchctl print "gui/$UID_/$LABEL" 2>/dev/null | sed -n 's/.*last exit code = \([0-9-]*\).*/\1/p' | head -1)
    case "$LAST" in ''|0) ;; *) OURS_FAILING=1 ;; esac
  fi
fi

OTHER=""; OTHER_RUNNING=0
# lsof only lists this user's processes, so also probe the port itself: a server
# run by another account (root, _mysql) shows up there and nowhere else.
LISTENER_PID=$(lsof -nP -iTCP:3306 -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -1 | awk '{print $2}' || true)
PORT_BUSY=0; nc -z -w 2 127.0.0.1 3306 >/dev/null 2>&1 && PORT_BUSY=1
OURS_LISTENING=0
[ -n "$LISTENER_PID" ] && ps -o command= -p "$LISTENER_PID" 2>/dev/null | grep -q "^$MYSQL_HOME/bin/mysqld" && OURS_LISTENING=1
if [ "$PORT_BUSY" = 1 ] && [ "$OURS_LISTENING" = 0 ] && [ "$OURS_RUNNING" = 0 ]; then
  WHO=$( [ -n "$LISTENER_PID" ] && ps -o comm= -p "$LISTENER_PID" 2>/dev/null | xargs basename 2>/dev/null || echo "a server run by another account or app")
  OTHER="$WHO running on port 3306"
  OTHER_RUNNING=1
fi
if [ -z "$OTHER" ]; then
  if [ -x /usr/local/mysql/bin/mysqld ]; then OTHER="Oracle installer (/usr/local/mysql)"
  elif command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qE '^mysql(@[0-9.]+)?$'; then OTHER="Homebrew"
  elif [ -d /Applications/MAMP ]; then OTHER="MAMP"
  elif [ -d /Applications/XAMPP ]; then OTHER="XAMPP"
  elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Image}}' 2>/dev/null | grep -qi mysql; then OTHER="Docker container"
  fi
fi

WB_DEST=""; WB_VER=""
# Workbench 26 unpacks as "MySQL Workbench.app"; the older DMG installed "MySQLWorkbench.app".
for d in "$APPS" "$HOME/Applications"; do
  for app in "$WB_APP" "MySQLWorkbench.app"; do
    if [ -d "$d/$app" ]; then
      WB_DEST="$d"
      WB_VER=$(defaults read "$d/$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
      break 2
    fi
  done
done

FILES=0; [ -f "$DATA/test_db-master/employees.sql" ] && FILES=1

echo
echo "What is on this Mac ($ARCH):"
if [ "$OURS" = 1 ]; then
  if [ "$OURS_RUNNING" = 1 ]; then echo "  MySQL Server      ours, running on 127.0.0.1:3306 (~/mysql)"
  elif [ "$OURS_FAILING" = 1 ]; then echo "  MySQL Server      ours, installed but failing to start (~/mysql)"
  else echo "  MySQL Server      ours, installed but not running (~/mysql)"; fi
else
  echo "  MySQL Server      none from this unit"
fi
if [ -n "$OTHER" ]; then echo "  Other MySQL       $OTHER"; else echo "  Other MySQL       none"; fi
if [ -n "$WB_DEST" ]; then echo "  MySQL Workbench   $WB_VER ($WB_DEST)"; else echo "  MySQL Workbench   not installed"; fi
if [ "$FILES" = 1 ]; then echo "  Employees files   present (~/MIS781/test_db-master)"; else echo "  Employees files   not downloaded"; fi
echo "  Employees data    (checked when you connect)"

# ---- 2. Recommendation -------------------------------------------------------
REC=""; NOTE=""
if [ "$INTEL" = 1 ]; then
  if [ "$OURS" = 1 ] || [ -n "$OTHER" ]; then REC=load
  else REC=quit; NOTE="Intel Mac: the installer here is for Apple Silicon. See 'Intel Macs' in the README for the two downloads to install by hand, then run this again to load the data."; fi
elif [ "$OURS" = 1 ] && [ "$OTHER_RUNNING" = 1 ]; then
  REC=remove-server; NOTE="Two servers want port 3306 and the other one has it, so ours cannot start. Remove ours and use the other, or remove the other by hand and run Install again."
elif [ "$OURS" = 0 ]; then
  REC=install; [ -n "$OTHER" ] && NOTE="Install will use the existing server ($OTHER) and add Workbench and the data."
elif [ -z "$WB_DEST" ] || [ "$FILES" = 0 ]; then
  REC=install
elif [ "$OURS_FAILING" = 1 ]; then
  REC=remove-server; NOTE="The server is installed but will not start. The quickest fix is Remove server, then Install again (Workbench and the files are kept)."
else
  REC=load
fi

label() {
  case "$1" in
    install) echo "Install everything that is missing" ;;
    load) echo "Load the Employees database" ;;
    reset) echo "Reset the MySQL root password (databases are kept)" ;;
    remove-server) echo "Remove MySQL Server (then reinstall; Workbench and files are kept)" ;;
    remove-all) echo "Remove everything (server, Workbench, Employees files, downloads)" ;;
    quit) echo "Quit" ;;
  esac
}

MENU=()
[ "$INTEL" = 0 ] && MENU+=(install)
{ [ "$OURS" = 1 ] || [ -n "$OTHER" ]; } && MENU+=(load)
[ "$OURS" = 1 ] && MENU+=(reset)
{ [ "$OURS" = 1 ] || [ -n "$OTHER" ]; } && MENU+=(remove-server)
MENU+=(remove-all quit)

echo
[ -n "$NOTE" ] && { echo "$NOTE" | fold -s -w 78 | sed 's/^/  /'; echo; }
echo "Recommended: $(label "$REC")"

# ---- 3. Choose ---------------------------------------------------------------
[ "$ACTION" = scan ] && exit 0
if [ -z "$ACTION" ]; then
  if [ "$HAVE_TTY" = 0 ]; then
    echo
    echo "(No terminal to ask on. Set MIS781_ACTION to one of: ${MENU[*]} to run an action.)"
    exit 0
  fi
  echo
  DEFAULT=0
  for i in {1..${#MENU[@]}}; do
    [ "${MENU[$i]}" = "$REC" ] && DEFAULT=$i
    printf '  %d. %s\n' "$i" "$(label "${MENU[$i]}")"
  done
  while true; do
    printf 'Choose [%d]: ' "$DEFAULT"
    read -r CHOICE < /dev/tty
    [ -z "$CHOICE" ] && CHOICE=$DEFAULT
    if echo "$CHOICE" | grep -qE '^[0-9]+$' && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#MENU[@]}" ]; then
      ACTION="${MENU[$CHOICE]}"; break
    fi
    echo "  Type a number between 1 and ${#MENU[@]}."
  done
else
  if ! printf '%s\n' "${MENU[@]}" | grep -qx "$ACTION"; then
    echo "ERROR: MIS781_ACTION=$ACTION is not available on this Mac (choices: ${MENU[*]})."
    exit 1
  fi
fi
echo

# ---- 4. Act ------------------------------------------------------------------
# Destructive actions in unattended mode need MIS781_CONFIRM=yes; otherwise the
# worker runs in dry-run mode so the student sees the list and nothing changes.
confirm_flag() {
  if [ "$CONFIRMED" = 1 ]; then echo "--yes"
  elif [ -n "${MIS781_ACTION:-}" ] || [ "$HAVE_TTY" = 0 ]; then echo "--dry-run"
  fi
}

reset_password() {
  local NEWPW NEWPW2 PW_SQL PW_ESC i ROWS
  # INIT and CNF stay global: the EXIT trap below is expanded when the shell exits.
  echo "Reset the MySQL root password"
  echo "-----------------------------"
  if [ "$OURS_RUNNING" = 0 ] && [ "$OURS_FAILING" = 1 ]; then
    echo "The server is not starting at all, so a password reset will not help."
    echo "Choose 'Remove MySQL Server' and then 'Install' instead."
    exit 1
  fi
  NEWPW="${MIS781_NEW_PASSWORD:-}"
  if [ -z "$NEWPW" ]; then
    if [ "$HAVE_TTY" = 0 ]; then echo "ERROR: set MIS781_NEW_PASSWORD for an unattended reset."; exit 1; fi
    echo "Choose a NEW password for the MySQL 'root' account. >>> WRITE IT DOWN. <<<"
    while [ -z "$NEWPW" ]; do
      printf '  New root password (typing is hidden): '; IFS= read -rs NEWPW < /dev/tty; echo
      printf '  Type it again: '; IFS= read -rs NEWPW2 < /dev/tty; echo
      if [ -z "$NEWPW" ]; then echo "  It cannot be empty."; elif [ "$NEWPW" != "$NEWPW2" ]; then echo "  They do not match, try again."; NEWPW=""; fi
    done
  fi
  echo
  echo "This will:"
  echo "  - stop MySQL Server in ~/mysql (anything connected to it is disconnected)"
  echo "  - give the 'root' account the new password; the old one stops working"
  echo "  - start the server again"
  echo "  - give Workbench the new password for its connection to this server (saved in your keychain)"
  echo "  Every database on the server is kept."
  if [ "$CONFIRMED" = 0 ]; then
    if [ -n "${MIS781_ACTION:-}" ] || [ "$HAVE_TTY" = 0 ]; then
      echo; echo "Nothing was changed. (Set MIS781_CONFIRM=yes to go ahead unattended.)"; exit 0
    fi
    printf 'Continue? [y/N] '; read -r ANS < /dev/tty
    case "$ANS" in [Yy]*) ;; *) echo "Nothing was changed."; exit 0 ;; esac
  fi
  echo

  INIT=$(mktemp "${TMPDIR:-/tmp}/mis781-reset.XXXXXX"); chmod 600 "$INIT"
  CNF=$(mktemp "${TMPDIR:-/tmp}/mis781.XXXXXX"); chmod 600 "$CNF"
  trap 'rm -f "$INIT" "$CNF"' EXIT
  PW_SQL=$(printf '%s' "$NEWPW" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
  printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\nFLUSH PRIVILEGES;\n" "$PW_SQL" > "$INIT"
  PW_ESC=$(printf '%s' "$NEWPW" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '[client]\nuser=root\nhost=127.0.0.1\nport=3306\npassword="%s"\n' "$PW_ESC" > "$CNF"
  unset NEWPW NEWPW2 PW_SQL PW_ESC

  printf '[1/4] Stopping the server'
  launchctl bootout "gui/$UID_/$LABEL" >/dev/null 2>&1 || true
  # Wait for the process itself to exit, not just for the socket to close: InnoDB
  # keeps ibdata1 locked until the very end of the shutdown.
  for i in $(seq 1 60); do
    pgrep -f "^$MYSQL_HOME/bin/mysqld" >/dev/null 2>&1 || break
    [ "$i" = 20 ] && pgrep -f "^$MYSQL_HOME/bin/mysqld" | xargs kill 2>/dev/null   # not under launchd, or slow: ask it directly
    printf '.'; sleep 1
  done
  if pgrep -f "^$MYSQL_HOME/bin/mysqld" >/dev/null 2>&1; then
    echo; echo "ERROR: the running server would not stop. Restart your Mac and try again."; exit 1
  fi
  echo

  printf '[2/4] Starting it once to set the new password'
  "$MYSQL_HOME/bin/mysqld" --defaults-file="$MYSQL_HOME/my.cnf" --init-file="$INIT" >/dev/null 2>&1 &
  for i in $(seq 1 60); do
    "$MYSQL_HOME/bin/mysqladmin" --no-defaults --socket="$SOCK" ping >/dev/null 2>&1 && break
    printf '.'; sleep 1
  done
  echo
  if ! "$MYSQL_HOME/bin/mysqladmin" --defaults-extra-file="$CNF" shutdown >/dev/null 2>&1; then
    echo "ERROR: the server did not accept the new password. Last lines of ~/mysql/mysql-error.log:"
    tail -20 "$MYSQL_HOME/mysql-error.log" 2>/dev/null | sed 's/^/         /'
    pgrep -f "^$MYSQL_HOME/bin/mysqld" | xargs kill 2>/dev/null || true
    sleep 2
    launchctl bootstrap "gui/$UID_" "$PLIST" >/dev/null 2>&1 || true
    echo "       Choose 'Remove MySQL Server' and then 'Install' instead."
    exit 1
  fi
  for i in $(seq 1 30); do pgrep -f "^$MYSQL_HOME/bin/mysqld" >/dev/null || break; sleep 1; done
  rm -f "$INIT"

  printf '[3/4] Starting the server normally'
  if [ -f "$PLIST" ]; then
    launchctl bootstrap "gui/$UID_" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || true
  else
    nohup "$MYSQL_HOME/bin/mysqld" --defaults-file="$MYSQL_HOME/my.cnf" >/dev/null 2>&1 &
  fi
  for i in $(seq 1 60); do
    "$MYSQL_HOME/bin/mysqladmin" --no-defaults --socket="$SOCK" ping >/dev/null 2>&1 && break
    printf '.'; sleep 1
  done
  echo

  echo "[4/4] Checking the new password..."
  if "$MYSQL_HOME/bin/mysql" --defaults-extra-file="$CNF" -N -s -e 'SELECT 1' >/dev/null 2>&1; then
    ROWS=$("$MYSQL_HOME/bin/mysql" --defaults-extra-file="$CNF" -N -s -e "SELECT COUNT(*) FROM employees.employees" 2>/dev/null || echo 0)
    echo "  MySQL Server      OK  (running, new root password works)"
    if [ "$ROWS" = 300024 ]; then echo "  Employees data    OK  (300024 employees, untouched)"; else echo "  Employees data    not loaded (run this again and choose 'Load the Employees database')"; fi
    [ ! -f "$PLIST" ] && echo "  NOTE: no autostart entry was found; choose 'Install' once to put it back."
    echo
    # Workbench keeps the root password in the keychain, so give it the new one.
    ( MIS781_CNF="$CNF" worker zsh workbench-connection.sh ) || true
    echo
    echo "Done. Open MySQL Workbench and click the 'MIS781' connection; if it asks for a password, use the new one."
  else
    echo "ERROR: the server is back up but the new password does not work."
    echo "       Choose 'Remove MySQL Server' and then 'Install' instead."
    exit 1
  fi
}

case "$ACTION" in
  install)       worker zsh install.sh ;;
  load)          worker zsh import-employees.sh ;;
  reset)         reset_password ;;
  remove-server) worker bash uninstall-mysql.sh $(confirm_flag) ;;
  remove-all)    worker bash uninstall-mysql.sh --all $(confirm_flag) ;;
  quit)          echo "Nothing was changed."; exit 0 ;;
esac
