#!/data/data/com.termux/files/usr/bin/bash

# Termux Auto-Reconnector Bootstrapper
# This script is designed to be run via: curl | bash

# When piped to bash, standard input is consumed by the pipe. 
# We explicitly force 'read' to take input directly from the user's terminal (/dev/tty).
exec < /dev/tty

echo "======================================"
echo "    Roblox Termux Auto-Reconnector    "
echo "                Setup                 "
echo "======================================"

# --- Security Authentication ---
read -p "Enter the Authentication Key to continue: " user_key
if [[ "$user_key" != "KEY_RITIK" ]]; then
    echo "Given key is invalid or expaired. for more info contact us on discord."
    exit 1
fi
echo "Authentication successful!"
echo ""

# --- Dependency Installation ---
echo "Checking and installing essential Termux packages (tsu, procps, etc.)..."
echo "This might take a moment on the first run..."
pkg update -y
pkg install -y tsu procps coreutils ncurses-utils
echo "Essential packages successfully verified/installed."
echo ""

# --- Download Main Application ---
echo "Downloading core GUI script..."
curl -# -L "https://raw.githubusercontent.com/RiTiKM416/Roblox-reconnector/main/gui_reconnector.sh" -o "$PREFIX/bin/roblox-reconnector"
chmod +x "$PREFIX/bin/roblox-reconnector"

echo ""
echo "Installation complete!"
echo "Starting the application..."
echo ""

# Execute the downloaded GUI directly without the pipe constraint
exec "$PREFIX/bin/roblox-reconnector"
