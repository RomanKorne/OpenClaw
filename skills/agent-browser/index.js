// Minimal example: open a page and print title (sandboxed, no secrets)
const { chromium } = require('playwright');
(async ()=>{
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('https://example.com');
  const title = await page.title();
  console.log('Example.com title:', title);
  await browser.close();
})();
