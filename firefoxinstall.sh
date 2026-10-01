#!/bin/sh

# Firefox DEB installer for Ubuntu 26.04 LTS
#
# Migration order:
#   1. Prepare and verify Mozilla APT repository
#   2. Verify Firefox DEB is available
#   3. Remove Firefox Snap
#   4. Install Firefox DEB
#   5. Verify final installation
#
# Run with:
#   sudo sh firefoxinstall.sh

set -eu

MOZILLA_KEY_URL="https://packages.mozilla.org/apt/repo-signing-key.gpg"
MOZILLA_KEY="/etc/apt/keyrings/packages.mozilla.org.asc"
MOZILLA_SOURCE="/etc/apt/sources.list.d/mozilla.sources"
MOZILLA_PREFS="/etc/apt/preferences.d/mozilla"

EXPECTED_FINGERPRINT="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"

echo
echo "=============================================="
echo " Firefox DEB Installer - Ubuntu 26.04 LTS"
echo "=============================================="
echo

# ==================================================
# 1. REQUIRE ROOT
# ==================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo."
    echo
    echo "Use:"
    echo "  sudo sh firefoxinstall.sh"
    echo
    exit 1
fi

# ==================================================
# 2. VERIFY UBUNTU 26.04
# ==================================================

if [ ! -r /etc/os-release ]; then
    echo "ERROR: Cannot determine the operating system."
    exit 1
fi

. /etc/os-release

if [ "${ID:-}" != "ubuntu" ]; then
    echo "ERROR: This script is intended for Ubuntu."
    echo
    echo "Detected OS: ${ID:-unknown}"
    exit 1
fi

if [ "${VERSION_ID:-}" != "26.04" ]; then
    echo "ERROR: This script is intended for Ubuntu 26.04 LTS."
    echo
    echo "Detected Ubuntu version: ${VERSION_ID:-unknown}"
    exit 1
fi

echo "OK: Ubuntu 26.04 LTS detected."
echo

# ==================================================
# 3. CHECK REQUIRED COMMANDS
# ==================================================

echo "Checking required commands..."

for command in \
    apt-get \
    apt-cache \
    dpkg \
    dpkg-query \
    wget \
    gpg \
    awk \
    grep \
    install \
    mktemp \
    getent \
    id \
    cp \
    chown \
    date
do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo
        echo "ERROR: Required command not found: $command"
        echo
        exit 1
    fi
done

echo "OK: Required commands are available."
echo

# ==================================================
# 4. DETECT NORMAL DESKTOP USER
# ==================================================

TARGET_USER="${SUDO_USER:-}"

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then

    TARGET_USER=""
    TARGET_HOME=""
    TARGET_GROUP=""

    echo "WARNING: Normal desktop user could not be determined."
    echo "Snap profile backup will be skipped."
    echo

else

    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_GROUP="$(id -gn "$TARGET_USER")"

    if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
        echo
        echo "ERROR: Cannot determine home directory for:"
        echo "  $TARGET_USER"
        echo
        exit 1
    fi

    echo "Desktop user : $TARGET_USER"
    echo "Home         : $TARGET_HOME"
    echo "Primary group: $TARGET_GROUP"
    echo
fi

# ==================================================
# 5. VERIFY FIREFOX APT CONFIGURATION
# ==================================================

verify_firefox_apt_configuration() {

    FIREFOX_POLICY="$(apt-cache policy firefox)"

    # --------------------------------------------------
    # Verify Firefox candidate exists
    # --------------------------------------------------

    FIREFOX_CANDIDATE="$(
        printf '%s\n' "$FIREFOX_POLICY" |
        awk -F': ' '
            /^[[:space:]]*Candidate:/ {
                print $2
                exit
            }
        '
    )"

    if [ -z "$FIREFOX_CANDIDATE" ] ||
       [ "$FIREFOX_CANDIDATE" = "(none)" ]; then

        echo
        echo "ERROR: No Firefox APT candidate is available."
        return 1
    fi

    # --------------------------------------------------
    # Verify Mozilla repository appears in policy
    # --------------------------------------------------

    if ! printf '%s\n' "$FIREFOX_POLICY" |
        grep -q "https://packages.mozilla.org/apt"
    then

        echo
        echo "ERROR: Mozilla Firefox repository is not present."
        return 1
    fi

    # --------------------------------------------------
    # Verify Ubuntu Snap-transition package is -1
    #
    # Actual Ubuntu package versions look like:
    #
    #   1:1snap1-0ubuntu9.1 -1
    #   1:1snap1-0ubuntu8   -1
    #
    # IMPORTANT:
    # The correct pattern is "1:1snap", NOT "1:snap".
    # --------------------------------------------------

    UBUNTU_FIREFOX_PRIORITY="$(
        printf '%s\n' "$FIREFOX_POLICY" |
        awk '
            /^[[:space:]]+1:1snap/ {
                print $2
                exit
            }
        '
    )"

    if [ "$UBUNTU_FIREFOX_PRIORITY" != "-1" ]; then

        echo
        echo "ERROR: Ubuntu Firefox Snap-transition package"
        echo "       is not pinned to -1."
        echo
        echo "Detected priority:"
        echo "  ${UBUNTU_FIREFOX_PRIORITY:-not found}"
        echo
        echo "Configured APT preferences:"
        echo "----------------------------------------------"
        cat "$MOZILLA_PREFS"
        echo "----------------------------------------------"
        echo

        return 1
    fi

    # --------------------------------------------------
    # Verify our Mozilla pin configuration
    # --------------------------------------------------

    if [ ! -r "$MOZILLA_PREFS" ]; then

        echo
        echo "ERROR: Mozilla APT preferences file is missing."
        return 1
    fi

    if ! grep -q \
        "Pin: origin packages.mozilla.org" \
        "$MOZILLA_PREFS"
    then

        echo
        echo "ERROR: Mozilla repository pin is missing."
        return 1
    fi

    if ! grep -q \
        "Pin-Priority: 1000" \
        "$MOZILLA_PREFS"
    then

        echo
        echo "ERROR: Mozilla repository priority 1000 is missing."
        return 1
    fi

    # --------------------------------------------------
    # Verify Ubuntu pin configuration
    # --------------------------------------------------

    if ! grep -q \
        "Pin: release o=Ubuntu" \
        "$MOZILLA_PREFS"
    then

        echo
        echo "ERROR: Ubuntu Firefox pin rule is missing."
        return 1
    fi

    if ! grep -q \
        "Pin-Priority: -1" \
        "$MOZILLA_PREFS"
    then

        echo
        echo "ERROR: Ubuntu Firefox pin priority -1 is missing."
        return 1
    fi

    # --------------------------------------------------
    # Success
    # --------------------------------------------------

    echo "OK: Firefox candidate: $FIREFOX_CANDIDATE"
    echo "OK: Mozilla repository is available."
    echo "OK: Mozilla repository priority is 1000."
    echo "OK: Ubuntu Snap-transition Firefox is pinned to -1."

    return 0
}

# ==================================================
# 6. CHECK FIREFOX IS NOT RUNNING
# ==================================================

echo "[1/10] Checking whether Firefox is running..."

FIREFOX_RUNNING="no"

if command -v pgrep >/dev/null 2>&1; then

    if pgrep -x firefox >/dev/null 2>&1; then
        FIREFOX_RUNNING="yes"
    fi

    if pgrep -x firefox-bin >/dev/null 2>&1; then
        FIREFOX_RUNNING="yes"
    fi

fi

if [ "$FIREFOX_RUNNING" = "yes" ]; then

    echo
    echo "ERROR: Firefox is currently running."
    echo
    echo "Please completely close Firefox and run this script again."
    echo

    exit 1
fi

echo "OK: Firefox is not running."
echo

# ==================================================
# 7. CREATE APT KEYRING DIRECTORY
# ==================================================

echo "[2/10] Creating APT keyring directory..."

install -d -m 0755 /etc/apt/keyrings

echo "OK."
echo

# ==================================================
# 8. DOWNLOAD AND VERIFY MOZILLA SIGNING KEY
# ==================================================

echo "[3/10] Downloading Mozilla signing key..."

TMP_KEY="$(mktemp)"

cleanup() {
    rm -f "$TMP_KEY"
}

trap cleanup EXIT HUP INT TERM

if ! wget -q \
    "$MOZILLA_KEY_URL" \
    -O "$TMP_KEY"
then

    echo
    echo "ERROR: Failed to download Mozilla signing key."
    echo

    exit 1
fi

if [ ! -s "$TMP_KEY" ]; then

    echo
    echo "ERROR: Downloaded Mozilla signing key is empty."
    echo

    exit 1
fi

echo "Verifying Mozilla signing key fingerprint..."

KEY_FINGERPRINT="$(
    gpg \
        --show-keys \
        --with-colons \
        "$TMP_KEY" 2>/dev/null |
    awk -F: '
        $1 == "fpr" {
            print $10
            exit
        }
    '
)"

if [ "$KEY_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then

    echo
    echo "ERROR: Mozilla signing key fingerprint does not match."
    echo
    echo "Expected:"
    echo "  $EXPECTED_FINGERPRINT"
    echo
    echo "Received:"
    echo "  ${KEY_FINGERPRINT:-none}"
    echo
    echo "The key will NOT be installed."
    echo

    exit 1
fi

echo "OK: Mozilla signing key fingerprint verified."

install -m 0644 "$TMP_KEY" "$MOZILLA_KEY"

echo

# ==================================================
# 9. CONFIGURE MOZILLA REPOSITORY
# ==================================================

echo "[4/10] Configuring Mozilla APT repository..."

cat > "$MOZILLA_SOURCE" <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF

chmod 0644 "$MOZILLA_SOURCE"

echo "OK: Mozilla repository configured."
echo

# ==================================================
# 10. CONFIGURE APT PINNING
# ==================================================

echo "[5/10] Configuring APT pinning..."

cat > "$MOZILLA_PREFS" <<'EOF'
# Prefer packages from Mozilla's official APT repository.
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

# Prevent Ubuntu's Firefox Snap-transition package
# from being selected by APT.
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF

chmod 0644 "$MOZILLA_PREFS"

echo "Mozilla repository priority: 1000"
echo "Ubuntu Firefox priority:      -1"
echo

# ==================================================
# 11. UPDATE APT
# ==================================================

echo "[6/10] Updating APT package lists..."

if ! apt-get update; then

    echo
    echo "ERROR: apt-get update failed."
    echo
    echo "Firefox Snap has NOT been removed."
    echo

    exit 1
fi

echo
echo "OK: APT package lists updated."
echo

# ==================================================
# 12. VERIFY MOZILLA FIREFOX CANDIDATE
# ==================================================

echo "[7/10] Verifying Mozilla Firefox DEB candidate..."
echo

apt-cache policy firefox

echo

if ! verify_firefox_apt_configuration; then

    echo
    echo "Firefox Snap has NOT been removed."
    echo

    exit 1
fi

echo

# ==================================================
# 13. DETECT FIREFOX SNAP
# ==================================================

echo "[8/10] Checking Firefox Snap..."

SNAP_INSTALLED="no"

if command -v snap >/dev/null 2>&1; then

    if snap list firefox >/dev/null 2>&1; then
        SNAP_INSTALLED="yes"
    fi

fi

if [ "$SNAP_INSTALLED" = "yes" ]; then

    echo "Firefox Snap is installed."

else

    echo "Firefox Snap is not installed."

fi

echo

# ==================================================
# 14. BACKUP SNAP PROFILE
# ==================================================

if [ "$SNAP_INSTALLED" = "yes" ]; then

    if [ -n "$TARGET_USER" ]; then

        SNAP_FIREFOX_DIR="$TARGET_HOME/snap/firefox"

        if [ -d "$SNAP_FIREFOX_DIR" ]; then

            BACKUP_BASE="$TARGET_HOME/firefox-snap-backup"
            BACKUP_DIR="$BACKUP_BASE"

            if [ -e "$BACKUP_DIR" ]; then

                BACKUP_DIR="${BACKUP_BASE}-$(date +%Y%m%d-%H%M%S)"

            fi

            echo "Backing up Firefox Snap data..."
            echo
            echo "Source:"
            echo "  $SNAP_FIREFOX_DIR"
            echo
            echo "Destination:"
            echo "  $BACKUP_DIR"
            echo

            if ! mkdir -p "$BACKUP_DIR"; then

                echo
                echo "ERROR: Could not create backup directory."
                echo
                echo "Firefox Snap has NOT been removed."
                echo

                exit 1
            fi

            if ! cp -a "$SNAP_FIREFOX_DIR" "$BACKUP_DIR/"; then

                echo
                echo "ERROR: Could not back up Firefox Snap data."
                echo
                echo "Firefox Snap has NOT been removed."
                echo

                exit 1
            fi

            if ! chown -R "$TARGET_USER:$TARGET_GROUP" "$BACKUP_DIR"; then

                echo
                echo "ERROR: Could not set backup ownership."
                echo
                echo "Firefox Snap has NOT been removed."
                echo

                exit 1
            fi

            echo "OK: Firefox Snap data backed up."
            echo

        else

            echo "No Firefox Snap profile directory found."
            echo

        fi

    else

        echo "WARNING: Desktop user could not be determined."
        echo "Snap profile backup will be skipped."
        echo

    fi

fi

# ==================================================
# 15. REMOVE FIREFOX SNAP
# ==================================================

echo "=============================================="
echo " Removing Firefox Snap"
echo "=============================================="
echo

if [ "$SNAP_INSTALLED" = "yes" ]; then

    if ! snap remove firefox; then

        echo
        echo "ERROR: Failed to remove Firefox Snap."
        echo
        echo "The Mozilla APT repository is configured,"
        echo "but Firefox DEB has NOT been installed."
        echo

        exit 1
    fi

    echo
    echo "OK: Firefox Snap removed."

else

    echo "Firefox Snap was already absent."

fi

echo

# ==================================================
# 16. INSTALL FIREFOX DEB
# ==================================================

echo "=============================================="
echo " Installing Firefox DEB"
echo "=============================================="
echo

if ! apt-get install -y firefox; then

    echo
    echo "=============================================="
    echo " ERROR: Firefox DEB installation failed"
    echo "=============================================="
    echo
    echo "IMPORTANT:"
    echo "The Firefox Snap has already been removed."
    echo
    echo "The Mozilla APT repository remains configured."
    echo
    echo "Retry with:"
    echo
    echo "  sudo apt-get update"
    echo "  sudo apt-get install firefox"
    echo

    exit 1
fi

echo
echo "OK: Firefox DEB installed."
echo

# ==================================================
# 17. FINAL VERIFICATION
# ==================================================

echo "=============================================="
echo " Performing final verification"
echo "=============================================="
echo

# --------------------------------------------------
# Verify package installation
# --------------------------------------------------

echo "Checking installed Firefox package..."

FIREFOX_STATUS="$(
    dpkg-query \
        -W \
        -f='${Status}' \
        firefox 2>/dev/null || true
)"

if [ "$FIREFOX_STATUS" != "install ok installed" ]; then

    echo
    echo "ERROR: Firefox is not correctly installed."
    echo

    exit 1
fi

FIREFOX_VERSION="$(
    dpkg-query \
        -W \
        -f='${Version}' \
        firefox
)"

echo "Installed version: $FIREFOX_VERSION"
echo

# --------------------------------------------------
# Verify executable
# --------------------------------------------------

echo "Checking Firefox executable..."

if [ ! -x /usr/bin/firefox ]; then

    echo
    echo "ERROR: /usr/bin/firefox does not exist"
    echo "or is not executable."
    echo

    exit 1
fi

echo "OK: /usr/bin/firefox"
echo

# --------------------------------------------------
# Verify Snap is gone
# --------------------------------------------------

echo "Checking Firefox Snap..."

if command -v snap >/dev/null 2>&1 &&
   snap list firefox >/dev/null 2>&1
then

    echo
    echo "ERROR: Firefox Snap is still installed."
    echo

    exit 1
fi

echo "OK: Firefox Snap is not installed."
echo

# --------------------------------------------------
# Verify final APT configuration
# --------------------------------------------------

echo "Checking final Firefox APT configuration..."
echo

apt-cache policy firefox

echo

if ! verify_firefox_apt_configuration; then

    echo
    echo "ERROR: Final Firefox APT configuration verification failed."
    echo

    exit 1
fi

echo

# --------------------------------------------------
# Verify installed version equals APT candidate
# --------------------------------------------------

FINAL_POLICY="$(apt-cache policy firefox)"

FINAL_CANDIDATE="$(
    printf '%s\n' "$FINAL_POLICY" |
    awk -F': ' '
        /^[[:space:]]*Candidate:/ {
            print $2
            exit
        }
    '
)"

if [ "$FINAL_CANDIDATE" != "$FIREFOX_VERSION" ]; then

    echo
    echo "ERROR: Installed Firefox version does not match"
    echo "the current APT candidate."
    echo
    echo "Installed:"
    echo "  $FIREFOX_VERSION"
    echo
    echo "Candidate:"
    echo "  $FINAL_CANDIDATE"
    echo

    exit 1
fi

echo "OK: Installed Firefox matches APT candidate."
echo

# ==================================================
# FINAL SUCCESS
# ==================================================

echo "=============================================="
echo " Firefox DEB installation completed"
echo "=============================================="
echo
echo "Firefox version:"
echo "  $FIREFOX_VERSION"
echo
echo "Firefox source:"
echo "  Mozilla official APT repository"
echo
echo "Firefox Snap:"
echo "  NOT INSTALLED"
echo
echo "Ubuntu Snap-transition Firefox:"
echo "  BLOCKED (Pin-Priority -1)"
echo
echo "Mozilla repository:"
echo "  PRIORITY 1000"
echo
echo "Future Firefox updates:"
echo
echo "  sudo apt update"
echo "  sudo apt upgrade"
echo
echo "The Firefox Snap should not replace the Mozilla DEB."
echo
