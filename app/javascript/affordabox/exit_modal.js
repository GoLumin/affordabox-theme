// The exit-intent popup (ExitModal.astro): on desktop only, once a visit,
// when the pointer leaves through the top of the window. Sending it goes to
// the quote page with the phone (and email) filled in.
const modal = document.querySelector("[data-exit-modal]")

if (modal) {
  let shown = false
  const show = () => {
    if (shown || sessionStorage.getItem("exitModalShown")) return
    if (window.matchMedia("(max-width: 767px)").matches) return
    modal.classList.remove("hidden")
    shown = true
    sessionStorage.setItem("exitModalShown", "true")
    document.body.style.overflow = "hidden"
    modal.querySelector("input")?.focus()
  }
  const hide = () => {
    modal.classList.add("hidden")
    document.body.style.overflow = ""
  }

  document.addEventListener("mouseout", (event) => {
    if (event.clientY < 10 && !event.relatedTarget) show()
  })
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") hide()
  })
  modal.querySelectorAll("[data-exit-close]").forEach((el) => el.addEventListener("click", hide))
  modal.querySelector("[data-exit-form]")?.addEventListener("submit", (event) => {
    event.preventDefault()
    const data = new FormData(event.currentTarget)
    const params = new URLSearchParams()
    for (const name of ["phone", "email"]) if (data.get(name)) params.set(name, data.get(name))
    hide()
    window.location.href = `${modal.dataset.href}${params.size ? `?${params}` : ""}`
  })
}
