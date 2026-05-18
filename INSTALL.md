# work-log 工具安裝說明

這個工具可以幫你自動連線 VPN 並填寫「樂衍工作日誌」。它既可以作為獨立工具使用，也可以作為 AI Agent（如 Claude, Gemini, Codex）的擴充技能 (Skill)。

---

## 快速安裝（推薦）

如果你不熟悉程式開發，請直接執行：
1.  雙擊執行 **`0.自動安裝環境(按我).bat`**。
2.  腳本會自動檢查 Node.js、VPN 啟動檔、openconnect、`.env` 必要欄位、npm 套件與 Playwright Chromium。
3.  如果 `.env` 尚未建立或欄位未填完整，腳本會自動開啟 `.env`，請填入你的員編、內網密碼、VPN 帳密後存檔，再重新執行安裝。

---

## AI Agent 整合指南 (AI Agent Integration)

本工具遵循 **Progressive Disclosure** 標準，支援多種 AI Agent 偵測。

### 1. 支援的 Agent 與擺放路徑
若要在 AI 工具中使用此技能，請確保資料夾擺放在對應位置：

| Agent | 建議路徑 | 備註 |
|---|---|---|
| **Gemini CLI** | `.agents/skills/work-log` | 本專案預設路徑 |
| **Codex** | `%USERPROFILE%\.codex\skills\work-log` 或 `.agents/skills/work-log` | 若放在專案外，skill 目錄需有 `.record-work-root` 指向本專案 |
| **Claude Code** | `.claude/skills/work-log` | 需將 `.agents` 改名為 `.claude` |

> `run.ps1` 與 `work-log.js` 會用三種方式尋找真正的專案根目錄：先讀環境變數 `RECORD_WORK_ROOT`，再讀 skill 目錄內的 `.record-work-root`，最後才從 skill 目錄往上尋找。專案根必須同時包含 `.env` 或 `.env.example`、`vpn-connect.ps1`、以及 `*VPN*.bat`。因此 skill 放在 `.agents/skills/work-log`、`.claude/skills/work-log`、`skills/work-log`，或 Codex 的 `%USERPROFILE%\.codex\skills\work-log` 都能使用。

若要把同一份 skill 同步到 Codex/Claude 的使用者層級 skill 目錄，可執行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SyncExternalSkills
```

也可以指定任意外部 skill 目錄：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1" -SkillDir "$env:USERPROFILE\.codex\skills\work-log"
```

### 2. 給 AI Agent 的操作指令 (Important)
**如果你是 AI Agent，請遵循以下邏輯：**
- **檢查設定**：執行前請先檢查專案根目錄 `.env` 是否已填寫 `account`、`password`、`VPN_account`、`VPN_password`、`department`。
- **不要把 `.env` 寫到 skill 目錄或使用者家目錄**：正確位置是 record_work 專案根目錄，也就是與 `vpn-connect.ps1`、`1.啟動VPN.bat` 同層。若 skill 在專案外，請讀 `.record-work-root` 或 `RECORD_WORK_ROOT` 取得專案根。
- **主動詢問**：如果發現 `.env` 缺少個人帳密資訊，請**主動詢問使用者**並要求其提供，格式如下：
  > 偵測到尚未設定個人帳密。請依下列格式一次回覆（不要加引號）：
  > ```
  > account=你的員編
  > password=你的系統密碼
  > VPN_account=通常同 account
  > VPN_password=你的 VPN 密碼
  > department=3  # 3=內勤 4=培訓 5=業務 6=客服 7=工程 8=行銷 9=開業顧問
  > ```
- **自動寫入**：收到回覆後，請直接更新 `.env` 檔案，確保後續執行順暢。

---

## 專案結構

```
<專案根>/
├── 0.自動安裝環境(按我).bat     ← 一鍵安裝
├── 1.啟動VPN.bat               ← VPN 手動啟動
├── .env.example                ← 設定範本
├── .agents/                    ← AI Agent 核心目錄
│   └── skills/
│       └── work-log/
│           ├── SKILL.md        ← 技能定義
│           ├── work-log.js     ← Playwright 自動化
│           └── run.ps1         ← 執行腳本
└── vpn-installer/              (VPN 工具組)
```

## 安裝步驟（手動模式）

### Step 1：安裝套件
```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup.ps1"
```

### Step 2：建立設定檔
將 `.env.example` 複製為 `.env` 並填入資料。

### Step 3：手動驗證
```powershell
& ".agents\skills\work-log\run.ps1" -Content "安裝測試"
```

---

## 常見問題排查

| 症狀 | 可能原因 | 處理 |
|---|---|---|
| `npm install` 失敗 | Node 版本太舊 | 升級到 ≥ 18 |
| `.env 缺少 internal_ip` | `.env` 寫錯位置或範本未填完整 | 執行 `setup.ps1`，確認 `.env` 在專案根目錄 |
| Codex/Claude 使用者層級 skill 找不到 `.env` | skill 在專案外，無法靠父目錄找到 record_work | 執行 `setup.ps1 -SkillDir "<skill路徑>"`，讓安裝流程建立 `.record-work-root` |
| `VPN .bat not found` | skill 路徑層級與舊版腳本假設不一致，或 VPN bat 不在專案根目錄 | 更新到新版腳本，並確認 `1.啟動VPN.bat` 與 `vpn-connect.ps1` 在專案根目錄 |
| `VPN did not come up` | VPN 帳密錯 | 手動跑 `1.啟動VPN.bat` 看錯誤訊息 |
| 跳 UAC 不會自動過 | 提權請求 | 請使用者在 Windows 彈出視窗點擊「是」 |

## 維護者
skill 由原作者維護。
