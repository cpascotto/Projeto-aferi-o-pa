@echo off
setlocal EnableExtensions

:: ============================================================
:: build_vincere.bat
:: Builda o APK Vincere e instala no celular via ADB.
::
:: Uso:
::   build_vincere.bat            -> build incremental (rapido)
::   build_vincere.bat --clean    -> faz flutter clean antes
::                                   (forca download Chaquopy do zero)
::
:: Configuracoes que voce pode precisar ajustar:
::   API_BASE_URL          - URL da API de producao
::   FLUTTER_ROOT          - pasta de instalacao do Flutter
::   ANDROID_SDK_ROOT      - pasta do Android SDK
::   JAVA_HOME             - pasta do JDK (Android Studio JBR)
:: ============================================================

set "DO_CLEAN=0"
if /I "%~1"=="--clean" set "DO_CLEAN=1"
if /I "%~1"=="-c"       set "DO_CLEAN=1"

set "PROJECT_ROOT=%~dp0"
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

:: --- Configuracoes de API ---
:: A API local foi descontinuada. O app usa apenas o endpoint do ERP.
set "ERP_AFERICAO_URL=https://api.forzauno.com.br/KB16WT/rest/Forza/prcAfericao01"

:: --- Caminhos de ferramentas ---
set "FLUTTER_ROOT=C:\flutter"
set "ANDROID_SDK_ROOT=C:\Users\arthu\AppData\Local\Android\Sdk"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ADB_EXE=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"

:: --- Drives virtuais (necessario por causa de espacos no caminho) ---
set "DRIVE_ALIAS=Y:"
set "SHORT_DRIVE_ALIAS=X:"
set "FLUTTER_DIR=%SHORT_DRIVE_ALIAS%\flutter_app"

:: --- Caminhos do APK ---
set "APK_PATH=%FLUTTER_DIR%\build\app\outputs\flutter-apk\app-release.apk"
set "VINCERE_APK_PATH=%FLUTTER_DIR%\build\app\outputs\flutter-apk\vincere.apk"
set "PHONE_DOWNLOAD_PATH=/sdcard/Download/vincere.apk"

echo.
echo [1/7] Preparando ambiente...
echo ERP_AFERICAO_URL=%ERP_AFERICAO_URL%

call :ensure_subst "%DRIVE_ALIAS%" "%PROJECT_ROOT%"
if errorlevel 1 goto :fail
call :ensure_subst "%SHORT_DRIVE_ALIAS%" "%PROJECT_ROOT%"
if errorlevel 1 goto :fail

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo ERRO: Flutter nao encontrado em "%FLUTTER_ROOT%".
  goto :fail
)
if not exist "%ANDROID_SDK_ROOT%" (
  echo ERRO: Android SDK nao encontrado em "%ANDROID_SDK_ROOT%".
  goto :fail
)
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo ERRO: Java nao encontrado em "%JAVA_HOME%".
  goto :fail
)
if not exist "%ADB_EXE%" (
  echo ERRO: ADB nao encontrado em "%ADB_EXE%".
  goto :fail
)

set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_SDK_ROOT%\platform-tools;%PATH%"

echo.
echo [2/7] Verificando ERP (informativo, nao bloqueia o build)...
call :wait_http "%ERP_AFERICAO_URL%" "ERP Forza" 2
if errorlevel 1 (
  echo AVISO: ERP nao respondeu agora. O build vai continuar mesmo assim.
)

echo.
echo [3/7] Verificando dispositivo conectado...
"%ADB_EXE%" devices
if errorlevel 1 goto :fail

echo.
echo [4/7] Preparando build...
cd /d "%FLUTTER_DIR%"
if exist "%FLUTTER_DIR%\android\gradlew.bat" (
  call "%FLUTTER_DIR%\android\gradlew.bat" --stop >nul 2>&1
)
if "%DO_CLEAN%"=="1" (
  echo Modo --clean ligado: rodando flutter clean...
  call "%FLUTTER_ROOT%\bin\flutter.bat" clean
  if errorlevel 1 goto :fail
) else (
  echo Build incremental ^(use --clean para forcar limpeza completa^).
)
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
if errorlevel 1 goto :fail

echo.
echo [5/7] Buildando APK...
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release ^
  --dart-define=ERP_AFERICAO_URL=%ERP_AFERICAO_URL%
if errorlevel 1 goto :fail

if not exist "%APK_PATH%" (
  echo ERRO: APK nao encontrado em "%APK_PATH%".
  goto :fail
)
copy /Y "%APK_PATH%" "%VINCERE_APK_PATH%" >nul
if errorlevel 1 goto :fail

echo.
echo [6/7] Instalando APK no celular...
"%ADB_EXE%" install -r "%VINCERE_APK_PATH%"
if errorlevel 1 goto :fail

echo.
echo [7/7] Enviando APK para Downloads do celular...
"%ADB_EXE%" push "%VINCERE_APK_PATH%" "%PHONE_DOWNLOAD_PATH%"
if errorlevel 1 goto :fail
"%ADB_EXE%" shell ls -lh "%PHONE_DOWNLOAD_PATH%"
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo Build e instalacao concluidos com sucesso.
echo ERP usado  : %ERP_AFERICAO_URL%
echo APK local  : %VINCERE_APK_PATH%
echo APK celular: %PHONE_DOWNLOAD_PATH%
echo ============================================================
goto :end

:: ---- Subrotinas ----

:wait_http
set "WAIT_URL=%~1"
set "WAIT_NAME=%~2"
set "WAIT_MAX=%~3"
if "%WAIT_MAX%"=="" set "WAIT_MAX=30"
set "WAIT_ATTEMPT=0"
:wait_http_loop
set /a WAIT_ATTEMPT+=1
powershell -NoProfile -Command ^
  "try { $r = Invoke-WebRequest -UseBasicParsing '%WAIT_URL%' -TimeoutSec 3; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } else { exit 1 } } catch { exit 1 }"
if not errorlevel 1 (
  echo %WAIT_NAME% OK: %WAIT_URL%
  exit /b 0
)
if %WAIT_ATTEMPT% geq %WAIT_MAX% (
  echo ERRO: %WAIT_NAME% nao respondeu em %WAIT_URL%.
  exit /b 1
)
echo Aguardando %WAIT_NAME%... tentativa %WAIT_ATTEMPT%/%WAIT_MAX%
timeout /t 2 /nobreak >nul
goto :wait_http_loop

:ensure_subst
set "SUBST_DRIVE=%~1"
set "SUBST_TARGET=%~2"
subst %SUBST_DRIVE% /D >nul 2>&1
subst %SUBST_DRIVE% "%SUBST_TARGET%" >nul 2>&1
if errorlevel 1 (
  echo ERRO: Falha ao mapear drive %SUBST_DRIVE% para "%SUBST_TARGET%".
  exit /b 1
)
exit /b 0

:fail
echo.
echo Build interrompido por erro.
exit /b 1

:end
endlocal
