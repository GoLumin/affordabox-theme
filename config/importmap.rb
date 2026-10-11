# frozen_string_literal: true

# The website's scripts (Website.theme.importmap), apart from the admin's.
pin "affordabox", to: "affordabox/site.js"
pin_all_from Affordabox::Engine.root.join("app/javascript/affordabox"), under: "affordabox", to: "affordabox"
