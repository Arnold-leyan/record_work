# record_work

`record_work` 是一個給 AI Agent 使用的工作日誌自動填寫專案。它會透過 VPN 連進公司內網，登入內部系統，找到指定的工作日誌客戶，完成當日報到與備註填寫。

這個專案的目標不是讓使用者每天手動操作系統，而是讓 Codex、Claude Code 或其他 AI Agent 可以接到一句「幫我記錄工作日誌」之後，自動完成整個流程。

## 主要功能

- 自動檢查內網是否可連線。
- 必要時自動啟動 VPN。
- 登入內部顧客管理系統。
- 搜尋設定好的工作日誌客戶。
- 如果今天尚未報到，會自動快速報到。
- 進入客服備註頁。
- 填寫對外與對內備註。
- 選擇指定部門 / 服務類型。
- 儲存日誌。
- 如果 VPN 是本次流程啟動的，結束後會自動關閉。

## 專案結構

```text
record_work/
  README.md
  INSTALL.md
  setup.ps1
  vpn-connect.ps1
  .env.example
  .agents/
    skills/
      work-log/
        SKILL.md
        run.ps1
        work-log.js
        package.json
        package-lock.json
  vpn-installer/
    bin/
      openconnect.exe
```

根目錄另外有兩個給人直接點擊使用的 `.bat`：

- `0.自動安裝環境(按我).bat`：執行安裝與環境檢查。
- `1.啟動VPN.bat`：手動啟動 VPN。

實際自動化主要由 `.agents/skills/work-log/run.ps1` 和 `.agents/skills/work-log/work-log.js` 負責。

## 使用環境

目前此專案以 Windows 為主要執行環境，並需要：

- Windows PowerShell 5.1 或更新版本。
- Node.js LTS。
- npm。
- 可用的 VPN 帳密與連線設定。
- 內部系統帳密。
- 第一次連 VPN 時可能需要同意 Windows UAC 管理員權限。

## 安裝方式

一般使用者可以直接雙擊：

```text
0.自動安裝環境(按我).bat
```

或在 PowerShell 執行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1"
```

安裝流程會檢查 Node.js、建立 `.env`、安裝 npm 套件，並安裝 Playwright Chromium。

如果 `.env` 尚未填好，安裝程式會開啟設定檔，請填入帳號、密碼、VPN 與內網設定後再重新執行安裝。

## 設定檔

`.env` 是本機私密設定檔，裡面包含帳密與 VPN 資訊。請勿提交到 Git，也不要公開分享。

需要設定的欄位包含：

```dotenv
account=內部系統帳號
password=內部系統密碼
VPN_account=VPN帳號
VPN_password=VPN密碼
VPN_gateway=VPN主機與連接埠
VPN_cert=VPN憑證pin
internal_ip=內網系統IP
department=部門代碼
customer_name=工作日誌客戶名稱
```

`customer_name` 通常設定為工作日誌用的客戶名稱。`department` 則依公司內部系統的服務類型代碼設定。

## 手動測試

可以用以下命令測試一筆日誌：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\.agents\skills\work-log\run.ps1" -Content "測試工作日誌"
```

如果對外備註與對內備註不同，可以使用：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\.agents\skills\work-log\run.ps1" -Content "對外備註" -Content2 "對內備註"
```

如果沒有提供 `-Content2`，系統會把 `-Content` 同時填入對外與對內備註。

## 給 AI Agent 的使用方式

AI Agent 不需要重新撰寫瀏覽器自動化流程，直接呼叫既有 skill 即可。

Repo 內建 skill 位置：

```text
.agents/skills/work-log
```

Agent 執行格式：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\run.ps1" -Content "<今日工作內容>"
```

如果要安裝到 Codex 的 skill 目錄：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkillDir "$env:USERPROFILE\.codex\skills\work-log"
```

如果要安裝到 Claude Code 的 skill 目錄：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkillDir "$env:USERPROFILE\.claude\skills\work-log"
```

詳細的 AI Agent 安裝與接手流程請看 [INSTALL.md](INSTALL.md)。

## 常見問題

### 安裝時提示 Node.js 未安裝

請先安裝 Node.js LTS，重新開啟 PowerShell 後再執行安裝。

### `.env` 缺少設定

請依照 `.env.example` 補齊必要欄位，特別是內部系統帳密、VPN 帳密、VPN gateway、VPN cert、internal IP 與 department。

### VPN 無法連線

請確認 VPN 帳密、gateway、cert pin 是否正確，並確認 Windows UAC 權限提示有被允許。

### AI Agent 找不到專案根目錄

如果 skill 被複製到外部目錄，需要透過 `setup.ps1 -SkillDir "<skill-dir>"` 安裝，讓系統自動建立 `.record-work-root`。也可以設定 `RECORD_WORK_ROOT` 指向真正的 `record_work` 目錄。

## 安全提醒

- `.env` 內含機密資料，不應提交或公開。
- Playwright 的 browser profile 可能包含登入 session，也不應提交。
- 本專案只應用於設定好的工作日誌流程，不應用來填寫未授權的客戶或非當日紀錄。

