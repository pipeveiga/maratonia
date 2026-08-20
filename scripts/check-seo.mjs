#!/usr/bin/env node
// Revisa el sitio ya generado y avisa si algo se rompió: títulos fuera de
// rango, canonical o hreflang mal, JSON-LD inválido, links internos rotos,
// imágenes sin alt, archivos referenciados que no existen.
//
//   npm run check:seo

import { readdir, readFile, stat } from "node:fs/promises";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { LOCALES, PAGES, SITE, DEFAULT_LOCALE } from "./seo.config.mjs";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const WEB = join(ROOT, "web");

// Google corta el título alrededor de los 60-65 caracteres y la
// descripción alrededor de los 160. Fuera de esos rangos no se penaliza,
// pero el resultado se ve cortado o Google lo reescribe.
const TITLE_RANGE = [25, 70];
const DESCRIPTION_RANGE = [70, 175];

const problems = [];
const warnings = [];

function fail(file, message) { problems.push(`${file}: ${message}`); }
function warn(file, message) { warnings.push(`${file}: ${message}`); }

async function htmlFiles(dir) {
  const found = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) found.push(...await htmlFiles(full));
    else if (entry.name.endsWith(".html")) found.push(full);
  }
  return found;
}

async function exists(path) {
  try { await stat(path); return true; } catch { return false; }
}

function all(html, re) {
  return [...html.matchAll(re)].map((m) => m[1]);
}

function pageUrl(page, locale) {
  return SITE + (locale === DEFAULT_LOCALE ? page.path : `/${locale}${page.path}`);
}

/** Todas las URLs que el sitio debería tener, y su archivo. */
function expectedPages() {
  const map = new Map();
  for (const page of PAGES) {
    for (const locale of LOCALES) {
      const path = locale === DEFAULT_LOCALE ? page.path : `/${locale}${page.path}`;
      map.set(join(WEB, path === "/" ? "index.html" : join(path, "index.html")), { page, locale });
    }
  }
  return map;
}

async function checkPage(file, html, meta) {
  const name = relative(ROOT, file);
  const isError = /name="robots"[^>]*noindex/.test(html);

  const title = /<title>([\s\S]*?)<\/title>/.exec(html)?.[1];
  if (!title) fail(name, "no tiene <title>");
  else if (title.length < TITLE_RANGE[0] || title.length > TITLE_RANGE[1]) {
    warn(name, `título de ${title.length} caracteres, fuera de ${TITLE_RANGE.join("-")}`);
  }

  const description = /<meta name="description" content="([^"]*)"/.exec(html)?.[1];
  if (!description && !isError) fail(name, "no tiene meta description");
  else if (description && (description.length < DESCRIPTION_RANGE[0] || description.length > DESCRIPTION_RANGE[1])) {
    warn(name, `descripción de ${description.length} caracteres, fuera de ${DESCRIPTION_RANGE.join("-")}`);
  }

  const h1 = all(html, /<h1\b[^>]*>([\s\S]*?)<\/h1>/g);
  if (h1.length !== 1) fail(name, `tiene ${h1.length} <h1> (debe haber exactamente uno)`);

  if (!/<html[^>]+lang="/.test(html)) fail(name, "el <html> no declara lang");

  if (isError) return; // La 404 no lleva canonical, hreflang ni datos estructurados.

  const canonical = /<link rel="canonical" href="([^"]*)"/.exec(html)?.[1];
  if (!canonical) fail(name, "no tiene canonical");
  else if (meta && canonical !== pageUrl(meta.page, meta.locale)) {
    fail(name, `canonical apunta a ${canonical}`);
  }

  // hreflang: cada página tiene que listarse a sí misma y a sus hermanas.
  if (meta) {
    const alternates = [...html.matchAll(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)"/g)];
    const byLang = Object.fromEntries(alternates.map((m) => [m[1], m[2]]));
    for (const locale of [...LOCALES, "x-default"]) {
      const expected = pageUrl(meta.page, locale === "x-default" ? DEFAULT_LOCALE : locale);
      if (byLang[locale] !== expected) {
        fail(name, `falta o está mal el hreflang="${locale}" (esperaba ${expected})`);
      }
    }
    if (byLang[meta.locale] !== canonical) {
      fail(name, "el hreflang del propio idioma no coincide con el canonical");
    }
  }

  for (const property of ["og:title", "og:description", "og:url", "og:image", "og:type", "og:site_name"]) {
    if (!new RegExp(`<meta property="${property}"`).test(html)) fail(name, `falta ${property}`);
  }
  if (!/<meta name="twitter:card"/.test(html)) fail(name, "falta twitter:card");

  const jsonLd = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/.exec(html)?.[1];
  if (!jsonLd) fail(name, "no tiene JSON-LD");
  else {
    try {
      const data = JSON.parse(jsonLd);
      const types = (data["@graph"] || []).map((node) => node["@type"]).flat();
      for (const required of ["Organization", "WebSite", "WebPage"]) {
        if (!types.includes(required)) fail(name, `el JSON-LD no incluye ${required}`);
      }
      // Las preguntas del FAQPage tienen que estar visibles en la página.
      const faq = (data["@graph"] || []).find((node) => node["@type"] === "FAQPage");
      if (faq) {
        const visible = all(html, /<summary\b[^>]*>([\s\S]*?)<\/summary>/g).length;
        if (faq.mainEntity.length !== visible) {
          fail(name, `el FAQPage declara ${faq.mainEntity.length} preguntas y la página muestra ${visible}`);
        }
      }
    } catch (error) {
      fail(name, `JSON-LD inválido: ${error.message}`);
    }
  }

  // Imágenes sin alt.
  for (const tag of html.match(/<img\b[^>]*>/g) || []) {
    if (!/\salt=/.test(tag)) fail(name, `<img> sin alt: ${tag.slice(0, 70)}`);
  }

  // Nada de restos del generador ni del viejo cambio de idioma por JS.
  for (const leftover of ["<!--SEO-->", "<!--LANG_TOGGLE-->", "language.js", "data-en=", "data-i18n-attribute"]) {
    if (html.includes(leftover)) fail(name, `quedó "${leftover}" en la salida`);
  }
}

async function checkLinks(file, html) {
  const name = relative(ROOT, file);
  const hrefs = [
    ...all(html, /href="(\/[^"#?]*)"/g),
    ...all(html, /src="(\/[^"#?]*)"/g),
  ];
  for (const href of new Set(hrefs)) {
    const target = href.endsWith("/") ? join(WEB, href, "index.html") : join(WEB, href);
    if (!await exists(target)) fail(name, `link interno roto: ${href}`);
  }
}

async function main() {
  const expected = expectedPages();
  const files = await htmlFiles(WEB);

  for (const [file] of expected) {
    if (!await exists(file)) fail(relative(ROOT, file), "falta esta página (¿corriste npm run build:web?)");
  }

  for (const file of files) {
    const html = await readFile(file, "utf8");
    await checkPage(file, html, expected.get(file));
    await checkLinks(file, html);
  }

  for (const required of ["robots.txt", "sitemap.xml", "site.webmanifest", "404.html"]) {
    if (!await exists(join(WEB, required))) fail(required, "falta este archivo");
  }

  const sitemap = await readFile(join(WEB, "sitemap.xml"), "utf8");
  for (const page of PAGES) {
    for (const locale of LOCALES) {
      if (!sitemap.includes(`<loc>${pageUrl(page, locale)}</loc>`)) {
        fail("sitemap.xml", `no incluye ${pageUrl(page, locale)}`);
      }
    }
  }

  for (const message of warnings) console.log(`  aviso   ${message}`);
  for (const message of problems) console.log(`  ERROR   ${message}`);

  console.log(
    `\n${files.length} páginas revisadas · ${problems.length} errores · ${warnings.length} avisos`,
  );
  process.exit(problems.length > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
