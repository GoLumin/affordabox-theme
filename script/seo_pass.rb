#!/usr/bin/env ruby
# frozen_string_literal: true

# The SEO audit's content fixes (2026-10), applied to what's in the CMS
# without re-running the whole import: each page's title, description and
# H1 (seo_copy.rb); the city entries as web pages and the other collections'
# entries out of the sitemap (they have no pages); the photos' alt text; the
# site's name, description, logo and favicon (Settings › General and
# Branding, which the CMS's Organization structured data reads).
#
#   CMS_PROFILE=localhost ruby script/seo_pass.rb
#
# With the Approvals plugin on, each page and entry change waits there.
require_relative "cms_client"
require_relative "seo_copy"

ROOT = File.expand_path("..", __dir__)
STATE = JSON.parse(File.read(ENV.fetch("IMPORT_STATE", File.join(ROOT, "tmp/redesign_import.json"))))
def cms(...) = CmsClient.call(...)
pending = 0
count = ->(answer) { pending += 1 if answer.is_a?(Hash) && answer["status"] == "pending_approval" }

puts "Pages"
SEO_COPY.each do |path, copy|
  page = cms(:get, "/pages/#{path}", missing_ok: true)&.dig("page") or next
  seo = page["seo"].to_h.merge("meta_title" => copy[:title], "meta_description" => copy[:description])
  blocks = page["blocks"]
  blocks.each { it["data"]["heading"] = copy[:h1] if it["type"] == "page_hero" && copy[:h1] }
  next if seo == page["seo"] && !copy[:h1]

  count.(cms(:patch, "/pages/#{path}", {"page" => {"seo" => seo, "blocks" => blocks}}))
  puts "  /#{path}"
end

puts "Entries"
cms(:get, "/collections")["collections"].each do |collection|
  slug = collection["slug"]
  cms(:get, "/collections/#{slug}/entries?per=200")["entries"].each do |entry|
    record = cms(:get, "/collections/#{slug}/entries/#{entry["slug"]}")["entry"]
    wanted = slug == "locations" ? {"schema_type" => "WebPage", "noindex" => false} : {"noindex" => true}
    seo = record["seo"].to_h.merge(wanted)
    next if seo == record["seo"].to_h

    count.(cms(:patch, "/collections/#{slug}/entries/#{entry["slug"]}", {"entry" => {"seo" => seo}}))
  end
  puts "  #{slug}"
end

puts "Alt text"
ALTS.each do |path, alt|
  id = STATE["assets"][path] or next
  cms(:patch, "/assets/#{id}", {"asset" => {"alt" => alt}})
end

puts "Settings"
cms(:patch, "/settings/general", {"setting" => {"data" => {"title" => "AffordABox",
  "description" => "Dumpsters, shipping containers, portable storage and self-storage across Minnesota's NW Twin Cities metro and Wright County."}}})
logo, favicon = STATE["assets"].values_at("general/logo/logo.png", "general/logo/favicon.png")
cms(:patch, "/settings/branding", {"setting" => {"data" => {"logo_id" => logo, "favicon_id" => favicon}.compact}})

puts pending.positive? ? "Done: #{pending} changes wait in Approvals." : "Done."
