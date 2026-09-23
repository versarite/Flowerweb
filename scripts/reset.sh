#!/bin/bash

# Ping router once, wait up to 5 seconds
if ! ping -c 1 -W 5 192.168.43.1 > /dev/null 2>&1
then
    echo "Network down. Reconnecting..."
    ip link set wlan0 down
    sleep 10
    ip link set wlan0 up
else
    echo "Network online. No action needed."
fi

