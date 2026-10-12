// A landing page keeps people on it: buttons go up to its form (#quote)
// instead of to another page, and carry what was picked with them.
//
// A button marked data-lead-prefill="Size: 20 Yard dumpster" puts that in
// the form's "Anything else?" box (unless they've written there already).
// The ZIP check (lp_area) answers from the cities served and, when it's a
// yes, copies the ZIP into the form, so the form opens already checked.
const quoteForm = () => document.querySelector("#quote [data-lead-form]")

document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-lead-prefill]")
  if (!button) return
  const message = quoteForm()?.querySelector("textarea")
  if (message && !message.value.trim()) message.value = button.dataset.leadPrefill
})

document.querySelectorAll("[data-zip-check]").forEach((check) => {
  const areas = JSON.parse(check.dataset.areas || "{}")
  const input = check.querySelector("[data-zip-input]")
  const yes = check.querySelector("[data-zip-yes]")
  const no = check.querySelector("[data-zip-no]")
  const go = check.querySelector("[data-zip-go]")

  const answer = () => {
    const zip = input.value.trim()
    const valid = /^\d{5}$/.test(zip)
    const city = valid ? areas[zip] : undefined
    yes.textContent = city ? `✓ Yes! We deliver to ${city}.` : ""
    yes.hidden = !city
    no.hidden = !(valid && !city)
    go.hidden = !valid
    return valid
  }

  check.addEventListener("submit", (event) => {
    event.preventDefault()
    if (answer()) window.gtag?.("event", "zip_check", { in_area: areas[input.value.trim()] ? "yes" : "no" })
  })
  input.addEventListener("input", () => { if (input.value.trim().length === 5) answer() })

  go.addEventListener("click", () => {
    const zip = quoteForm()?.querySelector("[data-lead-zip]")
    if (!zip) return
    zip.value = input.value.trim()
    zip.dispatchEvent(new Event("input", { bubbles: true }))
  })
})
