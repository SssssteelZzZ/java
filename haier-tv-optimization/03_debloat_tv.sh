#!/usr/bin/env bash
# =============================================================================
#  03_debloat_tv.sh — удаление рекламы и предустановленного мусора
# =============================================================================
#  ДВА РЕЖИМА РАБОТЫ (это главное, что нужно понять):
#
#   disable   (по умолчанию) — `pm disable-user --user 0`
#             Приложение остаётся на диске, но не запускается и исчезает из меню.
#             Не стартует в фоне, не ест ОЗУ, не лезет в сеть за рекламой.
#             Откат: мгновенный, `pm enable`. Переживает перезагрузку.
#
#   uninstall (флаг --uninstall) — `pm uninstall -k --user 0`
#             Приложение удаляется для текущего пользователя, но APK остаётся
#             в системном разделе (root не нужен). Освобождает ещё и место.
#             Откат: `cmd package install-existing`. ВНИМАНИЕ: сброс к заводским
#             настройкам вернёт всё обратно — это нормально, так устроен Android.
#
#  Разницы в скорости между режимами почти нет: отключённое приложение
#  системой не запускается вообще. disable выбран по умолчанию как безопасный.
#
#  ФЛАГИ:
#    --apply        реально выполнить (без него — только показать план, dry-run)
#    --dry-run      явный холостой прогон (то же, что без --apply)
#    --uninstall    удалять, а не отключать
#    --google       затронуть также сервисы Google из BLOAT_GOOGLE
#    --patterns     затронуть найденное по шаблонам рекламы/телеметрии
#    --yes          не спрашивать подтверждение (для автоматизации)
#
#  ПРИМЕР ПОЛНОЙ ЧИСТКИ:
#    ./03_debloat_tv.sh --apply --google --patterns
# =============================================================================

set -u
cd "$(dirname "$0")"
source ./lib_common.sh
source ./tv_packages.conf

# --- Разбор аргументов командной строки --------------------------------------
APPLY=0; MODE="disable"; USE_GOOGLE=0; USE_PATTERNS=0; ASSUME_YES=0
for arg in "$@"; do
  case "${arg}" in
    --apply)     APPLY=1 ;;
    --dry-run)   APPLY=0 ;;
    --uninstall) MODE="uninstall" ;;
    --google)    USE_GOOGLE=1 ;;
    --patterns)  USE_PATTERNS=1 ;;
    --yes|-y)    ASSUME_YES=1 ;;
    *) echo "${C_RED}Неизвестный флаг: ${arg}${C_OFF}"; exit 1 ;;
  esac
done

DEV="$(tv_find)" || exit 1
STAMP="$(date +%Y%m%d-%H%M%S)"
RAM_BEFORE="$(free_ram_mb)"

# --- Собираем актуальный список того, что стоит на ТВ -------------------------
# Один раз тянем список пакетов и дальше работаем с локальным файлом:
# каждый вызов adb — это ~0.3 сек, на 200 пакетах это разница между 1 и 60 секундами.
INSTALLED="${REPORT_DIR}/.installed-${STAMP}.tmp"
tv_sh "pm list packages" | sed 's/^package://' | sort > "${INSTALLED}"

# --- Формируем очередь на обработку ------------------------------------------
TARGETS=()

# 1) базовый список мусора — берём всегда
for p in "${BLOAT_SAFE[@]}"; do
  grep -qx "${p}" "${INSTALLED}" && TARGETS+=("${p}")
done

# 2) сервисы Google — только по флагу
if [ "${USE_GOOGLE}" = "1" ]; then
  for entry in "${BLOAT_GOOGLE[@]}"; do
    p="${entry%%|*}"
    grep -qx "${p}" "${INSTALLED}" && TARGETS+=("${p}")
  done
fi

# 3) находки по шаблонам рекламы — только по флагу
if [ "${USE_PATTERNS}" = "1" ]; then
  for pat in "${BLOAT_PATTERNS[@]}"; do
    while IFS= read -r p; do
      [ -z "${p}" ] && continue
      TARGETS+=("${p}")
    done < <(grep -E "${pat}" "${INSTALLED}" || true)
  done
fi

# --- Финальная фильтрация: убрать дубли и всё защищённое ----------------------
# Это последний рубеж перед выполнением: даже если шаблон случайно поймал
# системный пакет, is_protected его отсюда выкинет.
FINAL=()
for p in $(printf '%s\n' "${TARGETS[@]:-}" | sort -u); do
  [ -z "${p}" ] && continue
  if is_protected "${p}"; then
    echo "${C_BLU}[защищён, пропуск] ${p}${C_OFF}"
    continue
  fi
  FINAL+=("${p}")
done

if [ "${#FINAL[@]}" -eq 0 ]; then
  echo "${C_GRN}Нечего чистить — всё уже сделано.${C_OFF}"
  rm -f "${INSTALLED}"; exit 0
fi

# --- Показываем план ----------------------------------------------------------
echo
echo "${C_YEL}=== ПЛАН: режим '${MODE}', пакетов ${#FINAL[@]} ===${C_OFF}"
printf '  %s\n' "${FINAL[@]}"
echo

if [ "${APPLY}" != "1" ]; then
  echo "${C_BLU}Это холостой прогон (dry-run) — ничего не изменено.${C_OFF}"
  echo "Чтобы выполнить: $0 --apply $([ "${USE_GOOGLE}" = 1 ] && echo --google) $([ "${USE_PATTERNS}" = 1 ] && echo --patterns)"
  rm -f "${INSTALLED}"; exit 0
fi

# --- Подтверждение ------------------------------------------------------------
if [ "${ASSUME_YES}" != "1" ]; then
  read -r -p "Выполнить '${MODE}' для ${#FINAL[@]} пакетов? Введи YES: " ANSWER
  [ "${ANSWER}" = "YES" ] || { echo "Отменено."; rm -f "${INSTALLED}"; exit 0; }
fi

# --- Журнал отката ------------------------------------------------------------
# Пишем «пакет<TAB>режим» — скрипт 99_restore_tv.sh по нему всё вернёт назад.
RESTORE_LOG="${REPORT_DIR}/restore-${STAMP}.log"
: > "${RESTORE_LOG}"

OK=0; FAIL=0
for p in "${FINAL[@]}"; do
  if [ "${MODE}" = "uninstall" ]; then
    # -k сохраняет данные и кэш приложения; --user 0 = только текущий пользователь
    RESULT="$(tv_sh "pm uninstall -k --user 0 ${p}")"
  else
    # disable-user отключает приложение так, что оно не стартует даже в фоне
    RESULT="$(tv_sh "pm disable-user --user 0 ${p}")"
  fi

  # pm печатает "Success" или "... new state: disabled-user" при успехе
  if echo "${RESULT}" | grep -qiE "success|disabled-user"; then
    echo "${C_GRN}[ok]${C_OFF}   ${p}"
    printf '%s\t%s\n' "${p}" "${MODE}" >> "${RESTORE_LOG}"
    OK=$((OK+1))
  else
    # Частая причина отказа — пакет прошит как «нельзя отключать» вендором.
    echo "${C_RED}[skip]${C_OFF} ${p} → ${RESULT:-нет ответа}"
    FAIL=$((FAIL+1))
  fi
done

# --- Чистим кэш приложений: освобождаем место и убираем мусор рекламных SDK ---
# 999G — заведомо больше объёма диска, значит система вычистит кэш полностью.
echo
echo "Чищу кэш приложений..."
tv_sh "pm trim-caches 999G" >/dev/null

rm -f "${INSTALLED}"
sleep 3                                   # даём системе освободить память
RAM_AFTER="$(free_ram_mb)"

echo
echo "${C_GRN}=== ГОТОВО ===${C_OFF}"
echo "  Обработано успешно : ${OK}"
echo "  Пропущено          : ${FAIL} (вендор запретил отключение — это нормально)"
echo "  Свободная ОЗУ      : ${RAM_BEFORE} МБ → ${RAM_AFTER} МБ"
echo "  Журнал отката      : ${RESTORE_LOG}"
echo
echo "Дальше: ./04_speedup_tv.sh   (ускорение интерфейса и блокировка рекламы в сети)"
