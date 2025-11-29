#!/bin/zsh

# LightroomToResolve macOS Installer Build Script
# - Lightroom Plugin & Resolve Script packaging
# - Environment variable setup via postinstall
# - Code Signing -> Notarization -> Stapling

set -e
set -u
set -o pipefail

#============================================
#  Colors & Helper Functions
#============================================
color_cyan="\033[36m"
color_yellow="\033[33m"
color_green="\033[32m"
color_red="\033[31m"
color_gray="\033[90m"
color_reset="\033[0m"

echo_header() {
    echo ""
    echo -e "${color_cyan}============================================${color_reset}"
    echo -e "${color_cyan}   $1${color_reset}"
    echo -e "${color_cyan}============================================${color_reset}"
    echo ""
}

echo_step() {
    echo -e "${color_yellow}► $1${color_reset}"
}

echo_success() {
    echo -e "${color_green}✓ $1${color_reset}"
}

echo_error() {
    echo -e "${color_red}✗ $1${color_reset}" 1>&2
}

#============================================
#  Configuration
#============================================
VERSION="1.0.0" # Update as needed
BUILD_DATE="$(date +%Y-%m-%d)"
PKG_ID_BASE="com.yourname.lightroomtoresolve"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
OUTPUT_DIR="${ROOT_DIR}/releases/${VERSION}/macOS"

LR_PLUGIN_SRC="${ROOT_DIR}/lightroom-plugin/SendToResolve.lrplugin"
RESOLVE_SCRIPT_SRC="${ROOT_DIR}/resolve-script/LightroomToResolve.lua"

# Environment variables for Signing/Notarization
# INSTALLER_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
# APPLE_API_KEY_PATH / APPLE_API_KEY_ID / APPLE_API_ISSUER or NOTARYTOOL_PROFILE

echo_header "LightroomToResolve ${VERSION} Installer Build"

echo_step "Creating output directories..."
mkdir -p "${OUTPUT_DIR}"
PKG_WORK_DIR="${OUTPUT_DIR}/pkgwork"
# Clean up previous build artifacts to prevent stale files from being packaged
if [[ -d "${PKG_WORK_DIR}" ]]; then
    rm -rf "${PKG_WORK_DIR}"
fi
mkdir -p "${PKG_WORK_DIR}"
echo_success "Output directories created"

#============================================
# Step 1: Prepare Component Packages
#============================================
echo_header "Step 1: Creating Component Packages"

# --- 1. Lightroom Plugin PKG ---
echo_step "Creating Lightroom Plugin PKG..."
PKGROOT_LR="${PKG_WORK_DIR}/root_lr"
# Lightroom Classic only auto-loads modules that live inside the user's
# ~/Library/Application Support/Adobe/Lightroom/Modules directory. Because an
# Installer.pkg cannot target an arbitrary user's home directory at build time,
# we stage the plugin under /Library/Application Support/LightroomToResolve and
# let the postinstall script replicate it into the active user's home later.
LR_PLUGIN_NAME="$(basename "${LR_PLUGIN_SRC}")"
LR_PLUGIN_STAGE_ROOT="/Library/Application Support/LightroomToResolve"
LR_PLUGIN_STAGE_PATH="${LR_PLUGIN_STAGE_ROOT}/PluginPayload"
mkdir -p "${PKGROOT_LR}${LR_PLUGIN_STAGE_PATH}"

RESOLVE_SCRIPT_NAME="$(basename "${RESOLVE_SCRIPT_SRC}")"
RESOLVE_SCRIPT_STAGE_ROOT="/Library/Application Support/LightroomToResolve"
RESOLVE_SCRIPT_STAGE_PATH="${RESOLVE_SCRIPT_STAGE_ROOT}/ResolvePayload"

if [[ ! -d "${LR_PLUGIN_SRC}" ]]; then
    echo_error "Plugin source not found: ${LR_PLUGIN_SRC}"
    exit 1
fi
cp -R "${LR_PLUGIN_SRC}" "${PKGROOT_LR}${LR_PLUGIN_STAGE_PATH}/"

PKG_LR="${PKG_WORK_DIR}/LightroomPlugin.pkg"

# Create scripts dir early for LightroomPlugin.pkg
SCRIPTS_DIR="${PKG_WORK_DIR}/scripts"
mkdir -p "${SCRIPTS_DIR}"

# postinstall: Environment Variables setup
# Note: Setting persistent env vars for GUI apps on macOS is tricky.
# launchctl setenv works for current session but not persistent.
# /etc/paths.d or /etc/launchd.conf (deprecated) or creating a launch agent.
# Here we use /etc/paths.d logic for PYTHONPATH (if possible) and launchctl for immediate effect.
# For standard users, shell config (.zshrc) is best but tough to touch from root installer.
#
# STRATEGY: Write a launch agent plist to /Library/LaunchAgents to set env vars for GUI sessions.

LAUNCH_AGENT_PATH="/Library/LaunchAgents/${PKG_ID_BASE}.env.plist"
RESOLVE_API_PATH="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
RESOLVE_LIB_PATH="/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
LR_PLUGIN_STAGE_DIR="${LR_PLUGIN_STAGE_PATH}/${LR_PLUGIN_NAME}"
LR_USER_MODULES_REL_PATH="Library/Application Support/Adobe/Lightroom/Modules"
RESOLVE_SCRIPT_STAGE_FILE="${RESOLVE_SCRIPT_STAGE_PATH}/${RESOLVE_SCRIPT_NAME}"
RESOLVE_USER_SCRIPTS_REL_PATH="Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Edit"
RESOLVE_SYSTEM_SCRIPTS_DIR=""

cat > "${SCRIPTS_DIR}/postinstall" <<EOF
#!/bin/bash
set -euo pipefail

log() {
    echo "[postinstall] \$1"
}

LOG_FILE="/Library/Logs/LightroomToResolve-installer.log"
mkdir -p "\$(dirname "\${LOG_FILE}")"
exec > >(tee -a "\${LOG_FILE}") 2>&1

PLUGIN_STAGE_DIR="${LR_PLUGIN_STAGE_DIR}"
PLUGIN_NAME="${LR_PLUGIN_NAME}"
USER_MODULES_SUFFIX="${LR_USER_MODULES_REL_PATH}"
RESOLVE_SCRIPT_STAGE_FILE="${RESOLVE_SCRIPT_STAGE_FILE}"
RESOLVE_SCRIPT_NAME="${RESOLVE_SCRIPT_NAME}"
RESOLVE_USER_SCRIPTS_SUFFIX="${RESOLVE_USER_SCRIPTS_REL_PATH}"
LAUNCH_AGENT_PATH="${LAUNCH_AGENT_PATH}"
RESOLVE_API_PATH="${RESOLVE_API_PATH}"
RESOLVE_LIB_PATH="${RESOLVE_LIB_PATH}"
HAVE_PLUGIN_STAGE=0
HAVE_RESOLVE_STAGE=0

# Ensure staged payload + Resolve script have predictable permissions before copy
if [[ -d "\${PLUGIN_STAGE_DIR}" ]]; then
    chmod -R 755 "\${PLUGIN_STAGE_DIR}"
    HAVE_PLUGIN_STAGE=1
else
    log "WARNING: Plugin staging directory not found (\${PLUGIN_STAGE_DIR})"
    # Debugging: list parent directory
    log "Listing of /Library/Application Support/LightroomToResolve:"
    ls -la "/Library/Application Support/LightroomToResolve" || true
fi

if [[ -f "\${RESOLVE_SCRIPT_STAGE_FILE}" ]]; then
    chmod 644 "\${RESOLVE_SCRIPT_STAGE_FILE}" 2>/dev/null || true
    HAVE_RESOLVE_STAGE=1
else
    log "WARNING: Resolve script staging file not found (\${RESOLVE_SCRIPT_STAGE_FILE})"
fi

# Copy Lightroom plugin into the detected user's ~/Library tree where Lightroom loads modules.
install_plugin_for_user() {
    local target_user="\$1"
    if [[ -z "\${target_user}" || "\${target_user}" == "root" ]]; then
        log "Skipping plugin install for invalid user: \${target_user}"
        return
    fi

    local home_dir
    home_dir=\$(dscl . -read "/Users/\${target_user}" NFSHomeDirectory 2>/dev/null | awk -F': ' 'NR==1 {print \$2}')
    if [[ -z "\${home_dir}" ]]; then
        log "WARNING: Unable to resolve home directory for \${target_user}"
        return
    fi
    log "Target user: \${target_user} | Home: \${home_dir}"

    local modules_dir="\${home_dir}/\${USER_MODULES_SUFFIX}"
    local target_path="\${modules_dir}/\${PLUGIN_NAME}"

    mkdir -p "\${modules_dir}"
    chown "\${target_user}":staff "\${modules_dir}"
    chmod 755 "\${modules_dir}"
    rm -rf "\${target_path}"
    cp -R "\${PLUGIN_STAGE_DIR}" "\${modules_dir}/"
    chown -R "\${target_user}":staff "\${target_path}"
    chmod -R 755 "\${target_path}"
    log "Lightroom plugin installed for \${target_user} -> \${target_path}"
}

install_resolve_script_for_user() {
    local target_user="\$1"
    if [[ -z "\${target_user}" || "\${target_user}" == "root" ]]; then
        log "Skipping Resolve script install for invalid user: \${target_user}"
        return
    fi
    if [[ "\${HAVE_RESOLVE_STAGE}" -ne 1 ]]; then
        log "Skipping Resolve script install for \${target_user} because staged payload is missing."
        return
    fi

    local home_dir
    home_dir=\$(dscl . -read "/Users/\${target_user}" NFSHomeDirectory 2>/dev/null | awk -F': ' 'NR==1 {print \$2}')
    if [[ -z "\${home_dir}" ]]; then
        log "WARNING: Unable to resolve home directory for \${target_user}"
        return
    fi

    local scripts_dir="\${home_dir}/\${RESOLVE_USER_SCRIPTS_SUFFIX}"
    local target_file="\${scripts_dir}/\${RESOLVE_SCRIPT_NAME}"

    mkdir -p "\${scripts_dir}"
    chown "\${target_user}":staff "\${scripts_dir}"
    chmod 755 "\${scripts_dir}"
    cp "\${RESOLVE_SCRIPT_STAGE_FILE}" "\${target_file}"
    chown "\${target_user}":staff "\${target_file}"
    chmod 644 "\${target_file}"
    log "Resolve script installed for \${target_user} -> \${target_file}"
}

CONSOLE_USER=\$(stat -f '%Su' /dev/console 2>/dev/null || true)
TARGET_USER="\${SUDO_USER:-\${CONSOLE_USER}}"

if [[ -n "\${TARGET_USER}" && "\${TARGET_USER}" != "root" ]]; then
    if [[ "\${HAVE_PLUGIN_STAGE}" -eq 1 ]]; then
        install_plugin_for_user "\${TARGET_USER}"
    else
        log "WARNING: Skipping user plugin install because staged payload is missing."
    fi
    install_resolve_script_for_user "\${TARGET_USER}"
else
    log "WARNING: Could not determine a non-root user for Lightroom plugin installation."
fi

if [[ "\${HAVE_PLUGIN_STAGE}" -eq 1 || "\${HAVE_RESOLVE_STAGE}" -eq 1 ]]; then
    while IFS=' ' read -r username uid; do
        if [[ "\${uid}" -lt 501 ]]; then
            continue
        fi
        if [[ "\${username}" == "\${TARGET_USER}" ]]; then
            continue
        fi
        if [[ "\${HAVE_PLUGIN_STAGE}" -eq 1 ]]; then
            install_plugin_for_user "\${username}"
        fi
        install_resolve_script_for_user "\${username}"
    done < <(dscl . -list /Users UniqueID 2>/dev/null || true)
fi

# Create LaunchAgent for Environment Variables
cat > "\${LAUNCH_AGENT_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PKG_ID_BASE}.env</string>
    <key>ProgramArguments</key>
    <array>
        <string>sh</string>
        <string>-c</string>
        <string>launchctl setenv RESOLVE_SCRIPT_API "\${RESOLVE_API_PATH}" RESOLVE_SCRIPT_LIB "\${RESOLVE_LIB_PATH}" PYTHONPATH "\${PYTHONPATH:+\${PYTHONPATH}:}\${RESOLVE_API_PATH}/Modules/"</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

chmod 644 "\${LAUNCH_AGENT_PATH}"
chown root:wheel "\${LAUNCH_AGENT_PATH}"

# Load it immediately for logged in users
# (This might fail if run as root installer without GUI context, but worth a try or rely on reboot)
# Note: Installers run as root, so launchctl load might target system domain unless dropped to user.
EOF

chmod +x "${SCRIPTS_DIR}/postinstall"
echo_success "postinstall script created"

pkgbuild \
    --root "${PKGROOT_LR}" \
    --identifier "${PKG_ID_BASE}.lrplugin" \
    --version "${VERSION}" \
    --install-location "/" \
    --scripts "${SCRIPTS_DIR}" \
    "${PKG_LR}"
echo_success "Lightroom Plugin PKG created"

echo_step "Creating Resolve Script PKG..."
PKGROOT_RES="${PKG_WORK_DIR}/root_resolve"
mkdir -p "${PKGROOT_RES}${RESOLVE_SCRIPT_STAGE_PATH}"

if [[ ! -f "${RESOLVE_SCRIPT_SRC}" ]]; then
    echo_error "Resolve script source not found: ${RESOLVE_SCRIPT_SRC}"
    exit 1
fi
cp "${RESOLVE_SCRIPT_SRC}" "${PKGROOT_RES}${RESOLVE_SCRIPT_STAGE_PATH}/"

PKG_RES="${PKG_WORK_DIR}/ResolveScript.pkg"
pkgbuild \
    --root "${PKGROOT_RES}" \
    --identifier "${PKG_ID_BASE}.resolvescript" \
    --version "${VERSION}" \
    --install-location "/" \
    "${PKG_RES}"
echo_success "Resolve Script PKG created"

#============================================
# Step 2: Distribution XML & Product PKG
#============================================
echo_header "Step 2: Building Signed Product PKG"

DIST_XML="${PKG_WORK_DIR}/Distribution.xml"
cat > "${DIST_XML}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>LightroomToResolve ${VERSION}</title>
    <options customize="always" allow-external-scripts="no"/>
    <domains enable_currentUserHome="false" enable_localSystem="true"/>
    
    <installation-check script="pm_install_check();"/>
    
    <script>
    <![CDATA[
    function pm_install_check() {
        var missing = [];
        
        // Check Adobe Lightroom Classic
        var lrPaths = [
            "/Applications/Adobe Lightroom Classic.app",
            "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app"
        ];
        var lrFound = false;
        for (var i = 0; i < lrPaths.length; i++) {
            if (system.files.fileExistsAtPath(lrPaths[i])) {
                lrFound = true;
                break;
            }
        }
        if (!lrFound) {
            missing.push("Adobe Lightroom Classic");
        }
        
        // Check DaVinci Resolve
        var resolvePath = "/Applications/DaVinci Resolve/DaVinci Resolve.app";
        if (!system.files.fileExistsAtPath(resolvePath)) {
            missing.push("DaVinci Resolve");
        }
        
        // Check Adobe DNG Converter
        var dngPath = "/Applications/Adobe DNG Converter.app/Contents/MacOS/Adobe DNG Converter";
        if (!system.files.fileExistsAtPath(dngPath)) {
            missing.push("Adobe DNG Converter");
        }
        
        if (missing.length > 0) {
            var message = "The following required applications are not installed:\n\n";
            for (var j = 0; j < missing.length; j++) {
                message += "• " + missing[j] + "\n";
            }
            message += "\nPlease install these applications before continuing with the installation.";
            my.result.title = "Required Applications Not Found";
            my.result.message = message;
            my.result.type = "Fatal";
            return false;
        }
        
        return true;
    }
    ]]>
    </script>
    
    <choices-outline>
        <line choice="choice_lr"/>
        <line choice="choice_res"/>
    </choices-outline>
    <choice id="choice_lr" title="Lightroom Plugin" enabled="true" selected="true">
        <pkg-ref id="${PKG_ID_BASE}.lrplugin"/>
    </choice>
    <choice id="choice_res" title="Resolve Script" enabled="true" selected="true">
        <pkg-ref id="${PKG_ID_BASE}.resolvescript"/>
    </choice>
    <pkg-ref id="${PKG_ID_BASE}.lrplugin">LightroomPlugin.pkg</pkg-ref>
    <pkg-ref id="${PKG_ID_BASE}.resolvescript">ResolveScript.pkg</pkg-ref>
</installer-gui-script>
EOF

# Detect Installer Identity
if [[ -z "${INSTALLER_IDENTITY:-}" ]]; then
    echo_step "INSTALLER_IDENTITY not set, attempting auto-detection..."
    INSTALLER_IDENTITY=$(security find-identity -v 2>/dev/null | awk -F '"' '/Developer ID Installer:/ {print $2; exit}') || true
fi

if [[ -z "${INSTALLER_IDENTITY:-}" ]]; then
    echo_error "Developer ID Installer certificate not found."
    echo "Skipping signing/notarization (unsigned build)."
    
    PRODUCT_PKG_PATH="${OUTPUT_DIR}/LightroomToResolve_${VERSION}_macOS_UNSIGNED.pkg"
    productbuild \
        --distribution "${DIST_XML}" \
        --package-path "${PKG_WORK_DIR}" \
        "${PRODUCT_PKG_PATH}"
else
    echo_success "Signing with: ${INSTALLER_IDENTITY}"
    PRODUCT_PKG_PATH="${OUTPUT_DIR}/LightroomToResolve_${VERSION}_macOS.pkg"
    
    productbuild \
        --distribution "${DIST_XML}" \
        --package-path "${PKG_WORK_DIR}" \
        --sign "${INSTALLER_IDENTITY}" \
        "${PRODUCT_PKG_PATH}"
    
    echo_success "Product PKG created and signed"

    #============================================
    # Step 4: Notarization
    #============================================
    echo_header "Step 4: Notarization"

    if [[ -n "${NOTARYTOOL_PROFILE:-}" ]] || [[ -n "${APPLE_API_KEY_ID:-}" ]]; then
        echo_step "Submitting to notarytool..."
        
        NOTARY_CMD=(xcrun notarytool submit "${PRODUCT_PKG_PATH}" --wait)
        
        if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
            NOTARY_CMD+=(--keychain-profile "${NOTARYTOOL_PROFILE}")
        elif [[ -n "${APPLE_API_KEY_PATH:-}" ]]; then
            NOTARY_CMD+=(--key "${APPLE_API_KEY_PATH}" --key-id "${APPLE_API_KEY_ID}" --issuer "${APPLE_API_ISSUER}")
        fi

        "${NOTARY_CMD[@]}"

        echo_step "Stapling ticket..."
        xcrun stapler staple "${PRODUCT_PKG_PATH}"
        echo_success "Notarization and stapling complete"
    else
        echo_step "Notarization credentials not found. Skipping."
    fi
fi

echo ""
echo_header "Build Complete"
echo "Installer: ${PRODUCT_PKG_PATH}"
echo ""

