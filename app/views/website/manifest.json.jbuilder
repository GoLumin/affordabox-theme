# frozen_string_literal: true

# The site as an app on a home screen.
json.name website_settings["title"].presence || "Affordabox"
json.short_name "Affordabox"
json.start_url "/"
json.display "standalone"
json.theme_color "#061b23"
json.background_color "#ffffff"
json.icons [{src: asset_path("affordabox/favicon.svg"), sizes: "any", type: "image/svg+xml"}]
