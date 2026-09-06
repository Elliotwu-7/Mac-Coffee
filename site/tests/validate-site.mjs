import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const siteRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const required = ["index.html", "styles.css", "i18n.js", "script.js"];

for (const file of required) {
  assert.ok(existsSync(join(siteRoot, file)), `Missing ${file}`);
}

const html = readFileSync(join(siteRoot, "index.html"), "utf8");
const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(ids.length, new Set(ids).size, "HTML IDs must be unique");

for (const [, anchor] of html.matchAll(/href="#([^"]+)"/g)) {
  assert.ok(ids.includes(anchor), `Missing internal anchor #${anchor}`);
}

for (const [tag] of html.matchAll(/<img\b[^>]*>/g)) {
  assert.match(tag, /\salt="[^"]*"/, `Image requires alt: ${tag}`);
  assert.match(tag, /\swidth="\d+"/, `Image requires width: ${tag}`);
  assert.match(tag, /\sheight="\d+"/, `Image requires height: ${tag}`);
}

for (const [, asset] of html.matchAll(/(?:src|href)="((?:assets\/|styles\.css|i18n\.js|script\.js)[^"]*)"/g)) {
  const cleanPath = asset.split(/[?#]/)[0];
  assert.ok(existsSync(join(siteRoot, cleanPath)), `Missing local asset ${cleanPath}`);
}

for (const [tag] of html.matchAll(/<a\b[^>]*target="_blank"[^>]*>/g)) {
  assert.match(tag, /rel="[^"]*noopener[^"]*"/, `External target requires noopener: ${tag}`);
}

for (const asset of ["assets/app-icon.png", "assets/panel-en.png", "assets/settings-ru.png", ".nojekyll"]) {
  assert.ok(existsSync(join(siteRoot, asset)), `Missing ${asset}`);
}

for (const phrase of [
  "Timed wake sessions for your Mac.",
  "brew tap rekurt/maccoffee",
  "brew install --cask maccoffee",
  "maccoffee_set_session",
  "Settings → AI & automation",
  "Battery protection",
  "No cloud backend",
  "lid closure",
]) {
  assert.ok(html.includes(phrase), `Missing required narrative: ${phrase}`);
}

for (const hook of ["data-language", "data-copy", 'id="wake-demo"', 'id="wake-toggle"', 'id="copy-status"']) {
  assert.ok(html.includes(hook), `Missing interaction hook ${hook}`);
}

for (const href of [
  "https://github.com/rekurt/Mac-Coffee",
  "https://github.com/rekurt/Mac-Coffee/releases/latest",
]) {
  assert.ok(html.includes(href), `Missing product link ${href}`);
}

const context = {};
vm.runInNewContext(readFileSync(join(siteRoot, "i18n.js"), "utf8"), context);
const translations = context.MacCoffeeTranslations;
assert.ok(translations?.en && translations?.ru, "English and Russian dictionaries are required");
assert.deepEqual(Object.keys(translations.ru).sort(), Object.keys(translations.en).sort(), "Language keys differ");
assert.ok(translations.zh, "Simplified Chinese dictionary is required");
assert.deepEqual(Object.keys(translations.zh).sort(), Object.keys(translations.en).sort(), "Chinese language keys differ");

const keys = [
  ...html.matchAll(/data-i18n(?:-aria)?="([^"]+)"/g),
].map((match) => match[1]);
for (const key of new Set(keys)) {
  assert.ok(key in translations.en, `Missing English translation for ${key}`);
  assert.ok(key in translations.ru, `Missing Russian translation for ${key}`);
  assert.ok(key in translations.zh, `Missing Chinese translation for ${key}`);
}

new vm.Script(readFileSync(join(siteRoot, "script.js"), "utf8"));

const css = readFileSync(join(siteRoot, "styles.css"), "utf8");
const script = readFileSync(join(siteRoot, "script.js"), "utf8");

for (const token of ["prefers-reduced-motion", ":focus-visible", "@media (max-width:", "[data-wake-active=\"true\"]"]) {
  assert.ok(css.includes(token), `Missing CSS contract ${token}`);
}

const attributes = new Map();
const translatedNode = { dataset: { i18n: "heroTitle" }, textContent: "" };
const ariaNode = { dataset: { i18nAria: "navLabel" }, setAttribute: (name, value) => attributes.set(`aria:${name}`, value) };
const languageButtons = ["en", "ru"].map((language) => ({
  dataset: { language },
  setAttribute: (name, value) => attributes.set(`${language}:${name}`, value),
}));
const wakeDemo = { setAttribute: (name, value) => attributes.set(`demo:${name}`, value) };
const wakeToggle = { setAttribute: (name, value) => attributes.set(`toggle:${name}`, value) };
const copyStatus = { textContent: "" };
const codeNode = { innerText: "maccoffee_set_session" };
const stored = new Map();
let clipboardText = "";

const runtime = {
  MacCoffeeTranslations: {
    en: { heroTitle: "Agents awake", navLabel: "Navigation", copySuccess: "Copied", copied: "Copied" },
    ru: { heroTitle: "Агенты работают", navLabel: "Навигация", copySuccess: "Скопировано", copied: "Готово" },
  },
  document: {
    documentElement: { lang: "en", classList: { add() {} } },
    addEventListener() {},
    querySelectorAll(selector) {
      if (selector === "[data-i18n]") return [translatedNode];
      if (selector === "[data-i18n-aria]") return [ariaNode];
      if (selector === "[data-language]") return languageButtons;
      return [];
    },
    querySelector(selector) {
      return {
        "#wake-demo": wakeDemo,
        "#wake-toggle": wakeToggle,
        "#copy-status": copyStatus,
        "#code": codeNode,
      }[selector] ?? null;
    },
  },
  localStorage: {
    getItem: (key) => stored.get(key) ?? null,
    setItem: (key, value) => stored.set(key, value),
  },
  navigator: { clipboard: { writeText: async (value) => { clipboardText = value; } } },
  IntersectionObserver: class { observe() {} unobserve() {} },
  setTimeout: (callback) => callback(),
};

vm.runInNewContext(script, runtime);
assert.ok(runtime.MacCoffeeSite, "Missing interaction API");
runtime.MacCoffeeSite.setLanguage("ru");
assert.equal(translatedNode.textContent, "Агенты работают", "Russian content was not applied");
assert.equal(attributes.get("ru:aria-pressed"), "true", "Russian language button was not selected");
runtime.MacCoffeeSite.setWakeState(true);
assert.equal(attributes.get("demo:data-wake-active"), "true", "Wake demo did not activate");
await runtime.MacCoffeeSite.copyCode({ dataset: { copy: "#code" }, querySelector: () => ({ textContent: "" }) });
assert.equal(clipboardText, "maccoffee_set_session", "Code was not copied");

for (const token of ["maccoffee-language", "navigator.clipboard", "IntersectionObserver", "MacCoffeeTranslations"]) {
  assert.ok(script.includes(token), `Missing script contract ${token}`);
}

assert.ok(!html.includes("<script>"), "Inline JavaScript is forbidden");
assert.ok(!html.includes("http://"), "Insecure HTTP URL is forbidden");

for (const metadata of [
  'property="og:title"',
  'property="og:description"',
  'property="og:image"',
  'name="twitter:card" content="summary_large_image"',
  'name="theme-color"',
]) {
  assert.ok(html.includes(metadata), `Missing metadata ${metadata}`);
}
assert.ok(existsSync(join(siteRoot, "assets/og.png")), "Missing social card");

const workflow = readFileSync(join(siteRoot, "../.github/workflows/pages.yml"), "utf8");
for (const token of ["pages: write", "id-token: write", "actions/upload-pages-artifact", "path: _site", "project-site decorate", "project-site validate", "actions/deploy-pages"]) {
  assert.ok(workflow.includes(token), `Missing Pages workflow contract ${token}`);
}
console.log(`Validated ${ids.length} IDs and ${new Set(keys).size} translation keys.`);
