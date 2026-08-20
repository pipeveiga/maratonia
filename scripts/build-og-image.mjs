#!/usr/bin/env node
// Dibuja la imagen que se ve cuando alguien comparte el sitio (Open Graph
// y Twitter Card), una por idioma, en el 1200x630 que esperan las redes.
//
// Necesita Playwright, que no es dependencia del sitio. Las imágenes ya
// están commiteadas en web/assets/, así que esto solo hace falta si cambia
// el texto o el diseño de la tarjeta:
//
//   npx playwright@1.56.1 install chromium   # una sola vez
//   node scripts/build-og-image.mjs

import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));

const CARDS = {
  es: {
    line1: "Tu plan de running,",
    line2: "en el Apple Watch.",
    chips: ["Planes de 5K a maratón", "Ritmo objetivo por voz", "Apple Health"],
  },
  en: {
    line1: "Your running plan,",
    line2: "on your Apple Watch.",
    chips: ["5K to marathon plans", "Voice pace coaching", "Apple Health"],
  },
};

// Playwright puede estar instalado en el proyecto o de forma global.
async function cargarPlaywright() {
  try {
    return await import("playwright");
  } catch {
    const { createRequire } = await import("node:module");
    const { execSync } = await import("node:child_process");
    const globalRoot = execSync("npm root -g", { encoding: "utf8" }).trim();
    const require = createRequire(import.meta.url);
    const entry = require.resolve("playwright", { paths: [globalRoot] });
    const mod = await import(pathToFileURL(entry).href);
    return mod.chromium ? mod : mod.default;
  }
}

const { chromium } = await cargarPlaywright();

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(join(ROOT, "scripts", "og-card.html")).href);

for (const [locale, card] of Object.entries(CARDS)) {
  await page.evaluate((data) => {
    document.getElementById("line1").textContent = data.line1;
    document.getElementById("line2").textContent = data.line2;
    document.getElementById("chips").innerHTML = data.chips.map((c) => `<li>${c}</li>`).join("");
  }, card);
  await page.evaluate(() => document.fonts.ready);
  const out = join(ROOT, "web", "assets", `og-cover-${locale}.png`);
  await page.screenshot({ path: out });
  console.log(`  ${out}`);
}

await browser.close();
