#!/bin/bash
# Установка «Срудж Богдан» на iPhone одной командой:
#   curl -fsSL https://raw.githubusercontent.com/s7v7nth/srudzh-bogdan/main/install.sh | bash
# Скачивает свежий код в ~/SrudzhBogdan и запускает refresh-app.sh. Повторный запуск обновляет приложение.
set -e
REPO="https://github.com/s7v7nth/srudzh-bogdan.git"
DEST="$HOME/SrudzhBogdan"
command -v git >/dev/null || { echo "Нет git. Поставь Xcode из App Store и открой его один раз."; exit 1; }
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  git clone "$REPO" "$DEST"
fi
cd "$DEST"
chmod +x refresh-app.sh
exec ./refresh-app.sh
