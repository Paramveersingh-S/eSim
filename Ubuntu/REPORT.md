# eSim 2.5 Upgradation on Ubuntu 25.04 (Plucky Puffin) & 25.10 — Technical Bug Analysis & Remediation Report

**Candidate Name:** Paramveer Singh  
**Roll Number:** LCO23586  
**Institution:** Chandigarh College of Engineering and Technology (CCET), Panjab University, Chandigarh  
**Department:** B.E. Electronics and Communication Engineering (ECE)  
**Student Email:** `lco23586@ccetac.in` / `lco23586@ccet.ac.in`  
**HOD Email:** `dssaini@ccet.ac.in` (Dr. Davinder Singh Saini, Head of Department, ECE)  
**Screening Task:** Task 4 — eSim Upgradation (`FOSSEE/eSim`, `installers` branch)  

---

## 1. Executive Summary

During the installation and verification of **eSim 2.5** from the `installers` branch of `FOSSEE/eSim` on **Ubuntu 25.04 (Plucky Puffin, Linux Kernel 6.14, GCC 14.2, Python 3.13, LLVM 20)**, **seven (7) critical installation and runtime bugs** were identified across `Ubuntu/install-eSim.sh`, `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh`, and the downstream `nghdl` build pipeline. These issues ranged from a fatal Bash syntax error in the top-level dispatcher script and a premature `exit 0` inside `installKicad()` that silently aborted the installer mid-flight, to KiCad 8.0 vs. 6.0 symbol table path mismatches, Python 3.13 `setuptools`/`distutils` build failures, and GCC 14 `-Werror` compilation errors in NGHDL.

All **7 issues** have been systematically diagnosed, resolved, and committed to the `installers` branch.

---

## 2. Summary Matrix of Identified Bugs & Fixes

| Bug ID | Component / File | Line(s) | Severity | Root Cause Description | Fix Implemented |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **BUG-01** | `Ubuntu/install-eSim.sh` | L59–L70 | **CRITICAL (Blocker)** | Missing closing `fi` for `if [[ -f "$SCRIPT" ]]; then` and orphaned `createConfigFile` lines (`echo "[eSim]" >> ...`) left inside `run_version_script()`, throwing `syntax error near unexpected token '}'`. | Removed orphaned config lines, added missing `fi`, and added missing script error handling. |
| **BUG-02** | `Ubuntu/install-eSim.sh` | L26, L49 | **HIGH (OS Detection)** | `lsb_release -d \| grep -oP '\d+\.\d+\.\d+'` requires 3 version octets (e.g. `22.04.4`), returning empty string on Ubuntu `25.04` (`Description: Ubuntu 25.04`). Also lacked `25.10` forward routing. | Updated regex to `\d+\.\d+(\.\d+)?` with fallback to `VERSION_ID` and added `25.04`/`25.10`+ routing. |
| **BUG-03** | `install-eSim-25.04.sh` | L135–L136 | **CRITICAL (Premature Abort)** | Inside `installKicad()`, when KiCad 8.0 is already installed, the script calls `exit 0` instead of `return 0`, terminating the entire shell process before `copyKicadLibrary`, `installNghdl`, `installSky130Pdk`, and `createDesktopStartScript` ever execute. | Replaced `exit 0` with `return 0` inside `installKicad()`. |
| **BUG-04** | `install-eSim-25.04.sh` | L234–L243 | **HIGH (GUI/Schematic Broken)** | `installKicad()` installs **KiCad 8.0**, which reads symbol tables from `~/.config/kicad/8.0/sym-lib-table`, but `copyKicadLibrary()` hardcodes `~/.config/kicad/6.0/`. Launching eSim schematic editor results in missing `eSim_Sources`, `eSim_Devices`, and `eSim_Plot` libraries. | Updated `copyKicadLibrary()` to populate `sym-lib-table` across `~/.config/kicad/{6.0,8.0,9.0}`. |
| **BUG-05** | `install-eSim-25.04.sh` | L147, L154 | **HIGH (APT Dependency)** | Hardcoded version pin `kicad=8.0.8+dfsg-1` fails with `E: Version '8.0.8+dfsg-1' for 'kicad' was not found` when the PPA updates point releases (`8.0.9`) or on Ubuntu 25.04 (`plucky`) where `libgit2-1.8` transitioned to `libgit2-1.9`. | Added `apt-cache madison` check for `8.0.8+dfsg-1` with automatic fallback to the available distribution `kicad` package. |
| **BUG-06** | `install-eSim-25.04.sh` | L174–L224 | **HIGH (Python 3.13 / PEP 668)** | 1) `sudo apt install python3-virtualenv` lacked `-y`. 2) On Ubuntu 25.04 (Python 3.13), `setuptools>=75` removed legacy `setup.py` hooks needed by `pyhdlparser`, and bare `pip3` calls risk hitting PEP 668 `externally-managed-environment` if venv activation fails. | Added `-y`, `python3-venv`, `python3-dev`, explicit `$config_dir/env/bin/python -m pip`, pinned `setuptools<75 wheel`, and used `--no-build-isolation` for `pyhdlparser`. |
| **BUG-07** | `install-eSim-25.04.sh` & `nghdl` | L62–L81 | **MEDIUM-HIGH (NGHDL Build)** | Ubuntu 25.04 ships **LLVM 20** and **GCC 14.2** by default, and drops `libcanberra-gtk-module` (GTK2). GHDL fails against LLVM 20 (`/usr/bin/llvm-config`), and NGHDL C code models fail under GCC 14's default `-Werror=implicit-function-declaration`. | Installed `llvm-18-dev` & `libcanberra-gtk3-module`, patched `install-nghdl.sh` to use `/usr/bin/llvm-config-18`, and exported permissive GCC 14 `CFLAGS`. |

---

## 3. Detailed Technical Analysis & Code Remediation

### 3.1 BUG-01 & BUG-02: Syntax Error and Version Detection in `Ubuntu/install-eSim.sh`

In the upstream `installers` branch (`Ubuntu/install-eSim.sh`, lines 58–70), `run_version_script()` had an unclosed `if [[ -f "$SCRIPT" ]]; then` block merged with lines from `createConfigFile`:

```bash
# UPSTREAM BROKEN CODE (Ubuntu/install-eSim.sh:58-70)
    if [[ -f "$SCRIPT" ]]; then
        echo "Running script: $SCRIPT $ARGUMENT"
        bash "$SCRIPT" "$ARGUMENT"
    echo "[eSim]" >> $config_dir/$config_file
    echo "eSim_HOME = $eSim_Home" >> $config_dir/$config_file
    ...
}
```

Executing `bash -n Ubuntu/install-eSim.sh` immediately fails with:
```text
Ubuntu/install-eSim.sh: line 70: syntax error near unexpected token `}'
```

**Remediation:** Closed the `if [[ -f "$SCRIPT" ]]` block properly with `else ... fi`, removed the stray `config.ini` lines (which belong in `createConfigFile` inside the child script), and updated `get_ubuntu_version()` to parse two-digit Ubuntu releases (`25.04`, `25.10`) cleanly.

---

### 3.2 BUG-03: Premature Installer Termination (`exit 0` inside `installKicad()`)

In `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh` (lines 134–137):
```bash
            else
                echo "KiCad 8.0 is already installed."
                exit 0
            fi
```
When `installKicad` is invoked at line 394 during `./install-eSim.sh --install`, if KiCad 8.0 is already present on the machine (e.g., on a retry or pre-installed workstation), `exit 0` terminates the entire bash script immediately. Consequently:
- `copyKicadLibrary` is **skipped** (eSim symbols are never installed),
- `installNghdl` is **skipped** (mixed-signal VHDL/Spice simulation fails),
- `installSky130Pdk` is **skipped** (SKY130 PDK models are missing),
- `createDesktopStartScript` is **skipped** (`/usr/bin/esim` is never created!).

**Remediation:** Replaced `exit 0` with `return 0` so execution returns cleanly to main and completes all subsequent installation stages.

---

### 3.3 BUG-04: KiCad 8.0 vs. KiCad 6.0 Symbol Table Path Mismatch

While `installKicad()` in `install-eSim-25.04.sh` installs **KiCad 8.0**, `copyKicadLibrary()` (lines 234–243) still copied `sym-lib-table` only into `~/.config/kicad/6.0/`:
```bash
# UPSTREAM BROKEN CODE (install-eSim-25.04.sh:234-243)
    if [ -d ~/.config/kicad/6.0 ];then
        echo "kicad config folder already exists"
    else 
        mkdir -p ~/.config/kicad/6.0
    fi
    cp kicadLibrary/template/sym-lib-table ~/.config/kicad/6.0/
```
When eSim opens Eeschema (KiCad 8.0), KiCad looks in `~/.config/kicad/8.0/sym-lib-table`, resulting in missing eSim symbol libraries.

**Remediation:** Updated `copyKicadLibrary()` to install `sym-lib-table` into `~/.config/kicad/6.0/`, `~/.config/kicad/8.0/`, and `~/.config/kicad/9.0/`.

---

### 3.4 BUG-06 & BUG-07: Python 3.13 (PEP 668) & GCC 14 / LLVM 18 Compatibility for NGHDL

Ubuntu 25.04 ships with **Python 3.13**, **GCC 14.2**, and **LLVM 20**, and removes the obsolete GTK2 `libcanberra-gtk-module` package.
1. Inside `installDependency()`, we pre-install `python3-venv`, `python3-dev`, and pin `setuptools<75 wheel` inside `$HOME/.esim/env` before running `pip install --no-build-isolation https://github.com/hdl/pyhdlparser/tarball/master`.
2. Inside `installNghdl()`, we install `llvm-18`, `llvm-18-dev`, and `libcanberra-gtk3-module`, dynamically patch `install-nghdl.sh` to point to `/usr/bin/llvm-config-18`, and export `CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"` so legacy C code models in `ngspice`/`nghdl` compile cleanly under GCC 14.2.
