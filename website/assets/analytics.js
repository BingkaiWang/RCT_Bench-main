const GA_MEASUREMENT_ID = "G-K7LEB65WYZ";

let ready = false;

export function initAnalytics() {
  if (!GA_MEASUREMENT_ID || GA_MEASUREMENT_ID === "G-XXXXXXXXXX") {
    return;
  }

  window.dataLayer = window.dataLayer || [];
  window.gtag = function gtag() {
    window.dataLayer.push(arguments);
  };

  const script = document.createElement("script");
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(GA_MEASUREMENT_ID)}`;
  document.head.append(script);

  window.gtag("js", new Date());
  window.gtag("config", GA_MEASUREMENT_ID, {
    anonymize_ip: true,
    page_title: document.title,
    page_path: window.location.pathname,
  });
  ready = true;
}

export function trackEvent(name, params = {}) {
  if (!ready || typeof window.gtag !== "function") {
    return;
  }
  window.gtag("event", name, params);
}
