// The 3-D quote pages: loads the configurator for the block's product
// (configurator_dumpsters, _portable_storage, _shipping_containers).
const root = document.querySelector("[data-configurator]")
if (root) import(`affordabox/configurator_${root.dataset.configurator.replace(/-/g, "_")}`)
