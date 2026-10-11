// The 3-step free-quote form (LeadForm.svelte): ZIP and service, what it's
// for, then name and phone. The ZIP is checked against the cities served;
// the service, project, phone and email can come from the address
// (/get-a-quote?service=Dumpster&use=Roofing). It posts to the Forms plugin
// without leaving the page, then goes to the thank-you page.
import { readAttribution } from "affordabox/attribution"

// Cloudflare Turnstile, when Settings › Forms has it: drawn when the form's
// last step opens (it can't draw inside a hidden step), once per form.
// The script loads with render=explicit, so it waits until then.
function renderTurnstile(form) {
  const widget = form.querySelector("[data-lead-turnstile]")
  if (!widget || widget.dataset.widgetId) return
  if (!window.turnstile) {
    widget.dataset.waiting = "1"
    return setTimeout(() => renderTurnstile(form), 250)
  }
  widget.dataset.widgetId = window.turnstile.render(widget, {
    sitekey: widget.dataset.sitekey,
    theme: widget.dataset.theme || "light",
    size: "flexible",
  })
}

const FALLBACK = "Something went wrong. Please call us and we'll help right away."
const MESSAGES = {
  captcha_failed: "Please complete the verification.",
  rate_limited: "Too many tries. Please wait a few minutes and try again.",
}

function setup(form) {
  const card = form.closest("[aria-live]") || form.parentElement
  const steps = [...form.querySelectorAll("[data-lead-step]")]
  const error = form.querySelector("[data-lead-error]")
  const zip = form.querySelector("[data-lead-zip]")
  const service = form.querySelector("[data-lead-service]")
  const areas = JSON.parse(form.dataset.areas || "{}")
  const hidden = (name) => form.querySelector(`[data-lead-hidden="${name}"]`)
  let step = 1

  const fail = (message) => {
    error.textContent = message
    error.hidden = !message
  }

  const show = (n) => {
    step = n
    steps.forEach((el) => { el.hidden = Number(el.dataset.leadStep) !== n })
    card.querySelectorAll("[data-lead-progress]").forEach((bar) => {
      const on = Number(bar.dataset.leadProgress) <= n
      bar.classList.toggle("bg-brand-500", on)
      bar.classList.toggle("bg-neutral-200", !on)
    })
    const label = card.querySelector("[data-lead-step-label]")
    if (label) label.textContent = `Step ${n} of 3`
    fail("")
    if (n === 3) renderTurnstile(form)
  }

  const checkZip = () => {
    const value = zip.value.trim()
    const valid = /^\d{5}$/.test(value)
    const city = valid ? areas[value] : undefined
    const inArea = form.querySelector("[data-lead-in-area]")
    inArea.hidden = !(valid && city)
    inArea.textContent = city ? `✓ Yes! We serve ${city}.` : ""
    form.querySelector("[data-lead-out-area]").hidden = !(valid && !city)
    hidden("city").value = city || form.dataset.city || ""
    hidden("in_area").value = valid ? (city ? "yes" : "no") : ""
    return valid
  }

  // From the address: ?service=…&use=…&phone=…&email=…
  const params = new URLSearchParams(window.location.search)
  const wanted = params.get("service")
  if (wanted && [...service.options].some((o) => o.value === wanted)) service.value = wanted
  const phone = form.querySelector("[data-lead-phone]")
  const email = form.querySelector("[data-lead-email]")
  if (params.get("phone") && phone) phone.value = params.get("phone")
  if (params.get("email") && email) email.value = params.get("email")

  form.querySelectorAll("[data-lead-use]").forEach((pill) => {
    pill.addEventListener("click", () => {
      form.querySelectorAll("[data-lead-use]").forEach((other) => other.setAttribute("aria-pressed", String(other === pill)))
      hidden("use_case").value = pill.dataset.leadUse
    })
    if (params.get("use") === pill.dataset.leadUse) pill.click()
  })
  if (params.get("use") && !hidden("use_case").value) hidden("use_case").value = params.get("use")

  zip.addEventListener("input", checkZip)
  checkZip()

  form.querySelectorAll("[data-lead-next]").forEach((button) => button.addEventListener("click", () => {
    if (step === 1) {
      if (!checkZip()) return fail("Please enter a 5-digit ZIP code.")
      if (!service.value) return fail("Please choose a service.")
    }
    show(Math.min(step + 1, 3))
  }))
  form.querySelectorAll("[data-lead-back]").forEach((button) => button.addEventListener("click", () => show(Math.max(step - 1, 1))))

  form.addEventListener("submit", async (event) => {
    event.preventDefault()
    if (step < 3) return
    const data = new FormData(form)
    const done = () => {
      window.gtag?.("event", "quote_complete", { service: service.value })
      window.location.href = form.dataset.redirect || "/thank-you"
    }
    if (!String(data.get("first_name") || "").trim()) return fail("Please enter your name.")
    if (String(data.get("phone") || "").replace(/\D/g, "").length < 7) return fail("Please enter a valid phone number.")
    const widget = form.querySelector(".cf-turnstile")
    if (widget && !data.get("cf-turnstile-response")) return fail("Please complete the verification.")

    const attribution = readAttribution()
    for (const [name, value] of Object.entries(attribution)) {
      const input = hidden(name)
      if (input) { input.value = value; data.set(name, value) }
    }
    // A bot filled the hidden field: pretend it worked.
    if (String(data.get(form.dataset.honeypot) ?? "").trim()) return done()

    const submit = form.querySelector('button[type="submit"]')
    const label = submit.textContent
    submit.disabled = true
    submit.textContent = submit.dataset.busyLabel || label
    try {
      const response = await fetch(form.action, { method: "POST", body: data, headers: { Accept: "application/json" } })
      const body = await response.json().catch(() => ({}))
      if (response.ok) return done()
      fail(MESSAGES[body.error] ?? (body.errors ? "Please check the form and try again." : FALLBACK))
    } catch {
      fail(FALLBACK)
    }
    submit.disabled = false
    submit.textContent = label
    if (widget?.dataset.widgetId) window.turnstile?.reset(widget.dataset.widgetId)
  })
}

document.querySelectorAll("form[data-lead-form]").forEach(setup)
