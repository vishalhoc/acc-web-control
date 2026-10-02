#!/system/bin/sh
# ACC Battery Master - Service Boot Script
MODDIR=${0%/*}
LOG=/data/local/tmp/acc_web_ui.log

echo "[$(date)] Starting ACC Battery Master Service" > $LOG

# Wait for boot completion
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done
sleep 2

# Apply SELinux permissions live
magiskpolicy --live "allow magisk sysfs_battery file *" 2>>$LOG || :
magiskpolicy --live "allow magisk proc_battery_cmd file *" 2>>$LOG || :

# Launch ACC Daemon
id=acc
domain=vr25
TMPDIR=/dev/.$domain/$id
execDir=/data/adb/$domain/$id
dataDir=/data/adb/$domain/${id}-data

if [ -f $execDir/${id}d.sh ]; then
    mkdir -p $TMPDIR
    export dataDir domain execDir id TMPDIR
    [ -f $execDir/setup-busybox.sh ] && . $execDir/setup-busybox.sh 2>/dev/null || :
    [ -f $execDir/release-lock.sh ] && . $execDir/release-lock.sh 2>/dev/null || :
    start-stop-daemon -bx $execDir/${id}d.sh -S 2>>$LOG || :
fi

# Resolve true web directory
if [ -d "/data/adb/modules/acc/web" ]; then
    WEB_DIR="/data/adb/modules/acc/web"
elif [ -d "/data/adb/vr25/acc/web" ]; then
    WEB_DIR="/data/adb/vr25/acc/web"
elif [ -d "$MODDIR/web" ]; then
    WEB_DIR="$MODDIR/web"
else
    WEB_DIR="$(readlink -f "${0%/*}")/web"
fi

# Ensure permissions on web files
chmod -R 0755 "$WEB_DIR/cgi-bin" 2>/dev/null || :
chmod 0644 "$WEB_DIR/index.html" "$WEB_DIR/httpd.conf" 2>/dev/null || :

# Start Busybox HTTPD daemon if not running
BUSYBOX="/data/adb/magisk/busybox"
[ -x "$BUSYBOX" ] || BUSYBOX="/data/adb/ksu/bin/busybox"
[ -x "$BUSYBOX" ] || BUSYBOX="busybox"

if ! pgrep -f "httpd -p .*8091" >/dev/null; then
    $BUSYBOX httpd -p 0.0.0.0:8091 -h "$WEB_DIR" -c "$WEB_DIR/httpd.conf" >> $LOG 2>&1
    echo "[$(date)] ACC Web UI listening on port 8091" >> $LOG
else
    echo "[$(date)] ACC Web UI already running on port 8091" >> $LOG
fi

exit 0
