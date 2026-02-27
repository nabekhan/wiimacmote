#!/bin/bash
# Test Wiimote pairing from the command line
# Trying multiple approaches to find what works

WIIMOTE_ADDR="00-1e-35-28-5a-25"
HOST_ADDR="9C:58:84:66:89:C5"

echo "=========================================="
echo " Wiimote Pairing Test Script"
echo "=========================================="
echo ""
echo " Wiimote MAC:  $WIIMOTE_ADDR"
echo " Host BT MAC:  $HOST_ADDR"
echo ""
echo " For Wiimote pairing, the PIN is the host"
echo " BT address bytes reversed: C5:89:66:84:58:9C"
echo ""

# First, make sure any stale pairing is removed
echo "--- Step 0: Removing any stale pairing ---"
blueutil --unpair "$WIIMOTE_ADDR" 2>&1
echo ""

echo "=========================================="
echo " TEST 1: blueutil --pair (no PIN)"
echo "=========================================="
echo ""
echo " >>> Press the RED SYNC button on the Wiimote NOW <<<"
echo " >>> Then press ENTER here within 3 seconds        <<<"
echo ""
read -p "Press ENTER after pressing SYNC..."
echo ""
echo "Pairing NOW (no PIN)..."
echo "Running: blueutil --pair $WIIMOTE_ADDR"
START=$(python3 -c "import time; print(time.time())")
blueutil --pair "$WIIMOTE_ADDR" 2>&1
EXIT_CODE=$?
END=$(python3 -c "import time; print(time.time())")
DURATION=$(python3 -c "print(f'{$END - $START:.1f}')")
echo ""
echo "Exit code: $EXIT_CODE (took ${DURATION}s)"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS! Pairing worked without PIN."
    echo "Checking paired devices..."
    blueutil --info "$WIIMOTE_ADDR" --format json-pretty 2>&1
    exit 0
fi

echo "Failed. Removing stale pairing and trying with PIN..."
blueutil --unpair "$WIIMOTE_ADDR" 2>&1
sleep 1

echo ""
echo "=========================================="
echo " TEST 2: blueutil --pair with binary PIN"
echo "         (host addr reversed: C5 89 66 84 58 9C)"
echo "=========================================="
echo ""
echo " >>> Press the RED SYNC button on the Wiimote NOW <<<"
echo " >>> Then press ENTER here within 3 seconds        <<<"
echo ""
read -p "Press ENTER after pressing SYNC..."
echo ""
echo "Pairing NOW (with reversed host address as PIN)..."
# PIN = host BT address reversed as binary bytes
PIN=$'\xC5\x89\x66\x84\x58\x9C'
echo "Running: blueutil --pair $WIIMOTE_ADDR <6-byte-binary-PIN>"
START=$(python3 -c "import time; print(time.time())")
blueutil --pair "$WIIMOTE_ADDR" "$PIN" 2>&1
EXIT_CODE=$?
END=$(python3 -c "import time; print(time.time())")
DURATION=$(python3 -c "print(f'{$END - $START:.1f}')")
echo ""
echo "Exit code: $EXIT_CODE (took ${DURATION}s)"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS! Pairing worked with reversed host address PIN."
    blueutil --info "$WIIMOTE_ADDR" --format json-pretty 2>&1
    exit 0
fi

echo "Failed. Removing stale pairing and trying alternate PIN..."
blueutil --unpair "$WIIMOTE_ADDR" 2>&1
sleep 1

echo ""
echo "=========================================="
echo " TEST 3: blueutil --pair with Wiimote addr as PIN"
echo "         (wiimote addr reversed: 25 5A 28 35 1E 00)"
echo "=========================================="
echo ""
echo " >>> Press the RED SYNC button on the Wiimote NOW <<<"
echo " >>> Then press ENTER here within 3 seconds        <<<"
echo ""
read -p "Press ENTER after pressing SYNC..."
echo ""
echo "Pairing NOW (with reversed Wiimote address as PIN)..."
# PIN = Wiimote BT address reversed as binary bytes
PIN=$'\x25\x5A\x28\x35\x1E\x00'
echo "Running: blueutil --pair $WIIMOTE_ADDR <6-byte-wiimote-addr-PIN>"
START=$(python3 -c "import time; print(time.time())")
blueutil --pair "$WIIMOTE_ADDR" "$PIN" 2>&1
EXIT_CODE=$?
END=$(python3 -c "import time; print(time.time())")
DURATION=$(python3 -c "print(f'{$END - $START:.1f}')")
echo ""
echo "Exit code: $EXIT_CODE (took ${DURATION}s)"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS! Pairing worked with reversed Wiimote address PIN."
    blueutil --info "$WIIMOTE_ADDR" --format json-pretty 2>&1
    exit 0
fi

echo "Failed. Removing stale pairing..."
blueutil --unpair "$WIIMOTE_ADDR" 2>&1
sleep 1

echo ""
echo "=========================================="
echo " TEST 4: blueutil --connect (skip pair, just connect)"
echo "=========================================="
echo ""
echo " >>> Press and HOLD 1+2 on the Wiimote NOW <<<"
echo " >>> Then press ENTER here within 3 seconds <<<"
echo ""
read -p "Press ENTER after pressing 1+2..."
echo ""
echo "Connecting NOW..."
echo "Running: blueutil --connect $WIIMOTE_ADDR"
START=$(python3 -c "import time; print(time.time())")
blueutil --connect "$WIIMOTE_ADDR" 2>&1
EXIT_CODE=$?
END=$(python3 -c "import time; print(time.time())")
DURATION=$(python3 -c "print(f'{$END - $START:.1f}')")
echo ""
echo "Exit code: $EXIT_CODE (took ${DURATION}s)"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS! Direct connect worked."
    blueutil --info "$WIIMOTE_ADDR" --format json-pretty 2>&1
    exit 0
fi

echo ""
echo "=========================================="
echo " ALL TESTS FAILED"
echo "=========================================="
echo ""
echo "Summary of errors. The Wiimote may require"
echo "the IOBluetooth private API approach with"
echo "the custom PIN code callback."
echo ""
echo "Next steps to try:"
echo "  1. Use WiimotePair app from Dolphin project"
echo "  2. Use the IOBluetooth API approach in wiimacmote"
echo "  3. Try on a different macOS version"
