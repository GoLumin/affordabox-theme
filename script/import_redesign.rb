#!/usr/bin/env ruby
# frozen_string_literal: true

# Brings the CMS to the redesign (the "redesign" branch of
# GoLumin/affordabox-marketing, "Bold Industrial"): its block types, the
# collections its pages are built from (dumpster sizes, containers, portable
# sizes, storage units, facilities, the cities it serves, reviews, FAQs),
# the globals (site settings, the mega menu, the footer), the 3-step lead
# form, every page, and redirects from the old site's addresses.
#
#   CMS_PROFILE=localhost REDESIGN=../affordabox-redesign ruby script/import_redesign.rb
#
# REDESIGN is a checkout of that branch, for its photos. It can run again:
# records that are there are updated, files already sent (tmp/redesign_import.json)
# aren't sent twice. Pages are published (PUBLISH=0 leaves new ones drafts).
# The old site's pages that moved go to the trash, where they can be restored.
require_relative "cms_client"
require_relative "seo_copy"
require_relative "facts"
require_relative "landing"

ROOT = File.expand_path("..", __dir__)
REDESIGN = File.expand_path(ENV.fetch("REDESIGN", File.join(ROOT, "../affordabox-redesign")))
abort "No redesign checkout at #{REDESIGN} (set REDESIGN)" unless File.directory?(File.join(REDESIGN, "src"))
STATE_PATH = ENV.fetch("IMPORT_STATE", File.join(ROOT, "tmp/redesign_import.json"))
STATE = File.exist?(STATE_PATH) ? JSON.parse(File.read(STATE_PATH)) : {"assets" => {}}
PUBLISH = ENV.fetch("PUBLISH", "1") != "0"

def cms(...) = CmsClient.call(...)
def upsert(...) = CmsClient.upsert(...)

def save_state
  FileUtils.mkdir_p(File.dirname(STATE_PATH))
  File.write(STATE_PATH, JSON.pretty_generate(STATE))
end

# A file from the redesign checkout (src/assets/images/<path>, or public/<path>), as an asset id.
def img(path, alt: nil)
  alt ||= ALTS[path]
  STATE["assets"][path] ||= begin
    full = [File.join(REDESIGN, "src/assets/images", path), File.join(REDESIGN, "public", path)].find { File.exist?(it) } or abort "Missing #{path} in #{REDESIGN}"
    CmsClient.upload(File.basename(full), CmsClient.content_type(full), File.binread(full), alt:).tap { puts "  file #{path} → asset #{it}" }
  end
ensure
  save_state
end

def f(name, label, type, **options) = {"name" => name, "label" => label, "type" => type}.merge(options.transform_keys(&:to_s))
def url(value) = {"kind" => "url", "value" => value}
def page(value) = {"kind" => "page", "value" => value}
def b(type, data = {}) = {"type" => type, "version" => 1, "data" => data.transform_keys(&:to_s).reject { |_, v| v.nil? }}

# ===== The content model =====

SERVICES = ["any", "Dumpster", "Container — Buy", "Container — Rent", "Portable Storage", "Self-Storage"].freeze
REVIEW_CONTEXTS = %w[general portable moving dumpster container self-storage].freeze
FAQ_GROUPS = %w[home dumpster container-buy container-rent portable self-storage].freeze
BACKGROUNDS = %w[white muted dark].freeze
HEAD = [f("eyebrow", "Eyebrow", "string", help: "The small label above the heading, e.g. \"— How it works\"."), f("heading", "Heading", "string")].freeze
BUTTON = [f("button_label", "Button text", "string"), f("button_link", "Button link", "link")].freeze
LINK_ITEM = [f("label", "Label", "string", required: true), f("link", "Link", "link")].freeze

BLOCK_TYPES = [
  {slug: "breadcrumbs", label: "Breadcrumbs", icon: "ChevronRight", description: "Home › this page's parents › this page, from the page tree, with its structured data.",
   fields: [f("current_label", "This page's name", "string", help: "Blank uses the page's title.")]},
  {slug: "page_hero", label: "Page hero", icon: "Image", description: "The dark band a page opens with: a heading over a video or photo, and the lead form beside it.",
   fields: [f("style", "Background", "select", options: %w[video photo plain]), f("photo", "Photo", "asset"), f("video", "Video", "asset"),
     f("photo_opacity", "Photo strength", "select", options: %w[20 25]),
     f("layout", "Layout", "select", options: %w[split left center], help: "Split puts the lead form beside the words."),
     f("padding", "Height", "select", options: %w[tall large medium small]), f("heading_size", "Heading size", "select", options: %w[large medium]),
     *HEAD, f("body", "Words", "markdown"), f("detail", "More words", "text", help: "A second, smaller paragraph."),
     f("checklist", "Check marks", "string_list"),
     f("buttons", "Buttons", "repeater", of: [*LINK_ITEM, f("style", "Style", "select", options: %w[primary secondary])]),
     f("note", "Note beside the buttons", "string"),
     f("form_heading", "Lead form heading", "string"), f("form_service", "Lead form service", "select", options: SERVICES),
     f("form_zip", "Lead form ZIP", "string"), f("form_city", "Lead form city", "string")],
   defaults: {"style" => "plain", "layout" => "left", "padding" => "medium", "heading_size" => "large", "photo_opacity" => "20"}},
  {slug: "trust_bar", label: "Trust bar", icon: "BadgeCheck", description: "A strip of check-marked promises.",
   fields: [f("items", "Promises", "string_list", help: "Blank uses Site settings › Trust items."), f("dark", "Dark", "boolean")]},
  {slug: "product_router", label: "Service cards", icon: "LayoutGrid", description: "A card per service, with its photo and starting price.",
   fields: [*HEAD, f("intro", "Intro", "text"), f("cta_label", "Card link text", "string"),
     f("cards", "Cards", "repeater", of: [f("title", "Title", "string", required: true), f("link", "Link", "link"), f("price", "Price", "string"),
       f("blurb", "Words", "text"), f("image", "Photo", "asset"), f("featured", "Featured (dark)", "boolean"), f("badge", "Badge", "string")])],
   defaults: {"cta_label" => "Start"}},
  {slug: "feature_split", label: "Feature with photo", icon: "PanelRight", description: "A heading, words and check-marked points beside a photo with a badge (Meet the Mule).",
   fields: [*HEAD, f("body", "Words", "markdown"), f("points", "Points", "repeater", of: [f("title", "Title", "string", required: true), f("body", "Words", "text")]),
     f("image", "Photo", "asset"), f("badge_value", "Badge", "string"), f("badge_label", "Badge words", "string"), *BUTTON, f("dark", "Dark", "boolean")],
   defaults: {"dark" => true}},
  {slug: "process_steps", label: "Steps", icon: "ListOrdered", description: "Numbered steps in a row.",
   fields: [*HEAD, f("steps", "Steps", "repeater", of: [f("title", "Title", "string", required: true), f("body", "Words", "text")]), f("dark", "Dark", "boolean")]},
  {slug: "reviews", label: "Reviews", icon: "Star", description: "Reviews from the Reviews collection that suit the page.",
   fields: [*HEAD, f("context", "Which reviews", "select", options: REVIEW_CONTEXTS), f("limit", "How many", "integer", help: "Blank or 0 shows them all."),
     f("layout", "Layout", "select", options: %w[feed grid]), f("dark", "Dark", "boolean"), f("footnote", "Note below", "string")],
   defaults: {"context" => "general", "limit" => 3, "layout" => "feed"}},
  {slug: "faq", label: "FAQs", icon: "MessageCircleQuestion", description: "Questions from the FAQs collection that open to their answers, with their structured data.",
   fields: [*HEAD, f("group", "Which questions", "select", options: FAQ_GROUPS), f("style", "Style", "select", options: %w[simple cards]),
     f("schema", "Give search engines the questions (FAQPage)", "boolean")],
   defaults: {"style" => "simple", "schema" => true}},
  {slug: "cta_band", label: "Call to action", icon: "Megaphone", description: "The dark closing band: a heading, the phone number and the lead form.",
   fields: [f("heading", "Heading", "string"), f("body", "Words", "text"), f("service", "Lead form service", "select", options: SERVICES), f("note", "Note beside the phone", "string")],
   defaults: {"heading" => "Ready to get started?", "service" => "any"}},
  {slug: "dumpster_sizes", label: "Dumpster sizes", icon: "Truck", description: "A price card per dumpster size (the Dumpster sizes collection).",
   fields: [*HEAD, f("intro", "Intro", "text"), f("button_label", "Card button", "string"), Landing::BUTTON_TARGET_FIELD,
     f("schema", "Give search engines the prices (Product)", "boolean")],
   defaults: {"button_label" => "Get this size", "button_target" => "quote_page", "schema" => true}},
  {slug: "container_catalog", label: "Container catalogue", icon: "Container", description: "A card per container for sale (the Containers collection).",
   fields: [*HEAD, f("intro", "Intro", "text"), f("button_label", "Card button", "string"), f("schema", "Give search engines the prices (Product)", "boolean")],
   defaults: {"button_label" => "Get this container", "schema" => true}},
  {slug: "portable_sizes", label: "Portable storage sizes", icon: "Box", description: "A card per portable storage size (the Portable sizes collection).",
   fields: [*HEAD, f("intro", "Intro", "markdown"), f("button_label", "Card button", "string"), f("footnote", "Note below", "markdown"),
     f("schema_price", "Monthly price for search engines (Product)", "integer")],
   defaults: {"button_label" => "Get this size"}},
  {slug: "storage_units", label: "Storage unit sizes", icon: "Warehouse", description: "A card per self-storage unit size (the Storage units collection).",
   fields: [*HEAD, f("intro", "Intro", "text"), f("button_label", "Card button", "string"),
     f("facility", "Facility", "record_ref", of_collection: "facilities", help: "Only the sizes this facility has. Blank: every size.")], defaults: {"button_label" => "Check availability"}},
  {slug: "checklist", label: "Checklist", icon: "ListChecks", description: "A heading and words beside a column of check-marked points.",
   fields: [*HEAD, f("body", "Words", "text"), f("items", "Points", "repeater", of: [f("title", "Title", "string", required: true), f("body", "Words", "text")]),
     f("background", "Background", "select", options: BACKGROUNDS)], defaults: {"background" => "muted"}},
  {slug: "chips", label: "Link chips", icon: "Tags", description: "A row of rounded links (projects that lead to the quote).",
   fields: [*HEAD, f("intro", "Intro", "text"), f("chips", "Chips", "repeater", of: LINK_ITEM), f("background", "Background", "select", options: BACKGROUNDS)],
   defaults: {"background" => "white"}},
  {slug: "card_grid", label: "Cards", icon: "LayoutGrid", description: "Cards in a grid: words, check marks, a link; big link cards; people.",
   fields: [*HEAD, f("intro", "Intro", "text"), f("columns", "Columns", "select", options: %w[2 3 4]), f("style", "Style", "select", options: %w[card icon person link panel]),
     f("align", "Heading", "select", options: %w[center left]), f("background", "Background", "select", options: BACKGROUNDS),
     f("cards", "Cards", "repeater", of: [f("eyebrow", "Eyebrow", "string"), f("title", "Title", "string", required: true), f("body", "Words", "markdown"),
       f("checklist", "Check marks", "string_list"), f("link", "Link", "link"), f("link_label", "Link text", "string"), f("dark", "Dark", "boolean")]),
     f("note", "Note below", "markdown", help: "A dark line with an icon under the cards, e.g. the 10'×10' doors.")],
   defaults: {"columns" => "3", "style" => "card", "align" => "center", "background" => "white"}},
  {slug: "split", label: "Two columns", icon: "Columns2", description: "Words (with a button, a price or facts) beside a list, a table, check marks or a photo.",
   fields: [*HEAD, f("body", "Words", "markdown"), *BUTTON, f("button_style", "Button style", "select", options: %w[primary secondary]),
     f("facts", "Facts", "repeater", of: [f("label", "Label", "string", required: true), f("value", "Value", "string")]),
     f("facts_style", "Facts style", "select", options: %w[boxes specs]),
     f("price_label", "Price label", "string"), f("price_value", "Price", "string"),
     f("right", "Beside it", "select", options: %w[list check_grid rows image]),
     f("right_eyebrow", "Beside it: eyebrow", "string"), f("right_heading", "Beside it: heading", "string"),
     f("list", "List", "string_list"), f("rows", "Table rows", "repeater", of: [f("label", "Label", "string", required: true), f("value", "Value", "string"), f("highlight", "Green", "boolean")]),
     f("image", "Photo", "asset"), f("background", "Background", "select", options: BACKGROUNDS), f("large_text", "Larger words", "boolean"),
     f("align", "Line up", "select", options: %w[center start])],
   defaults: {"align" => "center", "right" => "list", "background" => "white", "facts_style" => "boxes", "button_style" => "primary"}},
  {slug: "callout", label: "Callout", icon: "Info", description: "A dark panel with a hazard stripe and a button, or a small muted note.",
   fields: [f("style", "Style", "select", options: %w[hazard note]), *HEAD, f("body", "Words", "markdown"), *BUTTON],
   defaults: {"style" => "hazard"}},
  {slug: "facility_cards", label: "Facility cards", icon: "Building2", description: "A card per self-storage facility (the Facilities collection).",
   fields: [*HEAD, f("facilities", "Facilities", "record_refs", of_collection: "facilities"), f("price_label", "Beside the button", "string")],
   defaults: {"price_label" => "Reserve online"}},
  {slug: "facility_details", label: "Facility details", icon: "MapPin", description: "A facility's address, hours, phone and features beside its map, with its structured data.",
   fields: [*HEAD, f("facility", "Facility", "record_ref", of_collection: "facilities", required: true)]},
  {slug: "location_directory", label: "Service area directory", icon: "Map", description: "The cities served (the Locations collection), by county.",
   fields: [f("counties", "Counties", "repeater", of: [f("name", "County", "string", required: true), f("blurb", "Words", "string")])]},
  {slug: "map_embed", label: "Map", icon: "Map", description: "A Google map of a place.",
   fields: [*HEAD, f("intro", "Intro", "text"), f("query", "Place", "string", required: true), f("height", "Height (px)", "integer")],
   defaults: {"height" => 420}},
  {slug: "contact_details", label: "Contact details", icon: "Phone", description: "The phones, address, hours and map (Site settings), beside the lead form.",
   fields: [f("heading", "Heading", "string"), f("form_heading", "Lead form heading", "string")], defaults: {"heading" => "Reach us"}},
  {slug: "prose", label: "Text", icon: "Text", description: "Formatted text: an article, or a small note.",
   fields: [f("body", "Text", "markdown"), f("style", "Style", "select", options: %w[article small]), f("background", "Background", "select", options: BACKGROUNDS)],
   defaults: {"style" => "article", "background" => "white"}},
  {slug: "thank_you", label: "Thank you", icon: "PartyPopper", description: "Where the forms land: a thank-you, the phone number and two buttons.",
   fields: [f("heading", "Heading", "string"), f("body", "Words", "text"), f("call_line", "Call line", "string", help: "{phone} is the toll-free number, as a link."),
     f("buttons", "Buttons", "repeater", of: [*LINK_ITEM, f("style", "Style", "select", options: %w[primary secondary])]),
     f("event", "Analytics event", "string", help: "Sent to Google Analytics when the page opens, e.g. generate_lead.")]},
  {slug: "service_area_teaser", label: "Service area teaser", icon: "MapPinned", description: "A centred line naming the cities served, and a button.",
   fields: [*HEAD, f("body", "Words", "text", help: "{cities} is the first cities of the Locations collection."), f("count", "How many cities", "integer"), *BUTTON],
   defaults: {"count" => 9}},
  {slug: "quote_configurator", label: "3-D quote", icon: "Box", description: "The 3-D configurator: size it, price it, then hand off to the online quote.",
   fields: [f("product", "Product", "select", options: %w[dumpsters portable-storage shipping-containers], required: true),
     f("fuse_url", "Online quote address", "url", help: "Where \"Continue\" goes, e.g. https://affordabox.gofuse.app/web-quotes/quote.")],
   defaults: {"fuse_url" => "https://affordabox.gofuse.app/web-quotes/quote"}},
  *Landing::BLOCK_TYPES
].freeze
OLD_BLOCK_TYPES = %w[main_hero container_slider bento_grid two_col quote_form logo_slider photo_gallery two_col_banner image_cta products
  single_hero title_bar rich_text faqs container_listing locations image_gallery features testimonials image_text hours].freeze

COLLECTIONS = {
  "dumpsters" => {name: "Dumpster sizes", fields: [f("yards", "Cubic yards", "integer"), f("price", "Starting price ($)", "integer"), f("dims", "Dimensions", "string"),
    f("fits", "What it fits", "text"), f("examples", "Example projects", "string_list"), f("popular", "Most popular", "boolean"), f("image", "Photo", "asset"),
    f("length_ft", "Length (ft, 3-D quote)", "integer"), f("height_ft", "Height (ft, 3-D quote)", "string"), f("order", "Order", "integer")]},
  "containers" => {name: "Containers", fields: [f("size", "Length", "select", options: ["20'", "40'"]),
    f("condition", "Condition", "select", options: ["New (one-trip)", "Used (cargo-worthy)"]), f("type", "Type", "select", options: %w[Standard High-Cube Double-Door Side-Door]),
    f("price", "Starting price ($)", "integer", help: "Blank shows Get a quote."), f("fits", "Words", "text"), f("popular", "Most popular", "boolean"),
    f("image", "Photo", "asset"), f("order", "Order", "integer")]},
  "portable-sizes" => {name: "Portable sizes", fields: [f("dims", "Dimensions", "string"), f("fits", "What it fits", "text"), f("rooms", "Rooms", "string"),
    f("monthly", "Monthly rate ($/mo, 3-D quote)", "integer"), f("popular", "Most popular", "boolean"), f("order", "Order", "integer")]},
  "storage-units" => {name: "Storage units", fields: [f("sqft", "Square feet", "integer"), f("fits", "What it fits", "text"),
    f("category", "Kind", "select", options: %w[drive-up climate oversized]), f("online_rate", "Online rate ($/mo)", "integer"), f("in_store_rate", "In-store rate ($/mo)", "integer"),
    f("facilities", "Facilities", "record_refs", of_collection: "facilities", help: "The facilities that have this size. None ticked: every facility."),
    f("image", "Photo", "asset"), f("order", "Order", "integer")]},
  "facilities" => {name: "Facilities", fields: [f("street", "Street", "string"), f("city", "City", "string"), f("state", "State", "string"), f("zip", "ZIP", "string"),
    f("lat", "Latitude", "string"), f("lng", "Longitude", "string"), f("features", "Features", "string_list"), f("blurb", "Words", "text"),
    f("office_hours", "Office hours", "string", help: "Blank: Site settings › Hours."), f("access_hours", "Gate access hours", "string"),
    f("image", "Photo", "asset"), f("link", "Its page", "link"), f("order", "Order", "integer")]},
  "locations" => {name: "Locations", fields: [f("city", "City", "string", required: true), f("zips", "ZIP codes", "string_list"), f("county", "County", "string"),
    f("tier", "Priority (1–3)", "integer"), f("services", "Services", "string_list", help: "Any of: dumpster, container-buy, container-rent, portable, self-storage."),
    f("nearby", "Nearby cities", "record_refs", of_collection: "locations"), f("blurb", "Words", "text"), f("order", "Order", "integer")]},
  "reviews" => {name: "Reviews", fields: [f("name", "Name", "string"), f("context", "Shown under it", "string"), f("tags", "Pages it suits", "string_list", help: REVIEW_CONTEXTS.join(", ")),
    f("quote", "Review", "text", required: true), f("rating", "Stars", "integer"), f("source", "Source", "string"), f("order", "Order", "integer")]},
  "faqs" => {name: "FAQs", fields: [f("answer", "Answer", "text", required: true), f("group", "Group", "select", options: FAQ_GROUPS), f("order", "Order", "integer")]}
}.freeze

GLOBALS = {
  "site_settings" => {name: "Site settings", fields: [
    f("name", "Business name", "string"), f("tagline", "Tagline", "string"), f("toll_free", "Toll-free phone", "string"), f("local_phone", "Local phone", "string"),
    f("email", "Email", "string"),
    f("address", "Address", "group", of: [f("street", "Street", "string"), f("city", "City", "string"), f("state", "State", "string"), f("zip", "ZIP", "string"),
      f("county", "County", "string"), f("lat", "Latitude", "string"), f("lng", "Longitude", "string")]),
    f("hours", "Hours", "string"), f("hours_detailed", "Hours by day (structured data)", "repeater", of: [f("day", "Day", "string"), f("open", "Opens (HH:MM)", "string"), f("close", "Closes", "string")]),
    f("primary_counties", "Counties served", "string_list"), f("founded_year", "Founded (year)", "integer", help: "Blank says \"Locally owned & operated\"."),
    f("rating", "Google rating", "string"), f("review_count", "Google review count", "integer", help: "Blank leaves the count out, and the rating out of the structured data."),
    f("social", "Social", "group", of: [f("facebook", "Facebook", "url"), f("instagram", "Instagram", "url"), f("youtube", "YouTube", "url"), f("google", "Google reviews", "url")]),
    f("pods_disclaimer", "PODS disclaimer", "text"), f("trust_items", "Trust items", "string_list"),
    f("logo", "Logo", "asset"), f("logo_white", "Logo on dark", "asset"), f("favicon", "Favicon", "asset"), f("share_image", "Default sharing image", "asset"),
    f("lead_form", "Lead form", "group", of: [f("subtitle", "Under the heading", "string"), f("note", "Below the button", "string"),
      f("use_cases", "What's it for?", "string_list")]),
    f("exit_modal", "Exit-intent popup", "group", of: [f("enabled", "Show it", "boolean"), f("title", "Title", "string"), f("subtitle", "Words", "text"),
      f("cta_label", "Button", "string"), f("cta_link", "Goes to", "link")]),
    f("not_found", "Page not found", "group", of: [f("heading", "Heading", "string"), f("body", "Words", "text"), f("links", "Services to jump to", "repeater", of: LINK_ITEM)])]},
  "nav" => {name: "Menu", fields: [
    f("megas", "Menus", "repeater", of: [*LINK_ITEM, f("image", "Photo", "asset"),
      f("columns", "Columns", "repeater", of: [f("heading", "Heading", "string"),
        f("links", "Links", "repeater", of: [*LINK_ITEM, f("meta", "Beside it", "string"), f("badge", "Badge", "string")])]),
      f("featured_eyebrow", "Promo eyebrow", "string"), f("featured_title", "Promo title", "string"), f("featured_cta", "Promo link text", "string"), f("featured_link", "Promo link", "link")]),
    f("links", "Plain links", "repeater", of: LINK_ITEM), f("cro_items", "Under the menus", "string_list"),
    f("cta_label", "Button", "string"), f("cta_link", "Button link", "link")]},
  "footer" => {name: "Footer", fields: [f("blurb", "Words", "text"),
    f("columns", "Columns", "repeater", of: [f("heading", "Heading", "string"), f("links", "Links", "repeater", of: LINK_ITEM)]),
    f("area_heading", "Service area heading", "string"), f("area_count", "How many cities", "integer"), f("area_all_label", "All locations link", "string"),
    f("legal_links", "Legal links", "repeater", of: LINK_ITEM), f("copyright", "Copyright line", "string", help: "{year} is this year; {name} the business name.")]}
}.freeze

PAGE_FIELDS = [f("exit_modal", "Exit-intent popup", "select", options: %w[on off], sidebar: true, help: "Off on pages after a form is sent."), Landing::LAYOUT_FIELD].freeze

# ===== The content =====

def entries
  {
    "dumpsters" => [
      ["10-yard", "10 Yard", {yards: 10, price: 419, dims: "≈ 12' L × 8' W × 3.5' H", fits: "Small cleanouts, single rooms, and yard projects.",
        examples: ["Garage or basement cleanout", "Small bathroom remodel", "Yard & landscaping debris"], image: img("dumpsters/10-yard.jpg", alt: "AffordABox 10 Yard roll-off dumpster"), length_ft: 12, height_ft: "3.5"}],
      ["15-yard", "15 Yard", {yards: 15, price: 499, dims: "≈ 14' L × 8' W × 4' H", fits: "Medium projects and whole-room remodels.",
        examples: ["Kitchen remodel", "Flooring tear-out", "Large garage cleanout"], popular: true, image: img("dumpsters/15-yard.jpg", alt: "AffordABox 15 Yard roll-off dumpster"), length_ft: 14, height_ft: "4"}],
      ["20-yard", "20 Yard", {yards: 20, price: 549, dims: "≈ 16' L × 8' W × 4.5' H", fits: "Larger renovations and multi-room cleanouts.",
        examples: ["Whole-home cleanout", "Roof tear-off", "Deck or fence removal"], image: img("dumpsters/studio.jpg", alt: "AffordABox 20 Yard roll-off dumpster"), length_ft: 16, height_ft: "4.5"}],
      ["25-yard", "25 Yard", {yards: 25, price: 629, dims: "≈ 18' L × 8' W × 5' H", fits: "Big construction, demo, and estate jobs.",
        examples: ["Construction debris", "Estate / hoarder cleanout", "Major renovation"], image: img("cms/dumpster-25yd.jpg", alt: "AffordABox 25 Yard roll-off dumpster"), length_ft: 18, height_ft: "5"}]
    ],
    "containers" => [
      ["20-standard-new", "20' Standard — New (one-trip)", {size: "20'", condition: "New (one-trip)", type: "Standard", price: 3500, fits: "Like-new, single-use container. Clean, dry, and ready for storage or builds.", popular: true}],
      ["20-highcube-new", "20' High-Cube — New (one-trip)", {size: "20'", condition: "New (one-trip)", type: "High-Cube", price: 3800, fits: "Extra foot of height (9'6\") for tall equipment or comfortable workshops."}],
      ["20-double-door-new", "20' Double-Door — New", {size: "20'", condition: "New (one-trip)", type: "Double-Door", fits: "Doors on both ends for drive-through access and easy loading."}],
      ["20-side-door-new", "20' Side-Door — New", {size: "20'", condition: "New (one-trip)", type: "Side-Door", fits: "Full-length side opening for pallets, retail, or workshop layouts."}],
      ["40-standard-new", "40' Standard — New (one-trip)", {size: "40'", condition: "New (one-trip)", type: "Standard", price: 5500, fits: "Maximum capacity for large storage or multi-use conversions."}],
      ["40-highcube-new", "40' High-Cube — New (one-trip)", {size: "40'", condition: "New (one-trip)", type: "High-Cube", price: 5900, fits: "Tallest, roomiest option — ideal for offices, gyms, and tall inventory."}],
      ["20-standard-used", "20' Standard — Used (cargo-worthy)", {size: "20'", condition: "Used (cargo-worthy)", type: "Standard", price: 1800, fits: "Wind- and water-tight at the best price. Honest cosmetic wear only.", popular: true}],
      ["40-standard-used", "40' Standard — Used (cargo-worthy)", {size: "40'", condition: "Used (cargo-worthy)", type: "Standard", price: 3200, fits: "Big, budget-friendly, and structurally sound for site storage."}]
    ].map { |slug, title, data| [slug, title, data.merge(image: img(data[:size] == "40'" ? "cms/container-40hc.jpg" : "cms/container-20-stacked.jpg"))] },
    "portable-sizes" => [
      ["8x8", "8' × 8'", {monthly: 149, dims: "8' W × 8' L × 8' H", fits: "A studio apartment or a single room's worth of furniture and boxes.", rooms: "Studio / 1 room"}],
      ["8x12", "8' × 12'", {monthly: 179, dims: "8' W × 12' L × 8' H", fits: "A 1–2 bedroom home or a mid-size remodel's contents.", rooms: "1–2 bedrooms"}],
      ["8x16", "8' × 16'", {monthly: 199, dims: "8' W × 16' L × 8' H", fits: "A 2–3 bedroom home, the most popular size for moves and renos.", rooms: "2–3 bedrooms", popular: true}],
      ["8x20", "8' × 20'", {monthly: 239, dims: "8' W × 20' L × 8' H", fits: "A full 3–4 bedroom home or a large job site's materials.", rooms: "3–4 bedrooms"}]
    ],
    "storage-units" => [
      ["5x5", "5 × 5", {sqft: 25, fits: "Closet — boxes, seasonal items, small furniture.", category: "drive-up"}],
      ["5x10", "5 × 10", {sqft: 50, fits: "Half a garage — 1 room of furniture.", category: "drive-up", image: img("cms/unit-5x10.jpg", alt: "What fits in a 5 × 10 storage unit")}],
      ["10x10", "10 × 10", {sqft: 100, fits: "1–2 bedrooms of furniture and boxes.", category: "climate", image: img("cms/unit-10x10.jpg", alt: "What fits in a 10 × 10 storage unit")}],
      ["10x15", "10 × 15", {sqft: 150, fits: "2–3 bedrooms, appliances, and boxes.", category: "drive-up", image: img("cms/unit-10x15.jpg", alt: "What fits in a 10 × 15 storage unit")}],
      ["10x20", "10 × 20", {sqft: 200, fits: "A full house or a car plus storage.", category: "drive-up", image: img("cms/unit-10x20.jpg", alt: "What fits in a 10 × 20 storage unit")}],
      ["10x30", "10 × 30", {sqft: 300, fits: "A large home, vehicle, or business inventory.", category: "oversized"}],
      ["oversized-10ft-door", "Oversized (10' door)", {sqft: 300, fits: "Boats, campers, trailers, and fish houses.", category: "oversized"}]
    ],
    "facilities" => [
      ["monticello", "AffordABox Self-Storage — Monticello", {street: "10111 Innsbrook Drive", city: "Monticello", state: "MN", zip: "55362", lat: "45.2972", lng: "-93.7611",
        features: ["Drive-up access", "Climate-controlled units", "Oversized units for boats & campers", "Month-to-month, online discounts", "Well-lit, secure facility"],
        blurb: "Our Monticello facility on Innsbrook Drive offers drive-up and climate-controlled units just off I-94 — park, load, and go without icy hallways, with oversized doors built for Minnesota boats and campers.",
        image: img("cms/facility-aisle.jpg", alt: "AffordABox self-storage in Monticello, MN"), link: page("self-storage/monticello")}],
      ["st-michael", "AffordABox Self-Storage — St. Michael", {street: "12231 43rd St NE", city: "St. Michael", state: "MN", zip: "55376", lat: "45.2102", lng: "-93.6647",
        features: ["Drive-up access", "Indoor & climate-controlled units", "Co-located with our delivery yard", "Month-to-month, online discounts", "Well-lit, secure facility"],
        blurb: "At the heart of our St. Michael yard, this facility pairs drive-up convenience with indoor climate-controlled units for Wright County renters who want quick, local access.",
        image: img("cms/facility-stmichael.jpg", alt: "AffordABox self-storage in St. Michael, MN"), link: page("self-storage/st-michael")}]
    ],
    "locations" => LOCATIONS.map { |slug, city, zips, county, tier, nearby, blurb| [slug, "#{city}, MN", {city:, zips:, county:, tier:, nearby:, blurb:,
      services: ALL_SERVICES + (%w[st-michael monticello].include?(slug) ? ["self-storage"] : [])}] },
    "reviews" => [
      ["moved-with-two-units", "Moved with 2 units in June", {tags: %w[moving portable general], quote: "I used 2 units from AffordABox to move ourselves in June. Customer service was very responsive and communication was concise and accurate. Delivery was on time and friendly, the units were clean and well maintained, and the value was outstanding. I'd use them again without hesitation."}],
      ["floor-reno-storage", "Storage during a floor reno", {tags: %w[portable moving general], quote: "We needed a portable storage unit while our floors were redone after water damage. The unit was delivered promptly and maneuvered down our driveway with a remote control. AffordABox did everything they promised — and their rates are cheaper, only $79 drop-off and next-day service."}],
      ["reliability-and-delivery", "Reliability & delivery", {tags: %w[general portable container], quote: "AffordABox was the only vendor I've worked with to actually provide a quality product and prompt delivery. They stood by everything they promised and executed to perfection."}],
      ["storage-and-moving", "Storage & moving", {tags: %w[general portable moving], quote: "100% recommend AffordABox for all storage and moving needs. Friendly and responsive staff, excellent pricing, quick delivery and pickup, and well-designed, clean containers."}]
    ].map { |slug, context, data| [slug, context, data.merge(name: "Verified Customer", context:, rating: 5, source: "Google")] },
    "faqs" => FAQS.flat_map { |group, list| list.each_with_index.map { |(q, a), i| ["#{group}-#{i + 1}", q, {answer: a, group:}] } }
  }
end

ALL_SERVICES = %w[dumpster container-buy container-rent portable].freeze
LOCATIONS = [
  ["st-michael", "St. Michael", ["55376"], "Wright", 1, %w[albertville otsego monticello buffalo], "Home of our yard at 12231 43rd St NE — we offer same-day and next-day delivery across St. Michael and all of Wright County, the fastest turnaround anywhere in our footprint."],
  ["monticello", "Monticello", ["55362"], "Wright", 1, %w[st-michael big-lake buffalo albertville], "Portable storage, roll-off dumpsters and containers reach Monticello in a day, and our drive-up self-storage facility on Innsbrook Drive serves the Lake Maria and I-94 corridor year-round."],
  ["elk-river", "Elk River", ["55330"], "Sherburne", 1, %w[otsego big-lake anoka rogers], "Just across the Mississippi from our Otsego neighbors, Elk River sits a short hop up Highway 101 from our St. Michael yard for quick dumpster drops and Mule-delivered storage in Sherburne County."],
  ["buffalo", "Buffalo", ["55313"], "Wright", 1, %w[st-michael monticello albertville], "The Wright County seat is core territory for us — homeowners around Buffalo Lake and contractors downtown count on next-day dumpsters and driveway-friendly portable storage."],
  ["anoka", "Anoka", ["55303"], "Anoka", 1, %w[andover dayton rogers], "One of our strongest converting markets, Anoka gets fast roll-off and container delivery where the Rum meets the Mississippi, serving renovation and cleanout projects across Anoka County."],
  ["minneapolis", "Minneapolis", %w[55401 55411 55412 55418 55430], "Hennepin", 1, %w[maple-grove dayton rogers], "We bring the same local, no-call-center service into the city — the Mule shines in tight Minneapolis driveways and alleys where the big national outfits won't go."],
  ["andover", "Andover", ["55304"], "Anoka", 2, %w[anoka dayton rogers], "Growing Andover neighborhoods lean on us for remodel dumpsters and on-site storage, an easy run up from the metro edge through Anoka County."],
  ["rogers", "Rogers", ["55374"], "Hennepin", 2, %w[dayton otsego st-michael maple-grove], "Sitting right on the I-94 corridor between our yard and the metro, Rogers gets some of our quickest delivery windows for containers and dumpsters alike."],
  ["albertville", "Albertville", ["55301"], "Wright", 2, %w[st-michael otsego monticello], "Practically next door to our St. Michael yard, Albertville and the outlet-mall area see near-instant delivery on everything from 10-yard dumpsters to 8×20 portable units."],
  ["otsego", "Otsego", %w[55330 55301], "Wright", 2, %w[st-michael elk-river albertville rogers], "Bordering both St. Michael and Elk River, Otsego is one of our most-served towns — the Mule places units cleanly in newer subdivisions without touching the lawn or driveway."],
  ["dayton", "Dayton", ["55327"], "Hennepin", 2, %w[rogers anoka andover maple-grove], "At the meeting point of Hennepin, Anoka and Wright counties, Dayton's fast-growing developments are an easy delivery for dumpsters, containers and portable storage."],
  ["big-lake", "Big Lake", ["55309"], "Sherburne", 2, %w[monticello elk-river], "Up the Highway 10 corridor in Sherburne County, Big Lake homeowners use us for lake-property cleanouts, off-season toy storage and renovation dumpsters."],
  ["maple-grove", "Maple Grove", %w[55311 55369], "Hennepin", 2, %w[rogers dayton minneapolis], "A busy metro-edge suburb, Maple Grove relies on us for renovation roll-offs and driveway storage with the kind of personal scheduling the national chains can't match."],
  ["hamel", "Hamel", ["55340"], "Hennepin", 3, %w[rogers maple-grove loretto], "The Hamel and Medina area gets the same tight-driveway Mule delivery and transparent pricing, an easy run down Highway 55 from our Wright County base."],
  ["loretto", "Loretto", ["55357"], "Hennepin", 3, %w[hamel rogers maple-grove], "Small-town Loretto and the surrounding Medina countryside are well within our quick-delivery range for dumpsters, containers and portable storage."]
].freeze

FAQS = {
  "dumpster" => [
    ["What's included in the dumpster rental price?", "Every dumpster is a flat rate that includes delivery, a 7-day rental period, pickup, and disposal of up to 5,000 lbs. There are no surprise fees — anything over the included tonnage is billed at a simple $0.10 per pound."],
    ["How fast can you deliver a dumpster?", "We deliver as soon as next-day across our service area, and same-day is often available near our St. Michael yard. Tell us your ZIP and we'll confirm the soonest window."],
    ["What can I put in the dumpster?", "Most household junk, renovation debris, furniture, roofing, and yard waste are fine. Hazardous materials, tires, batteries, paint, and appliances with refrigerant need special handling — just ask and we'll point you the right way."],
    ["Do I have to pay up front?", "No. $0 is due until your dumpster is delivered, so you only pay once it's in your driveway."],
    ["Will the dumpster damage my driveway?", "We take care with placement and can use boards to protect your surface. Let us know about tight or delicate driveways when you book."],
    ["What size dumpster do I need?", "A 10-yard suits small cleanouts, 15-yard fits a room remodel, 20-yard handles larger renovations, and 25-yard is for big demo or estate jobs. Not sure? A real local person will size it with you in about two minutes."]
  ],
  "container-buy" => [
    ["What's the difference between new and used containers?", "New (one-trip) containers have made a single cargo voyage and look nearly pristine. Used (cargo-worthy) containers are wind- and water-tight with honest cosmetic wear at a lower price. Both are structurally sound for storage."],
    ["How much does a shipping container cost?", "Used 20' containers start around $1,800 and new one-trip 20' containers start around $3,500, with 40' and high-cube options priced higher. We show real starting prices — never \"call for price.\""],
    ["What's the difference between standard and high-cube?", "High-cube containers are a foot taller (9'6\" vs 8'6\"), giving you extra headroom for tall equipment, shelving, or comfortable workshop and office conversions."],
    ["How is the container delivered and how much clearance do I need?", "We deliver on a tilt-bed truck. Plan for roughly the container length plus the truck — about 60 feet of straight clearance for a 20' and more for a 40' — on firm, level ground. We'll review your site with you before delivery."],
    ["Which way do the doors face when delivered?", "You choose. Tell us whether you want the doors at the front or rear of the placement and we'll set it down accordingly."],
    ["Can you modify a container?", "Yes — doors, windows, vents, electrical, and custom builds are available. Tell us your plan and we'll quote the modifications."]
  ],
  "container-rent" => [
    ["Can I rent a container month-to-month?", "Yes. Container rentals are month-to-month with no long-term contract — keep it for a single project or as long as you need."],
    ["Do you deliver and pick up the rental?", "We deliver it to your site and pick it up when you're done. Delivery is available as soon as next-day across our service area."],
    ["What can I use a rented container for?", "On-site project storage, a workshop, a portable office, overflow inventory, or seasonal and event storage — they're wind- and water-tight and lock securely."],
    ["Should I rent or buy?", "Rent if it's for a defined project or short-to-medium term; buy if you'll need on-site storage indefinitely. We're happy to talk through the math for your situation."]
  ],
  "portable" => [
    ["How much does portable storage cost?", "Portable storage starts at $149/mo plus a $79 delivery fee, with $0 due until your unit is delivered. It's month-to-month with no change or cancel fees."],
    ["What is the Mule Delivery System?", "The Mule is a remote-controlled system that places your unit precisely into tight driveways and alleys without damaging your driveway or yard, and it keeps the unit level so your contents don't shift during transport."],
    ["What size unit do I need?", "An 8×8 holds a studio, 8×12 fits 1–2 bedrooms, 8×16 (our most popular) suits 2–3 bedrooms, and 8×20 handles a full 3–4 bedroom home. Each unit holds about 4,500 lbs."],
    ["How long can I keep the unit?", "As long as you like — it's month-to-month with no long-term contract and no change or cancellation fees."],
    ["Can I store a boat, trailer, or fish house?", "Ask about units with 10'×10' doors built for Minnesota toys like boats, trailers, and fish houses."],
    ["Is AffordABox the same as PODS?", "No. AffordABox is a locally owned Minnesota company and is not associated with PODS. PODS is a registered trademark of The Procter & Gamble Company."]
  ],
  "self-storage" => [
    ["Where are your self-storage facilities?", "We have two Minnesota facilities: Monticello (10111 Innsbrook Drive) and St. Michael (at our 43rd St NE yard). Both offer drive-up and climate-controlled units."],
    ["What's the difference between drive-up and climate-controlled?", "Drive-up units let you pull right up and load without hallways — ideal in Minnesota winters. Climate-controlled units hold a steadier temperature for sensitive items like electronics, documents, and furniture."],
    ["Can I reserve a unit online?", "Yes — reserve online with no credit card required to hold your unit, and ask about online-only rate discounts. If a size shows as unavailable, leave your info and we'll call the moment one opens."],
    ["Do you have units for boats or campers?", "Yes — we offer oversized units with 10' doors for boats, campers, trailers, and other large vehicles."],
    ["What are the access hours?", "Access hours are posted at each facility; office hours are Mon–Fri 8AM–5PM CT. Contact us for current gate-access details."]
  ],
  "home" => [
    ["What areas do you serve?", "We serve Minnesota only — primarily St. Michael and Wright County, Sherburne County, and the northwest Twin Cities metro through Hennepin and Anoka counties, including Monticello, Elk River, Buffalo, Anoka, Rogers, Albertville, and Otsego."],
    ["How fast can you deliver?", "As soon as next-day across our service area, with same-day often available near our St. Michael yard."],
    ["Do I pay anything up front?", "No — $0 is due until your dumpster, container, or storage unit is delivered."],
    ["Do I talk to a real person?", "Always. There are no call centers — a real local person answers the phone and usually replies to quote requests within the hour."],
    ["Are your prices really online?", "Yes. We publish real starting prices for dumpsters, containers, and portable storage so you can see the price and book in about two minutes — no \"call for price\" runaround."],
    ["Can I rent month-to-month?", "Yes — portable storage, container rentals, and self-storage are all month-to-month with no long-term contracts and no change or cancel fees."]
  ]
}.freeze

def globals_data
  {
    "site_settings" => {
      "name" => "AffordABox", "tagline" => "Dumpsters, Containers & Storage — Priced Online, Delivered Local.",
      "toll_free" => "(833) 468-2269", "local_phone" => "(763) 314-0480", "email" => "info@golumin.io",
      "address" => {"street" => "12231 43rd St NE", "city" => "St. Michael", "state" => "MN", "zip" => "55376", "county" => "Wright", "lat" => "45.2102", "lng" => "-93.6647"},
      "hours" => "Mon–Fri 8AM–5PM CT",
      "hours_detailed" => %w[Monday Tuesday Wednesday Thursday Friday].map { {"day" => it, "open" => "08:00", "close" => "17:00"} },
      "primary_counties" => %w[Wright Sherburne Hennepin Anoka Stearns], "rating" => "5.0",
      "social" => {"facebook" => "https://www.facebook.com/gotabox/"},
      "pods_disclaimer" => "AffordABox is not associated with PODS. PODS is a registered trademark of The Procter & Gamble Company.",
      "trust_items" => ["Locally owned", "Next-day delivery", "$0 until it arrives", "No call centers", "Month-to-month"],
      "logo" => img("general/logo/logo.png", alt: "AffordABox — Dumpsters, Containers & Storage"), "logo_white" => img("general/logo/logo-white.png", alt: "AffordABox"),
      "favicon" => img("general/logo/favicon.png", alt: "AffordABox"), "share_image" => img("cms/portable-fleet.jpg", alt: "AffordABox portable storage units and delivery truck"),
      "lead_form" => {"subtitle" => "See the price, book the box — in about 2 minutes.", "note" => "🔒 No spam. A real local person replies — usually within the hour. No call centers.",
        "use_cases" => ["Moving", "Remodel / Renovation", "Construction / Job site", "Decluttering", "Business", "Event"]},
      "exit_modal" => {"enabled" => true, "title" => "Not sure what size you need?", "subtitle" => "Grab our free Size & Pricing Guide and we'll text you a quote — no guessing, no pressure.",
        "cta_label" => "Text me a quote", "cta_link" => page("get-a-quote")},
      "not_found" => {"heading" => "Page not found", "body" => "We couldn't find that page. It may have moved — but we can still get you the right box.",
        "links" => [["Dumpster Rentals", "dumpster-rentals"], ["Shipping Containers", "shipping-containers/buy"], ["Portable Storage", "portable-storage"], ["Self Storage", "self-storage"]].map { |l, p| {"label" => l, "link" => page(p)} }}
    },
    "nav" => {
      "megas" => [
        {"label" => "Dumpsters", "link" => page("dumpster-rentals"), "image" => img("cms/dumpster-25yd.jpg"),
         "columns" => [{"heading" => "By size — flat rate", "links" => [["10 Yard", "From $419"], ["15 Yard", "From $499", "Popular"], ["20 Yard", "From $549"], ["25 Yard", "From $629"]].map { |l, m, bdg| {"label" => l, "link" => page("dumpster-rentals"), "meta" => m, "badge" => bdg}.compact }},
           {"heading" => "By project", "links" => [["Home cleanout", "Decluttering"], ["Remodel / reno", "Remodel / Renovation"], ["Roofing", "Construction / Job site"], ["Construction", "Construction / Job site"]].map { |l, use| {"label" => l, "link" => url("/get-a-quote?service=Dumpster&use=#{URI.encode_www_form_component(use).gsub("+", "%20")}")} }}],
         "featured_eyebrow" => "Flat-rate pricing", "featured_title" => "Priced online. $0 due until delivery.", "featured_cta" => "See dumpster prices", "featured_link" => page("dumpster-rentals")},
        {"label" => "Containers", "link" => page("shipping-containers/buy"), "image" => img("cms/container-40hc.jpg"),
         "columns" => [{"heading" => "Buy a container", "links" => ["20' Standard", "40' High-Cube", "New (one-trip)", "Used (cargo-worthy)"].map { {"label" => it, "link" => page("shipping-containers/buy")} }},
           {"heading" => "Rent a container", "links" => ["Monthly rental", "On-site storage", "Portable office", "Workshop"].map { {"label" => it, "link" => page("shipping-containers/rent")} }}],
         "featured_eyebrow" => "Buy or rent", "featured_title" => "Wind & water-tight, delivered local.", "featured_cta" => "Browse containers", "featured_link" => page("shipping-containers/buy")},
        {"label" => "Storage", "link" => page("portable-storage"), "image" => img("cms/portable-fleet.jpg"),
         "columns" => [{"heading" => "Portable storage", "links" => [["How the Mule works"], ["Sizes 8×8 – 8×20"], ["Moving & remodels"], ["From $149/mo", nil, "Signature"]].map { |l, m, bdg| {"label" => l, "link" => page("portable-storage"), "meta" => m, "badge" => bdg}.compact }},
           {"heading" => "Self-storage facilities", "links" => [["Monticello", "self-storage/monticello", "Innsbrook Drive"], ["St. Michael", "self-storage/st-michael", "43rd St NE"], ["Compare unit sizes", "self-storage"], ["Reserve online", "self-storage"]].map { |l, p, m| {"label" => l, "link" => page(p), "meta" => m}.compact }}],
         "featured_eyebrow" => "Delivered by the Mule", "featured_title" => "Storage in your driveway. $0 until it arrives.", "featured_cta" => "Get portable storage", "featured_link" => page("portable-storage")}
      ],
      "links" => [{"label" => "Locations", "link" => page("locations")}, {"label" => "Reviews", "link" => page("reviews")}],
      "cro_items" => ["$0 until delivery", "Next-day", "No call centers"], "cta_label" => "Get a Quote", "cta_link" => page("get-a-quote")
    },
    "footer" => {
      "blurb" => "Dumpsters, containers, and storage — priced online and delivered local. {ownership}. A real local person answers the phone, no call centers.",
      "columns" => [
        {"heading" => "Services", "links" => [["Dumpster Rentals", "dumpster-rentals"], ["Buy a Container", "shipping-containers/buy"], ["Rent a Container", "shipping-containers/rent"], ["Portable Storage", "portable-storage"], ["Self-Storage", "self-storage"]].map { |l, p| {"label" => l, "link" => page(p)} }},
        {"heading" => "Company", "links" => [["About Us", "about"], ["Reviews", "reviews"], ["Contact", "contact"], ["Get a Quote", "get-a-quote"]].map { |l, p| {"label" => l, "link" => page(p)} }}
      ],
      "area_heading" => "Service Area", "area_count" => 6, "area_all_label" => "All locations →",
      "legal_links" => [{"label" => "Privacy Policy", "link" => page("privacy")}, {"label" => "Terms of Service", "link" => page("terms")}],
      "copyright" => "© {year} {name}. All rights reserved."
    }
  }
end

# ===== Pages =====

CHECKS_HOME = ["Next-day delivery", "$0 until delivery", "No call centers"].freeze
MULE = {eyebrow: "— The AffordABox advantage", heading: "Meet the Mule",
  body: "Our Mule Delivery System is the difference between a storage box dropped wherever the truck can reach — and one placed exactly where you need it. It's the local edge the national outfits simply don't have.",
  points: [["Remote-controlled placement", "We guide your unit into tight driveways and alleys by remote — exactly where you want it."],
    ["No driveway or lawn damage", "The Mule sets the box down gently, so your concrete and grass stay just as they were."],
    ["Stays level the whole way", "Your contents ride flat and don't shift in transport — nothing tips, slides, or breaks."]].map { |t, d| {"title" => t, "body" => d} },
  badge_value: "$0", badge_label: "due until it arrives", dark: true}.freeze
STEPS = {eyebrow: "— How it works", heading: "Three steps, about two minutes",
  steps: [["Tell us what you need", "Enter your ZIP and pick a service — our 2-minute quote does the rest."],
    ["Get a real human + a price", "A local person (never a call center) replies fast with a clear, upfront price."],
    ["We deliver next-day with the Mule", "We place it precisely in your driveway — no damage, no hassle, $0 until it arrives."]].map { |t, d| {"title" => t, "body" => d} }}.freeze
def mule(**overrides) = b("feature_split", MULE.merge(image: img("cms/mule-delivery.jpg", alt: "The AffordABox Mule remote-control system delivering a portable storage unit on a trailer"), button_label: "See portable storage", button_link: page("portable-storage")).merge(overrides))
def steps = b("process_steps", STEPS)
def reviews(context = "general", **rest) = b("reviews", {eyebrow: "— Reviews", heading: "What our neighbors say", context:, limit: 3, layout: "feed"}.merge(rest))
def faq(group, heading, **rest) = b("faq", {eyebrow: "— FAQ", heading:, group:, style: "simple", schema: true}.merge(rest))
def cta(service = "any", **rest) = b("cta_band", {heading: "Ready to get started?", body: "See your price and book in about two minutes — or call and talk to a real local person.", service:, note: "Mon–Fri 8AM–5PM CT · No call centers"}.merge(rest))
def crumbs(label = nil) = b("breadcrumbs", {current_label: label})
def hero(**data) = b("page_hero", {style: "photo", layout: "split", padding: "large", heading_size: "large", photo_opacity: "20"}.merge(data))
def text_hero(**data) = b("page_hero", {style: "plain", layout: "left", padding: "medium", heading_size: "large"}.merge(data))
def cards(*list) = list.map { |card| card.transform_keys(&:to_s).compact }

def pages
  {
    "home" => {title: "Home", seo: ["Dumpsters, Containers & Storage in Minnesota | Affordabox", "See the price and book in 2 minutes. Roll-off dumpsters, shipping containers, and portable storage delivered next-day across St. Michael, Wright County & the NW Twin Cities metro. Locally owned, no call centers."],
      blocks: [
        hero(style: "video", video: img("hero.mp4"), photo: img("hero-poster.jpg", alt: "AffordABox delivery"), padding: "tall",
          eyebrow: "— Serving the Twin Cities NW metro & Wright County", heading: "Dumpsters, Containers & Storage — Priced Online, Delivered Local.",
          body: "See the price, book the box in 2 minutes, and we'll be there as soon as tomorrow. Locally owned. Real people answer the phone.",
          checklist: CHECKS_HOME, form_heading: "Get your free quote", form_service: "any"),
        b("trust_bar"),
        b("product_router", eyebrow: "— What can we deliver?", heading: "Pick your service. See the price.", intro: "Every option is priced upfront and delivered local — usually as soon as next-day.", cta_label: "Start",
          cards: cards(
            {title: "Dumpster Rentals", link: page("dumpster-rentals"), price: "From $419", blurb: "Flat-rate roll-offs, 10–25 yard. Delivery, pickup & disposal included.", image: img("cms/dumpster-25yd.jpg")},
            {title: "Buy a Container", link: page("shipping-containers/buy"), price: "From $1,800", blurb: "New & used 20' and 40' containers. Real prices, no “call for quote.”", image: img("cms/container-40hc.jpg")},
            {title: "Rent a Container", link: page("shipping-containers/rent"), price: "Monthly rates", blurb: "The same fleet, month-to-month. Delivered and picked up when you're done.", image: img("cms/container-20-stacked.jpg")},
            {title: "Portable Storage", link: page("portable-storage"), price: "From $149/mo", blurb: "The white box, delivered to your driveway by the Mule. Load on your schedule.", image: img("cms/portable-fleet.jpg"), featured: true, badge: "Most popular"},
            {title: "Self-Storage", link: page("self-storage"), price: "Reserve online", blurb: "Drive-up & climate-controlled units in Monticello and St. Michael.", image: img("cms/facility-stmichael.jpg")})),
        mule, steps, reviews,
        b("service_area_teaser", eyebrow: "— Where we deliver", heading: "Proudly local across Minnesota's NW metro",
          body: "Serving {cities} and the surrounding Wright, Sherburne, Hennepin & Anoka county communities.", count: 9, button_label: "Find your city", button_link: page("locations")),
        faq("home", "Common questions"), cta
      ]},
    "get-a-quote" => {title: "Get a Quote", seo: ["Get Your Free Quote — Dumpsters, Containers & Storage | Affordabox", "Get your free AffordABox quote in about 2 minutes. A real local person replies — no call centers. $0 until delivery. Roll-off dumpsters, shipping containers and portable storage."],
      blocks: [
        hero(style: "plain", eyebrow: "— Free & no obligation", heading: "Get Your Free Quote",
          body: "It takes about two minutes. A real local person replies with a clear, upfront price — never a call center. You pay $0 until your box arrives.",
          checklist: ["Done in 2 minutes", "A real local person", "$0 until delivery", "No call centers"], form_heading: "Get your free quote", form_service: "any"),
        b("trust_bar"), steps, reviews
      ]},
    "dumpster-rentals" => {title: "Dumpster Rentals", seo: ["Roll-Off Dumpster Rentals in Minnesota | Affordabox", "Flat-rate roll-off dumpster rentals delivered as soon as next-day across St. Michael, Wright County & the NW Twin Cities metro. $0 due until delivery. See the price and book in 2 minutes."],
      blocks: [
        crumbs,
        hero(photo: img("dumpsters/hero.jpg"), photo_opacity: "25", eyebrow: "— Roll-off dumpsters across Minnesota's NW metro", heading: "Roll-Off Dumpster Rentals in Minnesota",
          body: "One flat rate — delivery, rental, pickup, and disposal all included. We deliver as soon as next-day, and **$0 is due until your dumpster is in the driveway**.",
          checklist: ["Flat-rate pricing", "Next-day delivery", "$0 until delivery"], form_heading: "Get your dumpster quote", form_service: "Dumpster"),
        b("dumpster_sizes", eyebrow: "— Sizes & flat-rate pricing", heading: "Pick your size, see the price",
          intro: "Every price below is a flat rate including delivery, a 7-day rental, pickup, and disposal up to 5,000 lbs.", button_label: "Get this size", schema: true),
        b("checklist", eyebrow: "— No surprises", heading: "What's included in every rental", body: "One flat rate, one clear bill. Here's exactly what you get — and what to know about overages.", background: "muted",
          items: [["Flat rate includes everything", "Flat rate includes delivery, 7-day rental, pickup, and disposal up to 5,000 lbs."], ["Simple overage", "Overage billed at $0.10/lb over the included tonnage."], ["Pay nothing up front", "$0 due until delivery."]].map { |t, d| {"title" => t, "body" => d} }),
        b("chips", eyebrow: "— What's your project?", heading: "A dumpster for any job", intro: "Not sure which size? Tell us your project and a real local person will size it with you.",
          chips: ["Home cleanout", "Remodel / renovation", "Roofing", "Construction / job site", "Estate cleanout"].map { {"label" => it, "link" => url("/get-a-quote?service=Dumpster&use=#{URI.encode_www_form_component(it).gsub("+", "%20")}")} }),
        steps, reviews("dumpster"), faq("dumpster", "Dumpster rental FAQs"), cta("Dumpster")
      ]},
    "shipping-containers" => {title: "Shipping Containers", seo: ["Shipping Containers for Sale & Rent | Affordabox", "New and used 20ft & 40ft shipping containers in Minnesota — buy or rent. Wind- and water-tight, delivered to your site as soon as next-day."],
      blocks: [
        crumbs,
        text_hero(layout: "center", padding: "medium", eyebrow: "— New & used · 20' & 40' · delivered local", heading: "Shipping Containers in Minnesota",
          body: "Wind- and water-tight 20' and 40' containers, delivered to your site as soon as next-day. Buy one outright or rent month-to-month — your call."),
        b("card_grid", columns: "2", style: "link", cards: cards(
          {eyebrow: "— Own it", title: "Containers for Sale", body: "New (one-trip) and used (cargo-worthy) 20' & 40' containers. Real starting prices from $1,800.", link: page("shipping-containers/buy"), link_label: "Browse containers for sale"},
          {eyebrow: "— Keep it as long as you need", title: "Containers for Rent", body: "Month-to-month rentals, delivered & picked up. Short-term or long-term — no long contract.", link: page("shipping-containers/rent"), link_label: "See rental options"})),
        cta("Container — Buy")
      ]},
    "shipping-containers/buy" => {title: "Buy", seo: ["Shipping Containers for Sale | Affordabox", "New (one-trip) and used (cargo-worthy) 20ft and 40ft shipping containers for sale in Minnesota. Wind- and water-tight, delivered to your site. Real starting prices — never call for price."],
      blocks: [
        crumbs,
        hero(photo: img("cms/container-40hc.jpg"), eyebrow: "— New & used containers, delivered local", heading: "Shipping Containers for Sale",
          body: "Buy a wind- and water-tight 20' or 40' container — new one-trip or budget-friendly cargo-worthy used. We publish real starting prices and deliver to your site as soon as next-day.",
          checklist: ["New & used", "20' & 40'", "Delivered to your site"], form_heading: "Get your container quote", form_service: "Container — Buy"),
        b("card_grid", eyebrow: "— Pick your condition", heading: "New (one-trip) or used (cargo-worthy)", intro: "Both are structurally sound and lock securely — the difference is cosmetic wear and price.", columns: "2", style: "card",
          cards: cards({title: "New — one-trip", body: "Manufactured recently and shipped just once, so they look nearly pristine — minimal wear, clean interiors, and a long service life. Ideal when appearance matters or you're planning a build."},
            {title: "Used — cargo-worthy", body: "Wind- and water-tight with honest cosmetic wear at the best price. Structurally sound and ready for on-site storage or job-site use the day they arrive."})),
        b("container_catalog", eyebrow: "— Our catalogue", heading: "Containers for sale", intro: "Standard, high-cube, double-door, and side-door options in 20' and 40'.", button_label: "Get this container", schema: true),
        b("split", eyebrow: "— Spec note", heading: "Standard vs. high-cube",
          body: "Both share the same footprint. The difference is height: standard containers stand 8'6\" tall, while high-cube containers add a full foot at 9'6\". That extra headroom matters for tall equipment, shelving, and comfortable workshop or office conversions.",
          facts: [{"label" => "Standard", "value" => "8'6\" exterior height"}, {"label" => "High-cube", "value" => "9'6\" exterior height"}], facts_style: "boxes",
          right: "list", right_eyebrow: "— What people buy them for", right_heading: "Popular uses",
          list: ["On-site & job-site storage", "Workshops & garages", "Portable offices", "Retail & pop-ups", "Custom builds & modifications"]),
        b("card_grid", eyebrow: "— Getting it on site", heading: "Delivery, clearance & door orientation", columns: "3", style: "card", background: "muted",
          cards: cards({title: "Tilt-bed delivery", body: "We deliver on a tilt-bed truck onto firm, level ground. We'll review your site with you before delivery so it lands exactly where you want it."},
            {title: "Clearance you'll need", body: "Plan for roughly the container length plus the truck — about 60 feet of straight clearance for a 20', and more for a 40'."},
            {title: "Door orientation", body: "You choose. Tell us whether you want the doors at the front or rear of the placement and we'll set it down accordingly."})),
        b("callout", style: "hazard", eyebrow: "— Make it yours", heading: "Custom modifications",
          body: "Doors, windows, vents, electrical, insulation, and full custom builds are available. Tell us your plan and we'll quote the modifications along with the container.",
          button_label: "Talk modifications", button_link: url("/get-a-quote?service=Container%20%E2%80%94%20Buy")),
        reviews("container"), faq("container-buy", "Buying a container — FAQs"), cta("Container — Buy")
      ]},
    "shipping-containers/rent" => {title: "Rent", seo: ["Shipping Containers for Rent | Affordabox", "Rent a 20ft or 40ft shipping container in Minnesota — month-to-month, delivered and picked up. Wind- and water-tight, lock securely, available as soon as next-day."],
      blocks: [
        crumbs,
        hero(photo: img("cms/container-20-stacked.jpg"), eyebrow: "— Month-to-month container rentals", heading: "Shipping Containers for Rent",
          body: "Short-term or long-term, delivered & picked up. Keep a wind- and water-tight container on site for a single project or as long as you need — no long-term contract.",
          checklist: ["Month-to-month", "Delivered & picked up", "Next-day delivery"], form_heading: "Get your rental quote", form_service: "Container — Rent"),
        b("split", eyebrow: "— Simple monthly billing", heading: "Pay by the month",
          body: "Rentals are billed monthly with no long-term contract. We deliver to your site and pick it up when you're done — you only pay for the months you keep it.",
          price_label: "Starting at", price_value: "Monthly rates — get a quote",
          right: "list", right_eyebrow: "— What people rent them for", right_heading: "Popular uses",
          list: ["On-site storage during a project", "Workshop or tool storage", "Portable office", "Overflow inventory", "Event & seasonal storage"]),
        b("card_grid", eyebrow: "— Not sure?", heading: "Rent or buy?", intro: "A quick way to decide which makes sense for your situation.", columns: "2", style: "card", background: "muted",
          cards: cards({title: "Rent if…", checklist: ["It's for a defined project or season", "You need it short- to medium-term", "You'd rather avoid the up-front cost", "You don't want to handle resale later"]},
            {title: "Buy if…", checklist: ["You'll need on-site storage indefinitely", "You want to modify or customize it", "Long-term ownership beats monthly cost", "You want a permanent fixture on your property"],
             link: page("shipping-containers/buy"), link_label: "See containers for sale"})),
        reviews("container"), faq("container-rent", "Renting a container — FAQs"), cta("Container — Rent")
      ]},
    "portable-storage" => {title: "Portable Storage", seo: ["Portable Storage Delivered to Your Driveway in Minnesota | Affordabox", "Portable storage units delivered to your driveway with the Mule and loaded on your schedule. From $149/mo + $79 delivery, $0 due until it arrives. Month-to-month, no change or cancel fees. Serving the NW Twin Cities metro & Wright County."],
      blocks: [
        crumbs,
        hero(photo: img("cms/portable-fleet.jpg"), eyebrow: "— Portable storage, the local way", heading: "Storage Delivered to Your Driveway — Loaded on Your Schedule.",
          body: "We place a ground-level unit right where you want it with the Mule Delivery System, then leave you to pack at your own pace. From **$149/mo + $79 delivery**, with $0 due until it arrives.",
          checklist: ["Mule-placed in your driveway", "$0 until delivery", "Month-to-month"], form_heading: "Get your free quote", form_service: "Portable Storage"),
        b("portable_sizes", eyebrow: "— Pick your size", heading: "Four sizes, one flat starting price",
          intro: "Every unit starts at **$149/mo** and holds ≈ 4,500 lbs per unit. Not sure which fits? Tell us your move and a real local person will size it with you.",
          button_label: "Get this size", footnote: "**Weight limit:** ≈ 4,500 lbs per unit. **Climate options:** Non-climate (standard) · Insulated · Climate-controlled.", schema_price: 149),
        mule,
        b("card_grid", eyebrow: "— What people use it for", heading: "One box, plenty of jobs", columns: "3", style: "icon", background: "muted",
          cards: ["Moving", "Remodel / restoration", "Decluttering", "Contractor on-site", "Business overflow", "Events"].map { {"title" => it} },
          note: "**10'×10' doors for Minnesota toys.** Need to store a boat, trailer, or fish house? Ask about units with 10'×10' doors built for Minnesota toys."),
        b("split", eyebrow: "— Honest pricing", heading: "Real prices. No surprises.",
          body: "One clear starting rate, one flat delivery fee, and nothing due until your unit is in your driveway. Keep it as long as you need — it's month-to-month with no penalties for changing your plans.",
          button_label: "Get your free quote", button_link: page("get-a-quote"), right: "rows", align: "start",
          rows: [{"label" => "Monthly rate", "value" => "From $149/mo"}, {"label" => "Delivery & pickup", "value" => "$79"},
            {"label" => "Due at booking", "value" => "$0 due until your unit is delivered.", "highlight" => true},
            {"label" => "Terms", "value" => "Month-to-month. No change fees, no cancel fees, no long-term contracts."}]),
        steps, reviews("portable"), faq("portable", "Portable storage questions"),
        b("callout", style: "note", body: "AffordABox is not associated with PODS. PODS is a registered trademark of The Procter & Gamble Company."),
        cta("Portable Storage")
      ]},
    "self-storage" => {title: "Self-Storage", seo: ["Self-Storage in Monticello & St. Michael, MN | Affordabox", "Drive-up and climate-controlled self-storage in Monticello and St. Michael, Minnesota. Reserve online with no credit card to hold, month-to-month with online discounts. Oversized units for boats and campers."],
      blocks: [
        crumbs,
        hero(photo: img("cms/facility-stmichael.jpg"), eyebrow: "— Two locations, both local", heading: "Self-Storage in Monticello & St. Michael, MN",
          body: "Drive-up and climate-controlled units at two Wright County facilities. Reserve online with no credit card to hold your space — month-to-month, with online-only discounts.",
          checklist: ["No credit card to reserve", "Online discounts", "Month-to-month"], form_heading: "Reserve your unit", form_service: "Self-Storage"),
        b("facility_cards", eyebrow: "— Choose your location", heading: "Two facilities, same local service", facilities: %w[monticello st-michael], price_label: "Reserve online"),
        b("card_grid", eyebrow: "— Which unit is right?", heading: "Drive-up, climate-controlled, or oversized", columns: "3", style: "card", background: "muted",
          cards: cards({title: "Drive-up units", body: "Pull right up to the door and load straight from your vehicle — no hallways, no elevators. The easiest option for furniture, totes, and quick in-and-out access through a Minnesota winter."},
            {title: "Climate-controlled units", body: "A steadier temperature year-round for the things that don't like swings — electronics, documents, photos, wood furniture, and anything you'd rather not leave in the cold or heat."},
            {title: "Oversized units", body: "Tall doors and extra room for boats, campers, trailers, and fish houses, plus business inventory or a vehicle you want under cover."})),
        b("split", eyebrow: "— Easy to reserve", heading: "Reserve online — no card to hold",
          body: "Lock in your unit online and we'll hold it for you with no credit card required. Ask about online-only rate discounts, and rent month-to-month with no long-term contract. If your size shows as full, leave your info and we'll call the moment one opens.",
          button_label: "Reserve online", button_link: page("get-a-quote"), right: "check_grid",
          list: ["No credit card to reserve", "Online-only discounts", "Month-to-month terms", "Real local office staff"]),
        reviews("self-storage"), faq("self-storage", "Self-storage questions"), cta("Self-Storage")
      ]},
    **%w[monticello st-michael].to_h { |slug| ["self-storage/#{slug}", facility_page(slug)] },
    "locations" => {title: "Locations", seo: ["Service Areas — Dumpsters, Containers & Storage Across NW Metro MN | Affordabox", "Every city we serve across Wright, Sherburne, Hennepin & Anoka counties. Roll-off dumpsters, shipping containers and portable storage delivered next-day from our St. Michael yard."],
      blocks: [
        crumbs,
        text_hero(eyebrow: "— Where we deliver", heading: "Dumpsters, Containers & Storage Across Minnesota's NW Metro",
          body: "We keep our footprint tight on purpose. Everything runs out of our yard in St. Michael, so the cities we serve across **Wright**, **Sherburne**, **Hennepin** and **Anoka** counties get fast, local service — real people, next-day delivery, and the Mule placing your box exactly where you want it."),
        b("location_directory", counties: [["Wright", "Our home county — same-day and next-day delivery from our St. Michael yard."], ["Sherburne", "Up the Highway 10 and 101 corridors, just across the river."],
          ["Hennepin", "From the metro edge into Minneapolis, including tight city driveways."], ["Anoka", "Where the Rum meets the Mississippi — fast roll-off and container drops."]].map { |n, d| {"name" => n, "blurb" => d} }),
        b("map_embed", eyebrow: "— Our service region", heading: "Centered on St. Michael, Minnesota", intro: "A short drive reaches every community we serve.", query: "St. Michael, MN", height: 420),
        cta
      ]},
    "about" => {title: "About", seo: ["About Us | Affordabox", "AffordABox is a locally owned dumpster, container and storage company serving homeowners, contractors and businesses across Wright County and the NW Twin Cities metro."],
      blocks: [
        crumbs,
        text_hero(eyebrow: "— {ownership}", heading: "Locally Owned. Built for Minnesota.",
          body: "AffordABox is a Minnesota company helping our neighbors get the right box, on time, at a fair price — with people who answer the phone."),
        b("split", eyebrow: "— Our story", heading: "Made for the way Minnesota actually works", large_text: true,
          body: "We serve homeowners cleaning out the garage, contractors running jobsites, and businesses that need storage that just shows up and works — across Wright County and the northwest Twin Cities metro.\n\nThe national outfits treat St. Michael like a dot on a map. We treat it like home, because it is. That means honest online pricing, real people on the phone, and delivery that respects your driveway, your lawn, and your schedule.",
          right: "image", image: img("cms/proud-owners.jpg", alt: "Happy AffordABox customers with their portable storage unit")),
        mule,
        b("card_grid", eyebrow: "— Why AffordABox", heading: "What you get with a local box company", columns: "3", style: "icon", background: "muted",
          cards: [["Locally owned & operated", "We live and work here. When you call, you reach the people who actually run the business — not a national queue."],
            ["Transparent online pricing", "See the price before you commit. No surprise fees, no haggling, no \"call for a quote.\""],
            ["No call centers", "A real local person answers the phone and knows your roads, your town, and your timeline."],
            ["$0 until delivery", "You pay nothing until your box actually shows up. No deposit games."],
            ["Month-to-month", "Keep it as long as you need. No long contracts, no early-return penalties."],
            ["Next-day delivery", "Need it fast? We can usually be there as soon as tomorrow."]].map { |t, d| {"title" => t, "body" => d} }),
        b("card_grid", eyebrow: "— The team", heading: "Real local people", intro: "The folks who answer the phone and make sure your box gets where it needs to go.", columns: "2", style: "person",
          cards: [["Sarah Pool", "Operations"], ["Jake Edwards", "Operations"]].map { |n, r| {"title" => n, "body" => r} }),
        reviews, cta
      ]},
    "contact" => {title: "Contact", seo: ["Contact Us | Affordabox", "Contact AffordABox in St. Michael, MN. Call toll-free or local and talk to a real local person — no call center. Dumpsters, containers and storage across Wright County and the NW metro."],
      blocks: [
        crumbs,
        text_hero(layout: "center", eyebrow: "— Get in touch", heading: "Contact AffordABox", body: "Questions, quotes, or scheduling — reach a real local person. No call centers, no runaround."),
        b("contact_details", heading: "Reach us", form_heading: "Get your free quote"), b("trust_bar")
      ]},
    "reviews" => {title: "Reviews", seo: ["Customer Reviews | Affordabox", "Read verified Google reviews from AffordABox customers across St. Michael, Wright County and the NW Twin Cities metro. 5-star rated for delivery, pricing and service."],
      blocks: [
        crumbs,
        text_hero(layout: "center", eyebrow: "— Verified Google reviews", heading: "What Our Customers Say", body: "{rating}",
          buttons: [{"label" => "Leave a review", "link" => page("contact"), "style" => "primary"}], note: "Real people. Real local jobs."),
        b("reviews", context: "general", limit: 0, layout: "grid", footnote: "Every review above is a real, verified Google review from an AffordABox customer."),
        cta
      ]},
    "faq" => {title: "FAQ", seo: ["Frequently Asked Questions | Affordabox", "Answers to common questions about dumpster rentals, shipping containers, portable storage and self-storage from AffordABox."],
      blocks: [
        crumbs,
        text_hero(eyebrow: "— Good to know", heading: "Frequently asked questions", body: "Everything you need to know about renting with AffordABox."),
        faq("home", "General", eyebrow: nil, style: "cards"), faq("dumpster", "Dumpster rentals", eyebrow: nil, style: "cards"),
        faq("container-buy", "Buying a container", eyebrow: nil, style: "cards"), faq("container-rent", "Renting a container", eyebrow: nil, style: "cards"),
        faq("portable", "Portable storage", eyebrow: nil, style: "cards"), faq("self-storage", "Self-storage", eyebrow: nil, style: "cards"),
        cta
      ]},
    "cold-storage" => {title: "Cold Storage", seo: ["Cold Storage & Refrigerated Containers | Affordabox", "Refrigerated container rentals with precise temperature control. Perfect for restaurants, events, agriculture, and pharmaceuticals. Get a quote from Affordabox."],
      blocks: [
        crumbs,
        hero(photo: img("cold-storage/blocks/5/value/bgImage.webp"), eyebrow: "— Cold storage", heading: "Refrigerated Container Rentals",
          body: "Keep it cold. Keep it fresh. Temperature-controlled storage containers delivered to your door — ideal for restaurants, catering, events, and agriculture.",
          checklist: ["-20°F to 70°F", "Digital controls", "Same-day delivery"], form_heading: "Get your cold storage quote", form_service: "any"),
        b("split", eyebrow: "— Dialed-in to the degree", heading: "Precise temperature control",
          body: "Our reefer containers maintain consistent temperatures from -20°F to 70°F. Digital controls, insulated walls, and reliable compressor units keep your goods at the perfect temperature.",
          facts: [["Temperature Range", "-20°F to 70°F"], ["Power", "480V 3-phase"], ["Sizes", "20ft & 40ft"], ["Delivery", "Same-day available"]].map { |l, v| {"label" => l, "value" => v} }, facts_style: "specs",
          right: "image", image: img("cold-storage/blocks/4/value/image.webp", alt: "Cold storage facility")),
        b("card_grid", eyebrow: "— Who we keep cool", heading: "Industries we serve", columns: "4", style: "card", align: "left", background: "muted",
          cards: [["Restaurants", "Overflow refrigeration during peak seasons or equipment failure."], ["Catering & Events", "Temporary cold storage for large events and weddings."],
            ["Agriculture", "Post-harvest cooling and storage for produce."], ["Pharmaceuticals", "Temperature-sensitive medicine and vaccine storage."]].map { |t, d| {"title" => t, "body" => d} }),
        cta
      ]},
    "privacy" => legal_page("Privacy Policy", "How AffordABox collects, uses and protects your information.", PRIVACY),
    "terms" => legal_page("Terms of Service", "The terms and conditions for using the AffordABox website and services.", TERMS),
    "thank-you" => {title: "Thank You", noindex: true, exit_modal: "off", seo: ["Thank You | Affordabox", "Thanks for your request — a real local person from AffordABox will be in touch shortly."],
      blocks: [b("thank_you", heading: "Thank you — we've got your request.",
        body: "A real local person will reach out shortly — usually within the hour during business hours (Mon–Fri 8AM–5PM CT). No call centers, no runaround.",
        call_line: "In a hurry? Call us now at {phone}.", event: "generate_lead",
        buttons: [{"label" => "Back to home", "link" => page("home"), "style" => "primary"}, {"label" => "Read our reviews", "link" => page("reviews"), "style" => "secondary"}])]},
    **configurator_pages
  }
end

# The 3-D quote pages (thank-you-quote-*), noindex: the online quote's hand-off, not in the menus.
def configurator_pages
  {"dumpsters" => ["Your Dumpster Quote — Size it. Price it.", "See your AffordABox roll-off dumpster in 3-D and price it live. Flat-rate — delivery, pickup, and disposal included, $0 until delivery, next-day."],
   "portable-storage" => ["Your Portable Storage Quote — Size it. Price it.", "See your AffordABox portable storage unit in 3-D and price it live. From $149/mo, $79 delivery, $0 until delivery, month-to-month."],
   "shipping-containers" => ["Your Shipping Container Quote — Size it. Price it.", "See your shipping container in 3-D and price it live. New & used 20' and 40', delivered local."]}.to_h do |product, (title, description)|
    ["thank-you-quote-#{product}", {title:, noindex: true, exit_modal: "off", seo: ["#{title} | Affordabox", description], blocks: [b("quote_configurator", product:)]}]
  end
end

def facility_page(slug)
  city = {"monticello" => "Monticello", "st-michael" => "St. Michael"}.fetch(slug)
  street = {"monticello" => "10111 Innsbrook Drive", "st-michael" => "12231 43rd St NE"}.fetch(slug)
  full = "#{street}, #{city}, MN #{{"monticello" => "55362", "st-michael" => "55376"}.fetch(slug)}"
  blurb = entries_cache["facilities"].find { it[0] == slug }[2][:blurb]
  seo_copy = {
    "monticello" => "Our Monticello self-storage facility sits on 10111 Innsbrook Drive in Wright County, just off I-94 — convenient for renters across Monticello, Big Lake, Otsego, Albertville, and the surrounding Sherburne and Wright County communities. Whether you're between homes near the Mississippi River, clearing out a lake place, or storing a boat for the season, you'll find drive-up, climate-controlled, and oversized units close to home.",
    "st-michael" => "Our St. Michael self-storage facility shares our 12231 43rd St NE delivery yard in the heart of Wright County, with quick access for renters across St. Michael, Albertville, Otsego, Hanover, Rogers, and the northwest Twin Cities metro. From a remodel overflow to seasonal boat and camper storage, you'll find drive-up, indoor, and climate-controlled units right where your crew already operates."
  }.fetch(slug)
  near = {"monticello" => "near I-94", "st-michael" => "in Wright County"}.fetch(slug)
  {title: city, seo: ["Self-Storage in #{city}, MN | Affordabox", "Drive-up and climate-controlled self-storage in #{city}, MN at #{street}. Reserve online with no credit card to hold, month-to-month with online discounts. Oversized units for boats and campers #{near}."],
   blocks: [
     crumbs,
     hero(photo: img(slug == "monticello" ? "cms/facility-aisle.jpg" : "cms/facility-stmichael.jpg"), photo_opacity: "25", eyebrow: "— AffordABox Self-Storage",
       heading: "Self-Storage in #{city}, MN", body: full, detail: blurb, checklist: ["Drive-up & climate-controlled", "No card to reserve", "Month-to-month"],
       form_heading: "Reserve your unit", form_service: "Self-Storage", form_city: city),
     b("facility_details", eyebrow: "— This facility", heading: "#{city} facility details", facility: slug),
     b("storage_units", eyebrow: "— Find your fit", heading: "Unit sizes in #{city}", intro: "Reserve online with no credit card to hold. Check live availability for the size you need.", button_label: "Check availability"),
     b("card_grid", columns: "2", style: "panel",
       cards: cards({title: "Built for Minnesota winters", body: "Drive-up units mean you park right at the door and load straight from your vehicle — no icy hallways, no stairs, no hauling totes down a long corridor in January. It's the fastest way in and out when the weather turns."},
         {title: "Room for your toys", body: "Oversized units with 10' doors give boats, campers, trailers, and fish houses a clean, secure home for the off-season — plus business inventory or a vehicle you'd rather keep covered.", dark: true})),
     b("prose", style: "small", body: seo_copy),
     reviews("self-storage"), faq("self-storage", "Self-storage questions"), cta("Self-Storage")
   ]}
end

def legal_page(title, description, body)
  {title:, noindex: true, seo: ["#{title} | Affordabox", description],
   blocks: [crumbs, text_hero(eyebrow: "— Legal", heading: title, body: "Last updated: October 2026", padding: "small", heading_size: "medium"), b("prose", style: "article", body:)]}
end

CONTACT_BLOCK = "AffordABox  \n12231 43rd St NE  \nSt. Michael, MN 55376  \nPhone: [(833) 468-2269](tel:+18334682269)  \nEmail: [info@golumin.io](mailto:info@golumin.io)"
PRIVACY = <<~MD.freeze
  This Privacy Policy explains how AffordABox ("we," "us," or "our") collects, uses, and protects information when you visit our website or request our services.

  ## Information we collect

  When you submit a quote request or contact form, we collect the information you provide — such as your name, phone number, email address, service address or ZIP code, and details about the service you need. We may also automatically collect basic usage data (such as pages visited) through analytics tools.

  ## How we use your information

  - To respond to your quote requests and inquiries.
  - To schedule, deliver, and service your rental or purchase.
  - To contact you about your order and provide customer support.
  - To improve our website and services.

  ## How we share your information

  We do not sell your personal information. We may share information with service providers who help us operate our business (for example, scheduling or communications tools), and where required by law.

  ## Cookies and analytics

  Our website may use cookies and third-party analytics (such as Google Analytics) to understand how visitors use the site. You can control cookies through your browser settings.

  ## Your choices

  You may opt out of marketing communications at any time. To request access to, correction of, or deletion of your information, contact us using the details below.

  ## Contact us

  #{CONTACT_BLOCK}
MD
TERMS = <<~MD.freeze
  These Terms of Service ("Terms") govern your use of the AffordABox website and the services we provide. By using our website or requesting our services, you agree to these Terms.

  ## Use of our website

  You agree to use this website for lawful purposes only and not to misuse, disrupt, or attempt to gain unauthorized access to any part of the site or our systems.

  ## Quotes and pricing

  Prices shown online are estimates and may vary based on your specific location, service details, and availability. A quote is not a binding contract until confirmed by us.

  ## Service, delivery, and payment

  Delivery windows, rental periods, and payment terms are provided at the time of booking. You are responsible for ensuring safe and legal access for delivery and pickup at your site.

  ## Cancellations and changes

  Cancellation and rescheduling policies are provided at the time of booking. Please contact us as soon as possible if your plans change.

  ## Limitation of liability

  To the fullest extent permitted by law, AffordABox is not liable for indirect, incidental, or consequential damages arising from the use of our website or services.

  ## Changes to these Terms

  We may update these Terms from time to time. Continued use of our website or services after changes are posted constitutes acceptance of the updated Terms.

  ## Contact us

  #{CONTACT_BLOCK}
MD

# The old site's addresses → the new ones. Exact rules win over wildcards.
CITY_SLUGS = LOCATIONS.map(&:first).freeze
REDIRECTS = {
  "/home" => "/", "/our-team" => "/about", "/who-we-are" => "/about", "/gallery" => "/about",
  "/contact-us" => "/contact", "/cart" => "/get-a-quote",
  "/monticello-self-storage" => "/self-storage/monticello", "/self-storage-monticello" => "/self-storage/monticello",
  "/self-storage-st-michael" => "/self-storage/st-michael", "/self-storage-saint-michael" => "/self-storage/st-michael",
  "/storage-locations" => "/self-storage",
  "/rent-storage-container" => "/shipping-containers/rent", "/shipping-containers-rental" => "/shipping-containers/rent", "/container-rentals" => "/shipping-containers/rent",
  "/shipping-containers-sale" => "/shipping-containers/buy", "/buy" => "/shipping-containers/buy", "/nationwide-inventory" => "/shipping-containers/buy",
  "/shipping-container-modifications" => "/shipping-containers/buy", "/shiping-containers" => "/shipping-containers",
  "/chassis-and-trailers" => "/shipping-containers", "/parts" => "/shipping-containers",
  "/delivery" => "/portable-storage", "/portable-container-sizes" => "/portable-storage", "/moving-overview" => "/portable-storage",
  "/storage-overview" => "/portable-storage", "/storage-tips" => "/portable-storage",
  "/residential-dumpster" => "/dumpster-rentals", "/X" => "/dumpster-rentals", "/dumpster-rental/*" => "/dumpster-rentals",
  "/terms-and-conditions" => "/terms", "/privacy-policy" => "/privacy",
  "/test" => "/", "/test-page" => "/", "/all-services" => "/",
  "/st-paul-mn" => "/locations", "/portable-storage-containers/*" => "/locations",
  **CITY_SLUGS.to_h { ["/#{it}-mn", "/locations/#{it}"] },
  **CITY_SLUGS.to_h { ["/portable-storage-containers/#{it}-mn", "/locations/#{it}"] }
}.freeze
# The old site's pages whose address moved (the redirects above take their place).
MOVED_PAGES = %w[our-team gallery contact-us monticello-self-storage rent-storage-container shipping-containers-sale self-storage-monticello self-storage-st-michael
  self-storage-saint-michael delivery cart buy shipping-containers-rental nationwide-inventory storage-locations test].freeze

# ===== Run =====

def entries_cache = @entries_cache ||= entries

# UPLOAD_ONLY=1 sends the files and stops: nothing the site shows changes,
# so the rest can then run in a minute, alongside the theme's update.
if ENV["UPLOAD_ONLY"] == "1"
  entries_cache; globals_data; pages
  puts "Uploaded #{STATE["assets"].size} files; nothing else changed."
  exit
end

puts "Block types"
BLOCK_TYPES.each do |type|
  upsert("/block_types/#{type[:slug]}", "block_type", {"slug" => type[:slug], "label" => type[:label], "description" => type[:description],
    "category" => "Affordabox", "icon" => type[:icon], "fields" => type[:fields], "defaults" => type[:defaults] || {}}, create_path: "/block_types")
end

puts "Collections"
COLLECTIONS.each_key do |slug|
  # Created bare first: a collection's fields can point at another (nearby → locations, facilities on blocks).
  cms(:post, "/collections", {"collection" => {"slug" => slug, "name" => COLLECTIONS[slug][:name], "schema" => {"fields" => []}}}) unless cms(:get, "/collections/#{slug}", missing_ok: true)
end
existing_containers = cms(:get, "/collections/containers/entries?per=100")["entries"].map { it["slug"] }
COLLECTIONS.each { |slug, c| cms(:patch, "/collections/#{slug}", {"collection" => {"name" => c[:name], "schema" => {"fields" => c[:fields]}}}) }
(existing_containers - entries_cache["containers"].map(&:first)).each do |slug|
  cms(:delete, "/collections/containers/entries/#{slug}") # the old site's listing; to the trash
end
entries_cache.each do |collection, list|
  list.each_with_index do |(slug, title, data), index|
    frontmatter = fix_facts(data.transform_keys(&:to_s).merge("order" => index + 1).reject { |_, v| v.nil? })
    frontmatter.merge!(FACILITY_GEO[slug]) if collection == "facilities" && FACILITY_GEO[slug]
    # Only the cities have pages: the other entries stay out of the sitemap.
    seo = collection == "locations" ? {"schema_type" => "WebPage"} : {"noindex" => true}
    upsert("/collections/#{collection}/entries/#{slug}", "entry", {"slug" => slug, "title" => title, "status" => "published", "locale" => "en", "frontmatter" => frontmatter, "seo" => seo},
      create_path: "/collections/#{collection}/entries")
  end
  puts "  #{collection}: #{list.size}"
end

puts "Globals"
globals = globals_data
GLOBALS.each do |slug, g|
  cms(:post, "/globals", {"global" => {"slug" => slug, "name" => g[:name], "data" => {}, "schema" => {"fields" => []}}}) unless cms(:get, "/globals/#{slug}", missing_ok: true)
  cms(:patch, "/globals/#{slug}/schema", {"global" => {"fields" => g[:fields]}})
  cms(:patch, "/globals/#{slug}", {"global" => {"name" => g[:name], "data" => fix_facts(globals.fetch(slug))}})
end
cms(:delete, "/globals/sidebar") if cms(:get, "/globals/sidebar", missing_ok: true)

puts "The lead form"
quote = cms(:get, "/forms/quote", missing_ok: true)&.dig("form") || {}
quote_notify = cms(:get, "/forms/quote/emails/notification", missing_ok: true)&.dig("email") || {}
attribution = %w[gclid gbraid wbraid fbclid msclkid ttclid utm_source utm_medium utm_campaign utm_term utm_content landing_page referrer page_url]
lead = {"slug" => "lead", "title" => "Lead (free quote)", "status" => "published", "submit_label" => "Get my quote", "success_message" => "Thanks! A real local person will be in touch shortly.",
  "fields" => [
    {"name" => "zip", "label" => "ZIP code", "type" => "text", "required" => true},
    {"name" => "service", "label" => "What do you need?", "type" => "select", "required" => true, "options" => [["Dumpster", "Dumpster Rental"], ["Container — Buy", "Container — Buy"], ["Container — Rent", "Container — Rent"], ["Portable Storage", "Portable Storage"], ["Self-Storage", "Self-Storage"]].map { |v, l| {"value" => v, "label" => l} }},
    {"name" => "use_case", "label" => "What's it for?", "type" => "text"},
    {"name" => "city", "label" => "City", "type" => "text", "help" => "Filled in from the ZIP code when it's one we serve."},
    {"name" => "in_area", "label" => "In the service area", "type" => "text", "help" => "yes or no, from the ZIP code."},
    {"name" => "first_name", "label" => "Name", "type" => "text", "required" => true},
    {"name" => "phone", "label" => "Phone", "type" => "tel", "required" => true},
    {"name" => "email", "label" => "Email", "type" => "email"},
    {"name" => "message", "label" => "Anything else?", "type" => "textarea"},
    *attribution.map { {"name" => it, "label" => it.tr("_", " ").sub(/\Autm /, "UTM ").sub(/\A\w/, &:upcase), "type" => "text", "help" => "Filled in by the site: where the visitor came from."} }
  ]}
# Who hears about a lead and where it's posted: the quote form's, unless given (kept out of this public repository).
webhook = ENV["ADS_LEADS_WEBHOOK_URL"].to_s.empty? ? quote["notify_webhook_url"] : ENV["ADS_LEADS_WEBHOOK_URL"]
lead["notify_webhook_url"] = webhook if webhook.to_s != ""
upsert("/forms/lead", "form", lead, create_path: "/forms")
recipients = ENV["QUOTE_RECIPIENTS"].to_s.strip.empty? ? quote_notify["recipients"] : ENV["QUOTE_RECIPIENTS"]
def eb(type, data) = {"id" => SecureRandom.uuid, "type" => type, "version" => 1, "data" => data}
cms(:patch, "/forms/lead/emails/notification", {"form_email" => {"enabled" => true, "subject" => "New Quote: {{service}} — {{zip}}", "recipients" => recipients.to_s,
  "blocks" => [eb("email_heading", {"text" => "New quote request", "level" => "h1", "align" => "left"}),
    eb("email_text", {"body" => "<p>{{first_name}} asked about {{service}} for ZIP {{zip}}. Call them back at {{phone}}.</p>"}),
    eb("email_submission", {"title" => "Request details", "skip_empty" => true})]}.compact})
cms(:patch, "/forms/lead/emails/confirmation", {"form_email" => fix_facts({"enabled" => true, "subject" => "Thank You for Your Inquiry",
  "blocks" => [eb("email_heading", {"text" => "Request Received!", "level" => "h1", "align" => "center"}),
    eb("email_text", {"body" => "<p>Hi {{first_name}},</p><p>Thanks for reaching out to AffordABox! A real local person will get back to you shortly — usually within the hour during business hours (Mon–Fri 8AM–5PM CT).</p>"}),
    eb("email_heading", {"text" => "Your request", "level" => "h3", "align" => "left"}),
    eb("email_text", {"body" => "<p>Service: {{service}}<br>ZIP: {{zip}}<br>Phone: {{phone}}</p>"}),
    eb("email_text", {"body" => "<p>Need it sooner? Call us at <a href=\"tel:+18334682269\">(833) 468-2269</a>.</p>"})]})})

puts "Pages"
all_pages = pages
all_pages.keys.sort_by { it.count("/") }.each do |path|
  spec = all_pages[path]
  parent_path, _, slug = path.rpartition("/")
  parent_id = parent_path.empty? ? nil : cms(:get, "/pages/#{parent_path}").dig("page", "id")
  copy = SEO_COPY[path] || {}
  title = copy[:title] || spec[:seo][0]
  description = copy[:description] || spec[:seo][1]
  spec[:blocks].each { it["data"]["heading"] = copy[:h1] if it["type"] == "page_hero" && copy[:h1] }
  spec[:blocks] = fix_facts(spec[:blocks])
  title, description = fix_facts([title, description])
  attributes = {"slug" => slug, "title" => spec[:title], "locale" => "en", "blocks" => spec[:blocks], "parent_id" => parent_id,
    "seo" => {"meta_title" => title, "meta_description" => description, "noindex" => (spec[:noindex] || nil)}.compact}
  existing = cms(:get, "/pages/#{path}", missing_ok: true)
  existing ? cms(:patch, "/pages/#{path}", {"page" => attributes}) : cms(:post, "/pages", {"page" => attributes.merge("status" => "draft")})
  cms(:patch, "/pages/#{path}/schema", {"page" => {"fields" => PAGE_FIELDS}})
  cms(:patch, "/pages/#{path}", {"page" => {"frontmatter" => {"exit_modal" => spec[:exit_modal] || "on"}}})
  puts "  /#{path == "home" ? "" : path}: #{spec[:blocks].size} blocks"
end

puts "The old site's moved pages, to the trash"
MOVED_PAGES.each { |path| cms(:delete, "/pages/#{path}") if cms(:get, "/pages/#{path}", missing_ok: true) }

puts "Redirects"
current = cms(:get, "/redirects/all")["redirects"].to_h { [it["source_path"], it] }
REDIRECTS.each do |from, to|
  attributes = {"source_path" => from, "destination_url" => to, "status_code" => 301, "active" => true, "notes" => "The old affordabox.com address (redesign)"}
  if (rule = current[from.chomp("/")])
    cms(:patch, "/redirects/#{rule["id"]}", {"redirect" => attributes}) unless rule["destination_url"] == to
  else
    cms(:post, "/redirects", {"redirect" => attributes})
  end
end

puts "Old block types"
OLD_BLOCK_TYPES.each { |slug| cms(:delete, "/block_types/#{slug}") if cms(:get, "/block_types/#{slug}", missing_ok: true) }

if PUBLISH
  cms(:post, "/pages/bulk_update_status", {"status" => "published", "paths" => all_pages.keys})
  puts "Published #{all_pages.size} pages."
end
puts "Done."
