#!/usr/bin/env node
// Genera el sitio público (web/) a partir de las plantillas bilingües
// de templates/.
//
// Por cada plantilla salen dos páginas reales, una por idioma:
//   templates/index.html         -> web/index.html        y web/en/index.html
//   templates/support/index.html -> web/support/index.html y web/en/support/index.html
//
// Tener una URL por idioma es lo que permite que Google indexe y posicione
// las dos versiones. Antes el idioma se cambiaba con JavaScript sobre la
// misma URL, así que el buscador solo podía quedarse con una (y, al
// renderizar con Accept-Language inglés, se quedaba con la equivocada).
//
// También se generan sitemap.xml y robots.txt.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  BRAND, DEFAULT_LOCALE, LANG_TOGGLE, LOCALES, OG_LOCALE,
  PAGES, SITE, SOCIAL_IMAGE,
} from "./seo.config.mjs";
import {
  applyEdits, escapeAttribute, findClosingTag, parseAttributes,
  removeAttribute, scanTags, setAttribute,
} from "./lib-html.mjs";
import { buildGraph, extractFaq } from "./structured-data.mjs";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const TEMPLATES = join(ROOT, "templates");
const OUTPUT = join(ROOT, "web");

const GENERATED_NOTICE = `<!--
  Archivo generado por scripts/build-web.mjs. No lo edites a mano:
  los cambios se hacen en templates/ y en scripts/seo.config.mjs,
  y después se corre "npm run build:web".
-->
`;

/** URL pública de una página en un idioma. */
function urlFor(page, locale) {
  const path = locale === DEFAULT_LOCALE ? page.path : `/${locale}${page.path}`;
  return SITE + path;
}

/** Ruta en disco donde se escribe una página. */
function fileFor(page, locale) {
  const path = locale === DEFAULT_LOCALE ? page.path : `/${locale}${page.path}`;
  return join(OUTPUT, path === "/" ? "index.html" : join(path, "index.html"));
}

function hasClass(attrs, className) {
  return (attrs.class || "").split(/\s+/).includes(className);
}

/** Borra los bloques escritos para los otros idiomas. */
function stripOtherLocales(html, locale) {
  const unwanted = LOCALES.filter((l) => l !== locale).map((l) => `locale-${l}`);
  let current = html;
  for (;;) {
    const tags = scanTags(current);
    const index = tags.findIndex(
      (tag) => !tag.isClose && unwanted.some((cls) => hasClass(parseAttributes(tag.attrsSource), cls)),
    );
    if (index === -1) return current;
    const open = tags[index];
    const close = tags[findClosingTag(tags, index)];
    current = current.slice(0, open.start) + current.slice(close.end);
  }
}

/**
 * Resuelve los data-en: en inglés reemplaza el texto (o el atributo que
 * indique data-i18n-attribute) y en los dos idiomas limpia los atributos
 * de traducción, que ya no hacen falta en una página por idioma.
 */
function resolveTranslations(html, locale) {
  const tags = scanTags(html);
  const edits = [];

  tags.forEach((tag, index) => {
    if (tag.isClose) return;
    const attrs = parseAttributes(tag.attrsSource);
    if (!("data-en" in attrs)) return;

    const target = attrs["data-i18n-attribute"];
    let source = tag.source;

    if (locale === "en") {
      if (target) {
        source = setAttribute(source, target, attrs["data-en"]);
      } else {
        const close = tags[findClosingTag(tags, index)];
        edits.push({ start: tag.end, end: close.start, replacement: attrs["data-en"] });
      }
    }

    source = removeAttribute(source, "data-en");
    source = removeAttribute(source, "data-es");
    source = removeAttribute(source, "data-i18n-attribute");
    edits.push({ start: tag.start, end: tag.end, replacement: source });
  });

  return applyEdits(html, edits);
}

/** Apunta los links internos a la versión del idioma que estamos generando. */
function localizeLinks(html, locale) {
  if (locale === DEFAULT_LOCALE) return html;
  let out = html;
  for (const page of PAGES) {
    const from = `href="${page.path}"`;
    const to = `href="/${locale}${page.path}"`;
    out = out.split(from).join(to);
  }
  return out;
}

/** El <title> completo lleva la marca; para redes alcanza con la parte útil. */
function socialTitle(title) {
  return title.split(" | ")[0].trim();
}

function alternateLinks(page) {
  const links = LOCALES.map(
    (locale) => `  <link rel="alternate" hreflang="${locale}" href="${urlFor(page, locale)}">`,
  );
  links.push(`  <link rel="alternate" hreflang="x-default" href="${urlFor(page, DEFAULT_LOCALE)}">`);
  return links.join("\n");
}

function headBlock({ page, locale, url, title, description, graph }) {
  const other = LOCALES.filter((l) => l !== locale);
  const meta = (attr, name, value) =>
    `  <meta ${attr}="${name}" content="${escapeAttribute(value)}">`;

  return [
    `  <title>${escapeAttribute(title)}</title>`,
    meta("name", "description", description),
    `  <link rel="canonical" href="${url}">`,
    alternateLinks(page),
    meta("name", "robots", "index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1"),
    meta("name", "theme-color", "#04173F"),
    meta("name", "apple-mobile-web-app-title", BRAND),
    meta("name", "application-name", BRAND),
    "",
    meta("property", "og:type", "website"),
    meta("property", "og:site_name", BRAND),
    meta("property", "og:locale", OG_LOCALE[locale]),
    ...other.map((l) => meta("property", "og:locale:alternate", OG_LOCALE[l])),
    meta("property", "og:title", socialTitle(title)),
    meta("property", "og:description", description),
    meta("property", "og:url", url),
    meta("property", "og:image", SOCIAL_IMAGE[locale].url),
    meta("property", "og:image:width", SOCIAL_IMAGE.width),
    meta("property", "og:image:height", SOCIAL_IMAGE.height),
    meta("property", "og:image:type", "image/png"),
    meta("property", "og:image:alt", SOCIAL_IMAGE[locale].alt),
    "",
    meta("name", "twitter:card", "summary_large_image"),
    meta("name", "twitter:title", socialTitle(title)),
    meta("name", "twitter:description", description),
    meta("name", "twitter:image", SOCIAL_IMAGE[locale].url),
    meta("name", "twitter:image:alt", SOCIAL_IMAGE[locale].alt),
    "",
    `  <link rel="icon" type="image/png" href="/assets/favicon.png">`,
    `  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">`,
    `  <link rel="manifest" href="/site.webmanifest">`,
    "",
    `  <script type="application/ld+json">`,
    JSON.stringify(graph, null, 2).replace(/</g, "\\u003c"),
    `  </script>`,
  ].join("\n");
}

function languageToggle(page, locale) {
  const toggle = LANG_TOGGLE[locale];
  const href = urlFor(page, toggle.to).replace(SITE, "");
  return [
    `<a class="lang-toggle" href="${href}" hreflang="${toggle.to}" lang="${toggle.to}"`,
    ` title="${escapeAttribute(toggle.title)}" rel="alternate">${toggle.label}</a>`,
  ].join("");
}

async function renderPage(page, locale) {
  const template = await readFile(join(TEMPLATES, page.template), "utf8");
  const copy = page[locale];
  const url = urlFor(page, locale);

  let html = stripOtherLocales(template, locale);
  html = resolveTranslations(html, locale);
  html = localizeLinks(html, locale);
  html = html.replace("<!--LANG_TOGGLE-->", languageToggle(page, locale));

  // El <html> tiene que declarar el idioma real de la página.
  html = html.replace(/<html\b[^>]*>/i, `<html lang="${locale}" data-locale="${locale}">`);

  const faq = extractFaq(html);
  const graph = buildGraph({
    page,
    locale,
    url,
    title: copy.title,
    description: copy.description,
    faq,
    homeName: BRAND,
  });

  html = html.replace(
    "<!--SEO-->",
    headBlock({ page, locale, url, title: copy.title, description: copy.description, graph }),
  );

  if (html.includes("<!--SEO-->") || html.includes("<!--LANG_TOGGLE-->")) {
    throw new Error(`Quedaron marcadores sin reemplazar en ${page.template} (${locale})`);
  }

  const destination = fileFor(page, locale);
  await mkdir(dirname(destination), { recursive: true });
  await writeFile(destination, GENERATED_NOTICE + html, "utf8");
  return { destination, url, faqCount: faq.length };
}

async function writeSitemap() {
  const today = new Date().toISOString().slice(0, 10);
  const entries = [];
  for (const page of PAGES) {
    for (const locale of LOCALES) {
      const alternates = [...LOCALES, "x-default"].map((code) => {
        const target = code === "x-default" ? DEFAULT_LOCALE : code;
        return `    <xhtml:link rel="alternate" hreflang="${code}" href="${urlFor(page, target)}"/>`;
      });
      entries.push([
        "  <url>",
        `    <loc>${urlFor(page, locale)}</loc>`,
        ...alternates,
        `    <lastmod>${today}</lastmod>`,
        `    <changefreq>${page.changefreq}</changefreq>`,
        `    <priority>${page.priority}</priority>`,
        "  </url>",
      ].join("\n"));
    }
  }

  const xml = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"',
    '        xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ...entries,
    "</urlset>",
    "",
  ].join("\n");

  await writeFile(join(OUTPUT, "sitemap.xml"), xml, "utf8");
  return entries.length;
}

async function writeRobots() {
  const robots = [
    "# robots.txt de maratonia.site",
    "# Sitio público y estático: se puede rastrear todo.",
    "",
    "User-agent: *",
    "Allow: /",
    "",
    `Sitemap: ${SITE}/sitemap.xml`,
    "",
  ].join("\n");
  await writeFile(join(OUTPUT, "robots.txt"), robots, "utf8");
}

async function main() {
  const built = [];
  for (const page of PAGES) {
    for (const locale of LOCALES) {
      built.push(await renderPage(page, locale));
    }
  }
  const urls = await writeSitemap();
  await writeRobots();

  for (const item of built) {
    const faq = item.faqCount ? `  (${item.faqCount} preguntas en FAQPage)` : "";
    console.log(`  ${item.url}${faq}`);
  }
  console.log(`\n${built.length} páginas, sitemap con ${urls} URLs, robots.txt listo.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
