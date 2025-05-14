#!/bin/bash
ROOT=$PWD
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;95m'
BLUE='\033[0;94m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120
export TUNNEL_TYPE=""

DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}
DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}
DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}
SMALL_SWARM_CONTRACT="0x69C6e1D608ec64885E7b185d39b04B491a71768C"
BIG_SWARM_CONTRACT="0x6947c6E196a48B77eFa9331EC1E3e45f3Ee5Fd58"

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt &>/dev/null; then
        echo -e "${CYAN}${BOLD}[✓] Debian/Ubuntu detected. Installing build-essential, gcc, g++...${NC}"
        sudo apt update > /dev/null 2>&1
        sudo apt install -y build-essential gcc g++ > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        echo -e "${CYAN}${BOLD}[✓] RHEL/CentOS detected. Installing Development Tools...${NC}"
        sudo yum groupinstall -y "Development Tools" > /dev/null 2>&1
        sudo yum install -y gcc gcc-c++ > /dev/null 2>&1
    elif command -v pacman &>/dev/null; then
        echo -e "${CYAN}${BOLD}[✓] Arch Linux detected. Installing base-devel...${NC}"
        sudo pacman -Sy --noconfirm base-devel gcc > /dev/null 2>&1
    else
        echo -e "${RED}${BOLD}[✗] Linux detected but unsupported package manager.${NC}"
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${CYAN}${BOLD}[✓] macOS detected. Installing Xcode Command Line Tools...${NC}"
    xcode-select --install > /dev/null 2>&1 # Consider adding a check if already installed
else
    echo -e "${RED}${BOLD}[✗] Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

if command -v gcc &>/dev/null; then
    export CC=$(command -v gcc)
    echo -e "${CYAN}${BOLD}[✓] Exported CC=$CC${NC}"
else
    echo -e "${RED}${BOLD}[✗] gcc not found. Please install it manually.${NC}"
    # On macOS, clang is often symlinked to gcc or available.
    # Consider checking for clang if gcc is not found on darwin.
    if [[ "$OSTYPE" == "darwin"* ]] && command -v clang &>/dev/null; then
        export CC=$(command -v clang)
        echo -e "${CYAN}${BOLD}[✓] Exported CC=$CC (using clang on macOS)${NC}"
    else
        exit 1 # Exit if no compiler is found
    fi
fi

check_cuda_installation() {
    echo -e "\n${CYAN}${BOLD}[✓] Checking GPU and CUDA installation...${NC}"
    GPU_AVAILABLE=false
    CUDA_AVAILABLE=false
    NVCC_AVAILABLE=false

    detect_gpu() {
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # GPU detection on macOS is different; typically no NVIDIA.
            # system_profiler SPDisplaysDataType can show GPU info.
            # For this script's purpose (CUDA), assume no NVIDIA GPU on macOS by default.
            echo -e "${YELLOW}${BOLD}[!] macOS detected. NVIDIA GPU check for CUDA is primarily for Linux.${NC}"
            echo -e "${YELLOW}${BOLD}[!] No NVIDIA GPU detected with any detection method${NC}"
            return 1
        fi

        if command -v lspci &> /dev/null; then
            if lspci | grep -i nvidia &> /dev/null; then
                echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via lspci)${NC}"
                return 0
            elif lspci | grep -i "vga\|3d\|display" | grep -i "amd\|radeon\|ati" &> /dev/null; then
                echo -e "${YELLOW}${BOLD}[!] AMD GPU detected (via lspci)${NC}"
                echo -e "${YELLOW}${BOLD}[!] This script only supports NVIDIA GPUs for CUDA installation${NC}"
                return 2
            fi
            # return 1 # Fall through if lspci exists but no known GPU found
        fi

        if command -v nvidia-smi &> /dev/null; then
            if nvidia-smi &> /dev/null; then
                echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via nvidia-smi)${NC}"
                return 0
            fi
        fi

        if [ -d "/proc/driver/nvidia" ] || [ -d "/dev/nvidia0" ]; then # Linux specific
            echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via system directories)${NC}"
            return 0
        fi

        if [ -x "/usr/local/cuda/samples/bin/x86_64/linux/release/deviceQuery" ]; then # Linux specific path
            if /usr/local/cuda/samples/bin/x86_64/linux/release/deviceQuery | grep "Result = PASS" &> /dev/null; then
                echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via deviceQuery)${NC}"
                return 0
            fi
        fi
        
        # Sysfs check, more common on Linux
        if [ -d "/sys/class/gpu" ] || (ls /sys/bus/pci/devices/*/vendor 2>/dev/null | xargs -r cat 2>/dev/null | grep -q "0x10de"); then
            echo -e "${GREEN}${BOLD}[✓] NVIDIA GPU detected (via sysfs)${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}${BOLD}[!] No NVIDIA GPU detected with any detection method${NC}"
        return 1
    }

    detect_gpu
    gpu_result=$?

    if [ $gpu_result -eq 0 ]; then
        GPU_AVAILABLE=true
    elif [ $gpu_result -eq 2 ]; then # AMD GPU
        echo -e "${YELLOW}${BOLD}[!] Proceeding with CPU-only mode${NC}"
        CPU_ONLY="true"
        return 0
    else # No NVIDIA GPU or error
        echo -e "${YELLOW}${BOLD}[!] No NVIDIA GPU detected - using CPU-only mode${NC}"
        echo -e "${YELLOW}${BOLD}[!] CUDA installation will be skipped${NC}"
        CPU_ONLY="true"
        return 0
    fi

    # CUDA Driver and NVCC checks (only if NVIDIA GPU was detected)
    if command -v nvidia-smi &> /dev/null; then
        echo -e "${GREEN}${BOLD}[✓] CUDA drivers detected (nvidia-smi found)${NC}"
        CUDA_AVAILABLE=true
        echo -e "${CYAN}${BOLD}[✓] GPU information:${NC}"
        nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu --format=csv,noheader
    elif [ -d "/proc/driver/nvidia" ]; then # Linux specific
        echo -e "${GREEN}${BOLD}[✓] CUDA drivers detected (NVIDIA driver directory found)${NC}"
        CUDA_AVAILABLE=true
    else
        echo -e "${YELLOW}${BOLD}[!] CUDA drivers not detected${NC}"
    fi

    if command -v nvcc &> /dev/null; then
        NVCC_VERSION=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
        echo -e "${GREEN}${BOLD}[✓] NVCC compiler detected (version $NVCC_VERSION)${NC}"
        NVCC_AVAILABLE=true
    else
        echo -e "${YELLOW}${BOLD}[!] NVCC compiler not detected${NC}"
    fi

    if [ "$GPU_AVAILABLE" = true ] && ([ "$CUDA_AVAILABLE" = false ] || [ "$NVCC_AVAILABLE" = false ]); then
        echo -e "${YELLOW}${BOLD}[!] NVIDIA GPU is available but CUDA environment is not completely set up${NC}"
        read -p "Would you like to install CUDA and NVCC? [Y/n] " install_choice
        install_choice=${install_choice:-Y}
        if [[ $install_choice =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}${BOLD}[✓] Downloading and running CUDA installation script from GitHub...${NC}"
            bash <(curl -sSL https://raw.githubusercontent.com/zunxbt/gensyn-testnet/main/cuda.sh) # This script is likely Linux-specific
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}${BOLD}[✓] CUDA installation script completed successfully${NC}"
                source ~/.profile 2>/dev/null || true
                source ~/.bashrc 2>/dev/null || true # Consider ~/.zshrc for macOS
                if [ -f "/etc/profile.d/cuda.sh" ]; then # Linux specific
                    source /etc/profile.d/cuda.sh
                fi
                if [ -d "/usr/local/cuda/bin" ] && [[ ":$PATH:" != *":/usr/local/cuda/bin:"* ]]; then
                    export PATH="/usr/local/cuda/bin:$PATH"
                fi
                if [ -d "/usr/local/cuda/lib64" ] && [[ ":$LD_LIBRARY_PATH:" != *":/usr/local/cuda/lib64:"* ]]; then # LD_LIBRARY_PATH is Linux
                    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH" # On macOS, DYLD_LIBRARY_PATH
                fi
                 if [[ "$OSTYPE" == "darwin"* ]] && [ -d "/usr/local/cuda/lib" ] && [[ ":$DYLD_LIBRARY_PATH:" != *":/usr/local/cuda/lib:"* ]]; then
                    export DYLD_LIBRARY_PATH="/usr/local/cuda/lib:$DYLD_LIBRARY_PATH"
                fi


                if command -v nvcc &> /dev/null; then
                    NVCC_VERSION=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
                    echo -e "${GREEN}${BOLD}[✓] NVCC successfully installed (version $NVCC_VERSION)${NC}"
                    NVCC_AVAILABLE=true
                else
                    echo -e "${YELLOW}${BOLD}[!] NVCC installation may require a system restart or manual PATH setup.${NC}"
                    echo -e "${YELLOW}${BOLD}[!] If you continue to have issues after this script completes, please restart your system or check your PATH.${NC}"
                fi
                if command -v nvidia-smi &> /dev/null; then
                    echo -e "${CYAN}${BOLD}[✓] Current NVIDIA driver information:${NC}"
                    nvidia-smi --query-gpu=driver_version,name,temperature.gpu,utilization.gpu,utilization.memory --format=csv,noheader
                fi
            else
                echo -e "${RED}${BOLD}[✗] CUDA installation failed${NC}"
                echo -e "${YELLOW}${BOLD}[!] Please try installing CUDA manually by following NVIDIA's installation guide${NC}"
                echo -e "${YELLOW}${BOLD}[!] Proceeding with CPU-only mode${NC}"
                CPU_ONLY="true"
            fi
        else
            echo -e "${YELLOW}${BOLD}[!] Proceeding without CUDA installation${NC}"
            echo -e "${YELLOW}${BOLD}[!] CPU-only mode will be used${NC}"
            CPU_ONLY="true"
        fi
    elif [ "$GPU_AVAILABLE" = true ] && [ "$CUDA_AVAILABLE" = true ] && [ "$NVCC_AVAILABLE" = true ]; then
        echo -e "${GREEN}${BOLD}[✓] GPU with CUDA environment properly configured${NC}"
        CPU_ONLY="false"
    else # Fallback if GPU not available or CUDA not fully set up and user chose not to install
        echo -e "${YELLOW}${BOLD}[!] Using CPU-only mode (default fallback)${NC}"
        CPU_ONLY="true"
    fi
    return 0
}
check_cuda_installation
export CPU_ONLY

if [ "$CPU_ONLY" = "true" ]; then
    echo -e "\n${YELLOW}${BOLD}[✓] Running in CPU-only mode${NC}"
else
    echo -e "\n${GREEN}${BOLD}[✓] Running with GPU acceleration${NC}"
fi

while true; do
    # Prompt the user
    echo -e "\n\033[36m\033[1mPlease select a swarm to join:\n[A] Math\n[B] Math Hard\033[0m"
    read -p "> " ab
    ab=${ab:-A} # Default to "A" if Enter is pressed
    case $ab in
        [Aa]*) USE_BIG_SWARM=false; break ;;
        [Bb]*) USE_BIG_SWARM=true; break ;;
        *) echo ">>> Please answer A or B." ;;
    esac
done

if [ "$USE_BIG_SWARM" = true ]; then
    SWARM_CONTRACT="$BIG_SWARM_CONTRACT"
else
    SWARM_CONTRACT="$SMALL_SWARM_CONTRACT"
fi

while true; do
    echo -e "\n\033[36m\033[1mHow many parameters (in billions)? [0.5, 1.5, 7, 32, 72]\033[0m"
    read -p "> " pc
    pc=${pc:-0.5} # Default to "0.5" if the user presses Enter
    case $pc in
        0.5 | 1.5 | 7 | 32 | 72) PARAM_B=$pc; break ;;
        *) echo ">>> Please answer in [0.5, 1.5, 7, 32, 72]." ;;
    esac
done

cleanup() {
    echo -e "${YELLOW}${BOLD}[✓] Shutting down processes...${NC}"
    # Ensure PIDs are numbers before killing
    [[ "$SERVER_PID" =~ ^[0-9]+$ ]] && kill $SERVER_PID 2>/dev/null || true
    [[ "$TUNNEL_PID" =~ ^[0-9]+$ ]] && kill $TUNNEL_PID 2>/dev/null || true
    exit 0
}
trap cleanup INT
sleep 2 # Why sleep here?

handle_port_3000() {
    local port_to_check="3000"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version using lsof
        LSOF_OUTPUT=$(lsof -iTCP:"$port_to_check" -sTCP:LISTEN -n -P)
        if echo "$LSOF_OUTPUT" | grep LISTEN > /dev/null; then
            PID=$(echo "$LSOF_OUTPUT" | awk '/LISTEN/{print $2; exit}') # Get PID from first LISTEN line
            if [ -n "$PID" ] && [[ "$PID" =~ ^[0-9]+$ ]]; then # Check if PID is a number
                echo -e "${YELLOW}[!] Port $port_to_check is in use by PID: $PID on macOS. Killing process...${NC}"
                kill -9 "$PID"
                sleep 2 # Give time for the process to be killed
            elif [ -n "$PID" ]; then
                 echo -e "${YELLOW}[!] Port $port_to_check is in use on macOS, but PID ($PID) is not a valid number. Manual check may be needed.${NC}"
            fi
        fi
    else
        # Linux version using ss
        if ! command -v ss &>/dev/null; then
            echo -e "${YELLOW}[!] 'ss' not found. Attempting to install 'iproute2'...${NC}"
            if command -v apt &>/dev/null; then
                sudo apt update > /dev/null 2>&1 && sudo apt install -y iproute2 > /dev/null 2>&1
            elif command -v yum &>/dev/null; then
                sudo yum install -y iproute > /dev/null 2>&1 # RHEL 7 and older use 'iproute', newer use 'iproute2'
            elif command -v pacman &>/dev/null; then
                sudo pacman -Sy --noconfirm iproute2 > /dev/null 2>&1
            else
                echo -e "${RED}[✗] Could not install 'ss'. Package manager not found or unsupported Linux distro.${NC}"
                # Do not exit here, as the script might still work if port is not in use.
            fi
        fi

        if command -v ss &>/dev/null; then
            PORT_LINE=$(ss -ltnp 2>/dev/null | grep ":$port_to_check ") # Added 2>/dev/null for ss
            if [ -n "$PORT_LINE" ]; then
                PID=$(echo "$PORT_LINE" | grep -oP 'pid=\K[0-9]+' | head -n 1) # Kept grep -oP for Linux as in original
                if [ -n "$PID" ] && [[ "$PID" =~ ^[0-9]+$ ]]; then
                    echo -e "${YELLOW}[!] Port $port_to_check is in use by PID: $PID on Linux. Killing process...${NC}"
                    kill -9 "$PID"
                    sleep 2 # Give time for the process to be killed
                elif [ -n "$PID" ]; then
                    echo -e "${YELLOW}[!] Port $port_to_check is in use on Linux, but PID ($PID) is not a valid number. Manual check may be needed.${NC}"
                fi
            fi
        else
             echo -e "${YELLOW}[!] 'ss' command not available on Linux and could not be installed. Cannot check port $port_to_check.${NC}"
        fi
    fi
}


if [ -f "modal-login/temp-data/userData.json" ]; then
    cd modal-login
    echo -e "\n${CYAN}${BOLD}[✓] Installing dependencies with npm. This may take a few minutes, depending on your internet speed...${NC}"
    npm install --legacy-peer-deps

    echo -e "\n${CYAN}${BOLD}[✓] Starting the development server...${NC}"
    
    handle_port_3000 # Call the unified function

    > server.log

    npm run dev > server.log 2>&1 &
    SERVER_PID=$!
    sleep 2 # Maybe remove this sleep?
    MAX_WAIT=30 # Or 90 in the other block
    PORT="" # Initialize PORT
    sleep 10
    # for ((i = 0; i < MAX_WAIT; i++)); do
    #     # ... 这里是检查 server.log 的逻辑 ...
    #     # 检查 server.log 文件是否存在，并且是否包含 "Local: http://localhost:" 这一行
    #     # 注意：这里已经移除了 tail -n 10，以便检查整个文件
    #     if [ -f "server.log" ] && grep -q "Local: http://localhost:" server.log; then
    #         # 如果找到那一行，提取端口号
    #         PORT=$(grep "Local: http://localhost:" server.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p' | head -n 1)
    #         # 检查是否成功提取到端口号
    #         if [ -n "$PORT" ]; then
    #             echo -e "${GREEN}${BOLD}[✓] Server is running successfully on port $PORT.${NC}"
    #             break # 找到端口后跳出循环
    #         fi
    #     fi
    #     sleep 1 # 每次检查间隔 1 秒
    # done

    if [ $i -eq $MAX_WAIT ]; then
        echo -e "${RED}${BOLD}[✗] Timeout waiting for server to start. Check server.log for details.${NC}"
        cat server.log
        [[ "$SERVER_PID" =~ ^[0-9]+$ ]] && kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi
    cd ..
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo -e "\n${CYAN}${BOLD}[✓] ORG_ID has been set to: ${BOLD}$ORG_ID\n${NC}"
else
    cd modal-login
    echo -e "\n${CYAN}${BOLD}[✓] Installing dependencies with npm. This may take a few minutes, depending on your internet speed...${NC}"
    # npm config set registry https://registry.npmmirror.com # Consider if this is always needed
    # yarn config set registry https://registry.npmmirror.com # Consider if yarn is used
    npm install --legacy-peer-deps
    echo -e "\n${CYAN}${BOLD}[✓] Starting the development server...${NC}"

    handle_port_3000 # Call the unified function

    npm run dev > server.log 2>&1 &
    SERVER_PID=$!
    MAX_WAIT=90 # Consider increasing
    PORT="" # Initialize PORT
    for ((i = 0; i < MAX_WAIT; i++)); do
        if grep -q "Local: http://localhost:" server.log; then # This grep pattern should be okay
            PORT=$(grep "Local: http://localhost:" server.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p' | head -n 1)
            if [ -n "$PORT" ]; then
                echo -e "${GREEN}${BOLD}[✓] Server is running successfully on port $PORT.${NC}"
                break
            fi
        fi
        sleep 1
    done

    if [ $i -eq $MAX_WAIT ]; then
        echo -e "${RED}${BOLD}[✗] Timeout waiting for server to start. Check server.log for details.${NC}"
        cat server.log # Display server log
        [[ "$SERVER_PID" =~ ^[0-9]+$ ]] && kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    echo -e "\n${CYAN}${BOLD}[✓] Detecting system architecture...${NC}"
    ARCH=$(uname -m)
    OS_KERNEL=$(uname -s | tr '[:upper:]' '[:lower:]') # Renamed to OS_KERNEL to avoid conflict with $OSTYPE

    if [ "$ARCH" = "x86_64" ]; then
        NGROK_ARCH="amd64"
        CF_ARCH="amd64" # cloudflared uses amd64 for x86_64
        echo -e "${GREEN}${BOLD}[✓] Detected x86_64 architecture.${NC}"
    elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
        NGROK_ARCH="arm64"
        CF_ARCH="arm64" # cloudflared uses arm64
        echo -e "${GREEN}${BOLD}[✓] Detected ARM64 architecture.${NC}"
    elif [[ "$ARCH" == arm* ]]; then # For 32-bit arm
        NGROK_ARCH="arm"
        CF_ARCH="arm" # cloudflared uses arm
        echo -e "${GREEN}${BOLD}[✓] Detected ARM architecture.${NC}"
    else
        echo -e "${RED}[✗] Unsupported architecture: $ARCH. Please use a supported system.${NC}"
        exit 1
    fi

    check_url() {
        local url=$1
        local max_retries=3
        local retry=0
        while [ $retry -lt $max_retries ]; do
            http_code=$(curl -s -o /dev/null -L -w "%{http_code}" "$url" 2>/dev/null) # Added -L for redirects
            if [ "$http_code" = "200" ] || [ "$http_code" = "404" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
                # For tunneling, we usually expect 200, but others might indicate it's alive
                return 0
            fi
            retry=$((retry + 1))
            sleep 2
        done
        return 1
    }

    install_localtunnel() {
        if command -v lt >/dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}[✓] Localtunnel is already installed.${NC}"
            return 0
        fi
        echo -e "\n${CYAN}${BOLD}[✓] Installing localtunnel...${NC}"
        if npm install -g localtunnel > /dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}[✓] Localtunnel installed successfully.${NC}"
            return 0
        else
            echo -e "${RED}${BOLD}[✗] Failed to install localtunnel.${NC}"
            return 1
        fi
    }
    
    install_cloudflared() {
        if command -v cloudflared >/dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}[✓] Cloudflared is already installed.${NC}"
            return 0
        fi
        echo -e "\n${YELLOW}${BOLD}[✓] Installing cloudflared...${NC}"
        # Adjust download URL based on OS
        local cf_os_arch_suffix
        if [[ "$OSTYPE" == "darwin"* ]]; then
             cf_os_arch_suffix="darwin-$CF_ARCH.tgz" # macOS uses .tgz and different naming
        else # Linux
             cf_os_arch_suffix="linux-$CF_ARCH" # Linux uses binary or .deb/.rpm sometimes
        fi

        CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-$cf_os_arch_suffix"
        echo "Attempting to download cloudflared from $CF_URL"

        if [[ "$OSTYPE" == "darwin"* ]]; then
            if wget -q --show-progress "$CF_URL" -O cloudflared.tgz; then
                tar -xzf cloudflared.tgz
                # The binary might be in a subdirectory or named differently, e.g., just 'cloudflared' or 'cloudflared-darwin-amd64'
                # Assuming it extracts as 'cloudflared' for simplicity. This might need adjustment.
                if [ ! -f "cloudflared" ] && [ -f "cloudflared-*" ]; then # Check if it has a different name
                    mv cloudflared-* cloudflared
                fi
                rm cloudflared.tgz
            else
                 echo -e "${RED}${BOLD}[✗] Failed to download cloudflared for macOS.${NC}"
                 return 1
            fi
        else # Linux
            if ! wget -q --show-progress "$CF_URL" -O cloudflared; then
                echo -e "${RED}${BOLD}[✗] Failed to download cloudflared for Linux.${NC}"
                return 1
            fi
        fi
        
        if [ ! -f "cloudflared" ]; then
            echo -e "${RED}${BOLD}[✗] Cloudflared binary not found after download/extraction.${NC}"
            return 1
        fi

        chmod +x cloudflared
        if sudo mv cloudflared /usr/local/bin/; then
            echo -e "${GREEN}${BOLD}[✓] Cloudflared installed successfully to /usr/local/bin/.${NC}"
            return 0
        else
            echo -e "${RED}${BOLD}[✗] Failed to move cloudflared to /usr/local/bin/. Try with sudo or check permissions.${NC}"
            # Try current directory if sudo fails for some reason and /usr/local/bin is not writable without sudo by script
            if mv cloudflared "$ROOT/cloudflared_executable"; then
                 echo -e "${YELLOW}${BOLD}[!] Moved cloudflared to $ROOT/cloudflared_executable. Ensure this is in your PATH or use absolute path.${NC}"
                 return 0 # Or return 1 if /usr/local/bin is strictly required
            fi
            return 1
        fi
    }

    install_ngrok() {
        if command -v ngrok >/dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}[✓] ngrok is already installed.${NC}"
            return 0
        fi
        echo -e "${YELLOW}${BOLD}[✓] Installing ngrok...${NC}"
        # NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-$OS_KERNEL-$NGROK_ARCH.tgz" # Original
        # Updated ngrok URL structure (example, check actual ngrok docs for latest)
        # Example: https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-darwin-amd64.zip for macOS
        # Example: https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip for Linux
        # The old URL might still work, but it's good to be aware of potential changes.
        # The provided script has a specific ngrok URL, let's stick to it unless it fails.
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-$OS_KERNEL-$NGROK_ARCH.tgz"
        if [[ "$OSTYPE" == "darwin"* ]] && [[ "$NGROK_ARCH" == "amd64" ]]; then # Common macOS setup
            NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip" # ngrok often uses .zip for mac
        elif [[ "$OSTYPE" == "darwin"* ]] && [[ "$NGROK_ARCH" == "arm64" ]]; then
            NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip"
        elif [[ "$OS_KERNEL" == "linux" ]]; then
             NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-$NGROK_ARCH.zip" # ngrok also provides .zip for linux
        fi


        echo "Attempting to download ngrok from $NGROK_URL"
        DOWNLOAD_EXT=".tgz"
        if [[ "$NGROK_URL" == *.zip ]]; then
            DOWNLOAD_EXT=".zip"
        fi
        
        if ! wget -q --show-progress "$NGROK_URL" -O "ngrok$DOWNLOAD_EXT"; then
            echo -e "${RED}${BOLD}[✗] Failed to download ngrok.${NC}"
            return 1
        fi

        if [[ "$DOWNLOAD_EXT" == ".zip" ]]; then
            if ! unzip -o "ngrok$DOWNLOAD_EXT" > /dev/null 2>&1; then # -o for overwrite
                echo -e "${RED}${BOLD}[✗] Failed to extract ngrok (zip).${NC}"
                rm "ngrok$DOWNLOAD_EXT"
                return 1
            fi
        else # .tgz
            if ! tar -xzf "ngrok$DOWNLOAD_EXT"; then
                echo -e "${RED}${BOLD}[✗] Failed to extract ngrok (tgz).${NC}"
                rm "ngrok$DOWNLOAD_EXT"
                return 1
            fi
        fi
        
        if [ ! -f "ngrok" ]; then
             echo -e "${RED}${BOLD}[✗] ngrok binary not found after extraction.${NC}"
             rm "ngrok$DOWNLOAD_EXT"
             return 1
        fi

        if sudo mv ngrok /usr/local/bin/; then
             echo -e "${GREEN}${BOLD}[✓] ngrok installed successfully to /usr/local/bin/.${NC}"
        else
            echo -e "${RED}${BOLD}[✗] Failed to move ngrok to /usr/local/bin/. Try with sudo or check permissions.${NC}"
            # Fallback to current directory
            if mv ngrok "$ROOT/ngrok_executable"; then
                 echo -e "${YELLOW}${BOLD}[!] Moved ngrok to $ROOT/ngrok_executable. Ensure this is in your PATH or use absolute path.${NC}"
            else
                rm "ngrok$DOWNLOAD_EXT" # Clean up downloaded file
                return 1
            fi
        fi
        rm "ngrok$DOWNLOAD_EXT" # Clean up downloaded file
        return 0
    }


    try_localtunnel() {
        echo -e "\n${CYAN}${BOLD}[✓] Trying localtunnel...${NC}"
        if install_localtunnel; then
            echo -e "\n${CYAN}${BOLD}[✓] Starting localtunnel on port $PORT...${NC}"
            TUNNEL_TYPE="localtunnel"
            # Check if $PORT is set
            if [ -z "$PORT" ]; then
                echo -e "${RED}${BOLD}[✗] Server port not identified. Cannot start localtunnel.${NC}"
                return 1
            fi
            lt --port "$PORT" > localtunnel_output.log 2>&1 &
            TUNNEL_PID=$!
            sleep 5 # Give localtunnel time to start and output URL
            URL=$(grep -o "https://[^ ]*" localtunnel_output.log | head -n1)
            if [ -n "$URL" ]; then
                # The password retrieval for localtunnel is not standard and might be specific to a certain setup or service.
                # This part: PASS=$(curl -s https://loca.lt/mytunnelpassword) is highly specific and likely won't work generally.
                # For a general solution, localtunnel usually just provides a URL without a separate password step like this.
                # If a password is required, it's usually part of the `lt` command or its output.
                echo -e "${GREEN}${BOLD}[✓] Localtunnel URL: ${YELLOW}${BOLD}${URL}${NC}"
                echo -e "${GREEN}${BOLD}Please visit this website and then log in using your email.${NC}"
                FORWARDING_URL="$URL"
                return 0
            else
                echo -e "${RED}${BOLD}[✗] Failed to get localtunnel URL. Check localtunnel_output.log.${NC}"
                cat localtunnel_output.log
                [[ "$TUNNEL_PID" =~ ^[0-9]+$ ]] && kill $TUNNEL_PID 2>/dev/null || true
            fi
        fi
        return 1
    }

    try_cloudflared() {
        echo -e "\n${CYAN}${BOLD}[✓] Trying cloudflared...${NC}"
        if install_cloudflared; then
            echo -e "\n${CYAN}${BOLD}[✓] Starting cloudflared tunnel...${NC}"
            TUNNEL_TYPE="cloudflared"
            if [ -z "$PORT" ]; then
                echo -e "${RED}${BOLD}[✗] Server port not identified. Cannot start cloudflared.${NC}"
                return 1
            fi
            # Ensure cloudflared is executable if it was moved to ROOT
            local cloudflared_cmd="cloudflared"
            if [ -x "$ROOT/cloudflared_executable" ]; then
                cloudflared_cmd="$ROOT/cloudflared_executable"
            elif ! command -v cloudflared &>/dev/null; then
                 echo -e "${RED}${BOLD}[✗] cloudflared command not found.${NC}"
                 return 1
            fi

            "$cloudflared_cmd" tunnel --url http://localhost:"$PORT" > cloudflared_output.log 2>&1 &
            TUNNEL_PID=$!
            counter=0
            MAX_WAIT_TUNNEL=15 # Increased wait time for tunnel URL
            CLOUDFLARED_URL=""
            while [ $counter -lt $MAX_WAIT_TUNNEL ]; do
                # More robust grep for cloudflared URL
                CLOUDFLARED_URL=$(grep -Eo 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' cloudflared_output.log | head -n1)
                if [ -n "$CLOUDFLARED_URL" ]; then
                    echo -e "${GREEN}${BOLD}[✓] Cloudflared tunnel URL obtained: $CLOUDFLARED_URL${NC}"
                    echo -e "\n${CYAN}${BOLD}[✓] Checking if cloudflared URL is working...${NC}"
                    if check_url "$CLOUDFLARED_URL"; then
                        FORWARDING_URL="$CLOUDFLARED_URL"
                        echo -e "${GREEN}${BOLD}[✓] Cloudflared tunnel is accessible.${NC}"
                        return 0
                    else
                        echo -e "${RED}${BOLD}[✗] Cloudflared URL ($CLOUDFLARED_URL) is not accessible. Retrying...${NC}"
                        # Do not break immediately, let it retry check_url or tunnel establishment
                    fi
                fi
                sleep 2 # Check every 2 seconds
                counter=$((counter + 1))
            done
            echo -e "${RED}${BOLD}[✗] Failed to get a working cloudflared URL or timed out. Check cloudflared_output.log.${NC}"
            cat cloudflared_output.log
            [[ "$TUNNEL_PID" =~ ^[0-9]+$ ]] && kill $TUNNEL_PID 2>/dev/null || true
        fi
        return 1
    }
    
    # ngrok URL extraction methods
    get_ngrok_url_method1() { # JSON log
        grep -o '"url":"https://[^"]*' ngrok_output.log 2>/dev/null | head -n1 | cut -d'"' -f4
    }
    get_ngrok_url_method2() { # API
        local url=""
        for try_port in $(seq 4040 4045); do # Default ngrok API ports
            local response=$(curl -s "http://localhost:$try_port/api/tunnels" 2>/dev/null)
            if [ -n "$response" ]; then
                url=$(echo "$response" | grep -o '"public_url":"https://[^"]*' | head -n1 | cut -d'"' -f4)
                if [ -n "$url" ]; then break; fi
            fi
        done
        echo "$url"
    }
    get_ngrok_url_method3() { # Plain text log
        grep -o "Forwarding[[:space:]]*https://[^ ]*" ngrok_output.log 2>/dev/null | awk '{print $2}' | head -n1
    }


    try_ngrok() {
        echo -e "\n${CYAN}${BOLD}[✓] Trying ngrok...${NC}"
        if install_ngrok; then
            TUNNEL_TYPE="ngrok"
            if [ -z "$PORT" ]; then
                echo -e "${RED}${BOLD}[✗] Server port not identified. Cannot start ngrok.${NC}"
                return 1
            fi
             local ngrok_cmd="ngrok"
            if [ -x "$ROOT/ngrok_executable" ]; then
                ngrok_cmd="$ROOT/ngrok_executable"
            elif ! command -v ngrok &>/dev/null; then
                 echo -e "${RED}${BOLD}[✗] ngrok command not found.${NC}"
                 return 1
            fi


            while true; do
                echo -e "\n${YELLOW}${BOLD}To get your ngrok authtoken:${NC}"
                echo "1. Sign up or log in at https://dashboard.ngrok.com"
                echo "2. Go to 'Your Authtoken' section: https://dashboard.ngrok.com/get-started/your-authtoken"
                # echo "3. Click on the eye icon to reveal your ngrok auth token" # Steps might change
                echo "3. Copy your auth token and paste it in the prompt below"
                echo -e "\n${BOLD}Please enter your ngrok authtoken:${NC}"
                read -r -p "> " NGROK_TOKEN # -r to prevent backslash escapes
                if [ -z "$NGROK_TOKEN" ]; then
                    echo -e "${RED}${BOLD}[✗] No token provided. Please enter a valid token.${NC}"
                    continue
                fi
                pkill -f ngrok 2>/dev/null || true # Kill existing ngrok instances
                sleep 1
                if "$ngrok_cmd" authtoken "$NGROK_TOKEN" --log=stderr; then # Log to stderr to see errors
                    echo -e "${GREEN}${BOLD}[✓] Successfully authenticated ngrok!${NC}"
                    break
                else
                    echo -e "${RED}[✗] Authentication failed. Please check your token and try again.${NC}"
                fi
            done
            
            # Try ngrok methods
            echo -e "\n${CYAN}${BOLD}[✓] Starting ngrok with method 1 (JSON log)...${NC}"
            "$ngrok_cmd" http "$PORT" --log=stdout --log-format=json > ngrok_output.log 2>&1 &
            TUNNEL_PID=$!
            sleep 5
            NGROK_URL=$(get_ngrok_url_method1)
            if [ -n "$NGROK_URL" ] && check_url "$NGROK_URL"; then FORWARDING_URL="$NGROK_URL"; return 0; else [[ "$TUNNEL_PID" =~ ^[0-9]+$ ]] && kill $TUNNEL_PID 2>/dev/null || true; echo -e "${RED}${BOLD}[✗] Failed method 1.${NC}"; fi

            echo -e "\n${CYAN}${BOLD}[✓] Starting ngrok with method 2 (API)...${NC}"
            "$ngrok_cmd" http "$PORT" --log=ngrok_plain.log > /dev/null 2>&1 & # Simpler log for this one
            TUNNEL_PID=$!
            sleep 5
            NGROK_URL=$(get_ngrok_url_method2)
            if [ -n "$NGROK_URL" ] && check_url "$NGROK_URL"; then FORWARDING_URL="$NGROK_URL"; return 0; else [[ "$TUNNEL_PID" =~ ^[0-9]+$ ]] && kill $TUNNEL_PID 2>/dev/null || true; echo -e "${RED}${BOLD}[✗] Failed method 2.${NC}"; fi
            
            echo -e "\n${CYAN}${BOLD}[✓] Starting ngrok with method 3 (Plain text log)...${NC}"
            "$ngrok_cmd" http "$PORT" --log=stdout > ngrok_output.log 2>&1 &
            TUNNEL_PID=$!
            sleep 5
            NGROK_URL=$(get_ngrok_url_method3)
            if [ -n "$NGROK_URL" ] && check_url "$NGROK_URL"; then FORWARDING_URL="$NGROK_URL"; return 0; else [[ "$TUNNEL_PID" =~ ^[0-9]+$ ]] && kill $TUNNEL_PID 2>/dev/null || true; echo -e "${RED}${BOLD}[✗] Failed method 3.${NC}"; fi
        fi
        return 1
    }


    start_tunnel() {
        if try_localtunnel; then return 0; fi
        echo -e "${YELLOW}[!] Localtunnel failed. Trying Cloudflared...${NC}"
        if try_cloudflared; then return 0; fi
        echo -e "${YELLOW}[!] Cloudflared failed. Trying ngrok...${NC}"
        if try_ngrok; then return 0; fi
        return 1
    }

    start_tunnel
    if [ $? -eq 0 ]; then
        if [ "$TUNNEL_TYPE" != "localtunnel" ] || [ -z "$(echo "$FORWARDING_URL" | grep 'loca.lt')" ]; then # Localtunnel has specific messaging already
             echo -e "${GREEN}${BOLD}[✓] Success! Please visit this website and log in using your email:${NC} ${CYAN}${BOLD}${FORWARDING_URL}${NC}"
        fi
    else
        echo -e "\n${RED}${BOLD}[✗] All automated tunneling methods failed.${NC}"
        echo -e "${BLUE}${BOLD}You can try a manual method if ngrok is installed:${NC}"
        echo "1. Ensure ngrok is installed and authenticated."
        echo "2. In a new terminal, run: ${YELLOW}ngrok http $PORT${NC} (where $PORT is the port your local server is running on, likely $PORT)"
        echo "3. Ngrok will provide a forwarding URL (e.g., https://xxxx.ngrok-free.app)."
        echo "4. Visit this URL in your browser and log in with your email. It might take ~30 seconds to load."
        echo "5. Return to this terminal. The script will wait for the login to complete."
    fi
    cd .. # Return to ROOT from modal-login
    echo -e "\n${CYAN}${BOLD}[↻] Waiting for you to complete the login process (userData.json creation)...${NC}"
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        echo -n "." # Progress indicator
        sleep 3
    done
    echo -e "\n${GREEN}${BOLD}[✓] Success! The userData.json file has been created. Proceeding with remaining setups...${NC}"
    rm -f modal-login/server.log modal-login/localtunnel_output.log modal-login/cloudflared_output.log modal-login/ngrok_output.log modal-login/ngrok_plain.log 2>/dev/null
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo -e "\n${CYAN}${BOLD}[✓] ORG_ID has been set to: $ORG_ID\n${NC}"

    echo -e "${CYAN}${BOLD}[✓] Waiting for API key to become activated...${NC}"
    API_KEY_URL="http://localhost:$PORT/api/get-api-key-status?orgId=$ORG_ID" # Use identified PORT
    if [ -z "$PORT" ]; then # Fallback if PORT was not found (e.g. if userData.json existed before server start)
        API_KEY_URL="http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID" # Default to 3000
        echo -e "${YELLOW}[!] Server port for API key check not dynamically found, defaulting to 3000.${NC}"
    fi

    while true; do
        STATUS=$(curl -s "$API_KEY_URL")
        if [[ "$STATUS" == "activated" ]]; then # Exact match
            echo -e "${GREEN}${BOLD}[✓] Success! API key is activated! Proceeding...\n${NC}"
            break
        else
            echo -e "[↻] Waiting for API key to be activated (Status: $STATUS)..."
            sleep 5
        fi
    done
    ENV_FILE="$ROOT"/modal-login/.env
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version of sed
        sed -i '' "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    else
        # Linux version of sed
        sed -i "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    fi
fi # End of if/else for modal-login/temp-data/userData.json

echo -e "${CYAN}${BOLD}[✓] Setting up Python virtual environment...${NC}"
if python3 -m venv --copies .venv && source .venv/bin/activate; then
    echo -e "${GREEN}${BOLD}[✓] Python virtual environment set up and activated successfully.${NC}"
else
    echo -e "${RED}${BOLD}[✗] Failed to set up or activate virtual environment.${NC}"
    exit 1
fi

# CONFIG_PATH logic
if [ -z "$CONFIG_PATH" ]; then # Only set if not already set
    if [ "$CPU_ONLY" = "false" ]; then # GPU path
        echo -e "${GREEN}${BOLD}[✓] GPU detected by script logic, configuring for GPU.${NC}"
        case "$PARAM_B" in
            32 | 72) CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-bnb-4bit-deepseek-r1.yaml" ;;
            0.5 | 1.5 | 7) CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-${PARAM_B}b-deepseek-r1.yaml" ;;
            *) echo ">>> Parameter size $PARAM_B not recognized for GPU. Defaulting to 0.5b."
               CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml" ;;
        esac
        if [ "$USE_BIG_SWARM" = true ]; then GAME="dapo"; else GAME="gsm8k"; fi
        echo -e "${GREEN}${BOLD}[✓] Config file (GPU): ${BOLD}$CONFIG_PATH\n${NC}"
        echo -e "${CYAN}${BOLD}[✓] Installing GPU-specific requirements...${NC}"
        pip install -r "$ROOT"/requirements-gpu.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
        pip install flash-attn --no-build-isolation # This might need specific CUDA toolkit version
    else # CPU path (includes macOS)
        echo -e "${YELLOW}${BOLD}[✓] No GPU detected or CPU-only mode, using CPU/macOS configuration.${NC}"
        pip install -r "$ROOT"/requirements-cpu.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
        # pip install torch torchvision torchaudio
        # pip install hivemind@git+https://github.com/learning-at-home/hivemind@1.11.11
        # For macOS, the config path should point to a mac-specific or generic CPU config
        # The original script had a specific mac config for 0.5b. We can adapt or generalize.
        if [[ "$OSTYPE" == "darwin"* ]]; then
             CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml" # Default mac
             # Could add logic based on PARAM_B for mac if different configs exist
             echo -e "${CYAN}${BOLD}[✓] Using macOS specific config for 0.5b parameter size (default for Mac).${NC}"
        else # Generic CPU for Linux
            # Assuming a generic CPU config or the smallest one if specific CPU configs don't exist.
            CONFIG_PATH="$ROOT/hivemind_exp/configs/cpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml" # Example path
            echo -e "${CYAN}${BOLD}[✓] Using generic CPU config for 0.5b parameter size (default for CPU).${NC}"
        fi
        GAME="gsm8k" # Default game for CPU/Mac
        echo -e "${CYAN}${BOLD}[✓] Config file (CPU/Mac): ${BOLD}$CONFIG_PATH\n${NC}"
    fi
fi


if [ -n "${HF_TOKEN}" ]; then
    HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
else
    echo -e "\n${CYAN}Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N]${NC}"
    read -r -p "> " yn
    yn=${yn:-N}
    case "$yn" in
        [Yy]*) read -r -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN ;;
        [Nn]*) HUGGINGFACE_ACCESS_TOKEN="None" ;;
        *) echo -e "${YELLOW}>>> No answer was given, so NO models will be pushed to the Hugging Face Hub.${NC}"
           HUGGINGFACE_ACCESS_TOKEN="None" ;;
    esac
fi

echo -e "\n${CYAN}${BOLD}This is your preferred ENV for this training session :\n${NC}"
print_env() {
    local name=$1
    local value # Declare local variable
    value=$(eval echo "\$$name") # Safely get variable value
    value=${value:-"Not Available"}
    echo -e "+ ${PURPLE}${BOLD}${name}${NC} : ${value}"
}
print_env "HF_TOKEN" # This will show what was originally in env
print_env "HUGGINGFACE_ACCESS_TOKEN" # This will show the one being used
print_env "ORG_ID"
print_env "IDENTITY_PATH"
print_env "SWARM_CONTRACT"
print_env "CONFIG_PATH"
print_env "GAME"
print_env "PUB_MULTI_ADDRS"
print_env "PEER_MULTI_ADDRS"
print_env "HOST_MULTI_ADDRS"
print_env "CPU_ONLY"
print_env "OSTYPE"

sleep 3 # Reduced sleep

echo -e "\n${GREEN}${BOLD}[✓] Good luck in the swarm! Your training session is about to begin.\n${NC}"

# Ensure python files exist before trying to sed them
HIVEP2P_DAEMON_FILE=$(python3 -c "import sys; import hivemind.p2p.p2p_daemon as m; sys.stdout.write(m.__file__)" 2>/dev/null)
HIVEDHT_NODE_FILE=$(python3 -c "import sys; import hivemind.dht.node as m; sys.stdout.write(m.__file__)" 2>/dev/null)

if [ -n "$HIVEP2P_DAEMON_FILE" ] && [ -f "$HIVEP2P_DAEMON_FILE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' -E 's/(startup_timeout: *float *= *)[0-9.]+/\1120.0/' "$HIVEP2P_DAEMON_FILE"
    else
        sed -i -E 's/(startup_timeout: *float *= *)[0-9.]+/\1120.0/' "$HIVEP2P_DAEMON_FILE"
    fi
else
    echo -e "${YELLOW}[!] Could not find hivemind.p2p.p2p_daemon file to modify startup_timeout.${NC}"
fi

if [ -n "$HIVEDHT_NODE_FILE" ] && [ -f "$HIVEDHT_NODE_FILE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' -e 's/bootstrap_timeout: Optional\[float\] = None/bootstrap_timeout: float = 120.0/' "$HIVEDHT_NODE_FILE"
    else
        sed -i -e 's/bootstrap_timeout: Optional\[float\] = None/bootstrap_timeout: float = 120.0/' "$HIVEDHT_NODE_FILE"
    fi
else
     echo -e "${YELLOW}[!] Could not find hivemind.dht.node file to modify bootstrap_timeout.${NC}"
fi


# Check if critical variables are set
if [ -z "$CONFIG_PATH" ]; then
    echo -e "${RED}${BOLD}[✗] CONFIG_PATH is not set. Cannot start training. Exiting.${NC}"
    exit 1
fi
if [ -z "$GAME" ]; then
    echo -e "${RED}${BOLD}[✗] GAME is not set. Cannot start training. Exiting.${NC}"
    exit 1
fi


if [ -n "$ORG_ID" ]; then
    python3 -m hivemind_exp.gsm8k.train_single_gpu \
    --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
    --identity_path "$IDENTITY_PATH" \
    --modal_org_id "$ORG_ID" \
    --contract_address "$SWARM_CONTRACT" \
    --config "$CONFIG_PATH" \
    --game "$GAME"
else
    python3 -m hivemind_exp.gsm8k.train_single_gpu \
    --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
    --identity_path "$IDENTITY_PATH" \
    --public_maddr "$PUB_MULTI_ADDRS" \
    --initial_peers "$PEER_MULTI_ADDRS" \
    --host_maddr "$HOST_MULTI_ADDRS" \
    --config "$CONFIG_PATH" \
    --game "$GAME"
fi

wait # Wait for background processes if any (python script runs in foreground)
echo -e "${GREEN}${BOLD}[✓] Training script finished.${NC}"
