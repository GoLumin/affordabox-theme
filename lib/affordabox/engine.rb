# frozen_string_literal: true

module Affordabox
  # A theme is an engine like a plugin: its views and helpers join the app's,
  # its assets join Propshaft's load path (app/assets/*/affordabox, so they
  # never collide with the admin's), and it registers with Website, which
  # turns the public site on. Its scripts get an importmap of their own
  # (config/importmap.rb), so the admin's never reach a visitor.
  class Engine < ::Rails::Engine
    initializer "affordabox.assets", before: "importmap" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    config.to_prepare do
      # A plugin too, so Settings › Plugins installs it from its GitHub
      # release, updates it, and switches the site on and off.
      Cms::Plugins.register :affordabox, name: "Affordabox", version: Affordabox::VERSION,
        description: "The affordabox.com website, as a theme: switch it off and the CMS is headless.",
        author: "Lumin", enabled_by_default: true, requires: ">= 1.18",
        homepage: "https://github.com/GoLumin/affordabox-theme"
      Website.register :affordabox, name: "Affordabox", version: Affordabox::VERSION,
        views: Affordabox::Engine.root.join("app/views"),
        importmap: Importmap::Map.new.draw(Affordabox::Engine.root.join("config/importmap.rb"))
    end
  end
end
