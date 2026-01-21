#!/bin/sh
# This script installs Ollama on Linux.
# It detects the current operating system architecture and installs the appropriate version of Ollama.

set -eu

# --- 1. DÉPENDANCES ET MISE À JOUR ---
echo ">>> Updating apt and installing dependencies (pciutils, lshw)..."
apt-get update
apt-get install -y pciutils lshw
# -------------------------------------

red="$( (/usr/bin/tput bold || :; /usr/bin/tput setaf 1 || :) 2>&-)"
plain="$( (/usr/bin/tput sgr0 || :) 2>&-)"

status() { echo ">>> $*" >&2; }
error() { echo "${red}ERROR:${plain} $*"; exit 1; }
warning() { echo "${red}WARNING:${plain} $*"; }

TEMP_DIR=$(mktemp -d)
cleanup() { rm -rf $TEMP_DIR; }
trap cleanup EXIT

available() { command -v $1 >/dev/null; }
require() {
    local MISSING=''
    for TOOL in $*; do
        if ! available $TOOL; then
            MISSING="$MISSING $TOOL"
        fi
    done

    echo $MISSING
}

[ "$(uname -s)" = "Linux" ] || error 'This script is intended to run on Linux only.'

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) error "Unsupported architecture: $ARCH" ;;
esac

IS_WSL2=false

KERN=$(uname -r)
case "$KERN" in
    *icrosoft*WSL2 | *icrosoft*wsl2) IS_WSL2=true;;
    *icrosoft) error "Microsoft WSL1 is not currently supported. Please use WSL2 with 'wsl --set-version <distro> 2'" ;;
    *) ;;
esac

VER_PARAM="${OLLAMA_VERSION:+?version=$OLLAMA_VERSION}"

SUDO=
if [ "$(id -u)" -ne 0 ]; then
    if ! available sudo; then
        error "This script requires superuser permissions. Please re-run as root."
    fi
    SUDO="sudo"
fi

NEEDS=$(require curl awk grep sed tee xargs)
if [ -n "$NEEDS" ]; then
    status "ERROR: The following tools are required but missing:"
    for NEED in $NEEDS; do
        echo "  - $NEED"
    done
    exit 1
fi

download_and_extract() {
    local url_base="$1"
    local dest_dir="$2"
    local filename="$3"

    if curl --fail --silent --head --location "${url_base}/${filename}.tar.zst${VER_PARAM}" >/dev/null 2>&1; then
        if ! available zstd; then
            error "This version requires zstd for extraction. Please install zstd."
        fi
        status "Downloading ${filename}.tar.zst"
        curl --fail --show-error --location --progress-bar \
            "${url_base}/${filename}.tar.zst${VER_PARAM}" | \
            zstd -d | $SUDO tar -xf - -C "${dest_dir}"
        return 0
    fi

    status "Downloading ${filename}.tgz"
    curl --fail --show-error --location --progress-bar \
        "${url_base}/${filename}.tgz${VER_PARAM}" | \
        $SUDO tar -xzf - -C "${dest_dir}"
}

# --- 2. CONFIGURATION DES CHEMINS ET RÉSEAU ---
OLLAMA_INSTALL_DIR="/workspace/ollama"
BINDIR="$OLLAMA_INSTALL_DIR/bin"
MODELS_DIR="$OLLAMA_INSTALL_DIR/models"

status "Creating custom directories at $OLLAMA_INSTALL_DIR..."
$SUDO mkdir -p "$BINDIR"
$SUDO mkdir -p "$MODELS_DIR"

# Configuration immédiate pour le script en cours
export OLLAMA_HOST="0.0.0.0:11434"  # Écoute sur toutes les interfaces
export OLLAMA_MODELS="$MODELS_DIR"
export PATH="$BINDIR:$PATH"
# ----------------------------------------------

if [ -d "$OLLAMA_INSTALL_DIR/lib/ollama" ] ; then
    status "Cleaning up old version at $OLLAMA_INSTALL_DIR/lib/ollama"
    $SUDO rm -rf "$OLLAMA_INSTALL_DIR/lib/ollama"
fi

status "Installing ollama to $OLLAMA_INSTALL_DIR"
$SUDO install -o0 -g0 -m755 -d $BINDIR
$SUDO install -o0 -g0 -m755 -d "$OLLAMA_INSTALL_DIR/lib/ollama"
download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}"

if [ -d "/usr/local/bin" ]; then
    status "Making ollama accessible in /usr/local/bin"
    $SUDO ln -sf "$OLLAMA_INSTALL_DIR/bin/ollama" "/usr/local/bin/ollama"
fi

if [ -f /etc/nv_tegra_release ] ; then
    if grep R36 /etc/nv_tegra_release > /dev/null ; then
        download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}-jetpack6"
    elif grep R35 /etc/nv_tegra_release > /dev/null ; then
        download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}-jetpack5"
    else
        warning "Unsupported JetPack version detected."
    fi
fi

# --- 3. PERSISTANCE DANS BASHRC ---
install_success() {
    status "The Ollama API is available at 0.0.0.0:11434 (External Access Enabled)."
    
    if ! grep -q "OLLAMA_MODELS" ~/.bashrc; then
        status "Adding env variables to ~/.bashrc..."
        echo "" >> ~/.bashrc
        echo "# Ollama Custom Config" >> ~/.bashrc
        echo "export OLLAMA_HOST=\"0.0.0.0:11434\"" >> ~/.bashrc
        echo "export OLLAMA_MODELS=\"$MODELS_DIR\"" >> ~/.bashrc
        echo "export PATH=\"$BINDIR:\$PATH\"" >> ~/.bashrc
    else
        status "Environment variables already present in ~/.bashrc"
    fi

    status "Install complete."
    warning "Please run 'source ~/.bashrc' or restart your terminal to apply changes."
}
trap install_success EXIT
# ----------------------------------

configure_systemd() {
    if ! id ollama >/dev/null 2>&1; then
        status "Creating ollama user..."
        $SUDO useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
    fi
    if getent group render >/dev/null 2>&1; then
        $SUDO usermod -a -G render ollama
    fi
    if getent group video >/dev/null 2>&1; then
        $SUDO usermod -a -G video ollama
    fi

    $SUDO usermod -a -G ollama $(whoami)

    status "Creating ollama systemd service..."
    # Ajout de OLLAMA_HOST dans le service systemd
    cat <<EOF | $SUDO tee /etc/systemd/system/ollama.service >/dev/null
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=$BINDIR/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=$BINDIR:$PATH"
Environment="OLLAMA_MODELS=$MODELS_DIR"
Environment="OLLAMA_HOST=0.0.0.0:11434"

[Install]
WantedBy=default.target
EOF
    SYSTEMCTL_RUNNING="$(systemctl is-system-running || true)"
    case $SYSTEMCTL_RUNNING in
        running|degraded)
            status "Enabling and starting ollama service..."
            $SUDO systemctl daemon-reload
            $SUDO systemctl enable ollama
            start_service() { $SUDO systemctl restart ollama; }
            trap start_service EXIT
            ;;
        *)
            warning "systemd is not running (common in docker/runpod)"
            ;;
    esac
}

if available systemctl; then
    configure_systemd
fi

if [ "$IS_WSL2" = true ]; then
    if available nvidia-smi && [ -n "$(nvidia-smi | grep -o "CUDA Version: [0-9]*\.[0-9]*")" ]; then
        status "Nvidia GPU detected."
    fi
    install_success
    exit 0
fi

if [ -f /etc/nv_tegra_release ] ; then
    status "NVIDIA JetPack ready."
    install_success
    exit 0
fi

if ! available lspci && ! available lshw; then
    warning "Unable to detect NVIDIA/AMD GPU."
    exit 0
fi

check_gpu() {
    case $1 in
        lspci)
            case $2 in
                nvidia) available lspci && lspci -d '10de:' | grep -q 'NVIDIA' || return 1 ;;
                amdgpu) available lspci && lspci -d '1002:' | grep -q 'AMD' || return 1 ;;
            esac ;;
        lshw)
            case $2 in
                nvidia) available lshw && $SUDO lshw -c display -numeric -disable network | grep -q 'vendor: .* \[10DE\]' || return 1 ;;
                amdgpu) available lshw && $SUDO lshw -c display -numeric -disable network | grep -q 'vendor: .* \[1002\]' || return 1 ;;
            esac ;;
        nvidia-smi) available nvidia-smi || return 1 ;;
    esac
}

if check_gpu nvidia-smi; then
    status "NVIDIA GPU installed."
    exit 0
fi

if ! check_gpu lspci nvidia && ! check_gpu lshw nvidia && ! check_gpu lspci amdgpu && ! check_gpu lshw amdgpu; then
    install_success
    warning "No NVIDIA/AMD GPU detected. Ollama will run in CPU-only mode."
    exit 0
fi

if check_gpu lspci amdgpu || check_gpu lshw amdgpu; then
    download_and_extract "https://ollama.com/download" "$OLLAMA_INSTALL_DIR" "ollama-linux-${ARCH}-rocm"
    install_success
    status "AMD GPU ready."
    exit 0
fi

status "NVIDIA GPU ready."
install_success
