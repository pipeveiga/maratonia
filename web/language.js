(function () {
  var GUARDADO = "maratonia-locale";

  var idiomas = navigator.languages && navigator.languages.length
    ? navigator.languages
    : [navigator.language || "es"];

  var preferencia = null;
  try { preferencia = localStorage.getItem(GUARDADO); } catch (e) {}

  // Si el sistema tiene español en CUALQUIER posición de la lista de
  // idiomas preferidos, la página entra en español. Solo cae a inglés
  // cuando no hay rastro de español (o si el usuario lo pidió a mano).
  var hayEspanol = idiomas.some(function (l) { return /^es/i.test(l); });
  var locale = (preferencia === "en" || preferencia === "es")
    ? preferencia
    : (hayEspanol ? "es" : "en");

  document.documentElement.lang = locale;
  document.documentElement.dataset.locale = locale;

  function aplicar(nuevo) {
    locale = nuevo;
    document.documentElement.lang = nuevo;
    document.documentElement.dataset.locale = nuevo;

    document.querySelectorAll("[data-en]").forEach(function (node) {
      var atributo = node.getAttribute("data-i18n-attribute");
      // La primera vez guardamos el texto original en español para
      // poder volver a él si el usuario alterna el idioma.
      if (node.getAttribute("data-es") === null) {
        node.setAttribute("data-es", atributo ? node.getAttribute(atributo) : node.textContent);
      }
      var valor = nuevo === "en" ? node.getAttribute("data-en") : node.getAttribute("data-es");
      if (atributo) {
        node.setAttribute(atributo, valor);
      } else {
        node.textContent = valor;
      }
    });

    var boton = document.querySelector(".lang-toggle");
    if (boton) {
      boton.textContent = nuevo === "en" ? "ES" : "EN";
      boton.setAttribute("aria-label", nuevo === "en" ? "Cambiar a español" : "Switch to English");
    }
  }

  function listo() {
    // Favicon para las páginas que no lo declaran en su HTML.
    if (!document.querySelector('link[rel="icon"]')) {
      var icono = document.createElement("link");
      icono.rel = "icon";
      icono.type = "image/png";
      icono.href = "/assets/favicon.png";
      document.head.appendChild(icono);
    }

    // Botón para alternar idioma, con la elección recordada.
    var nav = document.querySelector(".site-nav");
    if (nav && !nav.querySelector(".lang-toggle")) {
      var boton = document.createElement("button");
      boton.type = "button";
      boton.className = "lang-toggle";
      boton.addEventListener("click", function () {
        var nuevo = locale === "en" ? "es" : "en";
        try { localStorage.setItem(GUARDADO, nuevo); } catch (e) {}
        aplicar(nuevo);
      });
      nav.appendChild(boton);
    }

    aplicar(locale);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", listo);
  } else {
    listo();
  }
})();
