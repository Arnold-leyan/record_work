@echo off
setlocal enabledelayedexpansion

title 樂衍工作日誌 - 自動安裝工具

echo ======================================================
echo           樂衍工作日誌 自動環境安裝工具
echo ======================================================
echo.

:: 1. 檢查 Node.js
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [錯誤] 找不到 Node.js！
    echo 正在為您開啟 Node.js 下載頁面...
    echo 請下載並安裝 "LTS" 版本，安裝完後「重新啟動此腳本」。
    timeout /t 3 >nul
    start https://nodejs.org/
    pause
    exit
)

echo [1/3] 找到 Node.js，正在安裝必要套件 (npm install)...
cd /d "%~dp0.agents\skills\work-log"
call npm install --quiet
if %errorlevel% neq 0 (
    echo [錯誤] npm install 失敗！請檢查網路連線。
    pause
    exit
)

echo [2/3] 正在安裝瀏覽器元件 (playwright install)...
call npx playwright install chromium
if %errorlevel% neq 0 (
    echo [錯誤] 瀏覽器安裝失敗！
    pause
    exit
)

echo [3/3] 檢查設定檔 (.env)...
cd /d "%~dp0"
if not exist ".env" (
    echo 偵測到尚未建立設定檔，正在從範本建立...
    copy ".env.example" ".env" >nul
    echo 正在為您開啟 .env 檔案，請填入您的帳號密碼後存檔關閉。
    start notepad ".env"
    echo.
    echo *請在記事本中填好帳號密碼並儲存後，再回到這裡按任意鍵繼續*
    pause
) else (
    echo 設定檔 .env 已存在，跳過建立。
)

echo.
echo ======================================================
echo              恭喜！安裝程序已全部完成
echo ======================================================
echo.
echo 接下來您可以：
echo 1. 執行 "1.啟動VPN.bat" 測試連線
echo 2. 在對話框中對我說「幫我記今天的工作日誌」
echo.
pause
