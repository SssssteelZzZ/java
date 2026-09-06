#!/usr/bin/env bash
# =============================================================================
#  99_restore_tv.sh — полный откат всех изменений
# =============================================================================
#  ЗАЧЕМ: если что-то сломалось или просто захотелось вернуть как было.
#  Работает по журналам из папки reports/, которые пишут скрипты 03 и 04:
#    restore-*.log          — какие пакеты и каким способом были убраны
#    settings-backup-*.txt  — какие настройки и какие у них были значения
#
#  ЗАПУСК:
#    ./99_restore_tv.sh            — откатить ВСЁ (все журналы по порядку)
#    ./99_restore_tv.sh --packages — вернуть только приложения
#    ./99_restore_tv.sh --settings — вернуть только настройки
#    ./99_restore_tv.sh --all-system — аварийный режим: включить вообще все
#                                       отключённые пакеты, даже без журнала
# =============================================================================

set -u
cd "$(dirname "$0")"
source ./lib_common.sh

DO_PKG=1; DO_SET=1; ALL_SYSTEM=0
for arg in "$@"; do
  case "${arg}" in
    --packages)   DO_SET=0 ;;
    --settings)   DO_PKG=0 ;;
    --all-system) ALL_SYSTEM=1 ;;
    *) echo "${C_RED}Неизвестный флаг: ${arg}${C_OFF}"; exit 1 ;;
  esac
done

DEV="$(tv_find)" || exit 1
echo "${C_BLU}=== Откат изменений на ${DEV} ===${C_OFF}"

# --- 1. Возврат приложений ----------------------------------------------------
if [ "${DO_PKG}" = "1" ]; then
  echo
  echo "${C_YEL}[1] Возвращаю приложения${C_OFF}"

  if [ "${ALL_SYSTEM}" = "1" ]; then
    # Аварийный режим: журналы потеряны или откат делает другой компьютер.
    # `pm list packages -d` показывает все ОТКЛЮЧЁННЫЕ пакеты — включаем подряд.
    echo "  Аварийный режим: включаю все отключённые пакеты системы"
    while IFS= read -r p; do
      [ -z "${p}" ] && continue
      tv_sh "pm enable ${p}" >/dev/null && echo "  ${C_GRN}[on]${C_OFF} ${p}"
    done < <(tv_sh "pm list packages -d" | sed 's/^package://')
    # И доустанавливаем всё, что было удалено для пользователя 0:
    # разница между списком «включая удалённые» (-u) и списком активных.
    while IFS= read -r p; do
      [ -z "${p}" ] && continue
      tv_sh "cmd package install-existing ${p}" >/dev/null && echo "  ${C_GRN}[back]${C_OFF} ${p}"
    done < <(comm -23 \
              <(tv_sh "pm list packages -u" | sed 's/^package://' | sort) \
              <(tv_sh "pm list packages"    | sed 's/^package://' | sort))
  else
    # Обычный режим: идём по журналам от старых к новым.
    shopt -s nullglob                    # если файлов нет — цикл просто не выполнится
    LOGS=( "${REPORT_DIR}"/restore-*.log )
    if [ "${#LOGS[@]}" -eq 0 ]; then
      echo "  ${C_YEL}Журналов нет — нечего откатывать (или используй --all-system)${C_OFF}"
    fi
    for log in "${LOGS[@]}"; do
      echo "  Журнал: $(basename "${log}")"
      # В журнале строки вида "имя.пакета<TAB>disable" или "...<TAB>uninstall"
      while IFS=$'\t' read -r pkg mode; do
        [ -z "${pkg:-}" ] && continue
        if [ "${mode}" = "uninstall" ]; then
          # install-existing переустанавливает APK, который остался в системе
          RES="$(tv_sh "cmd package install-existing ${pkg}")"
        else
          RES="$(tv_sh "pm enable ${pkg}")"
        fi
        if echo "${RES}" | grep -qiE "success|installed|enabled"; then
          echo "    ${C_GRN}[ok]${C_OFF} ${pkg}"
        else
          echo "    ${C_RED}[??]${C_OFF} ${pkg} → ${RES:-нет ответа}"
        fi
      done < "${log}"
    done
  fi
fi

# --- 2. Возврат настроек ------------------------------------------------------
if [ "${DO_SET}" = "1" ]; then
  echo
  echo "${C_YEL}[2] Возвращаю настройки${C_OFF}"
  shopt -s nullglob
  BACKUPS=( "${REPORT_DIR}"/settings-backup-*.txt )
  if [ "${#BACKUPS[@]}" -eq 0 ]; then
    echo "  ${C_YEL}Бэкапов настроек нет${C_OFF}"
  fi
  # Идём по бэкапам в ОБРАТНОМ порядке (от новых к старым): так первым
  # применится самый ранний сохранённый снимок и мы вернёмся к исходному состоянию.
  for ((i=${#BACKUPS[@]}-1; i>=0; i--)); do
    b="${BACKUPS[$i]}"
    echo "  Бэкап: $(basename "${b}")"
    while read -r ns key old; do
      [ -z "${ns:-}" ] && continue
      if [ "${old}" = "null" ]; then
        # Значения не было изначально → удаляем ключ, а не пишем строку "null"
        tv_sh "settings delete ${ns} ${key}" >/dev/null
        echo "    ${key} → удалено (значения не было)"
      else
        tv_sh "settings put ${ns} ${key} ${old}" >/dev/null
        echo "    ${key} → ${old}"
      fi
    done < "${b}"
  done
fi

echo
echo "${C_GRN}=== Откат завершён. Перезагрузи телевизор: adb -s ${DEV} reboot ===${C_OFF}"
