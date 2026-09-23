#!/bin/bash
set -e
#
# deploy-test.sh
# Build and run a TEST copy of FlowerWeb on the Pi next to the live system.
#
#   ./scripts/deploy-test.sh          copy, compile and start the test copy
#   ./scripts/deploy-test.sh stop     stop the test copy
#   ./scripts/deploy-test.sh log      follow the test copy's log
#
# The test copy
#   - lives in ~/flowerweb-test on the Pi (the live /home/flowerweb is not touched)
#   - runs in SIMULATION mode: it never switches the relay and never reboots the Pi
#   - listens on port 8081 (the live system stays on 8080)
#   - is started by hand, not by systemd, so it is gone after a reboot
#

PI_USER="pi"
#PI_HOST="192.168.43.218"
#PI_HOST="100.98.27.45"

PI_HOST="192.168.43.73"
TEST_PORT=8081
TEST_ROOT="flowerweb-test"          # relative to the pi user's home

case "$1" in
  stop)
    ssh "${PI_USER}@${PI_HOST}" "pkill -f '${TEST_ROOT}/bin/flowerweb' && echo 'Test copy stopped.' || echo 'Test copy was not running.'"
    exit 0
    ;;
  log)
    ssh -t "${PI_USER}@${PI_HOST}" "tail -n 50 -f ~/${TEST_ROOT}/logs/flowerweb.log"
    exit 0
    ;;
esac

echo "------------------------------------------"
echo "FlowerWeb TEST deployment (simulation, port ${TEST_PORT})"
echo "------------------------------------------"

echo "[1/4] Testing SSH connection..."
ssh "${PI_USER}@${PI_HOST}" "echo Connected to \$(hostname); mkdir -p ~/${TEST_ROOT}/bin ~/${TEST_ROOT}/config ~/${TEST_ROOT}/logs"

echo
echo "[2/4] Synchronizing source to ~/${TEST_ROOT} ..."
rsync -a --exclude 'lib/' --exclude 'backup/' --exclude '*.lps' --exclude 'flowerweb' \
      src/ "${PI_USER}@${PI_HOST}:${TEST_ROOT}/src/"
rsync -a web/ "${PI_USER}@${PI_HOST}:${TEST_ROOT}/web/"
rsync -a --ignore-existing config/flowerweb.ini "${PI_USER}@${PI_HOST}:${TEST_ROOT}/config/flowerweb.ini"

echo
echo "[3/4] Compiling on the Pi (the live service keeps running)..."
ssh "${PI_USER}@${PI_HOST}" TEST_ROOT="${TEST_ROOT}" TEST_PORT="${TEST_PORT}" 'bash -s' << 'EOF'
set -e
cd ~/"$TEST_ROOT"

# Belt and braces: the test ini always says Simulate=1 (the port comes from --port)
sed -i 's/^Simulate=.*/Simulate=1/' config/flowerweb.ini
grep -q '^Simulate=' config/flowerweb.ini || sed -i 's/^\[Relay\]$/[Relay]\nSimulate=1/' config/flowerweb.ini
grep -q 'TEST' config/flowerweb.ini || sed -i '/^\[Server\]/,/^\[/ s/^Name=\(.*\)$/Name=\1 (TEST)/' config/flowerweb.ini

cd src
rm -f flowerweb
lazbuild -q flowerweb.lpi > ../logs/build.log 2>&1 || { tail -n 30 ../logs/build.log; echo "Compilation FAILED"; exit 1; }
echo "Compilation successful."
cp -f flowerweb ../bin/

echo
echo "[4/4] (Re)starting the test copy..."
pkill -f "$TEST_ROOT/bin/flowerweb" || true
sleep 1
nohup ~/"$TEST_ROOT"/bin/flowerweb --simulate --port "$TEST_PORT" \
      > ~/"$TEST_ROOT"/logs/console.log 2>&1 < /dev/null &
sleep 2
if pgrep -f "$TEST_ROOT/bin/flowerweb" > /dev/null; then
    echo "Test copy running."
else
    echo "Test copy did not start:"
    tail -n 20 ~/"$TEST_ROOT"/logs/console.log
    exit 1
fi
EOF

echo
echo "Open http://${PI_HOST}:${TEST_PORT}  (orange SIMULATION banner = test copy)"
echo "Log:  ./scripts/deploy-test.sh log      Stop: ./scripts/deploy-test.sh stop"
