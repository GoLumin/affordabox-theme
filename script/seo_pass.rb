#!/usr/bin/env ruby
# frozen_string_literal: true

# The content fixes from the SEO audit and the fact check (2026-10), applied
# to what's in the CMS without re-running the whole import:
# - each page's title, description and H1 (seo_copy.rb);
# - the fact corrections (facts.rb) in pages, entries, globals and emails;
# - the city entries as web pages, the other collections' entries out of
#   the sitemap (they have no pages), the facilities' coordinates;
# - the photos' alt text, and the site's name, description, logo and
#   favicon (Settings › General and Branding).
#
#   CMS_PROFILE=localhost ruby script/seo_pass.rb
#
# With the Approvals plugin on, a record holds one waiting change, which a
# new one replaces: each change here starts from the waiting one, so nothing
# queued before is lost.
require_relative "cms_client"
require_relative "seo_copy"
require_relative "facts"

ROOT = File.expand_path("..", __dir__)
STATE = JSON.parse(File.read(ENV.fetch("IMPORT_STATE", File.join(ROOT, "tmp/redesign_import.json"))))
def cms(...) = CmsClient.call(...)

PENDING = cms(:get, "/approvals", missing_ok: true).to_h.fetch("approvals", []).select { it["state"] == "pending" }
  .group_by { [it.dig("subject", "type"), it.dig("subject", "id")] }
  .transform_values do |list|
    answer = cms(:get, "/approvals/#{list.max_by { it["id"] }["id"]}")
    (answer["approval"] || answer)["payload"] || {}
  end
queued = 0
submit = lambda do |path, wrapper, attributes|
  answer = cms(:patch, path, {wrapper => attributes})
  queued += 1 if answer.is_a?(Hash) && answer["status"] == "pending_approval"
end

puts "Pages"
cms(:get, "/pages?per=200")["pages"].each do |summary|
  page = cms(:get, "/pages/#{summary["path"]}")["page"]
  base = PENDING.fetch(["Page", page["id"]], {})
  blocks = JSON.parse(JSON.generate(base["blocks"] || page["blocks"]))
  seo = (base["seo"] || page["seo"]).to_h
  if (copy = SEO_COPY[page["path"]])
    seo = seo.merge("meta_title" => copy[:title], "meta_description" => copy[:description])
    blocks.each { it["data"]["heading"] = copy[:h1] if it["type"] == "page_hero" && copy[:h1] }
  end
  blocks, seo = fix_facts(blocks), fix_facts(seo)
  next if blocks == page["blocks"] && seo == page["seo"].to_h

  submit.("/pages/#{page["path"]}", "page", {"blocks" => blocks, "seo" => seo})
  puts "  /#{page["path"]}"
end

puts "Entries"
cms(:get, "/collections")["collections"].each do |collection|
  slug = collection["slug"]
  changed = 0
  cms(:get, "/collections/#{slug}/entries?per=200")["entries"].each do |summary|
    entry = cms(:get, "/collections/#{slug}/entries/#{summary["slug"]}")["entry"]
    base = PENDING.fetch(["CollectionEntry", entry["id"]], {})
    frontmatter = fix_facts(base["frontmatter"] || entry["frontmatter"])
    frontmatter = frontmatter.merge(FACILITY_GEO.fetch(entry["slug"], {})) if slug == "facilities"
    seo = (base["seo"] || entry["seo"]).to_h.merge(slug == "locations" ? {"schema_type" => "WebPage", "noindex" => false} : {"noindex" => true})
    next if frontmatter == entry["frontmatter"] && seo == entry["seo"].to_h

    submit.("/collections/#{slug}/entries/#{entry["slug"]}", "entry", {"frontmatter" => frontmatter, "seo" => seo})
    changed += 1
  end
  puts "  #{slug}: #{changed}"
end

puts "Globals"
%w[site_settings nav footer].each do |slug|
  global = cms(:get, "/globals/#{slug}")["global"]
  data = fix_facts(PENDING.dig(["Global", global["id"]], "data") || global["data"])
  next if data == global["data"]

  submit.("/globals/#{slug}", "global", {"data" => data})
  puts "  #{slug}"
end

puts "Emails, alt text, settings"
%w[notification confirmation].each do |kind|
  email = cms(:get, "/forms/lead/emails/#{kind}", missing_ok: true)&.dig("email") or next
  fixed = fix_facts(email["blocks"])
  cms(:patch, "/forms/lead/emails/#{kind}", {"form_email" => {"blocks" => fixed}}) unless fixed == email["blocks"]
end
ALTS.each { |path, alt| (id = STATE["assets"][path]) && cms(:patch, "/assets/#{id}", {"asset" => {"alt" => alt}}) }
cms(:patch, "/settings/general", {"setting" => {"data" => {"title" => "AffordABox",
  "description" => "Dumpsters, shipping containers, portable storage and self-storage across Minnesota's NW Twin Cities metro and Wright County."}}})
logo, favicon = STATE["assets"].values_at("general/logo/logo.png", "general/logo/favicon.png")
cms(:patch, "/settings/branding", {"setting" => {"data" => {"logo_id" => logo, "favicon_id" => favicon}.compact}})

puts queued.positive? ? "Done: #{queued} changes wait in Approvals (one per record, including anything queued before)." : "Done."
