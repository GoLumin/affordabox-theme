# frozen_string_literal: true

namespace :affordabox do
  # The theme's spec draws every page from spec/fixtures/cms/snapshot.json.
  # This refreshes it from the CMS the site runs on, through the cms CLI
  # (CMS_PROFILE picks which), so a change to the content model there shows
  # up as a failing spec here before it shows up as a broken page. Pages and
  # entries are read whether they're live or drafts.
  desc "Refresh spec/fixtures/cms/snapshot.json from the CMS (the cms CLI; CMS_PROFILE)"
  task :snapshot do
    cms = ->(*args) { JSON.parse(IO.popen(["cms", *args, "--raw"], &:read).presence || abort("cms #{args.join(" ")} failed")) }
    keep = ->(record, *keys) { record.slice(*keys) }
    all = lambda do |path, key|
      (1..).lazy.map { |page| cms.("get", "#{path}#{path.include?("?") ? "&" : "?"}page=#{page}&per=100")[key] }.take_while(&:present?).flat_map(&:itself).to_a
    end

    pages = all.("/pages", "pages").map { cms.("get", "/pages/#{it["path"]}")["page"] }
    collections = cms.("collections")["collections"]
    entries = collections.flat_map do |collection|
      all.("/collections/#{collection["slug"]}/entries", "entries").map { cms.("get", "/collections/#{collection["slug"]}/entries/#{it["slug"]}")["entry"].merge("collection" => collection["slug"]) }
    end
    snapshot = {
      "block_types" => cms.("blocks")["block_types"].map { keep.(it, "slug", "label", "category", "version", "fields", "defaults") },
      "collections" => collections.map { keep.(it, "slug", "name", "enable_blocks", "schema") },
      "globals" => cms.("globals")["globals"].map { keep.(it, "slug", "name", "data", "fields") },
      "pages" => pages.map { keep.(it, "path", "slug", "title", "locale", "blocks", "frontmatter", "seo") },
      "entries" => entries.map { keep.(it, "collection", "slug", "title", "locale", "frontmatter", "body_markdown", "seo") },
      "forms" => cms.("forms")["forms"].map { keep.(it, "slug", "title", "fields", "submit_label", "success_message") },
      "site" => cms.("get", "/settings/general")["setting"]["data"].then { {"name" => it["title"], "description" => it["description"]} }
    }
    path = Affordabox::Engine.root.join("spec/fixtures/cms/snapshot.json")
    path.write(JSON.pretty_generate(snapshot))
    puts "#{path}: #{snapshot.transform_values(&:size).to_h}"
  end
end
