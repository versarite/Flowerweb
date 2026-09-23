#!/bin/bash
set -e
#
# deploy.sh
# Synchronize the FlowerWeb project to the Raspberry Pi and build it there.
#

PI_USER="pi"
#PI_HOST="192.168.43.218"
#PI_HOST="100.98.27.45"

PI_HOST="192.168.43.73"
PI_ROOT="/home/flowerweb"

echo "------------------------------------------"
echo "FlowerWeb Deployment"
echo "------------------------------------------"

echo "[1/4] Testing SSH connection..."
ssh "${PI_USER}@${PI_HOST}" "echo Connected to \$(hostname)" || exit 1

echo
echo "[2/4] Synchronizing source..."
rsync -av --exclude 'lib/' --exclude 'backup/' --exclude '*.lps' --exclude 'flowerweb' \
      src/ "${PI_USER}@${PI_HOST}:${PI_ROOT}/src/"
rsync -av web/     "${PI_USER}@${PI_HOST}:${PI_ROOT}/web/"
rsync -av systemd/ "${PI_USER}@${PI_HOST}:${PI_ROOT}/systemd/"

# flowerweb.ini on the Pi holds the settings made from the web page
# (pulse time, timer, next watering). Only copy it if the Pi has none yet.
rsync -av --exclude 'flowerweb.ini' config/ "${PI_USER}@${PI_HOST}:${PI_ROOT}/config/"
rsync -av --ignore-existing config/flowerweb.ini \
      "${PI_USER}@${PI_HOST}:${PI_ROOT}/config/flowerweb.ini"

echo
echo "[3/4] Compiling on RPI..."
ssh "${PI_USER}@${PI_HOST}" << 'EOF'

set -e

cd /home/flowerweb/src

rm -f /home/flowerweb/src/flowerweb
lazbuild flowerweb.lpi

echo "Compilation successful."

mkdir -p ../bin
cp -f flowerweb ../bin/

if ! cmp -s ../systemd/flowerweb.service /etc/systemd/system/flowerweb.service; then
    echo
    echo "NOTE: systemd/flowerweb.service has changed. Install it once with:"
    echo "  sudo cp /home/flowerweb/systemd/flowerweb.service /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo
fi

sudo /usr/bin/systemctl restart flowerweb
sudo /usr/bin/systemctl status flowerweb --no-pager
EOF
echo
echo "[4/4] Deployment completed."
echo "Done."
