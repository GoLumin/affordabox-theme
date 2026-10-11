// The header's menu on phones (PrimaryNav.astro): the button opens and
// closes it; following a link closes it. The mega menus on wider screens
// open on hover and keyboard focus, in CSS.
const button = document.getElementById("mobile-menu-btn")
const menu = document.getElementById("mobile-menu")

const setOpen = (open) => {
  menu.classList.toggle("hidden", !open)
  button.querySelector(".menu-open")?.classList.toggle("hidden", open)
  button.querySelector(".menu-close")?.classList.toggle("hidden", !open)
  button.setAttribute("aria-expanded", String(open))
}

if (button && menu) {
  button.addEventListener("click", () => setOpen(menu.classList.contains("hidden")))
  menu.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => setOpen(false)))
}
