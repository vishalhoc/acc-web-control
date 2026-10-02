#!/system/bin/sh
# ACC Battery Master - High Performance CGI API Handler
# Provides REST-like JSON API for ACC Web UI via Busybox HTTPD

printf "Content-Type: application/json\r\n"
printf "Access-Control-Allow-Origin: *\r\n"
printf "Cache-Control: no-cache, no-store, must-revalidate\r\n"
printf "\r\n"

ACC_BIN="/data/adb/vr25/acc/acc.sh"
ACC_CONFIG="/data/adb/vr25/acc-data/config.txt"
BATT_SYS="/sys/class/power_supply/battery"

# Parse query string parameters with pure POSIX shell (zero forks)
QS="${QUERY_STRING:-}"
ACTION=""
PC=""
RC=""
SC=""
PRESET=""
ENABLE=""
OP=""
SWITCH=""

_save_IFS="$IFS"
IFS='&'
set -- $QS
IFS="$_save_IFS"

for pair in "$@"; do
    case "$pair" in
        action=*) ACTION="${pair#action=}" ;;
        pc=*) PC="${pair#pc=}" ;;
        rc=*) RC="${pair#rc=}" ;;
        sc=*) SC="${pair#sc=}" ;;
        preset=*) PRESET="${pair#preset=}" ;;
        enable=*) ENABLE="${pair#enable=}" ;;
        op=*) OP="${pair#op=}" ;;
        switch=*) SWITCH="${pair#switch=}" ;;
    esac
done

case "$ACTION" in
    get_data|"")
        # Telemetry
        CAPACITY=$(cat $BATT_SYS/capacity 2>/dev/null || echo 0)
        STATUS=$(cat $BATT_SYS/status 2>/dev/null || echo "Unknown")
        CURRENT=$(cat $BATT_SYS/current_now 2>/dev/null || echo 0)
        VOLTAGE=$(cat $BATT_SYS/voltage_now 2>/dev/null || echo 0)
        TEMP_RAW=$(cat $BATT_SYS/temp 2>/dev/null || echo 0)
        HEALTH=$(cat $BATT_SYS/health 2>/dev/null || echo "Good")
        SLATE_MODE=$(cat $BATT_SYS/batt_slate_mode 2>/dev/null || echo 0)
        SIOP_LEVEL=$(cat $BATT_SYS/siop_level 2>/dev/null || echo 100)
        MTK_CMD=$(cat /proc/mtk_battery_cmd/current_cmd 2>/dev/null || echo "0 0")
        
        # Temperature formatting
        if [ "$TEMP_RAW" -gt 150 ]; then
            TEMP_INT=$(( TEMP_RAW / 10 ))
            TEMP_DEC=$(( TEMP_RAW % 10 ))
            TEMP_C="${TEMP_INT}.${TEMP_DEC}"
        else
            TEMP_C="$TEMP_RAW.0"
        fi
        
        # Voltage formatting
        if [ "$VOLTAGE" -gt 100000 ]; then
            VOLTAGE_MV=$(( VOLTAGE / 1000 ))
        else
            VOLTAGE_MV="$VOLTAGE"
        fi
        
        # Current in mA
        CURRENT_MA="$CURRENT"
        
        # Power in Watts: (V_mV * I_mA) / 1000000
        # Positive = charging into battery, Negative = discharging from battery
        POWER_INT=$(( (VOLTAGE_MV * CURRENT_MA) / 1000000 ))
        POWER_REM=$(( (VOLTAGE_MV * CURRENT_MA) % 1000000 ))
        if [ "$POWER_REM" -lt 0 ]; then POWER_REM=$(( -POWER_REM )); fi
        POWER_DEC=$(( POWER_REM / 10000 ))
        if [ "$POWER_DEC" -lt 10 ]; then POWER_DEC="0${POWER_DEC}"; fi
        POWER_W="${POWER_INT}.${POWER_DEC}"
        
        # Power source
        USB_ONLINE=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
        AC_ONLINE=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
        PLUGGED="false"
        PWR_SRC="Battery"
        if [ "$USB_ONLINE" = "1" ]; then
            PLUGGED="true"
            PWR_SRC="USB Charger"
        elif [ "$AC_ONLINE" = "1" ]; then
            PLUGGED="true"
            PWR_SRC="AC Charger"
        fi
        
        # Read ACC thresholds from config
        # format: capacity=(shutdown cooldown resume pause cooldown_mode cooldown_pause)
        CAP_LINE=$(grep -E "^capacity=" "$ACC_CONFIG" 2>/dev/null || echo "capacity=(5 50 60 90 false false)")
        PAUSE_CAP=$(echo "$CAP_LINE" | sed -E 's/capacity=\(([0-9]+)[ ]+([0-9]+)[ ]+([0-9]+)[ ]+([0-9]+).*/\4/')
        RESUME_CAP=$(echo "$CAP_LINE" | sed -E 's/capacity=\(([0-9]+)[ ]+([0-9]+)[ ]+([0-9]+)[ ]+([0-9]+).*/\3/')
        SHUTDOWN_CAP=$(echo "$CAP_LINE" | sed -E 's/capacity=\(([0-9]+)[ ]+([0-9]+)[ ]+([0-9]+)[ ]+([0-9]+).*/\1/')
        
        : ${PAUSE_CAP:=90}
        : ${RESUME_CAP:=60}
        : ${SHUTDOWN_CAP:=5}
        
        # Check daemon
        ACCD_PID=$(pgrep -f accd 2>/dev/null | head -n 1)
        DAEMON_RUNNING="false"
        if [ -n "$ACCD_PID" ]; then
            DAEMON_RUNNING="true"
        fi
        
        # Status normalization based on hardware current
        if [ "$STATUS" = "Unknown" ] || [ -z "$STATUS" ] || [ "$STATUS" = "Discharging" ]; then
            if [ "$CURRENT_MA" -gt 40 ]; then
                STATUS="Charging"
            elif [ "$CURRENT_MA" -lt -40 ]; then
                STATUS="Discharging"
            else
                [ "$PLUGGED" = "true" ] && STATUS="Idle" || STATUS="Discharging"
            fi
        fi
        
        # Idle / Bypass state
        IS_BYPASS="false"
        if [ "$SLATE_MODE" = "1" ] || [ "$SIOP_LEVEL" = "0" ] || [ "$MTK_CMD" = "0 1" ] || [ "$STATUS" = "Not charging" ] || [ "$STATUS" = "Idle" ]; then
            IS_BYPASS="true"
        fi

        cat <<EOF
{
  "success": true,
  "level": $CAPACITY,
  "status": "$STATUS",
  "current_ma": $CURRENT_MA,
  "voltage_mv": $VOLTAGE_MV,
  "power_w": $POWER_W,
  "temp_c": $TEMP_C,
  "health": "$HEALTH",
  "plugged": $PLUGGED,
  "power_source": "$PWR_SRC",
  "is_bypass": $IS_BYPASS,
  "slate_mode": $SLATE_MODE,
  "siop_level": $SIOP_LEVEL,
  "mtk_current_cmd": "$MTK_CMD",
  "pause_capacity": $PAUSE_CAP,
  "resume_capacity": $RESUME_CAP,
  "shutdown_capacity": $SHUTDOWN_CAP,
  "daemon_running": $DAEMON_RUNNING,
  "daemon_pid": "${ACCD_PID:-0}"
}
EOF
        ;;

    set_thresholds)
        if [ -z "$PC" ] || [ -z "$RC" ]; then
            echo '{"success": false, "error": "Missing pc or rc parameters"}'
            exit 0
        fi
        : ${SC:=5}
        
        # Ensure hardware bypass lock is cleared
        echo 0 > $BATT_SYS/batt_slate_mode 2>/dev/null
        echo 100 > $BATT_SYS/siop_level 2>/dev/null
        echo 0 0 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
        
        # Apply thresholds with composite switch and off_mid=false
        $ACC_BIN -s pc=$PC rc=$RC sc=$SC om=false dp=- s="battery/batt_slate_mode 0 1 battery/siop_level 100 0 /proc/mtk_battery_cmd/current_cmd 0::0 0::1 --" >/dev/null 2>&1
        $ACC_BIN -D restart >/dev/null 2>&1
        
        cat <<EOF
{
  "success": true,
  "message": "Thresholds applied: Cut at ${PC}%, Resume at ${RC}%, Shutdown at ${SC}%",
  "pause_capacity": $PC,
  "resume_capacity": $RC,
  "shutdown_capacity": $SC
}
EOF
        ;;

    apply_preset)
        case "$PRESET" in
            custom_90_60)
                echo 0 > $BATT_SYS/batt_slate_mode 2>/dev/null
                echo 100 > $BATT_SYS/siop_level 2>/dev/null
                echo 0 0 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
                $ACC_BIN -s pc=90 rc=60 sc=5 om=false dp=- s="battery/batt_slate_mode 0 1 battery/siop_level 100 0 /proc/mtk_battery_cmd/current_cmd 0::0 0::1 --" >/dev/null 2>&1
                $ACC_BIN -D restart >/dev/null 2>&1
                MSG="Applied: Cut at 90%, Auto-Resume below 60%"
                ;;
            lifespan_80_70)
                echo 0 > $BATT_SYS/batt_slate_mode 2>/dev/null
                echo 100 > $BATT_SYS/siop_level 2>/dev/null
                echo 0 0 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
                $ACC_BIN -s pc=80 rc=70 sc=5 om=false dp=- s="battery/batt_slate_mode 0 1 battery/siop_level 100 0 /proc/mtk_battery_cmd/current_cmd 0::0 0::1 --" >/dev/null 2>&1
                $ACC_BIN -D restart >/dev/null 2>&1
                MSG="Applied: Maximum Battery Lifespan (70% - 80%)"
                ;;
            bypass_charger_only)
                echo 1 > $BATT_SYS/batt_slate_mode 2>/dev/null
                echo 0 > $BATT_SYS/siop_level 2>/dev/null
                echo 0 1 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
                MSG="Bypass Mode Activated: Running 100% on external charger power (Battery resting idle)"
                ;;
            stock_100)
                echo 0 > $BATT_SYS/batt_slate_mode 2>/dev/null
                echo 100 > $BATT_SYS/siop_level 2>/dev/null
                echo 0 0 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
                $ACC_BIN -s pc=100 rc=95 sc=5 om=false dp=- s="battery/batt_slate_mode 0 1 battery/siop_level 100 0 /proc/mtk_battery_cmd/current_cmd 0::0 0::1 --" >/dev/null 2>&1
                $ACC_BIN -D restart >/dev/null 2>&1
                MSG="Stock Full Charging Activated (100% limit)"
                ;;
            *)
                echo '{"success": false, "error": "Unknown preset"}'
                exit 0
                ;;
        esac
        cat <<EOF
{
  "success": true,
  "message": "$MSG",
  "preset": "$PRESET"
}
EOF
        ;;

    toggle_bypass)
        if [ "$ENABLE" = "1" ]; then
            echo 1 > $BATT_SYS/batt_slate_mode 2>/dev/null
            echo 0 > $BATT_SYS/siop_level 2>/dev/null
            echo 0 1 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
            MSG="Charger Power Path Activated: Phone powered directly by charger, battery charging halted."
        else
            echo 0 > $BATT_SYS/batt_slate_mode 2>/dev/null
            echo 100 > $BATT_SYS/siop_level 2>/dev/null
            echo 0 0 > /proc/mtk_battery_cmd/current_cmd 2>/dev/null
            $ACC_BIN -D restart >/dev/null 2>&1
            MSG="Standard Charging Restored: Normal battery charging enabled."
        fi
        cat <<EOF
{
  "success": true,
  "message": "$MSG",
  "bypass_enabled": $([ "$ENABLE" = "1" ] && echo "true" || echo "false")
}
EOF
        ;;

    daemon_control)
        case "$OP" in
            restart)
                $ACC_BIN -D restart >/dev/null 2>&1
                MSG="ACC Daemon restarted"
                ;;
            stop)
                $ACC_BIN -D stop >/dev/null 2>&1
                MSG="ACC Daemon stopped"
                ;;
            start)
                $ACC_BIN -D start >/dev/null 2>&1
                MSG="ACC Daemon started"
                ;;
            *)
                echo '{"success": false, "error": "Invalid operation"}'
                exit 0
                ;;
        esac
        cat <<EOF
{
  "success": true,
  "message": "$MSG"
}
EOF
        ;;

    get_log)
        LOG_FILE="/dev/.vr25/acc/accd-a32x.log"
        [ -f "$LOG_FILE" ] || LOG_FILE="/data/adb/vr25/acc-data/logs/accd.log"
        LOG_CONTENT=""
        if [ -f "$LOG_FILE" ]; then
            LOG_CONTENT=$(tail -n 60 "$LOG_FILE" 2>/dev/null | tr '\n' '@' | sed 's/"/\\"/g' | sed 's/@/\\n/g')
        fi
        cat <<EOF
{
  "success": true,
  "log": "$LOG_CONTENT"
}
EOF
        ;;

    *)
        echo '{"success": false, "error": "Invalid action"}'
        ;;
esac
