// The website's scripts, loaded as modules from the theme's own importmap
// (Website.theme.importmap): nothing is bundled, and none of the admin's.
import "affordabox/attribution"
import "affordabox/nav"
import "affordabox/lead_form"
import "affordabox/exit_modal"
import "affordabox/track"

// The 3-D quote pages' WebGL, only where there's one.
if (document.querySelector("[data-configurator]")) import("affordabox/configurator")
