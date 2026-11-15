#!/bin/bash
#=============================================================================
#          FILE: install-eSim.sh
# 
#         USAGE: ./install-eSim.sh --install 
#                            OR
#                ./install-eSim.sh --uninstall
#                
#   DESCRIPTION: Master Installation Dispatcher for eSim EDA Suite (v2.5)
#                Updated with Ubuntu 25.04 (Plucky Puffin) & 25.10 support,
#                robust os-release parsing, and syntax error remediation.
#
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy, Jayanth Tatineni,
#                Anshul Verma, Shiva Krishna Sangati, Harsha Narayana P,
#                Paramveer Singh (Ubuntu 25.04+ Upgradation Fixes)
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#      REVISION: November 2026
#=============================================================================

set -o pipefail

# Function to detect Ubuntu version and full version string safely on 22.04 - 25.10+
get_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        VERSION_ID=$(grep "^VERSION_ID=" /etc/os-release | cut -d '"' -f 2)
    else
        VERSION_ID=$(lsb_release -rs 2>/dev/null || echo "unknown")
    fi
    # Fix Bug #2: Ubuntu 25.04 non-point releases output '25.04' (2 numbers, not 3).
    # Using '\d+\.\d+(\.\d+)?' prevents empty FULL_VERSION under set -e / pipefail.
    FULL_VERSION=$(lsb_release -d 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -n 1)
    if [[ -z "$FULL_VERSION" ]]; then
        FULL_VERSION="$VERSION_ID"
    fi
    echo "Detected Ubuntu Version: $VERSION_ID (Full: $FULL_VERSION)"
}

# Function to choose and run the appropriate version-specific installer script
run_version_script() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-eSim-scripts"
    
    case "$VERSION_ID" in
        "22.04")
            if [[ "$FULL_VERSION" == "22.04.4" ]]; then
                SCRIPT="$SCRIPT_DIR/install-eSim-22.04.sh"
            else
                SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
            fi
            ;;
        "23.04"|"23.10")
            SCRIPT="$SCRIPT_DIR/install-eSim-23.04.sh"
            ;;
        "24.04"|"24.10")
            SCRIPT="$SCRIPT_DIR/install-eSim-24.04.sh"
            ;;
        "25.04"|"25.10")
            SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
            ;;
        *)
            # Forward-compatible fallback for Ubuntu >= 25.x
            MAJOR_VER=$(echo "$VERSION_ID" | cut -d '.' -f 1)
            if [[ "$MAJOR_VER" =~ ^[0-9]+$ ]] && (( MAJOR_VER >= 25 )); then
                echo "Ubuntu $VERSION_ID (>= 25.04) detected; routing to Ubuntu 25.04+ installer."
                SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
            else
                echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
                exit 1
            fi
            ;;
    esac

    # Fix Bug #1: Properly close the if-block with 'fi' and remove orphaned
    # createConfigFile fragment that caused 'syntax error near unexpected token }'
    if [[ -f "$SCRIPT" ]]; then
        echo "Running version-specific installer: $SCRIPT $ARGUMENT"
        chmod +x "$SCRIPT"
        bash "$SCRIPT" "$ARGUMENT"
    else
        echo "Error: Installer script not found at $SCRIPT"
        exit 1
    fi
}

####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

if [ "$#" -eq 1 ]; then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1
fi

ARGUMENT=$1
if [[ "$ARGUMENT" != "--install" && "$ARGUMENT" != "--uninstall" ]]; then
    echo "Invalid argument: $ARGUMENT"
    echo "Usage: $0 --install | --uninstall"
    exit 1
fi

get_ubuntu_version
run_version_script
