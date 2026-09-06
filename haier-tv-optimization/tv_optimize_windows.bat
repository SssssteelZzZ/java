@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
REM =============================================================================
REM  tv_optimize_windows.bat - всё-в-одном для Windows (без Git Bash и Linux)
REM =============================================================================
REM  ЗАЧЕМ: то же самое, что делают bash-скрипты 01-04, но одним файлом
REM  и с меню, чтобы можно было просто дважды кликнуть.
REM
REM  ТРЕБОВАНИЯ:
REM   1. Скачать Android Platform Tools:
REM      https://dl.google.com/android/repository/platform-tools-latest-windows.zip
REM   2. Распаковать, положить ЭТОТ ФАЙЛ в ту же папку, где лежит adb.exe
REM   3. Запустить двойным кликом.
REM
REM  ПОРЯДОК ДЕЙСТВИЙ: пункт 1 (подключиться) -> 2 (посмотреть) -> 3 -> 4
REM =============================================================================

REM --- Адрес телевизора (взят с экрана настроек отладки) -----------------------
set TV_IP=192.168.0.149
set TV_PORT=37765
set TV=%TV_IP%:%TV_PORT%

REM --- Проверяем, что adb.exe рядом или в PATH ---------------------------------
where adb >nul 2>&1
if errorlevel 1 (
  if exist "%~dp0adb.exe" (
    REM %~dp0 - папка, где лежит этот .bat. Добавляем её в PATH на время работы.
    set "PATH=%~dp0;%PATH%"
  ) else (
    echo [!] adb.exe не найден. Положи этот файл в папку platform-tools рядом с adb.exe
    pause & exit /b 1
  )
)

:MENU
cls
echo ============================================================
echo   Оптимизация Haier Android TV PRO   ^(%TV%^)
echo ============================================================
echo   1 - Подключиться к телевизору (сопряжение по коду)
echo   2 - Показать, что установлено (ничего не меняет)
echo   3 - Удалить рекламу и предустановленный мусор
echo   4 - Ускорить интерфейс + включить блокировку рекламы (DNS)
echo   5 - Перезагрузить телевизор
echo   9 - ОТКАТ: вернуть все приложения обратно
echo   0 - Выход
echo ============================================================
set /p CHOICE="Выбор: "

if "%CHOICE%"=="1" goto CONNECT
if "%CHOICE%"=="2" goto SCAN
if "%CHOICE%"=="3" goto DEBLOAT
if "%CHOICE%"=="4" goto SPEEDUP
if "%CHOICE%"=="5" goto REBOOT
if "%CHOICE%"=="9" goto RESTORE
if "%CHOICE%"=="0" exit /b 0
goto MENU

REM =============================================================================
:CONNECT
REM  Android 11+ требует сначала сопряжение по коду, и порт сопряжения
REM  ОТЛИЧАЕТСЯ от порта подключения. Это самая частая ошибка.
echo.
echo Пробую подключиться напрямую (если сопряжение уже было)...
adb connect %TV%
adb shell getprop ro.product.model >nul 2>&1
if not errorlevel 1 goto CONNECT_OK

echo.
echo Нужно сопряжение. На телевизоре открой:
echo   Настройки - Для разработчиков - Отладка по Wi-Fi
echo   - "Подключить устройство с помощью кода подключения"
echo Там будет 6-значный код и адрес с ДРУГИМ портом (не %TV_PORT%).
echo.
set /p PPORT="Порт сопряжения (5 цифр): "
set /p PCODE="Код сопряжения (6 цифр): "
adb pair %TV_IP%:%PPORT% %PCODE%
adb connect %TV%

:CONNECT_OK
echo.
echo Подключено к:
adb -s %TV% shell getprop ro.product.model
adb -s %TV% shell getprop ro.build.version.release
pause & goto MENU

REM =============================================================================
:SCAN
REM  Просто выгружаем список пакетов в файл и показываем, кто ест память.
echo.
echo Сохраняю список установленных приложений в packages.txt ...
adb -s %TV% shell pm list packages > "%~dp0packages.txt"
echo Готово: %~dp0packages.txt
echo.
echo --- Кто сейчас занимает больше всего памяти ---
adb -s %TV% shell dumpsys meminfo | findstr /R /C:"K: " | more +2
pause & goto MENU

REM =============================================================================
:DEBLOAT
REM  Отключаем предустановленные витрины и рекламные модули.
REM  Используем pm disable-user: приложение остаётся на диске, но не запускается.
REM  Это полностью обратимо пунктом 9 меню.
echo.
echo Отключаю предустановленный мусор...
echo.
for %%P in (
  ru.ivi.client
  ru.more.play
  ru.okko.tv
  ru.rt.video.app.tv
  com.megogo.application
  com.megogo.tv
  ru.kinopoisk.yandex.tv
  ru.start.androidtv
  com.mts.mtstv
  one.premier.androidtv
  ru.tricolor.tv
  com.viju.androidtv
  tv.peers.android
  ru.limehd.tv
  ru.mts.mtstv
  ru.beeline.services
  com.netflix.ninja
  com.netflix.partner.activation
  com.amazon.amazonvideo.livingroom
  com.disney.disneyplus
  com.spotify.tv.android
  com.google.android.play.games
  com.google.android.videos
  com.google.android.apps.tachyon
  com.google.android.backuptransport
  com.google.android.feedback
  com.google.android.partnersetup
  com.google.android.printservice.recommendation
  com.google.android.syncadapters.contacts
  com.google.android.syncadapters.calendar
  com.google.android.marvin.talkback
  com.facebook.appmanager
  com.facebook.services
  com.facebook.system
) do (
  REM 2^>^&1 - перенаправление ошибок в общий вывод, чтобы видеть причину отказа
  adb -s %TV% shell pm disable-user --user 0 %%P 2>&1 | findstr /I "disabled Failure" && echo   %%P
)

echo.
echo Чищу кэш приложений...
adb -s %TV% shell pm trim-caches 999G
echo.
echo Готово. Если что-то нужное пропало - пункт 9 вернёт всё обратно.
pause & goto MENU

REM =============================================================================
:SPEEDUP
REM  Анимации + DNS с фильтром рекламы + отключение фоновых сканов.
echo.
echo [1/4] Ускоряю анимации интерфейса (в 2 раза)...
adb -s %TV% shell settings put global window_animation_scale 0.5
adb -s %TV% shell settings put global transition_animation_scale 0.5
adb -s %TV% shell settings put global animator_duration_scale 0.5

echo [2/4] Включаю блокировку рекламы через AdGuard DNS...
REM Приватный DNS режет рекламные домены во ВСЕХ приложениях сразу,
REM включая те, которые нельзя удалить.
adb -s %TV% shell settings put global private_dns_mode hostname
adb -s %TV% shell settings put global private_dns_specifier dns.adguard-dns.com

echo [3/4] Отключаю рекламный трекинг и отчёты...
adb -s %TV% shell settings put secure limit_ad_tracking 1
adb -s %TV% shell settings put secure send_action_app_error 0
adb -s %TV% shell settings put global network_recommendations_enabled 0

echo [4/4] Отключаю постоянные фоновые сканы Wi-Fi/Bluetooth...
adb -s %TV% shell settings put global wifi_scan_always_enabled 0
adb -s %TV% shell settings put global ble_scan_always_enabled 0
adb -s %TV% shell settings put global cached_apps_freezer enabled

echo.
echo Готово. Рекомендуется перезагрузка (пункт 5).
pause & goto MENU

REM =============================================================================
:REBOOT
adb -s %TV% reboot
echo Телевизор перезагружается. Подключение придётся установить заново (пункт 1).
pause & goto MENU

REM =============================================================================
:RESTORE
REM  Аварийный возврат: включаем ВСЕ отключённые пакеты и возвращаем анимации.
echo.
echo Включаю обратно все отключённые приложения...
for /f "tokens=2 delims=:" %%P in ('adb -s %TV% shell pm list packages -d') do (
  adb -s %TV% shell pm enable %%P >nul 2>&1
  echo   вернул: %%P
)
echo Возвращаю стандартные анимации...
adb -s %TV% shell settings put global window_animation_scale 1
adb -s %TV% shell settings put global transition_animation_scale 1
adb -s %TV% shell settings put global animator_duration_scale 1
echo Отключаю приватный DNS...
adb -s %TV% shell settings put global private_dns_mode off
echo.
echo Откат выполнен. Перезагрузи телевизор (пункт 5).
pause & goto MENU
