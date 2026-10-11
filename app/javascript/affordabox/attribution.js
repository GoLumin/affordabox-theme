// Ad click ids and campaign tags, caught on the page a visitor lands on and
// carried to whichever page they fill in the quote form on (src/lib/attribution.ts
// in the Astro site). The click id is only ever in that first address, so
// without this the lead reaches the ads app unattributable.
export const KEYS = ["gclid", "gbraid", "wbraid", "fbclid", "msclkid", "ttclid",
  "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content"]
const STORAGE_KEY = "affordabox:attribution"
const MAX = 200

function load() {
  try {
    const parsed = JSON.parse(sessionStorage.getItem(STORAGE_KEY) || "null")
    if (!parsed || typeof parsed !== "object") return {}
    return Object.fromEntries(Object.entries(parsed).filter(([, value]) => typeof value === "string"))
  } catch {
    return {}
  }
}

// Merges this address's parameters into what's kept. A later click id wins:
// the most recent click is the one that brought the visitor.
export function captureAttribution() {
  const stored = load()
  const params = new URLSearchParams(window.location.search)
  for (const key of KEYS) {
    const value = params.get(key)?.trim()
    if (value) stored[key] = value.slice(0, MAX)
  }
  // First touch only: where the visit started.
  if (!stored.landing_page) stored.landing_page = window.location.href.slice(0, MAX)
  if (!stored.referrer && document.referrer) stored.referrer = document.referrer.slice(0, MAX)
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(stored))
  } catch {
    // Storage denied (private browsing): the lead still goes through.
  }
  return stored
}

export function readAttribution() {
  return { ...captureAttribution(), page_url: window.location.href.slice(0, MAX) }
}

captureAttribution()
