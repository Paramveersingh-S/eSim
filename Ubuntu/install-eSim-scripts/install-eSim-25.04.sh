#!/bin/bash
#=============================================================================
#          FILE: install-eSim-25.04.sh
# 
#         USAGE: ./install-eSim-25.04.sh --install 
#                            OR
#                ./install-eSim-25.04.sh --uninstall
#                
#   DESCRIPTION: Installation script for eSim 2.5 EDA Suite on Ubuntu 25.04+
#                Fixes:
#                1. Replaced premature 'exit 0' with 'return 0' in installKicad()
#                   so remaining installation stages (KiCad symbols, NGHDL,
#                   SKY130 PDK, Desktop shortcut) are not skipped.
#                2. Updated copyKicadLibrary() to detect KiCad 8.0/9.0 config
#                   directory (~/.config/kicad/8.0) instead of hardcoded 6.0.
#                3. Resolved Ubuntu 25.04 (Plucky) KiCad package version pin
#                   conflict (kicad=8.0.8+dfsg-1 not found on plucky universe)
#                   with fallback to available 8.x/universe release & libgit2.
#                4. Added non-interactive '-y' flag to python3-virtualenv apt
#                   install and handled PEP 668 / Python 3.13 setuptools & wheel
#                   pre-installation inside ~/.esim/env before building hdlparse.
#                5. Exported GCC 14 compatibility CFLAGS (-Wno-error=implicit-function-declaration
#                   -Wno-error=int-conversion) and LLVM 18 path for NGHDL build.
#
#       AUTHORS: eSim Team, FOSSEE, IIT Bombay
#                Paramveer Singh (Ubuntu 25.04+ Upgradation Fixes)
#      REVISION: November 2026
#=============================================================================

config_dir="$HOME/.esim"
config_file="config.ini"
eSim_Home=$(pwd)
ngspiceFlag=0

error_exit()
{
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
}

function createConfigFile
{
    echo "Creating eSim configuration at $config_dir/$config_file..."
    mkdir -p "$config_dir"
    rm -f "$config_dir/$config_file"
    touch "$config_dir/$config_file"
    
    echo "[eSim]" >> "$config_dir/$config_file"
    echo "eSim_HOME = $eSim_Home" >> "$config_dir/$config_file"
    echo "LICENSE = %(eSim_HOME)s/LICENSE" >> "$config_dir/$config_file"
    echo "KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz" >> "$config_dir/$config_file"
    echo "IMAGES = %(eSim_HOME)s/images" >> "$config_dir/$config_file"
    echo "VERSION = %(eSim_HOME)s/VERSION" >> "$config_dir/$config_file"
    echo "MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json" >> "$config_dir/$config_file"
}

function installNghdl
{
    echo "Installing NGHDL..........................."
    # Fix Bug #7: Ensure LLVM-18, GHDL, flex, bison, and GCC-14 permissive flags
    # are configured on Ubuntu 25.04 before running install-nghdl.sh
    sudo apt-get install -y build-essential clang llvm-18 llvm-18-dev \
        libcanberra-gtk3-module flex bison libreadline-dev libncurses-dev \
        libxaw7-dev libfftw3-dev zlib1g-dev || true

    export LLVM_CONFIG=/usr/bin/llvm-config-18
    export CFLAGS="${CFLAGS} -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"

    unzip -o nghdl.zip
    cd nghdl/
    chmod +x install-nghdl.sh

    # Patch install-nghdl.sh on the fly if it references removed Ubuntu 25.04 packages
    if grep -q "libcanberra-gtk-module" install-nghdl.sh 2>/dev/null; then
        sed -i 's/libcanberra-gtk-module/libcanberra-gtk3-module/g' install-nghdl.sh
    fi
    if grep -q "/usr/bin/llvm-config " install-nghdl.sh 2>/dev/null && [ -x /usr/bin/llvm-config-18 ]; then
        sed -i 's|/usr/bin/llvm-config|/usr/bin/llvm-config-18|g' install-nghdl.sh
    fi

    trap "" ERR
    ./install-nghdl.sh --install
    trap error_exit ERR

    ngspiceFlag=1
    cd ../
}

function installSky130Pdk
{
    echo "Installing SKY130 PDK......................"
    tar -xJf library/sky130_fd_pr.tar.xz
    sudo rm -rf /usr/share/local/sky130_fd_pr
    echo "Copying SKY130 PDK........................."
    sudo mkdir -p /usr/share/local/
    sudo mv sky130_fd_pr /usr/share/local/
    sudo chown -R "$USER:$USER" /usr/share/local/sky130_fd_pr/
}

function installKicad
{
    echo "Installing KiCad..........................."
    ubuntu_version=$(lsb_release -rs)

    if [[ "$ubuntu_version" == "24.04" || "$ubuntu_version" == "25.04" || "$ubuntu_version" == "25.10" ]]; then
        echo "Ubuntu $ubuntu_version detected."
        kicadppa="kicad/kicad-8.0-releases"

        if dpkg -s kicad &>/dev/null; then
            installed_version=$(dpkg-query -W -f='${Version}' kicad | cut -d':' -f2 | cut -d'.' -f1)
            if [[ "$installed_version" != "8" ]]; then
                echo "A different version of KiCad ($installed_version) is installed."
                read -p "Do you want to remove it and install KiCad 8.0? (yes/no): " response

                if [[ "$response" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                    echo "Removing KiCad $installed_version..."
                    sudo apt-get remove --purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
                    sudo apt-get autoremove -y
                else
                    echo "Keeping existing KiCad $installed_version installation."
                    return 0
                fi
            else
                echo "KiCad 8.0 is already installed."
                # Fix Bug #3: Use 'return 0' instead of 'exit 0' so the caller
                # continues to copyKicadLibrary, installNghdl, installSky130Pdk, etc.
                return 0
            fi
        fi
    else
        kicadppa="kicad/kicad-6.0-releases"
    fi

    if ! grep -q "^deb .*${kicadppa}" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "Adding KiCad PPA to local apt repository: $kicadppa"
        sudo add-apt-repository -y "ppa:$kicadppa" || echo "Warning: PPA for $ubuntu_version not available, falling back to Ubuntu universe."
        sudo apt-get update || true
    else
        echo "KiCad PPA is already present in sources."
    fi

    # Fix Bug #5: Try pinned 8.0.8+dfsg-1 first, then gracefully fall back to the
    # available kicad 8.x/universe package on Ubuntu 25.04 Plucky
    if apt-cache madison kicad | grep -q "8.0.8+dfsg-1"; then
        sudo apt-get install -y --no-install-recommends kicad=8.0.8+dfsg-1 kicad-footprints kicad-libraries kicad-symbols kicad-templates
    else
        echo "Note: Exact pin 8.0.8+dfsg-1 not in apt cache; installing available KiCad release..."
        sudo apt-get install -y --no-install-recommends kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
    fi

    echo "KiCad installation completed successfully!"
}

function installDependency
{
    set +e
    trap "" ERR

    echo "Updating apt index files..................."
    sudo apt-get update
    
    set -e
    trap error_exit ERR
    
    # Fix Bug #6: Added '-y' for non-interactive apt execution and installed
    # python3-venv + python3-dev for Python 3.13 compatibility on Ubuntu 25.04
    echo "Installing virtualenv and Python build headers..."
    sudo apt-get install -y python3-virtualenv python3-venv python3-pip python3-dev \
        xterm python3-psutil python3-pyqt5 python3-matplotlib python3-setuptools

    echo "Creating virtual environment to isolate packages..."
    rm -rf "$config_dir/env"
    python3 -m virtualenv "$config_dir/env" || python3 -m venv "$config_dir/env"
    
    echo "Starting the virtual env..................."
    source "$config_dir/env/bin/activate"

    # Explicitly use the venv's python -m pip to avoid PEP 668 externally-managed errors
    VENV_PIP="$config_dir/env/bin/python -m pip"

    echo "Upgrading pip, setuptools, and wheel inside venv..."
    $VENV_PIP install --upgrade pip "setuptools<75" wheel

    echo "Installing Watchdog........................"
    $VENV_PIP install watchdog

    echo "Installing Hdlparse........................"
    $VENV_PIP install --no-build-isolation --upgrade https://github.com/hdl/pyhdlparser/tarball/master || $VENV_PIP install hdlparse

    echo "Installing Makerchip & SandPiper SaaS......"
    $VENV_PIP install makerchip-app sandpiper-saas

    echo "Installing Matplotlib and PyQt5 inside venv..."
    $VENV_PIP install matplotlib PyQt5 PyQt5-sip psutil
}

function copyKicadLibrary
{
    echo "Extracting custom KiCad Library..."
    tar -xJf library/kicadLibrary.tar.xz

    # Fix Bug #4: Detect installed KiCad 8.0 / 9.0 config directory instead of
    # only copying sym-lib-table to ~/.config/kicad/6.0
    kicad_base="$HOME/.config/kicad"
    mkdir -p "$kicad_base/6.0" "$kicad_base/8.0"
    
    for ver in "6.0" "8.0" "9.0"; do
        mkdir -p "$kicad_base/$ver"
        cp kicadLibrary/template/sym-lib-table "$kicad_base/$ver/"
        echo "Copied eSim sym-lib-table to $kicad_base/$ver/"
    done

    sudo mkdir -p /usr/share/kicad/symbols/
    sudo cp -r kicadLibrary/eSim-symbols/* /usr/share/kicad/symbols/

    set +e
    trap "" ERR
    rm -rf kicadLibrary
    set -e
    trap error_exit ERR

    sudo chown -R "$USER:$USER" /usr/share/kicad/symbols/
    echo "KiCad custom eSim symbols configured successfully!"
}

function createDesktopStartScript
{    
    echo '#!/bin/bash' > esim-start.sh
    echo "cd \"$eSim_Home/src/frontEnd\"" >> esim-start.sh
    echo "source \"$config_dir/env/bin/activate\"" >> esim-start.sh
    echo "python3 Application.py" >> esim-start.sh

    sudo chmod 755 esim-start.sh
    sudo cp -vp esim-start.sh /usr/bin/esim
    rm esim-start.sh

    echo "[Desktop Entry]" > esim.desktop
    echo "Version=1.0" >> esim.desktop
    echo "Name=eSim" >> esim.desktop
    echo "Comment=EDA Tool" >> esim.desktop
    echo "GenericName=eSim" >> esim.desktop
    echo "Keywords=eda-tools" >> esim.desktop
    echo "Exec=esim %u" >> esim.desktop
    echo "Terminal=true" >> esim.desktop
    echo "X-MultipleArgs=false" >> esim.desktop
    echo "Type=Application" >> esim.desktop
    getIcon="$config_dir/logo.png"
    echo "Icon=$getIcon" >> esim.desktop
    echo "Categories=Development;" >> esim.desktop
    echo "StartupNotify=true" >> esim.desktop

    sudo chmod 755 esim.desktop
    sudo cp -vp esim.desktop /usr/share/applications/
    mkdir -p "$HOME/Desktop"
    cp -vp esim.desktop "$HOME/Desktop/"

    set +e
    trap "" ERR
    gio set "$HOME/Desktop/esim.desktop" "metadata::trusted" true 2>/dev/null || true
    chmod a+x "$HOME/Desktop/esim.desktop"
    rm -f esim.desktop
    set -e
    trap error_exit ERR

    cp -vp images/logo.png "$config_dir"
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

if [ "$option" == "--install" ]; then
    set -e
    set -E
    trap error_exit ERR

    echo "Enter proxy details if you are connected to internet through proxy"
    echo -n "Is your internet connection behind proxy? (y/n): "
    read getProxy
    if [ "$getProxy" == "y" -o "$getProxy" == "Y" ]; then
        echo -n 'Proxy Hostname :'
        read proxyHostname
        echo -n 'Proxy Port :'
        read proxyPort
        echo -n "username@$proxyHostname:$proxyPort :"
        read username
        echo -n 'Password :'
        read -s passwd

        export http_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export https_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export HTTP_PROXY="$http_proxy"
        export HTTPS_PROXY="$https_proxy"
        export ftp_proxy="$http_proxy"
        export FTP_PROXY="$http_proxy"
        echo "Install with proxy"
    elif [ "$getProxy" == "n" -o "$getProxy" == "N" ]; then
        echo "Install without proxy"
    else
        echo "Please select the right option"
        exit 0
    fi

    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    createDesktopStartScript

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on \"eSim\" icon placed on Desktop"

elif [ "$option" == "--uninstall" ]; then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK (y/n):"
    read getConfirmation
    if [ "$getConfirmation" == "y" -o "$getConfirmation" == "Y" ]; then
        echo "Removing eSim............................"
        sudo rm -rf "$HOME/.esim" "$HOME/Desktop/esim.desktop" /usr/bin/esim /usr/share/applications/esim.desktop
        echo "Removing KiCad..........................."
        sudo apt-get purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates || true
        sudo rm -rf /usr/share/kicad
        sudo rm -f /etc/apt/sources.list.d/kicad*
        rm -rf "$HOME/.config/kicad/6.0" "$HOME/.config/kicad/8.0"
        echo "Removing SKY130 PDK......................"
        sudo rm -rf /usr/share/local/sky130_fd_pr
        echo "Removing NGHDL..........................."
        rm -rf library/modelParamXML/Nghdl/* library/modelParamXML/Ngveri/*
        if [ -d nghdl ]; then
            cd nghdl/
            chmod +x install-nghdl.sh
            ./install-nghdl.sh --uninstall || true
            cd ../
            rm -rf nghdl
        fi
        echo -e "----------------eSim Uninstalled Successfully----------------"
    fi
else
    echo "Please select the proper operation: --install | --uninstall"
fi
