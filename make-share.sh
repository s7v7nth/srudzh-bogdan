#!/bin/bash
# Собирает один файл для друга: «Установить-Срудж-Богдан.command».
# Внутри весь код приложения. Друг запускает файл, и всё ставится само.
set -eu
cd "$(dirname "$0")"
OUT="${1:-$HOME/Desktop/Установить-Срудж-Богдан.command}"
PAYLOAD="$(mktemp)"
tar --no-xattrs --exclude='.build' --exclude='.DS_Store' -czf "$PAYLOAD" \
  App LedgerCore project.yml SrudzhBogdan.xcodeproj refresh-app.sh

cat > "$OUT" <<'HEAD'
#!/bin/bash
# Установщик «Срудж Богдан». Распаковывает приложение в ~/SrudzhBogdan и ставит его на iPhone.
# Нужно: Xcode (из App Store, открыть один раз), Apple ID в Xcode (Settings → Accounts), iPhone по кабелю.
set -e
DEST="$HOME/SrudzhBogdan"
mkdir -p "$DEST"
sed '1,/^__PAYLOAD__$/d' "$0" | base64 -D | tar -xzf - -C "$DEST"
cd "$DEST"
chmod +x refresh-app.sh
./refresh-app.sh
echo; read -r -p "Нажми Enter, чтобы закрыть окно." _
exit 0
__PAYLOAD__
HEAD
base64 < "$PAYLOAD" >> "$OUT"
rm -f "$PAYLOAD"
chmod +x "$OUT"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
