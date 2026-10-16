# frozen_string_literal: true

# Landing pages (paid traffic): the block types only they use, the page
# field that turns one on, and the pages themselves. import_redesign.rb puts
# the block types and the field in with the rest of the content model;
# landing_pages.rb puts in just these, and the pages, as drafts.
module Landing
  def self.f(name, label, type, **options) = {"name" => name, "label" => label, "type" => type}.merge(options.transform_keys(&:to_s))
  def self.b(type, data = {}) = {"type" => type, "version" => 1, "data" => data.transform_keys(&:to_s).reject { |_, v| v.nil? }}

  SERVICES = ["Dumpster", "Container — Buy", "Container — Rent", "Portable Storage", "Self-Storage"].freeze
  AREA_SERVICES = %w[dumpster container-buy container-rent portable self-storage].freeze
  BACKGROUNDS = %w[white muted dark].freeze
  HEAD = [f("eyebrow", "Eyebrow", "string", help: "The small label above the heading, e.g. \"— How it works\"."), f("heading", "Heading", "string")].freeze

  # A page's "Layout": landing keeps only the logo and the phone up top, and a slim footer.
  LAYOUT_FIELD = f("layout", "Layout", "select", options: %w[standard landing], sidebar: true,
    help: "Landing: no menu, just the logo and the phone up top, and a slim footer. For ad traffic; start the page with a Landing hero.")

  # Dumpster sizes' buttons can stay on the page, for a landing page.
  BUTTON_TARGET_FIELD = f("button_target", "Button goes to", "select", options: %w[quote_page form],
    help: "form: up to this page's lead form (a Landing hero), noting the size.")

  BLOCK_TYPES = [
    {slug: "lp_hero", label: "Landing hero", icon: "Target", description: "A landing page's opening: the headline, the flat price, the phone and the lead form, nothing that leads off the page.",
     fields: [*HEAD, f("body", "Words", "markdown"),
       f("price_label", "Price label", "string"), f("price_value", "Price", "string", help: "Blank on a dumpster page: the lowest Dumpster size price."),
       f("price_note", "Beside the price", "string"), f("checklist", "Check marks", "string_list"), f("photo", "Photo", "asset"),
       f("call_label", "Above the phone", "string"), f("form_heading", "Lead form heading", "string"), f("form_service", "Lead form service", "select", options: SERVICES)],
     defaults: {"price_label" => "Flat rate from", "call_label" => "Rather talk? Call a real person"}},
    {slug: "lp_included", label: "What's included", icon: "Receipt", description: "What the price covers beside what costs extra, and a button up to the page's form.",
     fields: [*HEAD, f("intro", "Intro", "text"), f("included_heading", "Included: heading", "string"), f("included", "Included", "string_list"),
       f("extras_heading", "Extras: heading", "string"), f("extras", "Extras", "repeater", of: [f("label", "What", "string", required: true), f("value", "Price", "string")]),
       f("button_label", "Button text", "string", help: "Goes up to the page's lead form."), f("background", "Background", "select", options: BACKGROUNDS)],
     defaults: {"included_heading" => "Included in the flat rate", "extras_heading" => "Only if it applies", "background" => "muted"}},
    {slug: "lp_area", label: "Service area + ZIP check", icon: "MapPinned", description: "A ZIP check that carries the ZIP up to the page's form, and the cities a service reaches, by county (the Locations collection).",
     fields: [*HEAD, f("intro", "Intro", "text"), f("service", "Service", "select", options: AREA_SERVICES), f("button_label", "Button text", "string"),
       f("footnote", "Note below", "string", help: "{phone} is the toll-free number."), f("background", "Background", "select", options: BACKGROUNDS)],
     defaults: {"service" => "dumpster", "button_label" => "Get my price", "background" => "white"}}
  ].freeze

  PAGES = {
    "dumpster-rental-minnesota" => {
      title: "Dumpster Rental — Minnesota (landing)",
      seo: {"meta_title" => "Dumpster Rental in Minnesota — Flat Rate from $419 | AffordABox",
            "meta_description" => "Flat-rate 10–25 yard roll-off dumpsters across Wright County and the NW Twin Cities. Delivery, 7 days, pickup and disposal included. $0 until delivery.",
            "noindex" => true},
      frontmatter: {"layout" => "landing", "exit_modal" => "off"},
      blocks: [
        b("lp_hero", eyebrow: "— Roll-off dumpsters · Wright County & the NW metro", heading: "Dumpster Rental, One Flat Price",
          body: "10 to 25 yards, delivered as soon as next-day across Minnesota's NW metro. Delivery, a 7-day rental, pickup and disposal are all in the price — and **$0 is due until it's in your driveway**.",
          price_label: "Flat rate from", price_note: "Delivery, 7 days, pickup & disposal up to 5,000 lbs",
          checklist: ["Delivered as soon as next-day", "$0 until delivery", "10, 15, 20 & 25 yard sizes", "Real local people, no call centers"],
          call_label: "Rather talk? Call a real person", form_heading: "Get your dumpster price", form_service: "Dumpster"),
        b("trust_bar", items: ["Locally owned", "Flat-rate pricing", "Next-day delivery", "$0 until delivery", "No call centers"]),
        b("dumpster_sizes", eyebrow: "— Sizes & flat-rate pricing", heading: "Pick your size, see the price",
          intro: "Every price is flat: delivery, a 7-day rental, pickup and disposal up to 5,000 lbs. Not sure which size? Tell us the project and we'll size it with you.",
          button_label: "Get this size", button_target: "form", schema: false),
        b("lp_included", eyebrow: "— No surprises on the bill", heading: "What your flat rate covers",
          intro: "One clear price up front. Here's everything in it, and the one thing that can add to it.",
          included: ["Delivery to your driveway or job site", "A 7-day rental", "Pickup when you're done", "Disposal up to 5,000 lbs", "A real local person on the phone", "$0 due until delivery"],
          extras: [{"label" => "Weight over 5,000 lbs (weighed at the landfill)", "value" => "$0.10/lb"}, {"label" => "Due before your dumpster arrives", "value" => "$0"}],
          button_label: "Get my dumpster price", background: "muted"),
        b("process_steps", eyebrow: "— How it works", heading: "Booked in about two minutes", steps: [
          {"title" => "Tell us the ZIP and the job", "body" => "Enter your ZIP and what you're clearing out. The form takes about two minutes."},
          {"title" => "Get a real price from a real person", "body" => "A local person (never a call center) gets back to you fast with a flat, upfront price."},
          {"title" => "We drop it off as soon as next-day", "body" => "Fill it below the line, and when you're done we pick it up. Disposal's already in the price."}]),
        b("reviews", eyebrow: "— Reviews", heading: "What our neighbors say", context: "dumpster", limit: 3, layout: "feed"),
        b("lp_area", eyebrow: "— Where we deliver", heading: "Dumpsters across Wright County & the NW metro",
          intro: "Our yard is in St. Michael, so these towns are a short drive away. Check your ZIP and we'll carry it up to your quote.",
          service: "dumpster", button_label: "Get my price", footnote: "Don't see your town? Call {phone}. We may still be able to get there.", background: "white"),
        b("faq", eyebrow: "— FAQ", heading: "Dumpster rental questions", group: "dumpster", style: "simple", schema: false),
        b("cta_band", heading: "Ready for your dumpster?", body: "See your flat price in about two minutes, or call and talk to a real local person.",
          service: "Dumpster", note: "Mon–Fri 8AM–4PM CT · No call centers")
      ]
    }
  }.freeze
end
