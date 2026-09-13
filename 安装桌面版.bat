@echo off
setlocal
cd /d "%~dp0"
echo 正在安装白板声画工坊桌面版...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0安装桌面版.ps1"
if errorlevel 1 (
  echo.
  echo 安装失败，请截图当前窗口发给 ChatGPT。
  pause
  exit /b 1
)
echo.
echo 安装完成。桌面已创建“白板声画工坊”快捷方式。
pause
