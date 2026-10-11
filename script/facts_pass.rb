#!/usr/bin/env ruby
# frozen_string_literal: true

# Applies the fact corrections (facts.rb) to what's in the CMS: pages,
# entries, the globals and the lead form's confirmation email.
#
#   CMS_PROFILE=localhost ruby script/facts_pass.rb
#
# With the Approvals plugin on, a record may already have a change waiting.
# This builds on that change (its payload), not on what's live, so the new
# request carries both: approving the newest request for a record is enough.
require_relative "cms_client"
require_relative "facts"

def cms(...) = CmsClient.call(...)

PENDING = cms(:get, "/approvals", missing_ok: true).to_h.fetch("approvals", []).select { it["state"] == "pending" }
  .group_by { [it.dig("subject", "type"), it.dig("subject", "id")] }
  .transform_values { |list| cms(:get, "/approvals/#{list.max_by { it["id"] }["id"]}")["payload"] || {} }
queued = 0
submit = lambda do |path, wrapper, attributes|
  answer = cms(:patch, path, {wrapper => attributes})
  queued += 1 if answer.is_a?(Hash) && answer["status"] == "pending_approval"
end

puts "Pages"
cms(:get, "/pages?per=200")["pages"].each do |summary|
  page = cms(:get, "/pages/#{summary["path"]}")["page"]
  base = PENDING.fetch(["Page", page["id"]], {})
  blocks, seo = base["blocks"] || page["blocks"], base["seo"] || page["seo"]
  fixed_blocks, fixed_seo = fix_facts(blocks), fix_facts(seo)
  next if fixed_blocks == page["blocks"] && fixed_seo == page["seo"] && base.empty?
  next if fixed_blocks == blocks && fixed_seo == seo # nothing new beyond what's queued

  submit.("/pages/#{page["path"]}", "page", {"blocks" => fixed_blocks, "seo" => fixed_seo})
  puts "  /#{page["path"]}"
end

puts "Entries"
cms(:get, "/collections")["collections"].each do |collection|
  slug = collection["slug"]
  cms(:get, "/collections/#{slug}/entries?per=200")["entries"].each do |summary|
    entry = cms(:get, "/collections/#{slug}/entries/#{summary["slug"]}")["entry"]
    base = PENDING.fetch(["CollectionEntry", entry["id"]], {})
    frontmatter, seo = base["frontmatter"] || entry["frontmatter"], base["seo"] || entry["seo"]
    fixed = fix_facts(frontmatter)
    fixed = fixed.merge(FACILITY_GEO.fetch(entry["slug"], {})) if slug == "facilities"
    next if fixed == frontmatter

    submit.("/collections/#{slug}/entries/#{entry["slug"]}", "entry", {"frontmatter" => fixed, "seo" => seo})
    puts "  #{slug}/#{entry["slug"]}"
  end
end

puts "Globals"
%w[site_settings nav footer].each do |slug|
  global = cms(:get, "/globals/#{slug}")["global"]
  data = PENDING.dig(["Global", global["id"]], "data") || global["data"]
  fixed = fix_facts(data)
  next if fixed == data

  submit.("/globals/#{slug}", "global", {"data" => fixed})
  puts "  #{slug}"
end

puts "Emails"
%w[notification confirmation].each do |kind|
  email = cms(:get, "/forms/lead/emails/#{kind}", missing_ok: true)&.dig("email") or next
  fixed = fix_facts(email["blocks"])
  cms(:patch, "/forms/lead/emails/#{kind}", {"form_email" => {"blocks" => fixed}}) unless fixed == email["blocks"]
end

puts queued.positive? ? "Done: #{queued} requests wait in Approvals (each includes any change already queued for its record)." : "Done."
