#!/bin/bash
#
# uninstall-mysql.sh
# Detects and completely removes MySQL on macOS, whatever the install method:
#   - The MIS781 install.sh layout (~/mysql plus a launchd agent, no admin needed)
#   - Homebrew (mysql, mysql@8.4, mysql-client, ... on Apple Silicon or Intel)
#   - Official Oracle DMG/PKG installer (/usr/local/mysql*)
#   - Leftovers: launch daemons, data dirs, configs, package receipts
#
# Workbench and the Employees files are kept unless --all is given.
#
# Usage:
#   bash uninstall-mysql.sh            # interactive (asks before deleting)
#   bash uninstall-mysql.sh --dry-run  # show what would be removed, change nothing
#   bash uninstall-mysql.sh --yes      # no confirmation prompt (MIS781_CONFIRM=yes does the same)
#   bash uninstall-mysql.sh --all      # also remove Workbench, its saved connections,
#                                      # ~/MIS781 and the downloaded installers
#
# Or straight from GitHub without downloading:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thuc-gh/mis781-setup/main/uninstall-mysql.sh)"
#
# WARNING: this permanently deletes all MySQL databases on the machine.
# Back up first if needed:  mysqldump -u root -p --all-databases > backup.sql
#
set -u

DRY_RUN=false
ASSUME_YES=false
ALL=false
[ "${MIS781_CONFIRM:-}" = yes ] && ASSUME_YES=true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y)  ASSUME_YES=true ;;
    --all)     ALL=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done
APPS="${MIS781_APPS:-/Applications}"
WB_APP="MySQL Workbench.app"

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this script with sudo. Run it as your normal user;"
  echo "it will ask for your password when it needs admin rights."
  exit 1
fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }

run() {
  # Execute a command, or just print it in dry-run mode
  if $DRY_RUN; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

sudo_rm_rf() {
  for path in "$@"; do
    [ -e "$path" ] || continue
    run sudo rm -rf "$path"
  done
}

# ---------------------------------------------------------------------------
# 1. DETECT
# ---------------------------------------------------------------------------
bold "Scanning for MySQL installations..."

FOUND_ANY=false

# --- MIS781 home install (~/mysql + launch agent) ---
HOME_LABEL="com.mis781.mysqld"
HOME_PLIST="$HOME/Library/LaunchAgents/$HOME_LABEL.plist"
HOME_DIRS=()
[ -d "$HOME/mysql" ] && HOME_DIRS+=("$HOME/mysql")
[ -f "$HOME_PLIST" ] && HOME_DIRS+=("$HOME_PLIST")
if [ "${#HOME_DIRS[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: MySQL Server from this unit in your home folder (ours)"
  for d in "${HOME_DIRS[@]}"; do info "$d"; done
fi

# --- Homebrew ---
BREW_FORMULAE=()
BREW_PREFIX=""
if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
  while IFS= read -r f; do
    [ -n "$f" ] && BREW_FORMULAE+=("$f")
  done < <(brew list --formula 2>/dev/null | grep -E '^mysql(@[0-9.]+)?$|^mysql-client(@[0-9.]+)?$')
fi
if [ "${#BREW_FORMULAE[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: Homebrew installation (other, not from this unit)"
  for f in "${BREW_FORMULAE[@]}"; do info "formula: $f"; done
fi

# --- Homebrew data dirs (may exist even if formula was already uninstalled) ---
BREW_DATA_DIRS=()
for d in "/opt/homebrew/var/mysql" "/usr/local/var/mysql" "/opt/homebrew/etc/my.cnf" "/usr/local/etc/my.cnf"; do
  [ -e "$d" ] && BREW_DATA_DIRS+=("$d")
done
if [ "${#BREW_DATA_DIRS[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: Homebrew MySQL data/config (other)"
  for d in "${BREW_DATA_DIRS[@]}"; do info "$d"; done
fi

# --- Oracle DMG installer ---
DMG_DIRS=()
for d in /usr/local/mysql /usr/local/mysql-*; do
  # -e is false for broken symlinks, so check -L too
  { [ -e "$d" ] || [ -L "$d" ]; } && DMG_DIRS+=("$d")
done
if [ "${#DMG_DIRS[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: Oracle DMG installation (other, not from this unit)"
  for d in "${DMG_DIRS[@]}"; do info "$d"; done
fi

# --- Launch daemons / agents ---
LAUNCH_ITEMS=()
for d in /Library/LaunchDaemons /Library/LaunchAgents; do
  for p in "$d"/*mysql*; do
    [ -e "$p" ] && LAUNCH_ITEMS+=("$p")
  done
done
if [ "${#LAUNCH_ITEMS[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: launch daemons/agents"
  for p in "${LAUNCH_ITEMS[@]}"; do info "$p"; done
fi

# --- Misc system leftovers ---
MISC_PATHS=()
for p in "/Library/PreferencePanes/MySQL.prefPane" "/Library/StartupItems/MySQLCOM" \
         "/etc/my.cnf" "/etc/mysql" "/var/mysql"; do
  [ -e "$p" ] && MISC_PATHS+=("$p")
done
if [ "${#MISC_PATHS[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: system leftovers"
  for p in "${MISC_PATHS[@]}"; do info "$p"; done
fi

# --- Package receipts ---
RECEIPTS=()
while IFS= read -r r; do
  [ -n "$r" ] && RECEIPTS+=("$r")
done < <(pkgutil --pkgs 2>/dev/null | grep -i mysql)
if [ "${#RECEIPTS[@]}" -gt 0 ]; then
  FOUND_ANY=true
  bold "Found: installer receipts"
  for r in "${RECEIPTS[@]}"; do info "$r"; done
fi

# --- Running processes ---
RUNNING=false
if pgrep -x mysqld >/dev/null 2>&1 || pgrep -f mysqld_safe >/dev/null 2>&1; then
  RUNNING=true
  FOUND_ANY=true
  bold "Found: mysqld is currently running"
fi

# --- Things this script deliberately does NOT touch ---
if [ -d "/Applications/MAMP" ] || [ -d "/Applications/XAMPP" ]; then
  bold "Note: MAMP/XAMPP detected — its bundled MySQL is left alone."
  info "Remove the whole app from /Applications if you want it gone."
fi
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Image}}' 2>/dev/null | grep -qi mysql; then
  bold "Note: a MySQL Docker container is running — left alone (docker rm it yourself)."
fi

# --- Everything else from this unit (only with --all) ---
ALL_ITEMS=()
if $ALL; then
  for d in "$APPS" "$HOME/Applications"; do
    for app in "$WB_APP" "MySQLWorkbench.app"; do
      [ -d "$d/$app" ] && ALL_ITEMS+=("$d/$app")
    done
  done
  [ -e "$HOME/Library/Application Support/MySQL/Workbench" ] && ALL_ITEMS+=("$HOME/Library/Application Support/MySQL/Workbench")
  [ -e "$HOME/MIS781" ] && ALL_ITEMS+=("$HOME/MIS781")
  for f in mysql-26.10.0-macos15-arm64.tar.gz mysql-workbench-26.10.0-macos-arm64.zip test_db-master.zip; do
    [ -e "$HOME/Downloads/$f" ] && ALL_ITEMS+=("$HOME/Downloads/$f")
  done
  if [ "${#ALL_ITEMS[@]}" -gt 0 ]; then
    FOUND_ANY=true
    bold "Found: Workbench, saved connections, Employees files and downloads (removed with --all)"
    for p in "${ALL_ITEMS[@]}"; do info "$p"; done
  fi
fi

if ! $FOUND_ANY; then
  echo
  bold "No MySQL installation found. Nothing to do."
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. CONFIRM
# ---------------------------------------------------------------------------
echo
bold "WARNING: this will permanently delete ALL MySQL databases on this machine,"
bold "         plus everything listed above."
echo "         Back up first if needed:  mysqldump --all-databases > backup.sql"
echo
if $DRY_RUN && [ -n "${MIS781_ACTION:-}" ] && [ "${MIS781_CONFIRM:-}" != yes ]; then
  # Reached through the setup script unattended without MIS781_CONFIRM=yes.
  bold "Nothing was changed. Set MIS781_CONFIRM=yes to remove the items above unattended."
  exit 0
elif $DRY_RUN; then
  bold "Dry run: showing what would be done, changing nothing."
elif ! $ASSUME_YES; then
  printf 'Type "yes" to uninstall everything listed above: '
  # Read from the terminal, not stdin — stdin is the script itself under `curl | bash`
  if [ -r /dev/tty ]; then
    read -r answer < /dev/tty
  else
    read -r answer
  fi
  if [ "$answer" != "yes" ]; then
    echo "Aborted. Nothing was changed."
    exit 0
  fi
fi
echo

# ---------------------------------------------------------------------------
# 3. STOP SERVICES AND PROCESSES
# ---------------------------------------------------------------------------
bold "Stopping MySQL..."

for f in "${BREW_FORMULAE[@]+"${BREW_FORMULAE[@]}"}"; do
  run brew services stop "$f" 2>/dev/null || true
done

for p in "${LAUNCH_ITEMS[@]+"${LAUNCH_ITEMS[@]}"}"; do
  run sudo launchctl bootout system "$p" 2>/dev/null || \
    run sudo launchctl unload "$p" 2>/dev/null || true
done

if [ -f "$HOME_PLIST" ] || launchctl print "gui/$(id -u)/$HOME_LABEL" >/dev/null 2>&1; then
  run launchctl bootout "gui/$(id -u)/$HOME_LABEL" 2>/dev/null || \
    run launchctl unload "$HOME_PLIST" 2>/dev/null || true
fi

if $RUNNING; then
  run sudo pkill -x mysqld 2>/dev/null || true
  run sudo pkill -f mysqld_safe 2>/dev/null || true
  $DRY_RUN || sleep 2
  if ! $DRY_RUN && pgrep -x mysqld >/dev/null 2>&1; then
    info "mysqld still running, forcing..."
    run sudo pkill -9 -x mysqld 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 4. REMOVE
# ---------------------------------------------------------------------------
bold "Removing files..."

for d in "${HOME_DIRS[@]+"${HOME_DIRS[@]}"}"; do
  run rm -rf "${d:?}"
done
# PATH line that install.sh added
if grep -q 'MIS781' "$HOME/.zshrc" 2>/dev/null; then
  if $DRY_RUN; then
    info "[dry-run] remove the MIS781 PATH lines from ~/.zshrc"
  else
    cp "$HOME/.zshrc" "$HOME/.zshrc.mis781-backup"
    sed -i '' -e '/^# MySQL command-line tools for MIS781/d' -e '\|^export PATH="\$HOME/mysql/bin:\$PATH"$|d' "$HOME/.zshrc"
    info "removed the MIS781 PATH lines from ~/.zshrc (backup: ~/.zshrc.mis781-backup)"
  fi
fi

for f in "${BREW_FORMULAE[@]+"${BREW_FORMULAE[@]}"}"; do
  run brew uninstall --force "$f"
done

sudo_rm_rf "${BREW_DATA_DIRS[@]+"${BREW_DATA_DIRS[@]}"}"
sudo_rm_rf "${DMG_DIRS[@]+"${DMG_DIRS[@]}"}"
sudo_rm_rf "${LAUNCH_ITEMS[@]+"${LAUNCH_ITEMS[@]}"}"
sudo_rm_rf "${MISC_PATHS[@]+"${MISC_PATHS[@]}"}"

for r in "${RECEIPTS[@]+"${RECEIPTS[@]}"}"; do
  run sudo pkgutil --forget "$r"
done

# Per-user config (harmless to keep, but "complete uninstall" means complete)
if [ -f "$HOME/.my.cnf" ]; then
  run rm -f "$HOME/.my.cnf"
fi

# --all: Workbench and everything else this unit put on the Mac
for p in "${ALL_ITEMS[@]+"${ALL_ITEMS[@]}"}"; do
  # Try as the user first; a bundle installed by an Oracle .pkg has root-owned
  # files inside, so fall back to sudo when anything is left.
  run rm -rf "${p:?}" 2>/dev/null || true
  if ! $DRY_RUN && [ -e "$p" ]; then
    run sudo rm -rf "${p:?}"
  fi
done

# ---------------------------------------------------------------------------
# 5. VERIFY
# ---------------------------------------------------------------------------
echo
bold "Verifying..."
if $DRY_RUN; then
  info "dry run complete — nothing was changed."
  exit 0
fi

OK=true
if pgrep -x mysqld >/dev/null 2>&1; then
  info "FAIL: mysqld is still running"
  OK=false
fi
LEFTOVER="$(command -v mysql 2>/dev/null || true)"
if [ -n "$LEFTOVER" ]; then
  info "NOTE: a 'mysql' binary is still on PATH at $LEFTOVER"
  info "(open a NEW terminal window — this may just be a stale shell cache)"
fi
for d in "$HOME/mysql" "$HOME_PLIST" /usr/local/mysql /opt/homebrew/var/mysql /usr/local/var/mysql "${ALL_ITEMS[@]+"${ALL_ITEMS[@]}"}"; do
  if [ -e "$d" ]; then
    info "FAIL: $d still exists"
    OK=false
  fi
done

if $OK; then
  if $ALL; then bold "MySQL, Workbench and the MIS781 files have been completely removed."; else bold "MySQL Server has been completely removed. Workbench and the Employees files were kept."; fi
  echo "If your shell still autocompletes 'mysql', run: hash -r  (or open a new terminal)."
else
  bold "Some items could not be removed — see FAIL lines above."
  exit 1
fi
