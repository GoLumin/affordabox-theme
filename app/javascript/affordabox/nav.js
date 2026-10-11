// The sidebar's menu on phones, the link for the page being shown, and the
// compact top bar's menus (Sidebar.astro and AlternativeNavbar.astro).
const mobileNav = document.getElementById("mobile-nav")
const menuToggle = document.getElementById("menu-toggle")
const toggleMenu = () => {
  const open = mobileNav.classList.toggle("-translate-x-full") === false
  menuToggle?.setAttribute("aria-expanded", String(open))
}
if (mobileNav) {
  menuToggle?.addEventListener("click", toggleMenu)
  document.getElementById("menu-close")?.addEventListener("click", toggleMenu)
}

const here = window.location.pathname
document.querySelectorAll(".nav-item, .mobile-nav-item").forEach((item) => {
  const link = item.dataset.link
  if (!link || link === "#") return
  if (here === link || (link !== "/" && here.startsWith(link))) item.classList.add("bg-[#05171E]")
})

const compactToggle = document.getElementById("mobile-menu-toggle")
const compactMenu = document.getElementById("compact-menu")
compactToggle?.addEventListener("click", () => {
  const open = !compactMenu.classList.toggle("hidden")
  compactToggle.setAttribute("aria-expanded", String(open))
})

const moreToggle = document.getElementById("desktop-more-toggle")
const moreMenu = document.getElementById("desktop-more-menu")
if (moreToggle && moreMenu) {
  const setMore = (open) => {
    moreToggle.setAttribute("aria-expanded", String(open))
    moreMenu.classList.toggle("opacity-0", !open)
    moreMenu.classList.toggle("invisible", !open)
    moreMenu.classList.toggle("-translate-y-2", !open)
    moreMenu.classList.toggle("opacity-100", open)
    moreMenu.classList.toggle("visible", open)
    moreMenu.classList.toggle("translate-y-0", open)
    moreToggle.querySelector("svg")?.classList.toggle("rotate-180", open)
  }
  moreToggle.addEventListener("click", (event) => {
    event.preventDefault()
    event.stopPropagation()
    setMore(moreToggle.getAttribute("aria-expanded") !== "true")
  })
  document.addEventListener("click", (event) => {
    if (!moreToggle.contains(event.target) && !moreMenu.contains(event.target)) setMore(false)
  })
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setMore(false)
  })
}
