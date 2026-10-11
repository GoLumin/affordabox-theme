#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves affordabox.com from Directus (cms.affordabox.com, what the Astro site
# in GoLumin/affordabox-marketing reads) into a Libre Publish CMS, in the
# shape this theme draws: its block types, the containers collection, the
# globals, the quote form and its emails, the files, and every page.
#
#   CMS_PROFILE=localhost ruby script/import_directus.rb
#
# It can run again: a block type, global, form, entry or page that's there
# is updated rather than doubled, and files already uploaded (kept in
# tmp/directus_import.json) aren't sent twice. Pages arrive as drafts, and a
# page that's already published is left as it is. Directus is only read.
require "json"
require "net/http"
require "uri"
require "fileutils"
require "securerandom"

DIRECTUS = ENV.fetch("DIRECTUS_URL", "https://cms.affordabox.com").chomp("/")
PROFILE = ENV.fetch("CMS_PROFILE", "default")
PROFILE_ENV = File.expand_path("~/.config/cms/#{PROFILE}.env")
CONFIG = File.exist?(PROFILE_ENV) ? File.read(PROFILE_ENV).scan(/^(?:export\s+)?(\w+)="?([^"\n]*)"?$/).to_h : {}
CMS = (ENV["CMS_URL"] || CONFIG["CMS_URL"] || abort("No CMS_URL: set CMS_PROFILE to a cms CLI profile")).chomp("/")
TOKEN = ENV["USER_AGENT_TOKEN"] || CONFIG["USER_AGENT_TOKEN"] || abort("No token in #{PROFILE_ENV}")
ROOT = File.expand_path("..", __dir__)
STATE_PATH = File.join(ROOT, "tmp/directus_import.json")
# The Astro repo, beside this one, for the few files it serves itself.
MARKETING = ENV.fetch("MARKETING_REPO", File.expand_path("../affordabox-marketing", ROOT))
OLD_HOSTS = %w[affordabox.com www.affordabox.com].freeze

# ----- HTTP -----

def request(method, url, body: nil, headers: {}, multipart: nil)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 30, read_timeout: 600) do |http|
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri, headers)
    if multipart
      boundary = "----affordabox#{SecureRandom.hex(12)}"
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = multipart_body(multipart, boundary)
    elsif body
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
    end
    http.request(req)
  end
end

def multipart_body(parts, boundary)
  parts.map do |name, value|
    if value.is_a?(Hash)
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"; filename=\"#{value[:filename].delete('"')}\"\r\n" \
        "Content-Type: #{value[:type]}\r\n\r\n".b + value[:data].b + "\r\n".b
    else
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n".b
    end
  end.join.b + "--#{boundary}--\r\n".b
end

def cms(method, path, body = nil, missing_ok: false, multipart: nil)
  res = request(method, "#{CMS}/api#{path}", body:, multipart:, headers: {"Authorization" => "Bearer #{TOKEN}", "Accept" => "application/json"})
  code = res.code.to_i
  return nil if missing_ok && code == 404
  abort "#{method.upcase} #{path} answered #{code}: #{res.body.to_s[0, 800]}" unless code.between?(200, 299)
  warn "  #{path} is waiting for approval (Approvals plugin)" if code == 202
  res.body.to_s.strip.empty? ? {} : JSON.parse(res.body)
end

def directus(path, params = {})
  res = request(:get, "#{DIRECTUS}#{path}?#{URI.encode_www_form(params)}")
  abort "Directus #{path} answered #{res.code}" unless res.code == "200"
  JSON.parse(res.body)["data"]
end

# ----- What's kept between runs -----

STATE = File.exist?(STATE_PATH) ? JSON.parse(File.read(STATE_PATH)) : {"assets" => {}}
def save_state
  FileUtils.mkdir_p(File.dirname(STATE_PATH))
  File.write(STATE_PATH, JSON.pretty_generate(STATE))
end

# ----- Reading Directus the way the Astro site does (src/lib/getPageData.ts) -----

def fields_from(spec, prefix = "")
  spec.flat_map do |field|
    field.is_a?(String) ? ["#{prefix}#{field}"] : field.flat_map { |key, inner| fields_from(inner, "#{prefix}#{key}.") }
  end
end

ITEM = ["*", {"category" => ["*"]}, {"logos" => ["*", {"image_id" => ["*"]}]}, {"button" => ["*"]},
  {"sub_buttons" => ["*", {"button_id" => ["*"]}]}, {"buttons" => ["*", {"button_id" => ["*"]}]},
  {"list" => ["*", {"accordion_id" => ["*"]}, {"feature_id" => ["*"]}, {"timing_list_id" => ["*"]}]},
  {"main_button" => ["*"]}, {"images" => ["*", {"gallery_card_id" => ["*"]}, {"image_id" => ["*"]}]},
  {"cards" => ["*", {"binto_grid_card_id" => ["*", {"button" => ["*"]}]}, {"container_card_id" => ["*"]}, {"location_card_id" => ["*"]},
    {"dumpsters_id" => ["*", {"categories" => ["*", {"container_categories_id" => ["*"]}]}]},
    {"containers_id" => ["*", {"categories" => ["*", {"container_categories_id" => ["*"]}]}]},
    {"hero_card_id" => ["*"]}, {"product_card_id" => ["*"]}]}].freeze
PAGE = ["*", {"seo" => ["*"]}, {"blocks" => ["id", "collection", "sort", {"item" => ITEM}]}].freeze

# ----- Files -----

FILES = directus("/files", limit: -1, fields: "id,filename_download,type,title,description").to_h { [it["id"], it] }

# A Directus file id as a CMS asset id (a string, as asset fields hold
# them), uploading it the first time it's met. Nil for none.
def asset(directus_id)
  return nil if directus_id.nil? || directus_id.to_s.empty?
  directus_id = directus_id["id"] if directus_id.is_a?(Hash)
  STATE["assets"][directus_id] ||= begin
    file = FILES[directus_id] or (warn("  no Directus file #{directus_id}") || (return nil))
    res = request(:get, "#{DIRECTUS}/assets/#{directus_id}")
    abort "Directus file #{directus_id} answered #{res.code}" unless res.code == "200"
    alt = [file["description"], file["title"]].find { it.to_s.strip.length > 1 && !it.to_s.match?(/\A(image|img[ _-]?\d*)\z/i) }
    uploaded = upload(file["filename_download"], file["type"], res.body, alt:)
    puts "  file #{file["filename_download"]} → asset #{uploaded}"
    uploaded
  end
ensure
  save_state
end

# A file from the Astro repo's public/ folder, uploaded once.
def local_asset(path)
  STATE["assets"]["local:#{path}"] ||= begin
    full = File.join(MARKETING, "public", path)
    abort "Missing #{full} (set MARKETING_REPO to the affordabox-marketing checkout)" unless File.exist?(full)
    type = {".svg" => "image/svg+xml", ".png" => "image/png", ".webp" => "image/webp", ".jpg" => "image/jpeg"}.fetch(File.extname(full).downcase)
    upload(File.basename(full), type, File.binread(full)).tap { puts "  file #{path} → asset #{it}" }
  end
ensure
  save_state
end

def upload(filename, type, data, alt: nil)
  parts = {"file" => {filename:, type:, data:}, "folder" => "/affordabox"}
  parts["alt"] = alt if alt
  record = cms(:post, "/assets", multipart: parts)
  (record["asset"] || record)["id"].to_s
end

# ----- Links -----

PAGE_PATHS = {} # Directus slug → CMS path, filled in once pages are known

# A Directus link (a string, often an absolute affordabox.com URL) as a link
# field: a page by its path when the site has it, else the URL as written.
def link(value)
  value = value.to_s.strip
  return nil if value.empty?

  if (uri = (URI.parse(value) rescue nil)) && OLD_HOSTS.include?(uri.host)
    value = (uri.path.to_s.empty? ? "/" : uri.path) + (uri.fragment ? "##{uri.fragment}" : "")
  end
  if value.start_with?("/") && !value.include?("#")
    path = value.delete_prefix("/").chomp("/")
    path = "home" if path.empty?
    return {"kind" => "page", "value" => path} if PAGE_PATHS.value?(path)
  end
  {"kind" => "url", "value" => value}
end

def text(value) = value.to_s.strip.then { it.empty? ? nil : it }

def compact(hash) = hash.reject { |_, v| v.nil? || v == [] || v == "" }

# ----- The content model: block types -----

def f(name, label, type, **options) = {"name" => name, "label" => label, "type" => type}.merge(options.transform_keys(&:to_s))
def button_fields(prefix = "button") = [f("#{prefix}_label", "Button text", "string"), f("#{prefix}_link", "Button link", "link")]

BLOCK_TYPES = [
  {slug: "main_hero", label: "Main hero", icon: "Image", description: "The home page's opening: a video or photo behind a big headline, buttons, and a row of highlights.",
   fields: [f("title", "Headline", "string", required: true),
     f("background", "Background", "select", options: %w[video image none]),
     f("video", "Background video", "asset", show_if: {"field" => "background", "equals" => "video"}),
     f("image", "Background photo", "asset", help: "Shown behind the headline, or while the video loads."),
     f("buttons", "Buttons", "repeater", of: [f("label", "Text", "string", required: true), f("link", "Link", "link")]),
     f("highlights", "Highlights", "repeater", help: "The row of icons along the bottom.", of: [f("icon", "Icon", "asset"), f("title", "Text", "string", required: true)])],
   defaults: {"background" => "image"}},
  {slug: "container_slider", label: "Container slider", icon: "GalleryHorizontal", description: "A heading and button, a row of outline buttons, then a sliding row of photo cards.",
   fields: [f("title", "Heading", "string"), *button_fields,
     f("filters", "Outline buttons", "repeater", of: [f("label", "Text", "string", required: true), f("link", "Link", "link")]),
     f("cards", "Cards", "repeater", of: [f("image", "Photo", "asset"), f("label", "Caption", "string"), f("link", "Link", "link")])]},
  {slug: "bento_grid", label: "Bento grid", icon: "LayoutGrid", description: "Up to five photo tiles in a mosaic, each with a tagline, title, words and a button.",
   fields: [f("title", "Heading", "string"),
     f("cards", "Tiles", "repeater", of: [f("image", "Photo", "asset"), f("tagline", "Tagline", "string"), f("title", "Title", "string"),
       f("body", "Words", "markdown"), *button_fields])]},
  {slug: "two_col", label: "Photo and text", icon: "Columns2", description: "A photo beside formatted text, on either side.",
   fields: [f("body", "Text", "markdown"), f("image", "Photo", "asset"),
     f("image_on_left", "Photo on the left", "boolean"), f("sticky_image", "Photo stays in view while the text scrolls", "boolean"), *button_fields],
   defaults: {"image_on_left" => true}},
  {slug: "quote_form", label: "Quote form", icon: "ClipboardList", description: "The request-a-quote form (Forms › Quote request).",
   fields: [f("eyebrow", "Small heading", "string"), f("heading", "Heading", "string"), f("intro", "Intro", "text")],
   defaults: {"eyebrow" => "Get a Quote", "heading" => "Request a Quote", "intro" => "Please fill out the form below and we’ll get back to you as soon as possible."}},
  {slug: "logo_slider", label: "Logo strip", icon: "GalleryHorizontalEnd", description: "Logos scrolling past.",
   fields: [f("logos", "Logos", "repeater", of: [f("image", "Logo", "asset", required: true), f("name", "Name", "string")])]},
  {slug: "photo_gallery", label: "Photo gallery", icon: "Images", description: "A grid of captioned photos that open full size.",
   fields: [f("title", "Heading", "string"),
     f("items", "Photos", "repeater", of: [f("image", "Photo", "asset", required: true), f("title", "Title", "string"), f("description", "Description", "string")])]},
  {slug: "two_col_banner", label: "Banner", icon: "PanelTop", description: "A heading, words and a button over a background, with a photo beside them.",
   fields: [f("heading", "Heading", "string"), f("body", "Words", "text"), f("background", "Background photo", "asset"), f("image", "Photo", "asset"), *button_fields]},
  {slug: "image_cta", label: "Call to action", icon: "Megaphone", description: "A heading, words and a button over a darkened photo.",
   fields: [f("title", "Heading", "string"), f("description", "Words", "text"), f("background", "Background photo", "asset"), f("image", "Photo", "asset"), *button_fields]},
  {slug: "products", label: "Product cards", icon: "LayoutGrid", description: "Cards with a photo, a title, a few words and a link.",
   fields: [f("title", "Heading", "string", help: "For editors; not shown."), f("button_label", "Card button text", "string"),
     f("cards", "Cards", "repeater", of: [f("title", "Title", "string"), f("image", "Photo", "asset"), f("description", "Words", "text"), f("link", "Link", "link")])],
   defaults: {"button_label" => "Learn More"}},
  {slug: "single_hero", label: "Page header", icon: "Heading1", description: "A page title over a darkened photo.",
   fields: [f("title", "Title", "string", required: true, help: "Wrap words in <span class=\"highlighted-title\">…</span> to highlight them."),
     f("description", "Words below", "text"), f("image", "Photo", "asset")]},
  {slug: "title_bar", label: "Title bar", icon: "Heading", description: "A slim page title, the photo fading in on the right.",
   fields: [f("title", "Title", "string"), f("image", "Photo", "asset")]},
  {slug: "rich_text", label: "Text", icon: "Text", description: "Formatted text.",
   fields: [f("body", "Text", "markdown"), f("centered", "Centered", "boolean")]},
  {slug: "faqs", label: "FAQs", icon: "MessageCircleQuestion", description: "Questions that open to their answers.",
   fields: [f("title", "Heading", "string"),
     f("items", "Questions", "repeater", of: [f("question", "Question", "string", required: true), f("answer", "Answer", "markdown")])]},
  {slug: "container_listing", label: "Container listing", icon: "Container", description: "Containers to filter by size, condition, height and category, with a sidebar to call or ask for a quote.",
   fields: [f("containers", "Containers", "record_refs", of_collection: "containers"),
     f("sidebar", "Sidebar text", "markdown"), *button_fields, f("show_more_label", "Show more button", "string")],
   defaults: {"show_more_label" => "Show More", "button_label" => "Get a quote"}},
  {slug: "locations", label: "Locations", icon: "MapPin", description: "Location cards with a photo, an address and a link.",
   fields: [f("title", "Heading", "string"), f("description", "Words", "text"), f("button_label", "Card button text", "string"),
     f("cards", "Locations", "repeater", of: [f("image", "Photo", "asset"), f("title", "Name", "string"), f("address", "Address", "string"), f("link", "Link", "link")])],
   defaults: {"button_label" => "View Location"}},
  {slug: "image_gallery", label: "Photo grid", icon: "Grid3x3", description: "Photos in a grid that open full size.",
   fields: [f("title", "Heading", "string"), f("images", "Photos", "repeater", of: [f("image", "Photo", "asset", required: true)])]},
  {slug: "features", label: "Feature band", icon: "ListChecks", description: "A green band: a heading, a line, and icons with short labels.",
   fields: [f("title", "Heading", "string"), f("description", "Words", "text"),
     f("items", "Features", "repeater", of: [f("icon", "Icon", "asset"), f("title", "Label", "string", required: true)])]},
  {slug: "testimonials", label: "Testimonials", icon: "Quote", description: "Reviews that slide past, with their stars.",
   fields: [f("title", "Heading", "string"),
     f("items", "Reviews", "repeater", of: [f("rating", "Stars (1–5)", "integer"), f("quote", "Review", "markdown"),
       f("name", "Name", "string", required: true), f("designation", "Who they are", "string"), f("photo", "Photo", "asset")])]},
  {slug: "image_text", label: "Photo and long text", icon: "PanelLeft", description: "A photo on the left of a column of formatted text.",
   fields: [f("image", "Photo", "asset"), f("body", "Text", "markdown")]},
  {slug: "hours", label: "Hours and features", icon: "Clock", description: "Columns of opening hours, or of features with check marks.",
   fields: [f("heading", "Heading", "string"),
     f("columns", "Columns", "repeater", of: [f("title", "Title", "string"),
       f("show_features", "A list of features rather than hours", "boolean"),
       f("rows", "Hours", "repeater", of: [f("day", "Day", "string"), f("time", "Time", "string"), f("bold", "Bold", "boolean")]),
       f("features", "Features", "string_list")])]},
  {slug: "thank_you", label: "Thank you", icon: "PartyPopper", description: "Where the quote form lands: a thank-you, the phone number, and what happens next.",
   fields: [f("heading", "Heading", "string"), f("body", "Words", "text"),
     f("call_label", "Call button", "string", help: "{phone} is the phone number in the Sidebar global."),
     f("home_label", "Home button", "string"), f("steps_heading", "Steps heading", "string"),
     f("steps", "Steps", "repeater", of: [f("title", "Title", "string"), f("body", "Words", "text")]),
     f("footnote", "Footnote", "text", help: "{phone} is the phone number, as a link.")]}
].freeze

# ----- Collections and globals -----

CONTAINER_FIELDS = [
  f("image", "Photo", "asset"), f("price", "Price ($)", "integer"),
  f("size", "Size", "string", help: "e.g. 20 ft. The filters drop a trailing \"ft\"."),
  f("height", "Height", "string"), f("condition", "Condition", "select", options: %w[new used]),
  f("delivery_time", "Delivery time", "string", help: "Blank shows 3-5 days."),
  f("link", "Link", "link"), f("button_label", "Button text", "string", help: "Blank shows Get a quote."),
  f("categories", "Categories", "string_list"), f("order", "Order", "integer")
].freeze

ITEM_LINK = [f("label", "Label", "string", required: true), f("link", "Link", "link"), f("icon", "Icon", "asset")].freeze

GLOBALS = {
  "nav" => {name: "Top bar", fields: [f("items", "Items", "repeater", help: "The icon links across the top of pages with the standard top bar.", of: ITEM_LINK)]},
  "sidebar" => {name: "Sidebar", fields: [f("logo", "Logo", "asset"), f("phone", "Phone number", "string"),
    f("items", "Items", "repeater", help: "The sidebar's links; the compact top bar shows the first five, then a More menu.", of: ITEM_LINK)]},
  "footer" => {name: "Footer", fields: [f("logo", "Logo", "asset"),
    f("columns", "Columns", "repeater", of: [f("heading", "Heading", "string"),
      f("items", "Links", "repeater", of: [f("label", "Label", "string", required: true), f("link", "Link", "link")])]),
    f("socials_heading", "Social heading", "string"),
    f("socials", "Social links", "repeater", of: [f("label", "Name", "string", required: true), f("link", "Link", "link"), f("icon", "Icon", "asset")]),
    f("legal_links", "Legal links", "repeater", of: [f("label", "Label", "string", required: true), f("link", "Link", "link")]),
    f("copyright", "Copyright line", "string", help: "{year} is this year.")]},
  "site_settings" => {name: "Site settings", fields: [f("favicon", "Favicon", "asset"), f("share_image", "Default sharing image", "asset"),
    f("listing", "Container listing sidebar", "group", of: [f("process_heading", "Process heading", "string"),
      f("steps", "Process steps", "repeater", of: [f("title", "Step", "string", required: true), f("icon", "Icon", "asset")]),
      f("reasons_heading", "Reasons heading", "string"),
      f("reasons", "Reasons", "repeater", of: [f("text", "Reason", "markdown", required: true), f("icon", "Icon", "asset")])]),
    f("not_found", "Page not found", "group", of: [f("heading", "Heading", "string"), f("body", "Words", "text"), f("button_label", "Button", "string")])]}
}.freeze

PAGE_FIELDS = [
  f("navbar", "Top bar", "select", options: %w[standard compact none], sidebar: true,
    help: "Standard: the sidebar and the icon bar. Compact: one bar of links and no sidebar. None: the sidebar only."),
  f("hide_sidebar", "Hide the sidebar on wide screens", "boolean", sidebar: true)
].freeze
NAVBARS = {"navbar-default" => "standard", "alternative" => "compact", "none" => "none"}.freeze

# ----- The quote form (src/components/forms/QuoteForm.svelte) -----

LOCATIONS = ["Minnesota", "North Dakota", "South Dakota", "Wisconsin", "Texas"].freeze
def options(*values) = values.map { |v| v.is_a?(Array) ? {"value" => v[0], "label" => v[1]} : {"value" => v, "label" => v} }
ATTRIBUTION = %w[gclid gbraid wbraid fbclid msclkid ttclid utm_source utm_medium utm_campaign utm_term utm_content landing_page referrer page_url].freeze

QUOTE_FORM = {
  "slug" => "quote", "title" => "Quote request", "status" => "published", "submit_label" => "Submit Inquiry",
  "success_message" => "Thank you! We'll be in touch shortly.",
  "fields" => [
    {"name" => "inquiry_type", "label" => "What can we help you with?", "type" => "select", "required" => true,
     "options" => options(["shipping-container-rentals", "Shipping Containers Rentals"], ["shipping-container-sales", "Shipping Containers Sales"],
       ["dumpsters", "Dumpster Rentals"], ["self-storage", "Self Storage"], ["portable-storage", "Portable Storage & Moving"], ["general-inquiry", "General Inquiry / Contact Us"])},
    {"name" => "location", "label" => "Location", "type" => "select", "options" => options(*LOCATIONS)},
    {"name" => "delivery_city", "label" => "Facility", "type" => "select", "options" => options("Monticello", "St. Michael")},
    {"name" => "delivery_zip", "label" => "Zip code", "type" => "text"},
    {"name" => "destination_zip_code", "label" => "Destination zip code", "type" => "text"},
    {"name" => "disposal_type", "label" => "What are you disposing of?", "type" => "select",
     "options" => options("Construction materials", "Mixed rubbish/Household garbage", "Both", "Other")},
    {"name" => "rental_duration", "label" => "Rental duration", "type" => "select",
     "options" => options("Two weeks or less", "Three weeks or less", "More than three weeks")},
    {"name" => "service_type", "label" => "Service type", "type" => "select",
     "options" => options(["store-it", "Store It"], ["move-it", "Move It"], ["keep-it", "Keep It"],
       ["dumpster-transit", "Dumpster"], ["shipping-container-rental", "Shipping container rental"], ["shipping-container-sale", "Shipping container sale"])},
    {"name" => "sizes_needed", "label" => "Size(s) needed", "type" => "text", "help" => "The site joins the sizes ticked, with commas."},
    {"name" => "rent_or_purchase", "label" => "Rent or purchase?", "type" => "select", "options" => options("Rent", "Purchase")},
    {"name" => "features_needed", "label" => "Container type", "type" => "select",
     "options" => options("Standard (8’)", "High Cube (9.5’)", "Double Door", "Side Door", "Other")},
    {"name" => "delivery_date", "label" => "Estimated move-in date", "type" => "text", "help" => "A date picker on the site."},
    {"name" => "what_storing", "label" => "What you're storing", "type" => "textarea"},
    {"name" => "first_name", "label" => "First name", "type" => "text", "required" => true},
    {"name" => "last_name", "label" => "Last name", "type" => "text", "required" => true},
    {"name" => "email", "label" => "Email", "type" => "email", "required" => true},
    {"name" => "phone", "label" => "Phone", "type" => "tel", "required" => true},
    {"name" => "project_details", "label" => "How can we help you?", "type" => "textarea", "required" => true,
     "placeholder" => "Tell us more about your project or any special requirements..."},
    *ATTRIBUTION.map { {"name" => it, "label" => it.tr("_", " ").sub(/\Autm /, "UTM ").sub(/\A\w/, &:upcase), "type" => "text", "help" => "Filled in by the site: where the visitor came from."} }
  ]
}.merge(ENV["ADS_LEADS_WEBHOOK_URL"].to_s.empty? ? {} : {"notify_webhook_url" => ENV["ADS_LEADS_WEBHOOK_URL"]}).freeze

# Who hears about each request, and where leads go: kept out of this public
# repository. Unset, a run leaves what the CMS has.
#   QUOTE_RECIPIENTS="a@example.com, b@example.com" ADS_LEADS_WEBHOOK_URL=https://… ruby script/import_directus.rb
NOTIFY = ENV["QUOTE_RECIPIENTS"].to_s.split(",").map(&:strip).reject(&:empty?).freeze

def email_block(type, data) = {"id" => SecureRandom.uuid, "type" => type, "version" => 1, "data" => data}

EMAILS = {
  "notification" => {"enabled" => true, "subject" => "New Inquiry Submission", **(NOTIFY.empty? ? {} : {"recipients" => NOTIFY.join(", ")}),
    "blocks" => [email_block("email_heading", {"text" => "New quote request", "level" => "h1", "align" => "left"}),
      email_block("email_text", {"body" => "<p>{{first_name}} {{last_name}} asked for a quote. Reply to this email to answer them.</p>"}),
      email_block("email_submission", {"title" => "Request details", "skip_empty" => true})]},
  "confirmation" => {"enabled" => true, "subject" => "Thank You for Your Inquiry",
    "blocks" => [email_block("email_heading", {"text" => "Request Received!", "level" => "h1", "align" => "center"}),
      email_block("email_text", {"body" => "<p>Hi {{first_name}},</p><p>Thank you for reaching out to Affordabox! We've successfully received your quote request and our team is reviewing the details.</p>"}),
      # Not the answers table: that would show the visitor the ad-tracking fields too.
      email_block("email_heading", {"text" => "Your Request Summary", "level" => "h3", "align" => "left"}),
      email_block("email_text", {"body" => "<p>What can we help you with: {{inquiry_type}}<br>Name: {{first_name}} {{last_name}}<br>Email: {{email}}<br>Phone: {{phone}}<br>Project details: {{project_details}}</p>"}),
      email_block("email_text", {"body" => "<p>A specialist will be in touch shortly, usually the same business day. Need it sooner? Call us at <a href=\"tel:8334682269\">(833) 468-2269</a>.</p>"})]}
}.freeze

# ----- Directus blocks → CMS blocks -----

def buttons(list) = Array(list).filter_map { (b = it["button_id"]) && compact("label" => text(b["label"]), "link" => link(b["link"])) }

def button(prefix, record) = record ? {"#{prefix}_label" => text(record["label"]), "#{prefix}_link" => link(record["link"])} : {}

def container_entry(record)
  slug = "#{record["title"].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")}-#{record["id"][0, 6]}"
  entry = {"slug" => slug, "title" => text(record["title"]) || "Container", "status" => "published", "locale" => "en",
    "frontmatter" => compact("image" => asset(record["image"]), "price" => record["price"], "size" => text(record["size"]),
      "height" => text(record["height"]), "condition" => (%w[new used].include?(record["condition"]) ? record["condition"] : nil),
      "delivery_time" => text(record["delivery_time"]), "link" => link(record["link"]), "button_label" => text(record["button"]),
      "categories" => Array(record["categories"]).filter_map { it.dig("container_categories_id", "name") })}
  (@containers ||= {})[slug] = entry
  slug
end

def convert(collection, item, page_slug)
  case collection
  when "hero"
    ["main_hero", compact("title" => text(item["title"]),
      "background" => {"background-video" => "video", "background-image" => "image"}.fetch(item["background"], "none"),
      "video" => asset(item["video"]), "image" => asset(item["bg_image"]), "buttons" => buttons(item["buttons"]),
      "highlights" => Array(item["cards"]).filter_map { (c = it["hero_card_id"]) && compact("icon" => asset(c["image"]), "title" => text(c["title"])) })]
  when "container_slider"
    ["container_slider", compact("title" => text(item["title"]), **button("button", item["main_button"]), "filters" => buttons(item["sub_buttons"]),
      "cards" => Array(item["cards"]).filter_map { (c = it["container_card_id"]) && compact("image" => asset(c["image"]), "label" => text(c["label"]), "link" => link(c["link"])) })]
  when "binto_grid"
    ["bento_grid", compact("title" => text(item["title"]),
      "cards" => Array(item["cards"]).filter_map { (c = it["binto_grid_card_id"]) && compact("image" => asset(c["bg_Image"]), "tagline" => text(c["tagline"]), "title" => text(c["title"]), "body" => text(c["description"]), **button("button", c["button"])) })]
  when "two_col"
    ["two_col", compact("body" => text(item["description"]), "image" => asset(item["image"]), "image_on_left" => item["image_on_left"] == true,
      "sticky_image" => item["sticky_image"] == true, **button("button", item["button"].is_a?(Hash) ? {"label" => item["button"]["text"] || item["button"]["label"], "link" => item["button"]["link"]} : nil))]
  when "quote_form"
    # What the live form shows: QuoteForm.svelte has its words written in.
    ["quote_form", BLOCK_TYPES.find { it[:slug] == "quote_form" }[:defaults]]
  when "logo_slider"
    ["logo_slider", {"logos" => Array(item["logos"]).filter_map { (i = it["image_id"]) && (id = asset(i["image"])) && {"image" => id} }}]
  when "gallery"
    ["photo_gallery", compact("title" => text(item["title"]),
      "items" => Array(item["images"]).filter_map { (c = it["gallery_card_id"]) && (id = asset(c["image"])) && compact("image" => id, "title" => text(c["title"]), "description" => text(c["description"])) })]
  when "two_col_banner"
    ["two_col_banner", compact("heading" => text(item["title"]), "body" => text(item["description"]), "background" => asset(item["bg_image"]), "image" => asset(item["image"]), **button("button", item["button"]))]
  when "cta"
    ["image_cta", compact("title" => text(item["title"]), "description" => text(item["description"]), "background" => asset(item["bg_image"]), "image" => asset(item["image"]), **button("button", item["button"]))]
  when "products"
    ["products", compact("title" => text(item["title"]), "button_label" => "Learn More",
      "cards" => Array(item["cards"]).filter_map { (c = it["product_card_id"]) && compact("title" => text(c["title"]), "image" => asset(c["image"]), "description" => text(c["description"]), "link" => link(c["link"])) })]
  when "single_hero"
    ["single_hero", compact("title" => text(item["title"]), "description" => text(item["description"]), "image" => asset(item["image"]))]
  when "single_hero_type_two"
    ["title_bar", compact("title" => text(item["title"]), "image" => asset(item["image"]))]
  when "rich_text"
    ["rich_text", compact("body" => text(item["description"]), "centered" => item["content_in_center"] == true)]
  when "faqs"
    ["faqs", compact("title" => text(item["title"]),
      "items" => Array(item["list"]).filter_map { (q = it["accordion_id"]) && compact("question" => text(q["question"]), "answer" => text(q["answer"])) })]
  when "storage_containers", "dumpster_containers"
    key = collection == "storage_containers" ? "containers_id" : "dumpsters_id"
    ["container_listing", compact("containers" => Array(item["cards"]).filter_map { (c = it[key]) && container_entry(c) },
      "sidebar" => text(item["content"]), **button("button", item["button"]), "show_more_label" => "Show More")]
  when "locations"
    ["locations", compact("title" => text(item["title"]), "description" => text(item["description"]), "button_label" => "View Location",
      "cards" => Array(item["cards"]).filter_map { (c = it["location_card_id"]) && compact("image" => asset(c["image"]), "title" => text(c["title"]), "address" => text(c["address"]), "link" => link(c["link"])) })]
  when "image_gallery"
    ["image_gallery", compact("title" => text(item["title"]), "images" => Array(item["images"]).filter_map { (i = it["image_id"]) && (id = asset(i["image"])) && {"image" => id} })]
  when "features"
    ["features", compact("title" => text(item["title"]), "description" => text(item["description"]),
      "items" => Array(item["list"]).filter_map { (c = it["feature_id"]) && compact("icon" => asset(c["icon"]), "title" => text(c["title"])) })]
  when "testimonials"
    ["testimonials", compact("title" => text(item["title"]),
      "items" => Array(item["list"]).map { compact("rating" => it["rating"], "quote" => text(it["description"]), "name" => text(it["name"]) || "Customer", "designation" => text(it["designation"])) })]
  when "left_aligned_block"
    ["image_text", compact("image" => asset(item["image"]), "body" => text(item["description"]))]
  when "location_timing"
    ["hours", compact("heading" => text(item["heading"]),
      "columns" => Array(item["list"]).filter_map do |entry|
        (c = entry["timing_list_id"]) && compact("title" => text(c["title"]), "show_features" => c["show_features"] == true,
          "rows" => Array(c["list"]).map { compact("day" => text(it["day"]), "time" => text(it["timinig"]), "bold" => it["is_bold"] == true) },
          "features" => Array(c["features"]).filter_map { text(it["title"]) })
      end)]
  else
    warn "  #{page_slug}: no conversion for #{collection} blocks, left out"
    nil
  end
end

# The thank-you page is a route of its own in the Astro site
# (src/pages/thank-you.astro), its words written into it; here it's a page.
THANK_YOU = {
  "heading" => "Thank You!",
  "body" => "We've received your request and a storage specialist is already on it. Keep an eye on your inbox — a confirmation is on its way.",
  "call_label" => "Need it sooner? Call {phone}", "home_label" => "Back to Home", "steps_heading" => "What Happens Next",
  "steps" => [
    {"title" => "We review your request", "body" => "A specialist reads through the details you sent and puts together pricing for your location."},
    {"title" => "We reach out", "body" => "You'll hear from us by phone or email, usually the same business day, with your quote and available delivery dates."},
    {"title" => "We deliver", "body" => "Pick the option that fits, and we'll schedule the drop-off on the day you need it."}
  ],
  "footnote" => "Didn't get a confirmation email? Check your spam folder, or call us at {phone}."
}.freeze

# ----- Writing to the CMS -----

def upsert(path, wrapper, attributes, create_path:)
  if cms(:get, path, missing_ok: true)
    cms(:patch, path, {wrapper => attributes})
  else
    cms(:post, create_path, {wrapper => attributes})
  end
end

puts "Reading Directus at #{DIRECTUS}"
pages = directus("/items/pages", limit: -1, fields: fields_from(PAGE).join(","))
navbar = directus("/items/navbar", fields: "*,menu.*,menu.nav_item_id.*")
sidebar = directus("/items/sidebar", fields: "*,list.*,list.sidebar_item_id.*")
footer = directus("/items/footer", fields: "*,menu.*,menu.footer_item_id.*,socials.*,socials.social_item_id.*")
global = directus("/items/global", fields: "*")
pages.each { PAGE_PATHS[it["slug"]] = it["slug"].delete_prefix("/").then { |p| p.empty? ? "home" : p } }
PAGE_PATHS["/thank-you"] = "thank-you"

puts "Block types"
BLOCK_TYPES.each do |type|
  attributes = {"slug" => type[:slug], "label" => type[:label], "description" => type[:description], "category" => "Affordabox",
    "icon" => type[:icon], "fields" => type[:fields], "defaults" => type[:defaults] || {}}
  upsert("/block_types/#{type[:slug]}", "block_type", attributes, create_path: "/block_types")
end

puts "Collections"
upsert("/collections/containers", "collection", {"slug" => "containers", "name" => "Containers", "schema" => {"fields" => CONTAINER_FIELDS}}, create_path: "/collections")

puts "Pages' blocks, and their files"
converted = pages.to_h do |page|
  blocks = page["blocks"].sort_by { it["sort"].to_i }.filter_map do |block|
    next unless block["item"].is_a?(Hash)

    type, data = convert(block["collection"], block["item"], page["slug"])
    type && {"type" => type, "version" => 1, "data" => data}
  end
  [page["slug"], blocks]
end

puts "Containers"
(@containers || {}).each_value.with_index do |entry, index|
  entry["frontmatter"]["order"] = index + 1
  upsert("/collections/containers/entries/#{entry["slug"]}", "entry", entry, create_path: "/collections/containers/entries")
end

puts "Globals"
items = ->(list, key) { Array(list).filter_map { (i = it[key]) && compact("label" => text(i["label"]), "link" => link(i["link"]), "icon" => asset(i["icon"])) } }
global_data = {
  "nav" => {"items" => items.(navbar["menu"], "nav_item_id")},
  "sidebar" => compact("logo" => asset(sidebar["logo"]), "phone" => text(sidebar["phone_number"]), "items" => items.(sidebar["list"], "sidebar_item_id")),
  "footer" => compact("logo" => asset(footer["logo"]),
    "columns" => Array(footer["menu"]).filter_map { (c = it["footer_item_id"]) && compact("heading" => text(c["title"]), "items" => Array(c["list"]).map { compact("label" => text(it["label"]), "link" => link(it["link"])) }) },
    "socials_heading" => "Follow Us",
    "socials" => Array(footer["socials"]).filter_map { (s = it["social_item_id"]) && compact("label" => text(s["link"]) || "Social", "link" => link(s["link"]), "icon" => asset(s["icon"])) },
    "legal_links" => Array(footer["legal_links"]).map { compact("label" => text(it["title"]), "link" => link(it["link"])) },
    "copyright" => "{year} - AffordaBox. All rights reserved."),
  "site_settings" => compact("favicon" => asset(global["favicon"]),
    "listing" => {"process_heading" => "Buying online is easy",
      "steps" => [["Choose container", "iconType-1"], ["Pick delivery date", "iconType-2"], ["Receive container", "iconType-3"]].map { |title, icon| {"title" => title, "icon" => local_asset("assets/icons/#{icon}.svg")} },
      "reasons_heading" => "Why buy from Affordabox?",
      "reasons" => [["we **Service and deliver** your container", "slideImage-1"], ["**Shortest** lead time in industry", "slideImage-2"], ["**Warranty** on all of our container", "slideImage-3"]].map { |words, icon| {"text" => words, "icon" => local_asset("assets/icons/#{icon}.svg")} }},
    "not_found" => {"heading" => "Page not found", "body" => "The page you're looking for isn't here. It may have moved, or the link may be mistyped.", "button_label" => "Back to Home"})
}
GLOBALS.each do |slug, definition|
  existing = cms(:get, "/globals/#{slug}", missing_ok: true)
  cms(:post, "/globals", {"global" => {"slug" => slug, "name" => definition[:name], "data" => {}, "schema" => {"fields" => []}}}) unless existing
  cms(:patch, "/globals/#{slug}/schema", {"global" => {"fields" => definition[:fields]}})
  cms(:patch, "/globals/#{slug}", {"global" => {"name" => definition[:name], "data" => global_data.fetch(slug)}})
end

puts "The quote form and its emails"
upsert("/forms/quote", "form", QUOTE_FORM, create_path: "/forms")
EMAILS.each { |kind, email| cms(:patch, "/forms/quote/emails/#{kind}", {"form_email" => email}) }

puts "Pages"
pages.each do |page|
  path = PAGE_PATHS.fetch(page["slug"])
  next if path == "thank-you" # its own design, below

  seo = page["seo"].is_a?(Hash) ? page["seo"] : {}
  attributes = {"slug" => path, "title" => text(page["title"]), "locale" => "en", "blocks" => converted.fetch(page["slug"]),
    "seo" => compact("meta_title" => text(seo["title"]), "meta_description" => text(seo["meta_description"]), "canonical_url" => text(seo["canonical_url"]),
      "noindex" => (seo["no_index"] == true || nil), "nofollow" => (seo["no_follow"] == true || nil), "og_image_id" => asset(seo["og_image"]))}
  frontmatter = {"navbar" => NAVBARS.fetch(page["navbarType"].to_s, "standard"), "hide_sidebar" => page["hide_sidebar"] == true}
  existing = cms(:get, "/pages/#{path}", missing_ok: true)
  attributes["status"] = "draft" unless existing && existing.dig("page", "status") == "published"
  existing ? cms(:patch, "/pages/#{path}", {"page" => attributes}) : cms(:post, "/pages", {"page" => attributes})
  cms(:patch, "/pages/#{path}/schema", {"page" => {"fields" => PAGE_FIELDS}})
  cms(:patch, "/pages/#{path}", {"page" => {"frontmatter" => frontmatter}})
  puts "  /#{path == "home" ? "" : path}: #{attributes["blocks"].size} blocks"
end

thank_you = {"slug" => "thank-you", "title" => "Thank you", "locale" => "en",
  "blocks" => [{"type" => "thank_you", "version" => 1, "data" => THANK_YOU}],
  "seo" => {"meta_title" => "Thank You | Affordabox", "meta_description" => "Thanks for reaching out to Affordabox. A specialist will be in touch with your quote shortly.", "noindex" => true}}
existing = cms(:get, "/pages/thank-you", missing_ok: true)
thank_you["status"] = "draft" unless existing && existing.dig("page", "status") == "published"
existing ? cms(:patch, "/pages/thank-you", {"page" => thank_you}) : cms(:post, "/pages", {"page" => thank_you})
cms(:patch, "/pages/thank-you/schema", {"page" => {"fields" => PAGE_FIELDS}})
cms(:patch, "/pages/thank-you", {"page" => {"frontmatter" => {"navbar" => "standard", "hide_sidebar" => false}}})
puts "  /thank-you: 1 block"

cms(:patch, "/settings/general", {"setting" => {"data" => {"title" => "Affordabox", "description" => "Portable storage, shipping containers, dumpsters and self storage across the Midwest."}}})
puts "Done: #{pages.size + 0} pages, #{(@containers || {}).size} containers, #{STATE["assets"].size} files."
