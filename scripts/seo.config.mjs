// Metadatos SEO de maratonia.site, en un solo lugar.
//
// De acá salen los <title>, las descripciones, los canonical, los hreflang,
// las Open Graph y el JSON-LD de todas las páginas, en los dos idiomas.
// Si querés cambiar cómo se ve la web en Google, se cambia acá y se corre
// `npm run build:web`.

export const SITE = "https://maratonia.site";
export const BRAND = "Maratonia";
export const EMAIL = "contact@maratonia.site";
export const LOCALES = ["es", "en"];
export const DEFAULT_LOCALE = "es";

// Imagen de las tarjetas al compartir en redes (1200x630, el tamaño que
// esperan Facebook, LinkedIn, WhatsApp y X). Se genera con
// scripts/build-og-image.mjs.
export const SOCIAL_IMAGE = {
  width: 1200,
  height: 630,
  es: {
    url: SITE + "/assets/og-cover-es.png",
    alt: "Maratonia: tu plan de running, en el Apple Watch. Planes de 5K a maratón, ritmo objetivo por voz y Apple Health.",
  },
  en: {
    url: SITE + "/assets/og-cover-en.png",
    alt: "Maratonia: your running plan, on your Apple Watch. 5K to marathon plans, voice pace coaching and Apple Health.",
  },
};

// El icono cuadrado, que es lo que Google usa como logo de la organización.
export const APP_ICON = {
  url: SITE + "/assets/maratonia-icon.jpg",
  width: 512,
  height: 512,
};

export const OG_LOCALE = { es: "es_AR", en: "en_US" };

// Las páginas del sitio. `path` es la ruta en español; la inglesa se arma
// con el prefijo /en. `template` es el archivo fuente en templates/.
export const PAGES = [
  {
    id: "home",
    template: "index.html",
    path: "/",
    changefreq: "weekly",
    priority: "1.0",
    es: {
      title: "App de running para Apple Watch — planes de 5K a maratón | Maratonia",
      description:
        "Armá el plan en el iPhone y corré la sesión desde el Apple Watch: tramos, ritmo objetivo, avisos por voz y carreras guardadas en Apple Health. Sin el teléfono.",
    },
    en: {
      title: "Apple Watch Running App — 5K to Marathon Training Plans | Maratonia",
      description:
        "Build the plan on iPhone and run the session from Apple Watch: intervals, target pace, voice prompts and runs saved to Apple Health. Leave the phone at home.",
    },
  },
  {
    id: "support",
    template: "support/index.html",
    path: "/support/",
    changefreq: "monthly",
    priority: "0.6",
    es: {
      title: "Soporte y preguntas frecuentes de Maratonia, app de running",
      description:
        "Ayuda de Maratonia: permisos de Apple Health, ubicación en el Apple Watch, avisos por voz, cuenta y borrado de datos. Y contacto directo con el equipo.",
      breadcrumb: "Soporte",
    },
    en: {
      title: "Support and FAQ | Maratonia running app",
      description:
        "Maratonia help: Apple Health permissions, Apple Watch location, voice prompts, accounts and data deletion. Answers to the most common problems, plus direct contact.",
      breadcrumb: "Support",
    },
  },
  {
    id: "privacy",
    template: "privacy/index.html",
    path: "/privacy/",
    changefreq: "yearly",
    priority: "0.3",
    es: {
      title: "Política de privacidad | Maratonia, app de running",
      description:
        "Qué datos usa Maratonia y dónde viven: plan y preferencias en tu dispositivo, carreras en Apple Health, respaldo en tu iCloud. Sin publicidad ni tracking.",
      breadcrumb: "Privacidad",
    },
    en: {
      title: "Privacy Policy | Maratonia running app",
      description:
        "What data Maratonia uses and where it lives: plan and preferences on your device, runs in Apple Health, backup in your iCloud. No ads, no cross-app tracking.",
      breadcrumb: "Privacy",
    },
  },
  {
    id: "terms",
    template: "terms/index.html",
    path: "/terms/",
    changefreq: "yearly",
    priority: "0.3",
    es: {
      title: "Términos de uso | Maratonia, app de running",
      description:
        "Condiciones de uso de Maratonia, app de entrenamiento de running para iPhone y Apple Watch. Los planes y ritmos son orientativos y no reemplazan el consejo médico.",
      breadcrumb: "Términos",
    },
    en: {
      title: "Terms of Use | Maratonia running app",
      description:
        "Terms for using Maratonia, a running training app for iPhone and Apple Watch. Plans and paces are guidance only and do not replace medical advice.",
      breadcrumb: "Terms",
    },
  },
];

// Texto del botón que alterna idioma en la barra de navegación.
export const LANG_TOGGLE = {
  // En la página en español el botón lleva al inglés, y al revés.
  es: { label: "EN", to: "en", title: "Read this page in English" },
  en: { label: "ES", to: "es", title: "Leer esta página en español" },
};

export const HOME_HEADING = {
  es: "Maratonia",
  en: "Maratonia",
};
