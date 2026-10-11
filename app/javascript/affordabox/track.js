// Google Analytics, when the scripts global loads it (gtag): a click on
// anything marked data-track sends that event, and the thank-you page sends
// its conversion. The home page's video stays on its poster for visitors who
// ask for less motion.
const gtag = (...args) => window.gtag?.(...args)

document.addEventListener("click", (event) => {
  const el = event.target.closest("[data-track]")
  if (el) gtag("event", el.dataset.track, { location: window.location.pathname })
})

document.querySelectorAll("[data-gtag-event]").forEach((el) => gtag("event", el.dataset.gtagEvent, { value: 1 }))

if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  document.querySelectorAll("[data-hero-video]").forEach((video) => {
    video.removeAttribute("autoplay")
    video.pause()
  })
}
