// JSON-LD para Google. Todo lo que declaramos acá tiene que existir de
// verdad en la página: los datos estructurados que no coinciden con el
// contenido visible son motivo de penalización manual.

import { SITE, BRAND, EMAIL, APP_ICON } from "./seo.config.mjs";
import { decodeEntities, textContent } from "./lib-html.mjs";

const ORGANIZATION_ID = `${SITE}/#organization`;
const WEBSITE_ID = `${SITE}/#website`;
const APP_ID = `${SITE}/#app`;

const FEATURES = {
  es: [
    "Planes de entrenamiento de 5K, 10K, media maratón y maratón",
    "Entrenamiento por tramos con ritmo objetivo",
    "Avisos por voz de splits, tramos y correcciones de ritmo",
    "Ejecución autónoma en el Apple Watch, sin el iPhone",
    "Registro de distancia, frecuencia cardíaca, calorías y ruta en Apple Health",
    "Reproducción de música por Bluetooth desde el reloj",
  ],
  en: [
    "5K, 10K, half marathon and marathon training plans",
    "Interval training with target pace",
    "Voice prompts for splits, intervals and pace corrections",
    "Standalone Apple Watch workouts, no iPhone needed",
    "Distance, heart rate, calories and route saved to Apple Health",
    "Bluetooth music playback from the watch",
  ],
};

const APP_DESCRIPTION = {
  es: "App de running para iPhone y Apple Watch: arma planes de entrenamiento de 5K a maratón, guía la sesión por voz con ritmo objetivo y guarda cada carrera en Apple Health.",
  en: "Running app for iPhone and Apple Watch: build 5K to marathon training plans, get voice guidance with target pace, and save every run to Apple Health.",
};

function organization() {
  return {
    "@type": "Organization",
    "@id": ORGANIZATION_ID,
    name: BRAND,
    url: `${SITE}/`,
    email: EMAIL,
    logo: {
      "@type": "ImageObject",
      "@id": `${SITE}/#logo`,
      url: APP_ICON.url,
      contentUrl: APP_ICON.url,
      width: APP_ICON.width,
      height: APP_ICON.height,
      caption: BRAND,
    },
    image: { "@id": `${SITE}/#logo` },
    contactPoint: {
      "@type": "ContactPoint",
      email: EMAIL,
      contactType: "customer support",
      availableLanguage: ["Spanish", "English"],
    },
  };
}

function website(locale) {
  return {
    "@type": "WebSite",
    "@id": WEBSITE_ID,
    url: `${SITE}/`,
    name: BRAND,
    inLanguage: locale,
    publisher: { "@id": ORGANIZATION_ID },
  };
}

function application(locale) {
  return {
    "@type": ["SoftwareApplication", "MobileApplication"],
    "@id": APP_ID,
    name: BRAND,
    url: `${SITE}/`,
    applicationCategory: "HealthApplication",
    applicationSubCategory: locale === "en" ? "Running training" : "Entrenamiento de running",
    operatingSystem: "iOS, watchOS",
    description: APP_DESCRIPTION[locale],
    featureList: FEATURES[locale],
    inLanguage: ["es", "en"],
    author: { "@id": ORGANIZATION_ID },
    publisher: { "@id": ORGANIZATION_ID },
    image: { "@id": `${SITE}/#logo` },
  };
}

function webPage({ url, title, description, locale, isHome, breadcrumbId }) {
  const page = {
    "@type": "WebPage",
    "@id": `${url}#webpage`,
    url,
    name: decodeEntities(title),
    description: decodeEntities(description),
    inLanguage: locale,
    isPartOf: { "@id": WEBSITE_ID },
    about: { "@id": APP_ID },
    primaryImageOfPage: { "@id": `${SITE}/#logo` },
  };
  if (isHome) page["@type"] = "WebPage";
  if (breadcrumbId) page.breadcrumb = { "@id": breadcrumbId };
  return page;
}

function breadcrumbs({ url, homeName, pageName }) {
  return {
    "@type": "BreadcrumbList",
    "@id": `${url}#breadcrumb`,
    itemListElement: [
      { "@type": "ListItem", position: 1, name: homeName, item: url.replace(/\/[^/]+\/$/, "/") },
      { "@type": "ListItem", position: 2, name: pageName },
    ],
  };
}

/**
 * Arma el FAQPage leyendo los <details> que ya están en el HTML generado,
 * así lo que ve Google es exactamente lo que ve la persona.
 */
export function extractFaq(html) {
  const entries = [];
  const blockRe = /<details\b[^>]*>([\s\S]*?)<\/details>/gi;
  let match;
  while ((match = blockRe.exec(html)) !== null) {
    const block = match[1];
    const summary = /<summary\b[^>]*>([\s\S]*?)<\/summary>/i.exec(block);
    if (!summary) continue;
    const question = textContent(summary[1]);
    const answer = textContent(block.slice(summary.index + summary[0].length));
    if (question && answer) entries.push({ question, answer });
  }
  return entries;
}

function faqPage({ url, faq }) {
  return {
    "@type": "FAQPage",
    "@id": `${url}#faq`,
    mainEntity: faq.map((entry) => ({
      "@type": "Question",
      name: entry.question,
      acceptedAnswer: { "@type": "Answer", text: entry.answer },
    })),
  };
}

/** Grafo JSON-LD completo de una página. */
export function buildGraph({ page, locale, url, title, description, faq, homeName }) {
  const isHome = page.id === "home";
  const graph = [organization(), website(locale), application(locale)];

  const hasBreadcrumb = !isHome;
  const breadcrumbId = hasBreadcrumb ? `${url}#breadcrumb` : null;

  graph.push(webPage({ url, title, description, locale, isHome, breadcrumbId }));

  if (hasBreadcrumb) {
    graph.push(breadcrumbs({ url, homeName, pageName: page[locale].breadcrumb || page.id }));
  }
  if (faq && faq.length > 0) {
    graph.push(faqPage({ url, faq }));
  }

  return { "@context": "https://schema.org", "@graph": graph };
}
