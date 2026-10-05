// Captures the README screenshots from a running environment and renders
// the architecture diagram, using an installed Chrome/Edge (no browser
// download):
//
//   npm i --no-save playwright-core
//   scripts/screenshots/capture.sh          (sets up port-forwards + credentials)
//
// Credentials come from environment variables, never from files:
//   GRAFANA_USER / GRAFANA_PASSWORD, ARGOCD_PASSWORD
import { chromium } from "playwright-core";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
import fs from "node:fs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const out = path.join(root, "docs", "screenshots");
fs.mkdirSync(out, { recursive: true });

const browserPath = process.env.BROWSER_PATH ||
  ["C:/Program Files/Google/Chrome/Application/chrome.exe",
   "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
   "/usr/bin/google-chrome", "/usr/bin/chromium"].find((p) => fs.existsSync(p));

const only = process.argv.slice(2);
const want = (name) => only.length === 0 || only.includes(name);

const browser = await chromium.launch({ executablePath: browserPath, headless: true });
const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1, ignoreHTTPSErrors: true });
const page = await ctx.newPage();

async function shot(file, opts = {}) {
  const target = path.join(file.includes("/") ? root : out, file);
  await page.screenshot({ path: target, ...opts });
  console.log("wrote", path.relative(root, target));
}

if (want("diagram")) {
  await page.setViewportSize({ width: 1600, height: 820 });
  await page.goto(pathToFileURL(path.join(root, "docs/architecture/cloudcart-architecture.html")).href);
  await shot("docs/architecture/cloudcart-architecture.png", { clip: { x: 0, y: 0, width: 1600, height: 820 } });
  await page.setViewportSize({ width: 1600, height: 1000 });
}

if (want("grafana")) {
  await page.goto("http://localhost:13000/login");
  await page.fill('input[name="user"]', process.env.GRAFANA_USER);
  await page.fill('input[name="password"]', process.env.GRAFANA_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL((u) => !u.pathname.startsWith("/login"));
  await page.setViewportSize({ width: 1600, height: 2300 });
  await page.goto("http://localhost:13000/d/cloudcart-overview?orgId=1&from=now-30m&to=now&refresh=&kiosk");
  await page.waitForTimeout(12000); // let every panel query and render
  await shot("grafana-dashboard.png");
  await page.setViewportSize({ width: 1600, height: 1000 });
}

if (want("argocd")) {
  await page.goto("http://localhost:18080/login");
  await page.fill('input[name="username"]', "admin");
  await page.fill('input[name="password"]', process.env.ARGOCD_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL((u) => u.pathname.startsWith("/applications"));
  await page.waitForTimeout(4000);
  await shot("argocd-applications.png");
  await page.goto("http://localhost:18080/applications/argocd/cloudcart-local?view=tree&resource=");
  await page.waitForTimeout(6000);
  await shot("argocd-cloudcart-tree.png");
}

if (want("rollouts")) {
  await page.goto("http://localhost:3100/rollouts/rollout/cloudcart/order-service");
  await page.waitForTimeout(5000);
  await shot("argo-rollouts-order-service.png");
}

if (want("prometheus")) {
  await page.goto("http://localhost:19090/alerts?search=cloudcart");
  await page.waitForTimeout(4000);
  await shot("prometheus-alert-rules.png");
  await page.goto("http://localhost:19090/targets?search=cloudcart");
  await page.waitForTimeout(4000);
  await shot("prometheus-targets.png");
}

if (want("loki")) {
  const expr = encodeURIComponent(JSON.stringify({
    datasource: "loki", queries: [{ refId: "A", expr: '{namespace="cloudcart", level=~"WARN|ERROR"}' }],
    range: { from: "now-1h", to: "now" } }));
  await page.goto("http://localhost:13000/login");
  if (page.url().includes("/login")) {
    await page.fill('input[name="user"]', process.env.GRAFANA_USER);
    await page.fill('input[name="password"]', process.env.GRAFANA_PASSWORD);
    await page.click('button[type="submit"]');
    await page.waitForURL((u) => !u.pathname.startsWith("/login"));
  }
  await page.goto(`http://localhost:13000/explore?orgId=1&left=${expr}`);
  await page.waitForTimeout(8000);
  await shot("grafana-loki-logs.png");
}

await browser.close();
