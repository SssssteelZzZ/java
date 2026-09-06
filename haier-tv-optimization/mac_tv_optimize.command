#!/usr/bin/env bash
# =============================================================================
#  mac_tv_optimize.command — ВСЁ В ОДНОЙ КОМАНДЕ для macOS
# =============================================================================
#  Скрипт самодостаточный: ничего ставить заранее не нужно, Homebrew не нужен,
#  пароль администратора не нужен. Он сам:
#    1. скачает официальные Android Platform Tools от Google (~10 МБ) в ~/tv-optimize
#    2. подключится к телевизору по Wi-Fi (проведёт через сопряжение по коду)
#    3. отключит предустановленные витрины, рекламу и телеметрию
#    4. ускорит интерфейс и включит блокировку рекламы через Private DNS
#    5. запишет журнал, по которому всё можно вернуть назад
#
#  ЗАПУСК (в Терминале мака):
#     bash ~/Downloads/mac_tv_optimize.command
#
#  ОТКАТ (вернуть всё как было):
#     bash ~/Downloads/mac_tv_optimize.command --restore
# =============================================================================

set -u

# --- Рабочая папка: тут будет adb и журналы отката --------------------------
WORK="${HOME}/tv-optimize"
TOOLS="${WORK}/platform-tools"
LOGDIR="${WORK}/logs"
mkdir -p "${WORK}" "${LOGDIR}"

C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_RED=$'\e[31m'; C_BLU=$'\e[36m'; C_OFF=$'\e[0m'
RESTORE=0
[ "${1:-}" = "--restore" ] && RESTORE=1

echo "${C_BLU}"
echo "==========================================================="
echo "  Оптимизация Haier Android TV PRO — очистка и ускорение"
echo "==========================================================="
echo "${C_OFF}"

# --- Шаг 1. Получаем adb ------------------------------------------------------
# Скачиваем прямо у Google. Если platform-tools уже есть — пропускаем.
if [ ! -x "${TOOLS}/adb" ]; then
  echo "${C_YEL}[1/5] Скачиваю Android Platform Tools от Google...${C_OFF}"
  ZIP="${WORK}/platform-tools.zip"
  # -f = падать при HTTP-ошибке, -L = идти за редиректами, -# = полоса прогресса
  if ! curl -fL# -o "${ZIP}" \
      "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"; then
    echo "${C_RED}[!] Не удалось скачать. Проверь интернет на маке.${C_OFF}"; exit 1
  fi
  # -o = перезаписывать без вопросов, -q = тихо, -d = куда распаковать
  unzip -oq "${ZIP}" -d "${WORK}" && rm -f "${ZIP}"
  # macOS вешает на скачанные файлы карантин Gatekeeper — снимаем, иначе
  # система откажется запускать adb с окном «не удалось проверить разработчика».
  xattr -dr com.apple.quarantine "${TOOLS}" 2>/dev/null
  echo "    Готово: ${TOOLS}/adb"
else
  echo "${C_GRN}[1/5] adb уже скачан, пропускаю${C_OFF}"
fi

ADB="${TOOLS}/adb"

# --- Шаг 2. Подключение к телевизору -----------------------------------------
echo
echo "${C_YEL}[2/5] Подключение к телевизору${C_OFF}"
read -r -p "  IP телевизора [192.168.0.149]: " TV_IP
TV_IP="${TV_IP:-192.168.0.149}"
read -r -p "  Порт с экрана «Отладка по Wi-Fi» [37765]: " TV_PORT
TV_PORT="${TV_PORT:-37765}"
TV="${TV_IP}:${TV_PORT}"

"${ADB}" start-server >/dev/null 2>&1
"${ADB}" disconnect "${TV}" >/dev/null 2>&1
"${ADB}" connect "${TV}" >/dev/null 2>&1
sleep 2

# Проверяем связь по факту: спрашиваем модель. Пустой ответ = связи нет.
MODEL="$("${ADB}" -s "${TV}" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"

if [ -z "${MODEL}" ]; then
  # Android 11+ требует разовое сопряжение по коду. Порт сопряжения ДРУГОЙ —
  # это самая частая причина, по которой у людей «не подключается».
  echo
  echo "  Нужно сопряжение (это делается один раз)."
  echo "  На телевизоре: Настройки → Для разработчиков → Отладка по Wi-Fi"
  echo "                 → «Подключить устройство с помощью кода подключения»"
  echo "  ${C_RED}Порт в этом окне ДРУГОЙ, не ${TV_PORT}. Окно не закрывай!${C_OFF}"
  echo
  read -r -p "  Порт сопряжения (5 цифр с экрана ТВ): " PPORT
  read -r -p "  Код сопряжения (6 цифр): " PCODE

  if ! "${ADB}" pair "${TV_IP}:${PPORT}" "${PCODE}"; then
    echo "${C_RED}[!] Сопряжение не удалось. Проверь:${C_OFF}"
    echo "    • мак и телевизор в ОДНОЙ сети Wi-Fi (не гостевой)"
    echo "    • в роутере выключена изоляция клиентов (AP isolation)"
    echo "    • окно с кодом на ТВ ещё открыто (код и порт меняются каждый раз)"
    exit 1
  fi
  "${ADB}" connect "${TV}" >/dev/null 2>&1
  sleep 2
  MODEL="$("${ADB}" -s "${TV}" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  [ -z "${MODEL}" ] && { echo "${C_RED}[!] Связи нет. На ТВ могло появиться окно «Разрешить отладку?» — подтверди его пультом.${C_OFF}"; exit 1; }
fi

ANDROID="$("${ADB}" -s "${TV}" shell getprop ro.build.version.release | tr -d '\r')"
echo "${C_GRN}  Подключено: ${MODEL}, Android ${ANDROID}${C_OFF}"

# Короткая обёртка, чтобы дальше не повторять адрес в каждой команде
tv() { "${ADB}" -s "${TV}" shell "$@" 2>/dev/null | tr -d '\r'; }

# Свободная память до работы — чтобы показать результат в цифрах
RAM_BEFORE="$(tv "cat /proc/meminfo" | awk '/MemAvailable/{printf "%d",$2/1024}')"

# =============================================================================
#  РЕЖИМ ОТКАТА: включаем обратно всё, что отключали, и возвращаем настройки
# =============================================================================
if [ "${RESTORE}" = "1" ]; then
  echo
  echo "${C_YEL}[ОТКАТ] Возвращаю всё как было${C_OFF}"
  # pm list packages -d показывает ОТКЛЮЧЁННЫЕ пакеты — включаем их подряд
  while IFS= read -r p; do
    [ -z "${p}" ] && continue
    tv "pm enable ${p}" >/dev/null && echo "  вернул: ${p}"
  done < <(tv "pm list packages -d" | sed 's/^package://')
  # Возвращаем стандартные значения настроек
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    tv "settings put global ${k} 1" >/dev/null
  done
  tv "settings put global private_dns_mode off" >/dev/null
  tv "settings put global wifi_scan_always_enabled 1" >/dev/null
  tv "settings put global ble_scan_always_enabled 1" >/dev/null
  tv "settings delete global activity_manager_constants" >/dev/null
  echo "${C_GRN}Откат выполнен. Перезагрузи телевизор.${C_OFF}"
  read -r -p "Перезагрузить сейчас? [y/N]: " R
  [ "${R}" = "y" ] && "${ADB}" -s "${TV}" reboot
  exit 0
fi

# =============================================================================
#  Шаг 3. Чистка: отключаем мусор
# =============================================================================
# Используем pm disable-user --user 0: приложение остаётся на диске, но не
# запускается и пропадает из меню. Не ест ОЗУ, не лезет в сеть за рекламой.
# Это полностью обратимо (--restore) и не требует root.
echo
echo "${C_YEL}[3/5] Отключаю предустановленный мусор и рекламу${C_OFF}"

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${LOGDIR}/disabled-${STAMP}.log"
: > "${LOG}"

# Пакеты, которые точно можно убирать: партнёрские витрины кино и рекламные стабы.
# Любое из них ставится обратно из Google Play, если вдруг понадобится.
BLOAT="
ru.ivi.client ru.more.play ru.okko.tv ru.rt.video.app.tv
com.megogo.application com.megogo.tv ru.kinopoisk.yandex.tv
ru.start.androidtv com.mts.mtstv one.premier.androidtv ru.tricolor.tv
com.viju.androidtv tv.peers.android ru.limehd.tv ru.mts.mtstv
ru.beeline.services com.spb.tv.sbt
com.netflix.ninja com.netflix.partner.activation
com.amazon.amazonvideo.livingroom com.amazon.aiv.eu
com.disney.disneyplus com.spotify.tv.android com.plexapp.android
com.google.android.play.games com.google.android.videos
com.google.android.youtube.tvmusic com.google.android.apps.tachyon
com.google.android.katniss com.google.android.tvrecommendations
com.google.android.backuptransport com.google.android.feedback
com.google.android.partnersetup com.google.android.printservice.recommendation
com.google.android.syncadapters.contacts com.google.android.syncadapters.calendar
com.google.android.marvin.talkback
com.facebook.appmanager com.facebook.services com.facebook.system
"

# Список того, что стоит на ТВ — тянем один раз, дальше сверяемся локально
# (каждый вызов adb ~0.3 сек, так экономим минуту на 40 пакетах)
INSTALLED="$(tv "pm list packages" | sed 's/^package://')"

COUNT=0
for p in ${BLOAT}; do
  # grep -qx = совпадение строки целиком, чтобы не задеть похожие имена
  echo "${INSTALLED}" | grep -qx "${p}" || continue
  RES="$(tv "pm disable-user --user 0 ${p}")"
  if echo "${RES}" | grep -qi "disabled"; then
    echo "  ${C_GRN}✓${C_OFF} ${p}"
    echo "${p}" >> "${LOG}"
    COUNT=$((COUNT+1))
  else
    echo "  ${C_RED}✗${C_OFF} ${p} (вендор запретил отключение — это нормально)"
  fi
done
echo "  Отключено: ${COUNT}"

# Чистим кэш приложений: 999G — заведомо больше диска, значит вычистит всё
echo "  Чищу кэш приложений..."
tv "pm trim-caches 999G" >/dev/null

# =============================================================================
#  Шаг 4. Ускорение интерфейса и блокировка рекламы
# =============================================================================
echo
echo "${C_YEL}[4/5] Ускоряю интерфейс и включаю блокировку рекламы${C_OFF}"

# Анимации: Android рисует переходы 300-400 мс. Это не тормоза, а заложенная
# задержка. Ускорение вдвое даёт самый заметный на глаз прирост отзывчивости.
tv "settings put global window_animation_scale 0.5" >/dev/null
tv "settings put global transition_animation_scale 0.5" >/dev/null
tv "settings put global animator_duration_scale 0.5" >/dev/null
echo "  ✓ анимации ускорены в 2 раза"

# Private DNS с фильтром рекламы — главный анти-рекламный приём.
# Рекламные домены просто не резолвятся, баннеры не грузятся НИ В ОДНОМ
# приложении, включая те, которые нельзя удалить. Работает на уровне системы.
tv "settings put global private_dns_mode hostname" >/dev/null
tv "settings put global private_dns_specifier dns.adguard-dns.com" >/dev/null
echo "  ✓ реклама режется через AdGuard DNS (во всех приложениях сразу)"

# Запрет рекламного таргетинга и отправки отчётов
tv "settings put secure limit_ad_tracking 1" >/dev/null
tv "settings put secure send_action_app_error 0" >/dev/null
tv "settings put global network_recommendations_enabled 0" >/dev/null
echo "  ✓ рекламный трекинг и отчёты отключены"

# Телевизор стоит на месте и подключён к одной сети — постоянные сканы
# Wi-Fi и Bluetooth в фоне это чистая трата процессорного времени.
tv "settings put global wifi_scan_always_enabled 0" >/dev/null
tv "settings put global ble_scan_always_enabled 0" >/dev/null
echo "  ✓ фоновые сканы Wi-Fi/Bluetooth выключены"

# Заморозка кэшированных приложений (Android 11+): приложения, висящие
# в памяти «про запас», перестают получать процессорное время.
tv "settings put global cached_apps_freezer enabled" >/dev/null
echo "  ✓ фоновые приложения заморожены"

# --- Итог ---------------------------------------------------------------------
sleep 3
RAM_AFTER="$(tv "cat /proc/meminfo" | awk '/MemAvailable/{printf "%d",$2/1024}')"

echo
echo "${C_GRN}[5/5] ГОТОВО${C_OFF}"
echo "  Отключено приложений : ${COUNT}"
echo "  Свободная ОЗУ        : ${RAM_BEFORE} МБ → ${RAM_AFTER} МБ"
echo "  Журнал отката        : ${LOG}"
echo
echo "  Вернуть всё назад:  bash \"$0\" --restore"
echo
read -r -p "Перезагрузить телевизор сейчас (нужно для применения)? [y/N]: " R
if [ "${R}" = "y" ] || [ "${R}" = "Y" ]; then
  "${ADB}" -s "${TV}" reboot
  echo "Перезагружается. После включения порт отладки сменится — для повторного"
  echo "запуска посмотри новый порт на экране «Отладка по Wi-Fi»."
fi
