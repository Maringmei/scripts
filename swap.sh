#!/bin/bash
#
# Ubuntu Smart Swap Manager v2.0
# Ubuntu 20.04 / 22.04 / 24.04
#

set -euo pipefail

SWAPFILE="/swapfile"

########################################
# Root Check
########################################
if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run with sudo."
    exit 1
fi

########################################
# Detect RAM
########################################
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
RAM_GB=$(( (RAM_MB + 1023) / 1024 ))

########################################
# Recommend Swap
########################################
if (( RAM_GB <= 2 )); then
    REC_SWAP=2
    SWAPPINESS=30
elif (( RAM_GB <= 4 )); then
    REC_SWAP=2
    SWAPPINESS=20
elif (( RAM_GB <= 8 )); then
    REC_SWAP=4
    SWAPPINESS=15
else
    REC_SWAP=4
    SWAPPINESS=10
fi

########################################
# Show Current Swap
########################################
show_swap() {
    echo
    echo "Current Active Swap"
    echo "----------------------------------------"

    if swapon --show | grep -q .; then
        swapon --show
    else
        echo "No active swap."
    fi

    echo "----------------------------------------"

    TOTAL=$(free -h | awk '/Swap:/ {print $2}')
    echo "Total Swap : $TOTAL"
    echo
}

########################################
# Reset Swap
########################################
reset_swap() {

    echo
    echo "Removing all swap..."

    swapoff -a || true

    rm -f "$SWAPFILE"

    # Remove all swap entries
    sed -i '/ swap /d' /etc/fstab

    rm -f /etc/sysctl.d/99-smart-swap.conf

    sysctl --system >/dev/null

    echo
    echo "✅ Swap removed successfully."

    show_swap
}

########################################
# Create / Resize
########################################
create_swap() {

    read -rp "Enter swap size in GB [${REC_SWAP}]: " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$REC_SWAP}

    if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
        echo "Invalid size."
        exit 1
    fi

    if (( SWAP_SIZE < 1 )); then
        echo "Minimum swap is 1GB."
        exit 1
    fi

    FREE=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')

    if (( FREE <= SWAP_SIZE )); then
        echo
        echo "Not enough free disk."
        echo "Free: ${FREE}GB"
        exit 1
    fi

    echo
    echo "Disabling old swap..."
    swapoff -a || true

    rm -f "$SWAPFILE"

    sed -i '/ swap /d' /etc/fstab

    echo
    echo "Creating ${SWAP_SIZE}GB swap..."

    if command -v fallocate >/dev/null 2>&1; then

        if ! fallocate -l "${SWAP_SIZE}G" "$SWAPFILE"; then

            echo "fallocate failed."
            echo "Using dd..."

            dd if=/dev/zero of="$SWAPFILE" \
                bs=1G \
                count="$SWAP_SIZE" \
                status=progress
        fi

    else

        dd if=/dev/zero of="$SWAPFILE" \
            bs=1G \
            count="$SWAP_SIZE" \
            status=progress

    fi

    chmod 600 "$SWAPFILE"

    mkswap "$SWAPFILE" >/dev/null

    swapon "$SWAPFILE"

    echo "/swapfile none swap sw 0 0" >> /etc/fstab

    cat >/etc/sysctl.d/99-smart-swap.conf <<EOF
vm.swappiness=${SWAPPINESS}
vm.vfs_cache_pressure=50
EOF

    sysctl --system >/dev/null

    echo
    echo "✅ Swap configured successfully."

    show_swap
}

########################################
# Menu
########################################
clear

echo "========================================"
echo " Ubuntu Smart Swap Manager v2.0"
echo "========================================"
echo "Detected RAM        : ${RAM_MB} MB (~${RAM_GB} GB)"
echo "Recommended Swap    : ${REC_SWAP} GB"
echo "Recommended Swappiness : ${SWAPPINESS}"

show_swap

echo "1) Create / Resize Swap"
echo "2) Reset (Remove All Swap)"
echo "3) Exit"
echo

read -rp "Select option [1-3]: " OPTION

case "$OPTION" in

1)
    create_swap
    ;;

2)
    reset_swap
    ;;

3)
    exit 0
    ;;

*)
    echo "Invalid option."
    exit 1
    ;;

esac

echo
echo "Done."
