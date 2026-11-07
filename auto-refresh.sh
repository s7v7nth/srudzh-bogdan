#!/bin/bash
# Фоновая автопереустановка «Срудж Богдан» на все подключённые iPhone.
# Каждые 10 минут смотрит, какие телефоны сейчас на связи (кабель или Wi-Fi), и если с последней
# установки прошло больше 5 дней (подпись живёт 7), запускает refresh-app.sh для этого телефона.
#
#   ./auto-refresh.sh install     поставить в фон (запускается сам при входе в Мак)
#   ./auto-refresh.sh uninstall   убрать из фона
#   ./auto-refresh.sh status      что и когда ставилось
#   ./auto-refresh.sh             крутить цикл прямо в этом окне (для проверки)

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.srudzh-auto"
LOG="$STATE/auto.log"
PLIST="$HOME/Library/LaunchAgents/com.srudzh.autorefresh.plist"
MAX_AGE_DAYS=5
CHECK_EVERY=600
mkdir -p "$STATE"

case "${1:-run}" in
  install)
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.srudzh.autorefresh</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/auto-refresh.sh</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" && echo "Включено. Лог: $LOG"
    exit 0 ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST"; echo "Выключено."; exit 0 ;;
  status)
    for f in "$STATE"/*.last; do
      [ -e "$f" ] || { echo "Пока ничего не ставилось."; break; }
      echo "$(basename "$f" .last): $(date -r "$(cat "$f")" '+%d.%m %H:%M')"
    done
    tail -5 "$LOG" 2>/dev/null
    exit 0 ;;
esac

log() { echo "$(date '+%d.%m %H:%M') $*"; }

connected_devices() {
  local j; j="$(mktemp)"
  xcrun devicectl list devices --json-output "$j" >/dev/null 2>&1
  python3 -I - "$j" <<'PY'
import json, sys
for x in json.load(open(sys.argv[1])).get("result", {}).get("devices", []):
    hw, cp = x.get("hardwareProperties", {}), x.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical" and cp.get("pairingState") == "paired":
        print(hw.get("udid", x["identifier"]) + "\t" + x["identifier"])
PY
  rm -f "$j"
}

while true; do
  connected_devices | while IFS=$'\t' read -r udid ident; do
    [ -n "$udid" ] || continue
    # на связи ли телефон прямо сейчас (список устройств этого не показывает)
    xcrun devicectl device info details --device "$ident" 2>&1 | grep -q "Device State: connected" || continue
    last="$STATE/$udid.last"
    now=$(date +%s)
    if [ -f "$last" ] && [ $(( now - $(cat "$last") )) -lt $(( MAX_AGE_DAYS * 86400 )) ]; then continue; fi
    log "Переустанавливаю на $udid"
    if DEVICE_ID="$ident" bash "$DIR/refresh-app.sh" </dev/null >> "$STATE/$udid.log" 2>&1; then
      echo "$now" > "$last"; log "Готово: $udid"
    else
      log "Не вышло: $udid (подробности в $STATE/$udid.log), попробую через $((CHECK_EVERY/60)) мин"
    fi
  done
  sleep "$CHECK_EVERY"
done
