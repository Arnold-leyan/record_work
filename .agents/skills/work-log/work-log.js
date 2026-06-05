// 樂衍工作日誌 自動填寫腳本
// 用法: node work-log.js --content "今日工作內容" [--content2 "對外內容"]

import { chromium } from 'playwright';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function findProjectRoot(startDir) {
  function isProjectRoot(dir) {
    if (!dir || !fs.existsSync(dir)) return false;
    const hasEnv = fs.existsSync(path.join(dir, '.env')) || fs.existsSync(path.join(dir, '.env.example'));
    const hasVpnScript = fs.existsSync(path.join(dir, 'vpn-connect.ps1'));
    const hasVpnBat = fs.readdirSync(dir).some((name) => /VPN.*\.bat$/i.test(name));
    return hasEnv && hasVpnScript && hasVpnBat;
  }

  if (process.env.RECORD_WORK_ROOT && isProjectRoot(process.env.RECORD_WORK_ROOT)) {
    return path.resolve(process.env.RECORD_WORK_ROOT);
  }

  const rootFile = path.join(startDir, '.record-work-root');
  if (fs.existsSync(rootFile)) {
    const configuredRoot = fs.readFileSync(rootFile, 'utf8').split(/\r?\n/)[0].trim();
    if (isProjectRoot(configuredRoot)) return path.resolve(configuredRoot);
    console.error(`錯誤：${rootFile} 指向的 record_work 專案根目錄無效：${configuredRoot}`);
    process.exit(2);
  }

  let dir = path.resolve(startDir);
  while (true) {
    if (isProjectRoot(dir)) return dir;

    const parent = path.dirname(dir);
    if (parent === dir) {
      console.error(`錯誤：無法從 ${startDir} 找到 record_work 專案根目錄。請設定 RECORD_WORK_ROOT，或在 skill 目錄建立 .record-work-root。`);
      process.exit(2);
    }
    dir = parent;
  }
}

// .env 位於 record_work 專案根目錄；skill 可放在 .agents/skills、.claude/skills 或 skills 底下。
const PROJECT_ROOT = findProjectRoot(__dirname);
const ENV_PATH = path.join(PROJECT_ROOT, '.env');
dotenv.config({ path: ENV_PATH });

// 防止並行：同時間只允許一個 work-log 跑，避免重複報到
const LOCK_PATH = path.join(__dirname, '.run.lock');
function acquireLock() {
  if (fs.existsSync(LOCK_PATH)) {
    const age = Date.now() - fs.statSync(LOCK_PATH).mtimeMs;
    if (age < 5 * 60 * 1000) {
      console.error(`錯誤：另一個 work-log 正在執行中（lock 檔 ${LOCK_PATH} 存在，年齡 ${Math.round(age/1000)}s）。請等它跑完，或刪除 lock 檔。`);
      process.exit(4);
    }
    fs.unlinkSync(LOCK_PATH);
  }
  fs.writeFileSync(LOCK_PATH, String(process.pid));
}
function releaseLock() {
  try { fs.unlinkSync(LOCK_PATH); } catch {}
}
process.on('exit', releaseLock);
process.on('SIGINT', () => { releaseLock(); process.exit(130); });
process.on('SIGTERM', () => { releaseLock(); process.exit(143); });

const internalIp = process.env.internal_ip;
if (!internalIp) {
  console.error('錯誤：.env 缺少 internal_ip');
  process.exit(2);
}
const BASE_URL = `http://${internalIp}/`;
const USER_DATA_DIR = path.join(__dirname, '.browser-profile');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { content: '', content2: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--content') out.content = args[++i] ?? '';
    else if (args[i] === '--content2') out.content2 = args[++i] ?? '';
  }
  return out;
}

function log(msg) {
  console.log(`[${new Date().toLocaleTimeString('zh-TW', { hour12: false })}] ${msg}`);
}

function todayRocDate() {
  const now = new Date();
  const y = now.getFullYear() - 1911;
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}/${m}/${d}`;
}

async function findOwnNoteId(target, staffName, account) {
  const today = todayRocDate();
  return await target.evaluate(({ today, staffName, account }) => {
    function text(el) { return (el.innerText || el.textContent || '').replace(/[ \t]+/g, ' ').trim(); }
    function selectedText(sel) {
      if (!sel) return '';
      const opt = sel.options[sel.selectedIndex];
      return opt ? `${sel.value}:${opt.textContent.trim()}` : (sel.value || '');
    }
    const rows = [...document.querySelectorAll('div.exp_list[id^="exp_list_"]')];
    for (const row of rows) {
      const id = row.id.replace('exp_list_', '');
      const rowText = text(row);
      if (!rowText.includes(`掛號日期： ${today}`) && !rowText.includes(`掛號日期：\n ${today}`)) continue;
      const staff = selectedText(document.querySelector(`#staff_tag_${id}`));
      const doctorMatch = rowText.match(/主治醫師：\s*([^\n]+)/);
      const doctor = doctorMatch ? doctorMatch[1] : '';
      const editorExists = !!document.querySelector(`#cnote_edit_${id}, #cnote_save_${id}, #cnote_memo_par_one_${id}`);
      if ((staffName && (staff.includes(staffName) || doctor.includes(staffName))) || (account && doctor.includes(account))) {
        return id;
      }
      // 有些快速報到產生的「樂衍客服」列，備註頁的 staff_tag/主治醫師文字不完整，
      // 但 cnote_* DOM id 會沿用主畫面的掛號 id；若同頁只有這筆可編輯的今日日誌，先回傳它。
      if (editorExists && rows.length === 1) return id;
    }
    return null;
  }, { today, staffName, account });
}

async function findOwnRegisterId(page, staffName, account) {
  return await page.evaluate(({ staffName, account }) => {
    const rows = [...document.querySelectorAll('tbody#main_tb_register tr[id^="main_tr_"]')];
    for (const row of rows) {
      const id = row.id.replace('main_tr_', '');
      const text = (row.innerText || row.textContent || '').replace(/[ \t]+/g, ' ').trim();
      const doctor = row.getAttribute('data-doctor') || '';
      if ((staffName && (doctor.includes(staffName) || text.includes(staffName))) || (account && (doctor.includes(account) || text.includes(account)))) {
        return id;
      }
    }
    return null;
  }, { staffName, account });
}

async function openCusnotePage(ctx, page) {
  const [cusnotePage] = await Promise.all([
    ctx.waitForEvent('page', { timeout: 15000 }).catch(() => null),
    page.locator('span.bg_pink:has-text("樂衍客服")').first().click(),
  ]);
  let target = cusnotePage;
  if (!target) {
    await page.waitForURL(/leyan_cusnote/, { timeout: 15000 });
    target = page;
  } else {
    await target.waitForLoadState('domcontentloaded');
  }
  target.setDefaultTimeout(20000);
  await target.waitForTimeout(1500);
  return target;
}

async function main() {
  const { content, content2 } = parseArgs();
  if (!content || !content.trim()) {
    console.error('錯誤：必須提供 --content "工作內容"');
    process.exit(2);
  }

  const account = process.env.account;
  const password = process.env.password;
  const department = process.env.department;
  const customerName = process.env.customer_name || '樂衍工作日誌';

  if (!account || !password) {
    console.error(`錯誤：${ENV_PATH} 缺少 account 或 password`);
    process.exit(2);
  }
  if (!department) {
    console.error(`錯誤：${ENV_PATH} 缺少 department`);
    process.exit(2);
  }

  log(`使用帳號 ${account}，部門代碼 ${department}，目標客戶「${customerName}」`);

  if (!fs.existsSync(USER_DATA_DIR)) fs.mkdirSync(USER_DATA_DIR, { recursive: true });

  const ctx = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: false,
    viewport: { width: 1440, height: 900 },
  });
  const page = ctx.pages()[0] || (await ctx.newPage());
  page.setDefaultTimeout(20000);

  let staffName = null;
  try {
    log(`前往 ${BASE_URL}`);
    await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });

    // 步驟 3: 登入（若已是登入狀態 persistent profile 會跳過）
    const logoutBox = page.locator('div.logout_box').first();
    const needsLogin = !(await logoutBox.isVisible().catch(() => false));
    if (needsLogin) {
      log('未登入，輸入帳密');
      await page.locator('#sfno').waitFor({ state: 'visible' });
      await page.locator('#sfno').fill(account);
      await page.locator('#password').fill(password);
      await page.locator('#btn_login').click();
      await page.waitForLoadState('domcontentloaded');
      await logoutBox.waitFor({ state: 'visible', timeout: 15000 });
    } else {
      log('已是登入狀態，跳過登入');
    }

    // 步驟 4: 抓使用者名稱
    const logoutText = (await logoutBox.innerText()).trim();
    staffName = logoutText.split(/\s+/)[0];
    log(`登入身分：${staffName}`);

    // 步驟 5: 點選「查詢」
    log('點選查詢按鈕');
    await page.locator('button.patient-profile__search-btn').click();

    // 步驟 6: 輸入姓名並查詢
    log(`搜尋客戶「${customerName}」`);
    const nameInput = page.locator('#schbox_name');
    await nameInput.waitFor({ state: 'visible' });
    await nameInput.fill(customerName);
    await page.locator('button.btn_green:has-text("查詢")').first().click();

    // 步驟 7: 點第一列搜尋結果
    const firstRow = page.locator('tr.customer-data').first();
    await firstRow.waitFor({ state: 'visible' });
    const cussn = await firstRow.getAttribute('data-cussn');
    log(`找到客戶 data-cussn=${cussn}，點選第一列`);
    await firstRow.click();

    // 步驟 8: 點「確定」
    log('點選確定');
    await page.locator('button.btn-selected-customer').click();

    // 步驟 9: 確認當日是否已有「本登入者」的報到。
    // 注意：main_tb_register 可能列出同一天其他同仁的報到資料，不能只看第一列。
    const tableBody = page.locator('tbody#main_tb_register');
    await tableBody.waitFor({ state: 'visible' });
    await page.waitForTimeout(1500);
    const anyRegisteredRow = tableBody.locator('tr[id^="main_tr_"]').first();
    const hasAnyRegisteredRow = await anyRegisteredRow.isVisible().catch(() => false);

    let target = null;
    let noteId = null;
    let registerId = null;
    let alreadyRegistered = false;

    if (hasAnyRegisteredRow) {
      registerId = await findOwnRegisterId(page, staffName, account);
      log('今天已有部分報到資料，先進入備註頁確認是否有本人的日誌');
      target = await openCusnotePage(ctx, page);
      log(`進入備註頁 URL=${target.url()}`);
      noteId = await findOwnNoteId(target, staffName, account);
      if (!noteId && registerId) {
        log(`備註頁姓名比對失敗，改用主畫面本人掛號 ID=${registerId} 作為日誌 ID`);
        noteId = registerId;
      }
      alreadyRegistered = !!noteId;
      if (!noteId) {
        log('備註頁找不到本人的今日日誌，需回到報到頁快速報到');
        if (target !== page) await target.close();
        else throw new Error('已在備註頁但找不到本人的今日日誌，無法回到報到頁執行快速報到');
      }
    }

    if (!noteId) {
      log('今天尚未報到本人資料，點擊「快速報到」');
      page.once('dialog', d => d.accept().catch(() => {}));
      await page.locator('span.bg_pink:has-text("快速報到")').first().click();
      await tableBody.locator('tr[id^="main_tr_"]').first().waitFor({ state: 'visible', timeout: 15000 });
      await page.waitForTimeout(1500);
      registerId = await findOwnRegisterId(page, staffName, account);
      log('快速報到完成，重新進入備註頁尋找本人日誌');
      target = await openCusnotePage(ctx, page);
      log(`進入備註頁 URL=${target.url()}`);
      noteId = await findOwnNoteId(target, staffName, account);
      if (!noteId && registerId) {
        log(`備註頁姓名比對失敗，改用快速報到掛號 ID=${registerId} 作為日誌 ID`);
        noteId = registerId;
      }
      if (!noteId) throw new Error(`快速報到後仍找不到 ${staffName}/${account} 的今日日誌`);
    }

    log(`本人的日誌 ID=${noteId}`);
    const editBtn = target.locator(`#cnote_edit_${noteId}`);
    await editBtn.waitFor({ state: 'visible' });
    log('點擊「修改」');
    await editBtn.click();

    // 步驟 11.3-11.5: 填內容、選部門
    const par1 = target.locator(`#cnote_memo_par_one_${noteId}`);
    const par2 = target.locator(`#cnote_memo_par_two_${noteId}`);
    const jobType = target.locator(`#job-type-${noteId}`);

    await par1.waitFor({ state: 'visible' });
    await par1.fill(content);
    await par2.fill(content2 ?? content);
    await jobType.selectOption(department);
    log(`已填入內容，部門選 ${department}`);

    // 步驟 11.6: 儲存
    page.once('dialog', d => d.accept().catch(() => {}));
    target.once('dialog', d => d.accept().catch(() => {}));
    await target.locator(`#cnote_save_${noteId}`).click();
    log('已點擊儲存');

    // 等存檔完成（按鈕通常會變成「修改」表示完成）
    await target.locator(`#cnote_edit_${noteId}`).waitFor({ state: 'visible', timeout: 15000 });
    log('儲存成功');

    // 步驟 11.7: 關閉分頁
    if (target !== page) {
      await target.close();
      log('已關閉備註頁');
    }

    log('=== 完成 ===');
    console.log(JSON.stringify({
      ok: true,
      staffName,
      customer: customerName,
      alreadyRegistered,
      regId: noteId,
      noteId,
      department,
      contentLength: content.length,
      content2Length: (content2 ?? content).length,
    }, null, 2));
  } catch (err) {
    log(`錯誤：${err.message}`);
    try {
      const shotPath = path.join(__dirname, `error-${Date.now()}.png`);
      await page.screenshot({ path: shotPath, fullPage: true });
      log(`已存錯誤截圖：${shotPath}`);
    } catch {}
    console.log(JSON.stringify({ ok: false, error: err.message, staffName }, null, 2));
    process.exitCode = 1;
  } finally {
    await ctx.close();
  }
}

main();
