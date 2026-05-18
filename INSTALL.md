# work-log 工具安裝說明

這個工具可以幫你自動連線 VPN 並填寫「樂衍工作日誌」。它既可以作為獨立工具使用，也可以作為 AI Agent（如 Claude, Gemini, Codex）的擴充技能 (Skill)。

---

## 快速安裝（推薦）

如果你不熟悉程式開發，請直接執行：
1.  雙擊執行 **`0.自動安裝環境(按我).bat`**。
2.  腳本會自動檢查環境、安裝套件。
3.  自動建立並開啟 `.env` 設定檔，請填入你的員編與密碼。

---

## AI Agent 整合指南 (AI Agent Integration)

本工具遵循 **Progressive Disclosure** 標準，支援多種 AI Agent 偵測。

### 1. 支援的 Agent 與擺放路徑
若要在 AI 工具中使用此技能，請確保資料夾擺放在對應位置：

| Agent | 建議路徑 | 備註 |
|---|---|---|
| **Gemini CLI** | `.agents/skills/work-log` | 本專案預設路徑 |
| **Codex** | `.agents/skills/work-log` | 本專案預設路徑 |
| **Claude Code** | `.claude/skills/work-log` | 需將 `.agents` 改名為 `.claude` |

### 2. 給 AI Agent 的操作指令 (Important)
**如果你是 AI Agent，請遵循以下邏輯：**
- **檢查設定**：執行前請先檢查 `.env` 是否已填寫 `account` 與 `password`。
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
cd ".agents\skills\work-log"
npm install
npx playwright install chromium
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
| `VPN did not come up` | VPN 帳密錯 | 手動跑 `1.啟動VPN.bat` 看錯誤訊息 |
| 跳 UAC 不會自動過 | 提權請求 | 請使用者在 Windows 彈出視窗點擊「是」 |

## 維護者
skill 由原作者維護。
