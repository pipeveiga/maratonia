// Utilidades mínimas para leer y reescribir el HTML de las plantillas.
// No usamos dependencias: el HTML de templates/ lo escribimos nosotros,
// está bien formado y no tiene "<" sueltos dentro de atributos.

const VOID_ELEMENTS = new Set([
  "area", "base", "br", "col", "embed", "hr", "img", "input",
  "link", "meta", "param", "source", "track", "wbr",
]);

const TAG_RE = /<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;
const ATTR_RE = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;

const NAMED_ENTITIES = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  rarr: "→", larr: "←", hellip: "…", mdash: "—", ndash: "–",
  aacute: "á", eacute: "é", iacute: "í", oacute: "ó", uacute: "ú", ntilde: "ñ",
  Aacute: "Á", Eacute: "É", Iacute: "Í", Oacute: "Ó", Uacute: "Ú", Ntilde: "Ñ",
  iquest: "¿", iexcl: "¡", uuml: "ü", Uuml: "Ü", middot: "·", deg: "°",
};

/** Convierte entidades HTML a texto plano (para el JSON-LD). */
export function decodeEntities(text) {
  return text.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (whole, body) => {
    if (body[0] === "#") {
      const code = body[1] === "x" || body[1] === "X"
        ? parseInt(body.slice(2), 16)
        : parseInt(body.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : whole;
    }
    return Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, body)
      ? NAMED_ENTITIES[body]
      : whole;
  });
}

/** Escapa texto para meterlo dentro de un atributo HTML. */
export function escapeAttribute(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Escapa texto plano para incrustarlo como contenido HTML. */
export function escapeText(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/**
 * Lista todas las etiquetas del documento, en orden. El contenido de
 * <script> y <style> se saltea entero para no confundir su código con HTML.
 */
export function scanTags(html) {
  const tags = [];
  TAG_RE.lastIndex = 0;
  let match;
  while ((match = TAG_RE.exec(html)) !== null) {
    const name = match[2].toLowerCase();
    const isClose = match[1] === "/";
    tags.push({
      start: match.index,
      end: TAG_RE.lastIndex,
      name,
      isClose,
      selfClosing: match[4] === "/" || VOID_ELEMENTS.has(name),
      attrsSource: match[3],
      source: match[0],
    });
    if (!isClose && (name === "script" || name === "style") && match[4] !== "/") {
      const closing = html.toLowerCase().indexOf("</" + name, TAG_RE.lastIndex);
      if (closing !== -1) TAG_RE.lastIndex = closing;
    }
  }
  return tags;
}

/** Atributos de una etiqueta, como objeto {nombre: valor}. */
export function parseAttributes(attrsSource) {
  const attrs = {};
  ATTR_RE.lastIndex = 0;
  let match;
  while ((match = ATTR_RE.exec(attrsSource)) !== null) {
    const value = match[2] ?? match[3] ?? match[4] ?? "";
    attrs[match[1].toLowerCase()] = value;
  }
  return attrs;
}

/** Índice, dentro de `tags`, de la etiqueta que cierra a `tags[openIndex]`. */
export function findClosingTag(tags, openIndex) {
  const open = tags[openIndex];
  if (open.selfClosing) return openIndex;
  let depth = 0;
  for (let i = openIndex + 1; i < tags.length; i += 1) {
    const tag = tags[i];
    if (tag.name !== open.name) continue;
    if (tag.isClose) {
      if (depth === 0) return i;
      depth -= 1;
    } else if (!tag.selfClosing) {
      depth += 1;
    }
  }
  throw new Error(`No se encontró el cierre de <${open.name}>`);
}

/**
 * Aplica una lista de ediciones {start, end, replacement} sobre el texto.
 * Se ordenan de atrás para adelante para que los índices sigan siendo válidos.
 */
export function applyEdits(html, edits) {
  const ordered = [...edits].sort((a, b) => b.start - a.start);
  let out = html;
  let previousStart = Infinity;
  for (const edit of ordered) {
    if (edit.end > previousStart) {
      throw new Error("Ediciones superpuestas: revisá el generador");
    }
    out = out.slice(0, edit.start) + edit.replacement + out.slice(edit.end);
    previousStart = edit.start;
  }
  return out;
}

/** Quita las etiquetas y deja el texto legible, ya sin entidades. */
export function textContent(html) {
  return decodeEntities(html.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
}

/** Reescribe (o agrega) un atributo dentro del código de una etiqueta. */
export function setAttribute(tagSource, name, value) {
  const pattern = new RegExp(`\\s${name}\\s*=\\s*("[^"]*"|'[^']*'|[^\\s>]+)`, "i");
  const rendered = `${name}="${escapeAttribute(value)}"`;
  if (pattern.test(tagSource)) {
    return tagSource.replace(pattern, ` ${rendered}`);
  }
  return tagSource.replace(/(\/?)>$/, ` ${rendered}$1>`);
}

/** Elimina un atributo del código de una etiqueta. */
export function removeAttribute(tagSource, name) {
  const pattern = new RegExp(`\\s${name}(\\s*=\\s*("[^"]*"|'[^']*'|[^\\s>]+))?`, "gi");
  return tagSource.replace(pattern, "");
}

export { VOID_ELEMENTS };
