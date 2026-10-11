// The sliding rows: the top bar's icon links, the container cards and the
// reviews, with the settings the Astro site gave them (Swiper, vendored in
// affordabox/vendor/swiper.js by bin/css).
import Swiper from "affordabox/vendor/swiper"

const SETTINGS = {
  nav: () => ({
    slidesPerView: "auto",
    breakpoints: {
      320: { slidesPerView: 2, spaceBetween: 10 },
      640: { slidesPerView: 3, spaceBetween: 15 },
      768: { slidesPerView: 4, spaceBetween: 20 },
      1024: { slidesPerView: 5, spaceBetween: 20 },
    },
  }),
  cards: (el) => ({
    slidesPerView: "auto",
    spaceBetween: 20,
    pagination: { el: el.querySelector(".swiper-pagination"), clickable: true, dynamicBullets: true },
    autoplay: { delay: 2500, disableOnInteraction: false },
    breakpoints: {
      320: { slidesPerView: 1, spaceBetween: 10 },
      640: { slidesPerView: 2, spaceBetween: 15 },
      768: { slidesPerView: 3, spaceBetween: 20 },
      1024: { slidesPerView: 4, spaceBetween: 20 },
    },
  }),
  testimonials: (el) => ({
    loop: el.querySelectorAll(".swiper-slide").length > 1,
    spaceBetween: 30,
    speed: 1000,
    autoplay: { delay: 2500, disableOnInteraction: false },
    navigation: { nextEl: el.querySelector(".swiper-button-next"), prevEl: el.querySelector(".swiper-button-prev") },
  }),
}

const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches

document.querySelectorAll("[data-slider]").forEach((el) => {
  const settings = SETTINGS[el.dataset.slider]?.(el)
  if (!settings) return
  if (reduced) delete settings.autoplay
  new Swiper(el, settings)
})
