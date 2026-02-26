#!/data/data/com.termux/files/usr/bin/bash

# Termux Auto-Reconnector Bootstrapper
# This script is designed to be run via: curl | bash

# This script is designed to be downloaded and run locally.

echo "======================================"
echo "    Roblox Termux Auto-Reconnector    "
echo "                Setup                 "
echo "======================================"

# --- Security Authentication ---
while true; do
    read -p "Enter the Authentication Key to continue: " user_key
    if [[ "$user_key" == "KEY_RITIK" ]]; then
        echo "Authentication successful!"
        echo ""
        break
    else
        echo "Given key is invalid or expired. For more info contact us on discord."
        echo ""
    fi
done

# --- Dependency Installation ---
echo "Checking and installing essential Termux packages (tsu, procps, etc.)..."
echo "This might take a moment on the first run..."
pkg update -y
pkg install -y tsu procps coreutils ncurses-utils
echo "Essential packages successfully verified/installed."
echo ""

# --- Download Main Application ---
echo "Downloading core GUI script..."
curl -sL "https://raw.githubusercontent.com/RiTiKM416/Roblox-reconnector/main/gui_reconnector.sh" -o "$PREFIX/bin/roblox-reconnector" &
CURL_PID=$!

spin='-\|/'
i=0
while kill -0 $CURL_PID 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r\e[36m[${spin:$i:1}] Downloading...\e[0m"
    sleep 0.1
done

printf "\r\e[32m[✓] Download complete!       \e[0m\n"
chmod +x "$PREFIX/bin/roblox-reconnector"

echo ""
echo "Installation complete!"
echo "Starting the application..."
echo ""

# Execute the downloaded GUI directly without the pipe constraint
exec "$PREFIX/bin/roblox-reconnector"
