(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const translations = globalThis.MacCoffeeTranslations;
  const storageKey = "maccoffee-language";

  const activeLanguage = () => {
    const language = document.documentElement.lang;
    return translations[language] ? language : "en";
  };

  const setLanguage = (language) => {
    const selected = translations[language] ? language : "en";
    const dictionary = translations[selected];

    document.documentElement.lang = selected;
    document.querySelectorAll("[data-i18n]").forEach((node) => {
      const value = dictionary[node.dataset.i18n];
      if (typeof value === "string") node.textContent = value;
    });
    document.querySelectorAll("[data-i18n-aria]").forEach((node) => {
      const value = dictionary[node.dataset.i18nAria];
      if (typeof value === "string") node.setAttribute("aria-label", value);
    });
    document.querySelectorAll("[data-language]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.language === selected));
    });

    try {
      localStorage.setItem(storageKey, selected);
    } catch {
      // Language selection still works when browser storage is unavailable.
    }
  };

  const setWakeState = (active) => {
    document.querySelector("#wake-demo")?.setAttribute("data-wake-active", String(active));
    document.querySelector("#wake-toggle")?.setAttribute("aria-pressed", String(active));
  };

  const selectForManualCopy = (node) => {
    if (!globalThis.getSelection || !document.createRange) return;
    const selection = globalThis.getSelection();
    const range = document.createRange();
    range.selectNodeContents(node);
    selection?.removeAllRanges();
    selection?.addRange(range);
  };

  const copyCode = async (button) => {
    const target = document.querySelector(button.dataset.copy);
    if (!target) return;

    const dictionary = translations[activeLanguage()];
    const status = document.querySelector("#copy-status");
    const label = button.querySelector("[data-copy-label]");

    try {
      await navigator.clipboard.writeText(target.innerText);
      if (status) status.textContent = dictionary.copySuccess;
      if (label) label.textContent = dictionary.copied;
      setTimeout(() => {
        if (label) label.textContent = translations[activeLanguage()].copy;
      }, 1600);
    } catch {
      selectForManualCopy(target);
      if (status) status.textContent = dictionary.copyFailure;
    }
  };

  globalThis.MacCoffeeSite = Object.freeze({ setLanguage, setWakeState, copyCode });

  document.addEventListener("DOMContentLoaded", () => {
    let storedLanguage = "en";
    try {
      storedLanguage = localStorage.getItem(storageKey) || "en";
    } catch {
      storedLanguage = "en";
    }
    setLanguage(storedLanguage);

    document.querySelectorAll("[data-language]").forEach((button) => {
      button.addEventListener("click", () => setLanguage(button.dataset.language));
    });

    const wakeToggle = document.querySelector("#wake-toggle");
    wakeToggle?.addEventListener("click", () => {
      const nextState = wakeToggle.getAttribute("aria-pressed") !== "true";
      setWakeState(nextState);
    });

    document.querySelectorAll("[data-copy]").forEach((button) => {
      button.addEventListener("click", () => copyCode(button));
    });

    const revealNodes = document.querySelectorAll("[data-reveal]");
    const reduceMotion = globalThis.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

    if (!("IntersectionObserver" in globalThis) || reduceMotion) {
      revealNodes.forEach((node) => node.classList.add("is-visible"));
      return;
    }

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -8%", threshold: 0.08 });

    revealNodes.forEach((node) => observer.observe(node));
  });
})();
