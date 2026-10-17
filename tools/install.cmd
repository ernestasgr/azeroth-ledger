@echo off
rem Install the checked-out addon into the Forever beta client and verify the copy.
setlocal
set "WOW_ROOT=C:\Program Files (x86)\World of Warcraft\_classic_beta_"
if not "%~1"=="" set "WOW_ROOT=%~1"
python "%~dp0install_local.py" --wow-root "%WOW_ROOT%" || exit /b 1
python "%~dp0install_local.py" --wow-root "%WOW_ROOT%" --verify-only || exit /b 1
echo Reload the UI (/reload) or restart the client to load the new files.
