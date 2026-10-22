#!/bin/bash
# Обновляет и переустанавливает «Срудж Богдан» на подключённый iPhone.
# Запускать раз в неделю: бесплатная подпись Apple живёт 7 дней, после чего приложение перестаёт открываться.
# Данные в приложении сохраняются, пока имя приложения (bundle id) не меняется.

set -u
cd "$(dirname "$0")" || exit 1

say() { printf '\n==> %s\n' "$1"; }
die() { printf '\nОшибка: %s\n' "$1" >&2; exit 1; }

# 1. Xcode
command -v xcodebuild >/dev/null || die "не найден Xcode. Поставь его из App Store, открой один раз и войди в Apple ID (Xcode → Settings → Accounts)."
xcodebuild -version >/dev/null 2>&1 || die "Xcode не готов. Выполни в терминале: sudo xcodebuild -license accept"

# 2. Свежий код
if [ -d .git ] && git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  say "Обновляю код"
  git pull --ff-only || die "не удалось обновить код (git pull). Напиши владельцу проекта."
fi
# Проект Xcode собирается из project.yml; если xcodegen стоит, пересоздаём его, иначе берём готовый из репозитория
if command -v xcodegen >/dev/null; then
  xcodegen generate >/dev/null 2>&1 || echo "Предупреждение: xcodegen не сработал, использую готовый проект."
fi

# 3. Команда подписи (Team ID) из Xcode; если не нашли, спросим один раз и запомним
TEAM_FILE="$HOME/.srudzh-team"
TEAM_ID="${TEAM_ID:-}"
[ -z "$TEAM_ID" ] && [ -f "$TEAM_FILE" ] && TEAM_ID="$(cat "$TEAM_FILE")"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -Eo 'teamID = [A-Z0-9]{10}' | head -1 | awk '{print $3}')"
fi
if [ -z "$TEAM_ID" ]; then
  echo "Не нашёл твой Apple ID в Xcode. Открой Xcode → Settings → Accounts, добавь Apple ID,"
  echo "потом найди Team ID (10 символов: Accounts → твоя команда → Manage Certificates → справа от имени) и введи его."
  read -r -p "Team ID: " TEAM_ID
fi
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Team ID должен быть из 10 заглавных букв и цифр."
echo "$TEAM_ID" > "$TEAM_FILE"

# 4. iPhone
say "Ищу iPhone"
DEV_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1
DEVICES="$(python3 - "$DEV_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for x in d.get("result", {}).get("devices", []):
    hw = x.get("hardwareProperties", {})
    cp = x.get("connectionProperties", {})
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS" and cp.get("pairingState") == "paired":
        print(x["identifier"] + "\t" + x.get("deviceProperties", {}).get("name", "iPhone"))
PY
)"
rm -f "$DEV_JSON"
[ -n "$DEVICES" ] || die "не вижу iPhone. Подключи кабелем, разблокируй экран, нажми «Доверять» на телефоне, включи Режим разработчика (Настройки → Конфиденциальность и безопасность → Режим разработчика)."
if [ "$(echo "$DEVICES" | wc -l | tr -d ' ')" -gt 1 ]; then
  echo "$DEVICES" | awk -F'\t' '{print NR") "$2}'
  read -r -p "Номер телефона: " N
  DEVICE="$(echo "$DEVICES" | sed -n "${N}p" | cut -f1)"
else
  DEVICE="$(echo "$DEVICES" | cut -f1)"
fi
[ -n "$DEVICE" ] || die "не выбран телефон."

# Бесплатный аккаунт не может использовать чужой bundle id, поэтому у каждого друга свой, но постоянный.
# Если на телефоне уже стоит версия владельца (com.timofei.srudzhbogdan), ставим поверх неё: так данные точно сохранятся.
OWNER_ID="com.timofei.srudzhbogdan"
if [ -z "${BUNDLE_ID:-}" ]; then
  APPS_JSON="$(mktemp)"
  xcrun devicectl device info apps --device "$DEVICE" --json-output "$APPS_JSON" >/dev/null 2>&1
  if grep -q "\"$OWNER_ID\"" "$APPS_JSON" 2>/dev/null; then
    BUNDLE_ID="$OWNER_ID"
  else
    BUNDLE_ID="com.srudzhbogdan.$(echo "$TEAM_ID" | tr 'A-Z' 'a-z')"
  fi
  rm -f "$APPS_JSON"
fi

# 5. Сборка (вне папки Documents: там подпись ломается из-за служебных меток macOS)
BUILD_DIR="$HOME/Library/Caches/srudzh-build"
say "Собираю приложение (первый раз до 5 минут)"
mkdir -p "$BUILD_DIR"
xcodebuild -project SrudzhBogdan.xcodeproj -scheme SrudzhBogdan \
  -destination "id=$DEVICE" -destination-timeout 90 -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build > "$BUILD_DIR.log" 2>&1 || { tail -15 "$BUILD_DIR.log"; die "сборка не удалась. Если в логе «Connecting to iPhone»: разблокируй телефон, переподключи кабель и запусти снова. Полный лог: $BUILD_DIR.log (пришли его владельцу проекта)."; }

# 6. Установка (первый вызов иногда падает на связи с телефоном, пробуем ещё раз)
APP="$BUILD_DIR/Build/Products/Debug-iphoneos/SrudzhBogdan.app"
say "Ставлю на телефон"
if ! xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null 2>&1; then
  sleep 3
  xcrun devicectl device install app --device "$DEVICE" "$APP" > "$BUILD_DIR.install.log" 2>&1 \
    || { tail -5 "$BUILD_DIR.install.log"; die "не удалось поставить на телефон. Разблокируй экран и запусти снова."; }
fi

xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 \
  || echo "Приложение поставлено. Если оно не открылось, на телефоне: Настройки → Основные → VPN и управление устройством → доверять разработчику."

say "Готово. Подпись действует 7 дней. Запусти скрипт снова не позже чем через неделю."
