// A gallery's photos open full size in its viewer: the arrows and the
// keyboard step through them, Escape or a click outside the photo closes it
// (Gallery.astro, ImageGallery.astro).
document.querySelectorAll("[data-gallery]").forEach((gallery) => {
  const items = [...gallery.querySelectorAll("[data-gallery-item]")]
  const box = gallery.querySelector("[data-lightbox]")
  if (!box || items.length === 0) return
  const image = box.querySelector("[data-lightbox-image]")
  const caption = box.querySelector("[data-lightbox-caption]")
  const close = box.querySelector("[data-lightbox-close]")
  let current = 0
  let opener = null

  const show = (index) => {
    current = (index + items.length) % items.length
    const img = items[current].querySelector("img")
    image.src = img.currentSrc || img.src
    image.alt = img.alt
    caption.textContent = items[current].dataset.caption || ""
  }
  const open = (index) => {
    opener = items[index]
    show(index)
    box.classList.remove("hidden")
    box.classList.add("flex")
    document.body.style.overflow = "hidden"
    close.focus()
  }
  const shut = () => {
    box.classList.add("hidden")
    box.classList.remove("flex")
    document.body.style.overflow = ""
    opener?.focus()
  }

  items.forEach((item, index) => {
    item.addEventListener("click", () => open(index))
    item.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        open(index)
      }
    })
  })
  close.addEventListener("click", shut)
  box.querySelector("[data-lightbox-prev]").addEventListener("click", () => show(current - 1))
  box.querySelector("[data-lightbox-next]").addEventListener("click", () => show(current + 1))
  box.addEventListener("click", (event) => {
    if (event.target === box) shut()
  })
  document.addEventListener("keydown", (event) => {
    if (box.classList.contains("hidden")) return
    if (event.key === "Escape") shut()
    if (event.key === "ArrowLeft") show(current - 1)
    if (event.key === "ArrowRight") show(current + 1)
  })
})
