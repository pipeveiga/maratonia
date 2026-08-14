// Servidor estático mínimo para Hostinger (entry file de la web app).
// Sin dependencias: sirve index.html, styles.css, assets/ y las páginas
// privacy/, support/ y terms/ con URLs limpias y barra final.

const http = require("http");
const fs = require("fs");
const path = require("path");

const RAIZ = __dirname;
const PUERTO = process.env.PORT || 3000;

// Archivos del propio servidor que jamás se sirven al público.
const PRIVADOS = new Set(["index.js", "package.json", "package-lock.json"]);

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function responder(res, codigo, cuerpo, tipo) {
  res.writeHead(codigo, { "Content-Type": tipo || "text/plain; charset=utf-8" });
  res.end(cuerpo);
}

// El HTML se revalida siempre; CSS/JS una semana; imágenes y fuentes,
// que cambian de nombre si cambian, un mes e inmutables.
const CACHE_LARGO = new Set([".jpg", ".jpeg", ".png", ".webp", ".svg", ".ico", ".woff", ".woff2"]);

function cachePara(ext) {
  if (ext === ".html") return "no-cache";
  if (CACHE_LARGO.has(ext)) return "public, max-age=2592000, immutable";
  return "public, max-age=604800";
}

function servirArchivo(res, ruta) {
  const ext = path.extname(ruta).toLowerCase();
  fs.readFile(ruta, (err, datos) => {
    if (err) return responder(res, 404, "No encontrado");
    res.writeHead(200, {
      "Content-Type": MIME[ext] || "application/octet-stream",
      "Cache-Control": cachePara(ext),
    });
    res.end(datos);
  });
}

const servidor = http.createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return responder(res, 405, "Método no permitido");
  }

  let pedido;
  try {
    pedido = decodeURIComponent(new URL(req.url, "http://x").pathname);
  } catch {
    return responder(res, 400, "Petición inválida");
  }

  // Nada de escaparse de la carpeta ni de leer el propio servidor.
  const ruta = path.normalize(path.join(RAIZ, pedido));
  if (!ruta.startsWith(RAIZ + path.sep) && ruta !== RAIZ) {
    return responder(res, 404, "No encontrado");
  }
  if (PRIVADOS.has(path.relative(RAIZ, ruta))) {
    return responder(res, 404, "No encontrado");
  }

  fs.stat(ruta, (err, info) => {
    if (!err && info.isDirectory()) {
      // /privacy → /privacy/ para que las rutas relativas no se rompan.
      if (!pedido.endsWith("/")) {
        res.writeHead(301, { Location: pedido + "/" });
        return res.end();
      }
      return servirArchivo(res, path.join(ruta, "index.html"));
    }
    if (!err && info.isFile()) {
      return servirArchivo(res, ruta);
    }
    // URL limpia sin extensión: /algo → /algo.html si existe.
    if (!path.extname(ruta)) {
      return servirArchivo(res, ruta + ".html");
    }
    return responder(res, 404, "No encontrado");
  });
});

servidor.listen(PUERTO, () => {
  console.log(`Maratonia web escuchando en el puerto ${PUERTO}`);
});
