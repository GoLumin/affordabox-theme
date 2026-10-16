#!/usr/bin/env ruby
# frozen_string_literal: true

# Puts the landing pages' block types in the CMS (script/landing.rb), adds
# the "Button goes to" field to Dumpster sizes and the "Layout" field to the
# landing pages, and creates the pages as drafts (an existing one is updated
# and keeps its status). Needs the theme release that draws them.
#
#   CMS_PROFILE=<profile> ruby script/landing_pages.rb
require_relative "cms_client"
require_relative "landing"

def cms(...) = CmsClient.call(...)

puts "Block types"
Landing::BLOCK_TYPES.each do |type|
  CmsClient.upsert("/block_types/#{type[:slug]}", "block_type", {"slug" => type[:slug], "label" => type[:label], "description" => type[:description],
    "category" => "Affordabox", "icon" => type[:icon], "fields" => type[:fields], "defaults" => type[:defaults] || {}}, create_path: "/block_types")
  puts "  #{type[:slug]}"
end
sizes = cms(:get, "/block_types/dumpster_sizes")["block_type"]
unless sizes["fields"].any? { it["name"] == "button_target" }
  cms(:patch, "/block_types/dumpster_sizes", {"block_type" => {"fields" => sizes["fields"] + [Landing::BUTTON_TARGET_FIELD]}})
  puts "  dumpster_sizes: + button_target"
end

puts "Pages"
Landing::PAGES.each do |path, spec|
  attributes = {"slug" => path, "title" => spec[:title], "locale" => "en", "blocks" => spec[:blocks], "seo" => spec[:seo]}
  if cms(:get, "/pages/#{path}", missing_ok: true)
    cms(:patch, "/pages/#{path}", {"page" => attributes})
  else
    cms(:post, "/pages", {"page" => attributes.merge("status" => "draft")})
  end
  fields = cms(:get, "/pages/home/schema", missing_ok: true)&.dig("page", "fields") || []
  fields = fields.reject { it["name"] == "layout" } + [Landing::LAYOUT_FIELD]
  cms(:patch, "/pages/#{path}/schema", {"page" => {"fields" => fields}})
  cms(:patch, "/pages/#{path}", {"page" => {"frontmatter" => spec[:frontmatter]}})
  puts "  /#{path}"
end
