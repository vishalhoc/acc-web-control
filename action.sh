#!/system/bin/sh
# Magisk Action Button Handler for ACC Battery Master
MODDIR=${0%/*}

echo "=========================================="
echo "  ⚡ ACC Battery Master & Web Control"
echo "  Samsung Galaxy M32 5G (MT6853)"
echo "=========================================="
echo ""

# Resolve true web directory
if [ -d "/data/adb/modules/acc/web" ]; then
    WEB_DIR="/data/adb/modules/acc/web"
elif [ -d "/data/adb/vr25/acc/web" ]; then
    WEB_DIR="/data/adb/vr25/acc/web"
else
    WEB_DIR="$MODDIR/web"
fi

# Ensure httpd is running
if ! pgrep -f "httpd -p .*8090" >/dev/null; then
    echo "[*] Launching Web UI server on port 8090..."
    /data/adb/magisk/busybox httpd -p 0.0.0.0:8090 -h "$WEB_DIR" -c "$WEB_DIR/httpd.conf"
    sleep 1
else
    echo "[✓] Web UI server is active on port 8090."
fi

# Ensure ACC daemon is alive
if ! pgrep -f "accd" >/dev/null; then
    echo "[*] Launching ACC charge daemon..."
    /system/bin/sh /data/adb/vr25/acc/service.sh >/dev/null 2>&1 &
else
    echo "[✓] ACC charge daemon is active."
fi

echo ""
echo "[*] Opening Battery Control Panel in Chrome..."
am start -a android.intent.action.VIEW -d "http://127.0.0.1:8090" -f 0x14000000 >/dev/null 2>&1

echo ""
echo "[✓] Web Control Panel launched successfully!"
echo "    Direct URL: http://127.0.0.1:8090"
echo "=========================================="
exit 0
