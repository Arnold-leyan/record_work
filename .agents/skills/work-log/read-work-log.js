// 樂衍工作日誌 查詢今日已填內容
// 用法: node read-work-log.js

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
  if (process.env.RECORD_WORK_ROOT && isProjectRoot(process.env.RECORD_WORK_ROOT)) return path.resolve(process.env.RECORD_WORK_ROOT);
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
      console.error(`錯誤：無法從 ${startDir} 找到 record_work 專案根目錄。`);
      process.exit(2);
    }
    dir = parent;
  }
}

const PROJECT_ROOT = findProjectRoot(__dirname);
const ENV_PATH = path.join(PROJECT_ROOT, '.env');
dotenv.config({ path: ENV_PATH });

const internalIp = process.env.internal_ip;
if (!internalIp) { console.error('錯誤：.env 缺少 internal_ip'); process.exit(2); }
const BASE_URL = `http://${internalIp}/`;
const USER_DATA_DIR = path.join(__dirname, '.browser-profile');

function log(msg) { console.log(`[${new Date().toLocaleTimeString('zh-TW', { hour12: false })}] ${msg}`); }

function todayRocDate() {
  const now = new Date();
  return `${now.getFullYear() - 1911}/${String(now.getMonth() + 1).padStart(2, '0')}/${String(now.getDate()).padStart(2, '0')}`;
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
      if ((staffName && (staff.includes(staffName) || doctor.includes(staffName))) || (account && doctor.includes(account))) return id;
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
      if ((staffName && (doctor.includes(staffName) || text.includes(staffName))) || (account && (doctor.includes(account) || text.includes(account)))) return id;
    }
    return null;
  }, { staffName, account });
}

async function textOrValue(locator) {
  if (!(await locator.count())) return '';
  const el = locator.first();
  if (!(await el.isVisible().catch(() => false))) return '';
  const tag = await el.evaluate(e => e.tagName.toLowerCase()).catch(() => '');
  if (tag === 'textarea' || tag === 'input' || tag === 'select') return await el.inputValue().catch(() => '');
  return (await el.innerText().catch(() => '')).trim();
}

async function main() {
  const account = process.env.account;
  const password = process.env.password;
  const customerName = process.env.customer_name || '樂衍工作日誌';
  if (!account || !password) { console.error(`錯誤：${ENV_PATH} 缺少 account 或 password`); process.exit(2); }
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

    const logoutText = (await logoutBox.innerText()).trim();
    staffName = logoutText.split(/\s+/)[0];
    log(`登入身分：${staffName}`);

    log('點選查詢按鈕');
    await page.locator('button.patient-profile__search-btn').click();
    log(`搜尋客戶「${customerName}」`);
    const nameInput = page.locator('#schbox_name');
    await nameInput.waitFor({ state: 'visible' });
    await nameInput.fill(customerName);
    await page.locator('button.btn_green:has-text("查詢")').first().click();

    const firstRow = page.locator('tr.customer-data').first();
    await firstRow.waitFor({ state: 'visible' });
    await firstRow.click();
    await page.locator('button.btn-selected-customer').click();

    const tableBody = page.locator('tbody#main_tb_register');
    await tableBody.waitFor({ state: 'visible' });
    await page.waitForTimeout(1500);
    const anyRegisteredRow = tableBody.locator('tr[id^="main_tr_"]').first();
    const alreadyRegistered = await anyRegisteredRow.isVisible().catch(() => false);
    if (!alreadyRegistered) {
      log('今天尚未報到，找不到今日工作日誌資料');
      console.log(JSON.stringify({ ok: true, staffName, customer: customerName, alreadyRegistered: false, message: '今天尚未報到，沒有工作日誌資料' }, null, 2));
      return;
    }

    log('今天已有部分報到資料，進入備註頁尋找本人的日誌');
    const registerId = await findOwnRegisterId(page, staffName, account);

    log('點擊「樂衍客服」進入備註頁');
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
    log(`進入備註頁 URL=${target.url()}`);

    let noteId = await findOwnNoteId(target, staffName, account);
    if (!noteId && registerId) {
      log(`備註頁姓名比對失敗，改用主畫面本人掛號 ID=${registerId} 作為日誌 ID`);
      noteId = registerId;
    }
    if (!noteId) {
      log(`備註頁找不到 ${staffName}/${account} 的今日日誌`);
      console.log(JSON.stringify({ ok: true, staffName, customer: customerName, alreadyRegistered: false, message: '今天尚未找到本人的工作日誌資料' }, null, 2));
      if (target !== page) await target.close();
      return;
    }
    log(`本人的日誌 ID=${noteId}`);
    const editBtn = target.locator(`#cnote_edit_${noteId}`);
    await editBtn.waitFor({ state: 'visible' });

    // 若內容在顯示模式讀不到，點修改讓 textarea 顯示；不點儲存。
    let par1 = target.locator(`#cnote_memo_par_one_${noteId}`);
    let par2 = target.locator(`#cnote_memo_par_two_${noteId}`);
    let jobType = target.locator(`#job-type-${noteId}`);
    if (!(await par1.isVisible().catch(() => false))) {
      log('點擊「修改」以讀取欄位內容（不儲存）');
      await editBtn.click();
      await par1.waitFor({ state: 'visible', timeout: 15000 });
    }

    const contentInternal = await textOrValue(par1);
    const contentExternal = await textOrValue(par2);
    let department = '';
    if (await jobType.isVisible().catch(() => false)) {
      department = await jobType.evaluate(sel => {
        const opt = sel.options[sel.selectedIndex];
        return opt ? `${opt.value}:${opt.textContent.trim()}` : sel.value;
      }).catch(async () => await textOrValue(jobType));
    }

    console.log(JSON.stringify({
      ok: true,
      staffName,
      customer: customerName,
      alreadyRegistered: true,
      regId: noteId,
      noteId,
      department,
      internalNote: contentInternal,
      externalNote: contentExternal,
    }, null, 2));

    if (target !== page) await target.close();
  } catch (err) {
    log(`錯誤：${err.message}`);
    try {
      const shotPath = path.join(__dirname, `read-error-${Date.now()}.png`);
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
