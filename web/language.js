(function () {
  var languages = navigator.languages && navigator.languages.length
    ? navigator.languages
    : [navigator.language || "es"];
  var isEnglish = /^en(?:-|$)/i.test(languages[0]);
  var locale = isEnglish ? "en" : "es";

  document.documentElement.lang = locale;
  document.documentElement.dataset.locale = locale;

  function applyEnglish() {
    if (!isEnglish) return;

    document.querySelectorAll("[data-en]").forEach(function (node) {
      var attribute = node.getAttribute("data-i18n-attribute");
      var value = node.getAttribute("data-en");

      if (attribute) {
        node.setAttribute(attribute, value);
      } else {
        node.textContent = value;
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", applyEnglish);
  } else {
    applyEnglish();
  }
})();
