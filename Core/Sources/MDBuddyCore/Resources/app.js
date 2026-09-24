/* MD Buddy page script: heading anchors, GitHub alerts, syntax highlighting. */
(function () {
  "use strict";

  // GitHub-style heading slugs so in-document links like [x](#some-heading) work.
  function addHeadingAnchors(root) {
    var seen = Object.create(null);
    root.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach(function (h) {
      if (h.id) return;
      var base = h.textContent.trim().toLowerCase()
        .replace(/[^\p{L}\p{N}\s_-]/gu, "")
        .replace(/\s/g, "-");
      var slug = base;
      if (seen[base] !== undefined) slug = base + "-" + (++seen[base]);
      else seen[base] = 0;
      h.id = slug;
    });
  }

  // > [!NOTE] / [!TIP] / [!IMPORTANT] / [!WARNING] / [!CAUTION]
  var ALERTS = { note: "Note", tip: "Tip", important: "Important", warning: "Warning", caution: "Caution" };
  function addAlerts(root) {
    root.querySelectorAll("blockquote").forEach(function (bq) {
      var p = bq.firstElementChild;
      if (!p || p.tagName !== "P") return;
      var text = p.firstChild;
      if (!text || text.nodeType !== Node.TEXT_NODE) return;
      var m = /^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\n|$)/i.exec(text.data);
      if (!m) return;
      var type = m[1].toLowerCase();
      text.data = text.data.slice(m[0].length);
      if (!p.textContent.trim() && !p.querySelector("img")) p.remove();
      bq.classList.add("alert", "alert-" + type);
      var title = document.createElement("p");
      title.className = "alert-title";
      title.textContent = ALERTS[type];
      bq.insertBefore(title, bq.firstChild);
    });
  }

  function highlight() {
    if (typeof hljs === "undefined") return;
    hljs.configure({ ignoreUnescapedHTML: true, throwUnescapedHTML: false });
    document.querySelectorAll("pre code").forEach(function (code) {
      var cls = code.className.match(/language-([\w+#.-]+)/);
      if (code.dataset.language === "auto") {
        hljs.highlightElement(code);
        return;
      }
      if (!cls) return;
      var lang = cls[1].toLowerCase();
      if (!hljs.getLanguage(lang)) return; // unknown fence language: leave as plain code
      code.className = "language-" + lang;
      try { hljs.highlightElement(code); } catch (e) { /* leave unhighlighted */ }
    });
  }

  // Quick Look gives previews no network access, so remote images (and missing local
  // ones) become a labelled chip instead of a broken-image icon.
  function replaceBrokenImage(img) {
    if (!img.parentNode) return;
    var remote = img.src.indexOf("mdbuddy-remote:") === 0;
    var source = remote ? img.src.slice("mdbuddy-remote:".length) : decodeURIComponent(img.src.replace(/^[a-z-]+:\/\//, ""));
    var chip = document.createElement("span");
    chip.className = "image-placeholder" + (remote ? " remote" : "");
    chip.title = (remote ? "Remote images can't load in Quick Look: " : "Image not found: ") + source;
    chip.textContent = img.alt || source.split("/").pop() || "image";
    img.parentNode.replaceChild(chip, img);
  }
  function watchImages() {
    document.querySelectorAll("img").forEach(function (img) {
      if (img.complete && img.naturalWidth === 0 && img.src) replaceBrokenImage(img);
      else img.addEventListener("error", function () { replaceBrokenImage(img); });
    });
  }

  var article = document.querySelector(".markdown-body");
  if (article) {
    addHeadingAnchors(article);
    addAlerts(article);
    watchImages();
  }
  highlight();
})();
