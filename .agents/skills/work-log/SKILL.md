---
name: work-log
description: |
  自動把使用者描述的「今日工作內容」填寫到公司內網（樂晴顧客管理系統 / 樂衍客服日誌）的當日備註欄。
  觸發詞：「記今天的工作日誌」、「填工作日誌」、「寫日誌」、「樂衍工作日誌」、「樂衍客服日誌」、
  「記錄今天做了什麼」、「報到並寫日誌」、「內勤/培訓/客服 日誌」，或直接 `/work-log <內容>`。
  全自動處理：VPN 連線（用完自動關）、內網登入（從 .env 讀帳密）、搜尋客戶「樂衍工作日誌」、
  必要時快速報到、進入「樂衍客服」備註頁、修改外部+內部備註、選擇服務類型（部門）、儲存。
  使用者只需提供今天的工作內容描述即可；分對外/對內可選傳第二段。
  禁止用途：不要拿這個 skill 去填別人的日誌、別的客戶或非當日的紀錄。
---

# 工作日誌自動化

把使用者描述的今日工作內容，透過 Playwright 自動填到內網的「樂衍客服」日誌系統。

## 使用方式

### 寫入今日工作日誌

呼叫時把日誌內容當參數傳入。範例：

```
/work-log 今天處理了 A 客戶的工單、修了 B 系統的 bug、開了一個會
```

如果使用者透過 Telegram 對 Claude Code 說「幫我記今天的工作日誌」之類的話，且後面附帶了實際內容，就直接呼叫這個 skill 並把內容當作 `$ARGUMENTS` 傳入。

### 查看今日已寫工作日誌

如果使用者說「查看今天工作日誌」、「我今天寫了什麼工作日誌」等，不要執行寫入流程；改執行唯讀查詢腳本：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\L164\.hermes\skills\productivity\work-log\read-run.ps1"
```

`read-run.ps1` 會連 VPN、登入、進入「樂衍客服」頁讀取當日內部/外部備註與部門；它會在備註頁用登入姓名/帳號（例如 `邱珞` / `L181`）尋找當日屬於本人的日誌，而不是讀第一筆同日資料。它可能點「修改」讓 textarea 顯示，但不會點儲存。執行完成後回報 JSON 裡的 `internalNote`、`externalNote`、`department`；如果同日只有其他同仁資料，應回報尚未找到本人的工作日誌。

注意：查看日誌才單獨跑 `read-run.ps1`。寫入日誌時請用 `run.ps1 -Verify`，讓寫入與讀回驗證共用同一次 VPN 連線，避免 `run.ps1` 關掉 VPN 後又為 `read-run.ps1` 重開一次。多行內容不要直接塞進 bash 字串；用 Python `subprocess.run([...])` 以參數陣列呼叫 PowerShell，避免反引號/換行被 shell 誤解。

## 第一次使用：preflight（每次執行前由 Claude 檢查）

**在執行 `run.ps1` 之前，Claude 必須做下列檢查；缺東西就向使用者收齊再繼續：**

需檢查的 key（在 `<專案根>/.env`；專案根是包含 `vpn-connect.ps1` 與 `*VPN*.bat` 的資料夾）：
如果 skill 被安裝在專案外（例如 `%USERPROFILE%\\.codex\\skills\\work-log`），先讀 skill 目錄的 `.record-work-root`，或環境變數 `RECORD_WORK_ROOT`，取得專案根。

此 Hermes/WSL 環境已安裝在：
- 專案根：`C:\Users\L164\record_work`（WSL: `/mnt/c/Users/L164/record_work`）
- skill 目錄：`C:\Users\L164\.hermes\skills\productivity\work-log`（WSL symlink: `/home/arnold/.hermes/skills/productivity/work-log`）

```
account=
password=
VPN_account=
VPN_password=
VPN_gateway=
VPN_cert=
internal_ip=
department=
```

`customer_name` **不要問**使用者，但**寫 `.env` 時自動補上預設值**「樂衍工作日誌」，
這樣 .env 內容對未來修改比較直覺。程式端也有 fallback，所以即使被刪掉也能跑。

### 問法（重要 — 不要用 AskUserQuestion）

AskUserQuestion 不適合自由文字（特別是密碼），別用。

**用一則 plain text 訊息一次問完所有缺的 key**，請使用者用 `key=value` 一次回覆，範例：

> 第一次使用需要設定。請依下列格式一次回覆（不用加引號）：
>
> ```
> account=你的員編，例如 L181
> password=你的內網密碼
> VPN_account=通常同 account
> VPN_password=通常同 password
> VPN_gateway=VPN 伺服器位址
> VPN_cert=VPN 憑證 pin，例如 pin-sha256:...
> internal_ip=內網系統 IP，例如 192.168.x.x
> department=3   # 3=內勤 4=培訓 5=業務 6=客服 7=工程 8=行銷 9=開業顧問
> ```

收到回覆後直接 parse 寫進 `.env`（保留既有不相關的 key，只新增/覆寫上述 key；值不要加引號；密碼含特殊字元直接寫，不要 escape）。

如果使用者只缺其中幾個（其他 key 已有值），就只問缺的那幾個，不要重問已存在的。

### 相依套件

確認 `<skill 目錄>/node_modules` 與 Playwright Chromium 已裝。沒裝就跑：

```powershell
cd "<skill 目錄>"
npm install
npx playwright install chromium
```

（一次性。）

### 順序

設定齊全 + 套件裝好 → 簡短跟使用者說「設定完成，開始執行」 → 進入下一節執行流程。

## 執行流程

執行 PowerShell 包裝腳本（與此 SKILL.md 同目錄）。在 Hermes/WSL 中，優先使用 Windows skill 目錄執行：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\L164\.hermes\skills\productivity\work-log\run.ps1" -Content "$ARGUMENTS" -Verify
```

PowerShell 原生範例：

```powershell
& "$PSScriptRoot\run.ps1" -Content "$ARGUMENTS"
```

腳本會：

1. 偵測內網 192.168.40.61:80 是否已通；不通的話會跑專案根目錄下的 `*VPN*.bat` 連 VPN
2. 執行 `node "$PSScriptRoot\work-log.js" --content "<使用者內容>"`
3. 腳本會先登入並搜尋客戶「樂衍工作日誌」，再進入「樂衍客服」備註頁用登入姓名/帳號尋找當日屬於本人的日誌；如果同日已有其他同仁資料但沒有本人的資料，必須回到報到頁點「快速報到」，再重新進入備註頁寫入本人的新日誌。不要把第一筆同日資料或其他同仁資料當成本人的報到。注意：快速報到後備註頁有時不顯示登入姓名/帳號，但 `cnote_*` DOM id 會沿用主畫面的 `main_tr_<掛號ID>`；此時可用主畫面 `data-doctor` 比對到的本人掛號 ID 作為日誌 ID。
4. 如果加上 `-Verify`（Hermes 預設使用），在關閉 VPN 前直接執行 `node "$PSScriptRoot\read-work-log.js"` 讀回今日內部/外部備註與部門，避免寫入後另跑 `read-run.ps1` 導致 VPN 重開
5. 如果 VPN 是這次腳本啟動的，跑完寫入與可選驗證後自動 kill `openconnect.exe` 把 VPN 關掉（會跳一次 UAC）；如果 VPN 在腳本啟動前就已連著，**不會**動它，避免影響使用者其他作業

如果使用者要分別輸入「對內」「對外」兩段不同內容，可以加 `-Content2`：

```powershell
& "$PSScriptRoot\run.ps1" -Content "對內描述" -Content2 "對外描述"
```

如果沒給 `Content2`，腳本會把 `Content` 同時填到兩個欄位。

### WSL/Hermes 多行內容注意事項

不要在 `terminal(command=...)` 的 bash 字串中用 PowerShell backtick newline（例如 `` `n ``）組多行工作日誌；bash 會把反引號當命令替換，可能造成內容被截斷或先錯誤覆寫。若要寫入多行內容，優先用 Python `subprocess.run([...])` 傳 argv，避免 shell quoting 問題：

```python
import subprocess
content = "1. 第一項\n2. 第二項\n3. 第三項"
subprocess.run([
    "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", r"C:\Users\L164\.hermes\skills\productivity\work-log\run.ps1",
    "-Content", content,
    "-Verify",
], check=True)
```

寫入時使用 `run.ps1 -Verify`，腳本會在同一次 VPN 連線中先寫入再讀回驗證；不要再另外執行 `read-run.ps1` 做寫入後驗證，除非 `-Verify` 失敗或使用者明確要求重新查看。因為寫入是覆蓋整個欄位，不是 append，回報時仍要核對 `-Verify` 輸出的 `internalNote` / `externalNote`。

## 設定來源

帳號密碼、預設部門、客戶名稱都從**專案根目錄**的 `.env` 讀取。
程式會先讀環境變數 `RECORD_WORK_ROOT`，再讀 skill 目錄內的 `.record-work-root`，最後才從 skill 目錄往上尋找同時包含 `.env` 或 `.env.example`、`vpn-connect.ps1`、`*VPN*.bat` 的資料夾；不要把 `.env` 寫在 skill 目錄、`.codex` 目錄或使用者家目錄。

- `account` / `password` — 內網登入帳密
- `VPN_account` / `VPN_password` — VPN 帳密（被 `vpn-connect.ps1` 讀取）
- `department` — 服務類型 (3=內勤, 4=培訓, 5=業務, 6=客服, 7=工程, 8=行銷, 9=開業顧問)
- `customer_name` — 要搜尋的客戶名稱（預設「樂衍工作日誌」）

## 回報結果

執行完後把腳本輸出原樣回給使用者，重點是：

- 登入時抓到的「使用者名稱」
- 是否需要快速報到（今天還沒報到），或者已經有報到資料直接寫日誌
- 最後是否儲存成功

如果中間任一步驟失敗（找不到元素、登入失敗、VPN 沒通），把腳本的錯誤訊息原封不動回報給使用者，**不要**自己重試或亂填。
