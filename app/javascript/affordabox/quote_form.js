// The quote form (QuoteForm.svelte in the Astro site): "What can we help you
// with?" shows that kind of request's questions, and only what's shown is
// sent. It posts to the Forms plugin without leaving the page and, once the
// CMS has it, goes to the thank-you page; otherwise each field's error
// shows beside it.
import { readAttribution } from "affordabox/attribution"

const FALLBACK = "Something went wrong on our end. Please try again, or give us a call and we'll take your details over the phone."
const MESSAGES = {
  captcha_failed: "Please complete the check and try again.",
  rate_limited: "Too many tries. Please wait a few minutes and try again.",
}
const SHIPPING_SERVICE = {
  "shipping-container-rentals": "shipping-container-rental",
  "shipping-container-sales": "shipping-container-sale",
}

function showSection(form) {
  const inquiry = form.querySelector('select[name="inquiry_type"]').value
  form.querySelectorAll("[data-section]").forEach((section) => {
    const active = section.dataset.section.split(" ").includes(inquiry)
    section.hidden = !active
    section.querySelectorAll("input, select, textarea").forEach((field) => { field.disabled = !active })
  })
  const shipping = form.querySelector("[data-shipping-service]")
  if (shipping) shipping.value = SHIPPING_SERVICE[inquiry] || ""
  showMoveOnly(form)
}

// Moving it somewhere else asks where to.
function showMoveOnly(form) {
  const service = form.querySelector('[data-section~="portable-storage"] select[name="service_type"]')
  const destination = form.querySelector("[data-move-only]")
  if (!service || !destination) return
  const shown = !service.disabled && service.value === "move-it"
  destination.hidden = !shown
  destination.querySelectorAll("input").forEach((input) => { input.disabled = !shown })
}

// The sizes ticked (dumpsters) or chosen (portable storage, containers), as
// the one field the CMS keeps.
function fillSizes(form) {
  const section = [...form.querySelectorAll("[data-section]")].find((s) => !s.hidden)
  const sizes = section
    ? [...section.querySelectorAll("[data-size-choice]:checked, [data-size-select]")].map((el) => el.value).filter(Boolean)
    : []
  form.querySelector("[data-sizes]").value = sizes.join(", ")
}

function fillAttribution(form) {
  const attribution = readAttribution()
  form.querySelectorAll("[data-attribution]").forEach((input) => { input.value = attribution[input.name] || "" })
}

function clearErrors(form) {
  form.querySelectorAll("[data-error-for]").forEach((el) => { el.hidden = true; el.textContent = "" })
  const status = form.querySelector("[data-form-status]")
  status.hidden = true
  status.textContent = ""
}

function showErrors(form, errors) {
  let first = null
  for (const [name, messages] of Object.entries(errors)) {
    const el = form.querySelector(`[data-error-for="${CSS.escape(name)}"]`)
    if (!el) continue
    el.textContent = [].concat(messages).map((message) => `This ${message}.`).join(" ")
    el.hidden = false
    first ||= form.querySelector(`[name="${CSS.escape(name)}"]:not([disabled])`)
  }
  first?.focus()
}

async function submit(event) {
  const form = event.currentTarget
  event.preventDefault()
  clearErrors(form)
  fillSizes(form)
  fillAttribution(form)

  const status = form.querySelector("[data-form-status]")
  const button = form.querySelector('button[type="submit"]')
  const data = new FormData(form)
  const done = () => { window.location.href = form.dataset.redirect || "/thank-you" }

  // A bot filled the hidden field: pretend it worked. (One that skips this script still posts it, and the CMS drops it.)
  if (String(data.get(form.dataset.honeypot) ?? "").trim()) return done()

  const label = button.textContent
  button.disabled = true
  button.textContent = button.dataset.busyLabel || label
  try {
    const response = await fetch(form.action, { method: "POST", body: data, headers: { Accept: "application/json" } })
    const body = await response.json().catch(() => ({}))
    // Left disabled: the page is on its way out.
    if (response.ok) return done()
    if (body.errors) showErrors(form, body.errors)
    status.textContent = MESSAGES[body.error] ?? (body.errors ? "Please check the highlighted fields." : FALLBACK)
    status.hidden = false
  } catch {
    status.textContent = FALLBACK
    status.hidden = false
  }
  button.disabled = false
  button.textContent = label
  // A Turnstile token is good once: the next try needs a fresh one.
  const widget = form.querySelector(".cf-turnstile")
  if (widget) window.turnstile?.reset(widget)
}

document.querySelectorAll("form[data-quote-form]").forEach((form) => {
  const inquiry = form.querySelector('select[name="inquiry_type"]')
  inquiry.addEventListener("change", () => showSection(form))
  form.querySelector('[data-section~="portable-storage"] select[name="service_type"]')?.addEventListener("change", () => showMoveOnly(form))
  form.addEventListener("submit", submit)
  showSection(form)
})
