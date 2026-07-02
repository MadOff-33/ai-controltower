const fs = require('fs');
const path = require('path');

async function main() {
  const projectPath = process.argv[2];
  if (!projectPath) {
    console.log(JSON.stringify({ status: 'not_verified', summary: 'Chemin de projet manquant.', checks: [] }));
    return;
  }

  const checks = [];
  let htmlPath = path.join(projectPath, 'index.html');
  if (!fs.existsSync(htmlPath)) {
    const found = fs.readdirSync(projectPath).find((f) => f.toLowerCase().endsWith('.html'));
    if (found) {
      htmlPath = path.join(projectPath, found);
    } else {
      console.log(JSON.stringify({ status: 'not_verified', summary: 'Aucun fichier HTML trouve a la racine du projet.', checks: [] }));
      return;
    }
  }

  const html = fs.readFileSync(htmlPath, 'utf8');
  const htmlIds = new Set([...html.matchAll(/\bid=["']([^"']+)["']/g)].map((m) => m[1]));
  const htmlClasses = new Set();
  for (const m of html.matchAll(/\bclass=["']([^"']+)["']/g)) {
    for (const cls of m[1].split(/\s+/)) {
      if (cls) htmlClasses.add(cls);
    }
  }

  const scriptFiles = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/g)].map((m) => m[1]);
  const missingRefs = [];
  for (const rel of scriptFiles) {
    const jsPath = path.join(projectPath, rel);
    if (!fs.existsSync(jsPath)) continue;
    const js = fs.readFileSync(jsPath, 'utf8');
    for (const m of js.matchAll(/getElementById\(\s*['"]([^'"]+)['"]\s*\)/g)) {
      if (!htmlIds.has(m[1])) missingRefs.push({ kind: 'id', name: m[1], file: rel });
    }
    for (const m of js.matchAll(/querySelector\(\s*['"]#([A-Za-z0-9_-]+)['"]\s*\)/g)) {
      if (!htmlIds.has(m[1])) missingRefs.push({ kind: 'id', name: m[1], file: rel });
    }
    for (const m of js.matchAll(/querySelector\(\s*['"]\.([A-Za-z0-9_-]+)['"]\s*\)/g)) {
      if (!htmlClasses.has(m[1])) missingRefs.push({ kind: 'class', name: m[1], file: rel });
    }
  }

  checks.push({
    name: 'dom_reference_check',
    status: missingRefs.length === 0 ? 'ok' : 'failed',
    detail: missingRefs.map((r) => `${r.file}: reference a "${r.name}" (${r.kind}) introuvable dans le HTML`).join('; ')
  });

  if (missingRefs.length > 0) {
    const first = missingRefs[0];
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le code cherche un element "${first.name}" qui n'existe pas dans la page (${first.file}).`,
      checks
    }));
    return;
  }

  let playwright;
  try {
    playwright = require('playwright');
  } catch (err) {
    checks.push({ name: 'browser_console', status: 'not_verified', detail: 'Playwright non installe.' });
    console.log(JSON.stringify({
      status: 'ok',
      summary: "Recoupement HTML/JS reussi. Le chargement dans un navigateur n'a pas pu etre verifie (Playwright non installe).",
      checks
    }));
    return;
  }

  const consoleErrors = [];
  const browser = await playwright.chromium.launch();
  try {
    const page = await browser.newPage();
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => {
      consoleErrors.push(err.message);
    });
    await page.goto(require('url').pathToFileURL(htmlPath).href);
    await page.waitForTimeout(3000);
  } finally {
    await browser.close();
  }

  checks.push({
    name: 'browser_console',
    status: consoleErrors.length === 0 ? 'ok' : 'failed',
    detail: consoleErrors.join(' | ')
  });

  if (consoleErrors.length > 0) {
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le site plante des l'ouverture : ${consoleErrors[0]}`,
      checks
    }));
    return;
  }

  console.log(JSON.stringify({ status: 'ok', summary: 'La page se charge correctement, sans erreur.', checks }));
}

main().catch((err) => {
  console.log(JSON.stringify({ status: 'not_verified', summary: 'Erreur inattendue pendant la verification: ' + err.message, checks: [] }));
});
