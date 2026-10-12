// The website's scripts, loaded as modules from the theme's own importmap
// (Website.theme.importmap): nothing is bundled, and none of the admin's.
import "affordabox/attribution"
import "affordabox/nav"
import "affordabox/lead_form"
import "affordabox/exit_modal"
import "affordabox/track"

// Landing pages: buttons that go up to the page's own form.
if (document.querySelector("[data-lead-prefill], [data-zip-check]")) import("affordabox/landing")

// The 3-D quote pages' WebGL, only where there's one.
if (document.querySelector("[data-configurator]")) import("affordabox/configurator")
