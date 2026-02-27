#!/usr/bin/env bash

# Check if blueutil is installed
if ! command -v blueutil &> /dev/null; then
    echo "blueutil could not be found. Please install it with 'brew install blueutil'."
    exit 1
fi

if [ -n "$1" ]; then
    MAC="$1"
    echo "Using provided MAC: $MAC"
else
    echo "Please press 1+2 on your Wiimote now..."
    # Scan for Wiimote
    INFO=$(blueutil --inquiry 5)
    MAC=$(echo "$INFO" | grep -iE 'Nintendo|Wiimote' | head -n 1 | awk '/address:/ {print $2}' | tr -d ',')
    
    if [ -z "$MAC" ]; then
        echo "No Wiimote found. Please ensure it is in pairing mode (LEDs blinking)."
        exit 1
    fi
    echo "Found Wiimote: $MAC"
fi

# Unpair first to clear state
echo "Clearing any existing pairing..."
blueutil --unpair "$MAC" &>/dev/null

# Convert MAC (00-1e-35-28-5a-25) to HEX string (001e35285a25)
HEX=$(echo "$MAC" | tr -d '-')

# Reverse the MAC bytes for PIN
# MAC: 00 1e 35 28 5a 25
# PIN: 25 5a 28 35 1e 00
PIN_HEX="\x${HEX:10:2}\x${HEX:8:2}\x${HEX:6:2}\x${HEX:4:2}\x${HEX:2:2}\x${HEX:0:2}"

echo "Generated PIN (reverse MAC): $PIN_HEX"

echo "Attempting to pair..."
# Echo the PIN as bytes and pipe to blueutil pair command
# Using printf to ensure correct byte output without newline
printf "$PIN_HEX" | blueutil --pair "$MAC"

if [ $? -eq 0 ]; then
    echo "Pairing successful!"
    echo "Connecting..."
    blueutil --connect "$MAC"
    if [ $? -eq 0 ]; then
        echo "Connected!"
    else
        echo "Failed to connect."
    fi
else
    echo "Pairing failed."
fi
