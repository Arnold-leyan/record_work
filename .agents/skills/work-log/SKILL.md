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

呼叫時把日誌內容當參數傳入。範例：

```
/work-log 今天處理了 A 客戶的工單、修了 B 系統的 bug、開了一個會
```

如果使用者透過 Telegram 對 Claude Code 說「幫我記今天的工作日誌」之類的話，且後面附帶了實際內容，就直接呼叫這個 skill 並把內容當作 `$ARGUMENTS` 傳入。

## 第一次使用：preflight（每次執行前由 Claude 檢查）

**在執行 `run.ps1` 之前，Claude 必須做下列檢查；缺東西就向使用者收齊再繼續：**

需檢查的 5 個 key（在 `<專案根>/.env`，路徑相對 skill：`../../../.env`）：

```
account=
password=
VPN_account=
VPN_password=
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

執行 PowerShell 包裝腳本（與此 SKILL.md 同目錄）：

```powershell
& "$PSScriptRoot\run.ps1" -Content "$ARGUMENTS"
```

腳本會：

1. 偵測內網 192.168.40.61:80 是否已通；不通的話會跑專案根目錄下的 `*VPN*.bat` 連 VPN
2. 執行 `node "$PSScriptRoot\work-log.js" --content "<使用者內容>"`
3. 如果 VPN 是這次腳本啟動的，跑完後自動 kill `openconnect.exe` 把 VPN 關掉（會跳一次 UAC）；如果 VPN 在腳本啟動前就已連著，**不會**動它，避免影響使用者其他作業

如果使用者要分別輸入「對內」「對外」兩段不同內容，可以加 `-Content2`：

```powershell
& "$PSScriptRoot\run.ps1" -Content "對內描述" -Content2 "對外描述"
```

如果沒給 `Content2`，腳本會把 `Content` 同時填到兩個欄位。

## 設定來源

帳號密碼、預設部門、客戶名稱都從**專案根目錄**的 `.env` 讀取
（路徑相對於 skill：`../../../.env`）：

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
