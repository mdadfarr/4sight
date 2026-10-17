import { chromium } from 'playwright';
const times = process.argv.slice(2).map(Number);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 2 });
const errs = [];
p.on('pageerror', e => errs.push(String(e)));
p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
for (const t of times) {
  await p.goto(`file://${process.cwd()}/index.html?t=${t}${process.env.DEMO ? '&demo' : ''}`);
  await p.waitForFunction(() => window.__ready === true, { timeout: 5000 }).catch(() => {});
  await p.screenshot({ path: `shot-t${t}.png` });
}
await b.close();
console.log(errs.length ? 'ERRORS:\n' + errs.join('\n') : 'ok, no console errors');
