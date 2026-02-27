#!/usr/bin/env bash

# Check if blueutil is installed
if ! command -v blueutil &> /dev/null; then
    echo "blueutil could not be found. Please install it with 'brew install blueutil'."
    exit 1
fi

HOST_ADDR="9C:58:84:66:89:C5"
echo "Host Bluetooth Address: $HOST_ADDR"

if [ -n "$1" ]; then
    MAC="$1"
    echo "Using provided MAC: $MAC"
else
    echo ">>> Please press the RED SYNC button on your Wiimote (under the battery cover) <<<"
    # echo "Press ENTER to start scanning..."
    # read

    # Scan for Wiimote
    INFO=$(blueutil --inquiry 5)
    MAC=$(echo "$INFO" | grep -iE 'Nintendo|Wiimote' | head -n 1 | awk '/address:/ {print $2}' | tr -d ',')
    
    if [ -z "$MAC" ]; then
        echo "No Wiimote found. Please ensure it is in SYNC mode (LEDs blinking)."
        exit 1
    fi
    echo "Found Wiimote: $MAC"
fi

# Unpair first to clear state
echo "Clearing any existing pairing..."
blueutil --unpair "$MAC" &>/dev/null

# For Red Sync button method, PIN is HOST address reversed
# Host: 9C:58:84:66:89:C5
# Reverse: C5 89 66 84 58 9C
HEX=$(echo "$HOST_ADDR" | tr -d ':')
PIN_HEX="\x${HEX:10:2}\x${HEX:8:2}\x${HEX:6:2}\x${HEX:4:2}\x${HEX:2:2}\x${HEX:0:2}"

echo "Generated PIN (reverse Host MAC): $PIN_HEX"

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
