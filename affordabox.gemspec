# frozen_string_literal: true

require_relative "lib/affordabox/version"

# The gemspec's name is the theme's key.
Gem::Specification.new do |spec|
  spec.name = "affordabox"
  spec.version = Affordabox::VERSION
  spec.summary = "The affordabox.com website, as a Libre Publish theme"
  spec.authors = ["Lumin"]
  spec.homepage = "https://github.com/GoLumin/affordabox-theme"
  spec.files = Dir["{app,config,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
