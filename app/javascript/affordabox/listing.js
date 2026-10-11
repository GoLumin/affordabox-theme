// The container listing (StorageContainers.astro): ticking filters narrows
// the cards (any of a group's values, every group) and puts them in the
// address so a filtered list can be linked to; "Show more" shows the next
// ten; the sidebar's reasons slide by on their own.
document.querySelectorAll("[data-listing]").forEach((listing) => {
  const grid = listing.querySelector("[data-listing-grid]")
  const cards = [...listing.querySelectorAll(".product-card")]
  const filters = [...listing.querySelectorAll("[data-listing-filter]")]
  const more = listing.querySelector("[data-listing-more]")
  const batch = Number(grid?.dataset.batchCount || 10)
  let visible = Number(grid?.dataset.initialCount || 10)

  const matches = (card, chosen) => Object.entries(chosen).every(([name, values]) => {
    const own = name === "category" ? (card.dataset.category || "").split("|") : [card.dataset[name]]
    return values.some((value) => own.includes(value))
  })

  const apply = () => {
    const chosen = {}
    filters.filter((input) => input.checked).forEach((input) => (chosen[input.name] ||= []).push(input.value))
    cards.forEach((card) => { card.style.display = matches(card, chosen) ? "block" : "none" })
    return chosen
  }

  const params = new URLSearchParams(window.location.search)
  filters.forEach((input) => {
    if ((params.get(input.name) || "").split(",").includes(input.value)) input.checked = true
    input.addEventListener("change", () => {
      const chosen = apply()
      const query = new URLSearchParams(Object.entries(chosen).map(([name, values]) => [name, values.join(",")]))
      const address = query.toString() ? `${window.location.pathname}?${query}` : window.location.pathname
      window.history.pushState({}, "", address)
    })
  })
  apply()

  more?.addEventListener("click", () => {
    const shown = cards.filter((card) => card.style.display !== "none")
    shown.slice(visible, visible + batch).forEach((card) => card.classList.remove("hidden"))
    visible += batch
    if (shown.length <= visible) more.style.display = "none"
  })

  const track = listing.querySelector("[data-reasons-track]")
  const dots = [...listing.querySelectorAll("[data-reasons-dot]")]
  if (track && dots.length > 1) {
    let current = 0
    const go = (index) => {
      current = (index + dots.length) % dots.length
      track.style.transform = `translateX(-${current * 100}%)`
      dots.forEach((dot, i) => {
        dot.classList.toggle("bg-gray-800", i === current)
        dot.classList.toggle("bg-gray-300", i !== current)
      })
    }
    dots.forEach((dot, index) => dot.addEventListener("click", () => go(index)))
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) setInterval(() => go(current + 1), 4000)
  }
})
