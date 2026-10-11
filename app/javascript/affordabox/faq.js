// FAQ answers open and close under their questions (Faq.astro).
document.querySelectorAll("[data-faq-toggle]").forEach((button) => {
  button.addEventListener("click", () => {
    const answer = document.getElementById(button.getAttribute("aria-controls"))
    const open = button.getAttribute("aria-expanded") !== "true"
    button.setAttribute("aria-expanded", String(open))
    answer.style.maxHeight = open ? `${answer.scrollHeight}px` : "0"
  })
})
