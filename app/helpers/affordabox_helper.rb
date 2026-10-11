# frozen_string_literal: true

# The theme's own vocabulary on top of WebsiteHelper: the globals the site
# is built around (site settings, the menu, the footer), its collections,
# the page being drawn, JSON-LD, and the lead form's services.
module AffordaboxHelper
  # The lead form's services (the CMS's "lead" form has the same values);
  # a block's "any" leaves the choice to the visitor.
  def affordabox_services
    form = affordabox_lead_form
    form ? Array(website_form_field(form, :service)["options"]).map { [it["value"], it["label"]] } : []
  end

  # The page or entry being drawn (website/pages/show and the entry templates
  # set it), for blocks that depend on where they are: breadcrumbs.
  def affordabox_page(record = nil)
    @affordabox_page = record if record
    @affordabox_page
  end

  # Sets the page or entry being drawn, from its template (outputs nothing).
  def affordabox_drawing(record)
    affordabox_page(record)
    nil
  end

  # The breadcrumb trail for the page being drawn: [[name, path], …] from the
  # page tree, the last one named by the breadcrumbs block when it says so.
  def affordabox_trail(current_label = nil)
    record = affordabox_page
    trail = record ? website_breadcrumbs(record) : []
    trail[-1] = [current_label, trail[-1][1]] if trail.size > 1 && current_label.present?
    trail
  end

  # Whether the page's breadcrumbs block sits right above its hero, which
  # then draws the trail in its own top (light on dark) instead of a white strip.
  def affordabox_crumbs_in_hero?
    types = Array(affordabox_page.try(:blocks)).map { it.is_a?(Hash) ? it["type"] : nil }
    types.each_cons(2).any? { |first, second| first == "breadcrumbs" && second == "page_hero" }
  end

  # Site settings (the "site_settings" global): the business's name,
  # phones, address, hours, and the words around the content.
  def affordabox_settings = website_global(:site_settings)

  def affordabox_name = affordabox_settings["name"].presence || website_settings["title"].presence || "AffordABox"

  # A phone number as a tel: link (+1 and its digits).
  def affordabox_tel(phone)
    digits = phone.to_s.gsub(/\D/, "")
    "tel:+#{digits.length == 10 ? "1#{digits}" : digits}"
  end

  def affordabox_toll_free = affordabox_settings.toll_free.to_s

  # "Locally owned since 2016", or the safe line while the year's unconfirmed.
  def affordabox_ownership
    year = affordabox_settings.founded_year
    year.present? ? "Locally owned since #{year}" : "Locally owned & operated"
  end

  # The rating line, never with a review count nobody has confirmed.
  def affordabox_rating_line
    rating = affordabox_settings.rating.presence
    count = affordabox_settings.review_count
    rating && count.present? ? "#{rating}★ from #{count} Google reviews" : "5-star rated on Google"
  end

  def affordabox_address_line(address = affordabox_settings.address)
    "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
  end

  # Words with the site's placeholders filled: {ownership}, {rating}, {year},
  # {name}, {phone}.
  def affordabox_fill(text)
    text.to_s.gsub("{ownership}", affordabox_ownership).gsub("{rating}", affordabox_rating_line)
      .gsub("{year}", Date.current.year.to_s).gsub("{name}", affordabox_name).gsub("{phone}", affordabox_toll_free)
  end

  # A link field's href, or nil.
  def affordabox_href(link) = website_href(link)

  # The "lead" form (the Forms plugin), drawn by every lead form on the site.
  def affordabox_lead_form
    return @affordabox_lead_form if defined?(@affordabox_lead_form)

    @affordabox_lead_form = defined?(Form) ? Form.find_by(slug: "lead", status: "published") : nil
  end

  # Cloudflare Turnstile ({site_key:, theme:}) when Settings › Forms has it
  # set up (the Forms plugin then refuses a submission without its token).
  def affordabox_turnstile
    captcha = Forms.public_captcha if defined?(Forms) && Forms.respond_to?(:public_captcha)
    {site_key: captcha[:site_key], theme: captcha[:theme].presence || "light"} if captcha && captcha[:provider] == "turnstile"
  end

  # ZIP code → city, for the lead form's "Yes! We serve …" (the Locations collection).
  def affordabox_zip_areas
    @affordabox_zip_areas ||= affordabox_locations.each_with_object({}) do |entry, zips|
      fields = website_fields(entry)
      fields.zips.each { zips[it.strip] ||= fields.city.to_s }
    end
  end

  # The cities served, nearest first (by priority, then the collection's order).
  def affordabox_locations = website_entries(:locations)

  # A collection's published entries, in their order.
  def affordabox_entries(collection) = website_entries(collection)

  # An asset's address at full size, for a video or a CSS background.
  def affordabox_file_url(id)
    return if id.blank?

    asset = MediaLibrary.find(id)
    rails_storage_proxy_path(asset.file) if asset&.file&.attached?
  end

  # An image's address at the largest offered size, for a poster or a background.
  def affordabox_image_url(id) = website_image(id)&.dig(:src) || affordabox_file_url(id)

  # Markdown as website_markdown draws it, but a single line break is a space
  # (Commonmarker otherwise makes it a <br>).
  def affordabox_markdown(text)
    return "" if text.blank?

    html = Commonmarker.to_html(affordabox_fill(text), options: Markdown::OPTIONS.deep_merge(render: {unsafe: true, hardbreaks: false}), plugins: {syntax_highlighter: nil})
    website_html Cms::Hooks.apply("website.markdown", sanitize(html, tags: Markdown::TAGS, attributes: Markdown::ATTRIBUTES), text: text)
  end

  # Markdown on one line: **bold** and links, without a paragraph around it.
  def affordabox_inline(text) = affordabox_markdown(text).to_s.strip.delete_prefix("<p>").delete_suffix("</p>").html_safe # rubocop:disable Rails/OutputSafety -- sanitized above

  # A JSON-LD <script> for schema.org data.
  def affordabox_json_ld(data) = website_json_ld(data)

  # An absolute address on the site.
  def affordabox_url(path) = website_url(path)

  # A block's section background: white, muted (neutral-50) or dark (ink-900).
  def affordabox_background(name)
    {"muted" => "bg-neutral-50", "dark" => "bg-ink-900 text-white"}.fetch(name.to_s, "bg-white")
  end

  # US dollars, whole: $1,800.
  def affordabox_usd(amount) = "$#{amount.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse}"

  # schema.org LocalBusiness for the whole site, from Site settings: one
  # business (the same @id and url on every page), with the cities a city page
  # is about as its areaServed. No rating unless both the rating and the
  # count are confirmed.
  def affordabox_local_business(area_served: nil)
    s = affordabox_settings
    a = s.address
    logo = website_image_url(s.logo, width: 600)
    data = {
      "@context" => "https://schema.org", "@type" => "LocalBusiness", "@id" => affordabox_url("/#localbusiness"),
      "name" => affordabox_name, "url" => affordabox_url("/"), "logo" => logo,
      "image" => website_image_url(s.share_image) || logo, "email" => s.email.presence,
      "telephone" => affordabox_tel(s.toll_free).delete_prefix("tel:"),
      "address" => {"@type" => "PostalAddress", "streetAddress" => a.street, "addressLocality" => a.city, "addressRegion" => a.state, "postalCode" => a.zip, "addressCountry" => "US"},
      "geo" => {"@type" => "GeoCoordinates", "latitude" => a.lat.to_f, "longitude" => a.lng.to_f},
      "openingHoursSpecification" => s.hours_detailed.map { {"@type" => "OpeningHoursSpecification", "dayOfWeek" => it.day, "opens" => it.open, "closes" => it.close} },
      "areaServed" => Array(area_served || s.primary_counties).map { {"@type" => "AdministrativeArea", "name" => it} },
      "priceRange" => "$$"
    }.compact
    if s.rating.present? && s.review_count.present?
      data["aggregateRating"] = {"@type" => "AggregateRating", "ratingValue" => s.rating.to_f, "reviewCount" => s.review_count}
    end
    data
  end

  def affordabox_product_schema(name:, description:, low:, high: nil, count: nil, image: nil)
    offers = {"@type" => "AggregateOffer", "priceCurrency" => "USD", "lowPrice" => low, "highPrice" => high, "offerCount" => count,
              "availability" => "https://schema.org/InStock"}.compact
    {"@context" => "https://schema.org", "@type" => "Product", "name" => name, "description" => description,
     "image" => website_image_url(image || affordabox_settings.share_image), "brand" => {"@type" => "Brand", "name" => affordabox_name}, "offers" => offers}.compact
  end

  # One FAQPage for the whole page, from every FAQ block on it that asks for
  # it: drawn by the first of them, nil for the rest (Google reads one per page).
  def affordabox_faq_schema
    return if @affordabox_faq_schema_drawn

    @affordabox_faq_schema_drawn = true
    blocks = Array(affordabox_page.try(:blocks)).select { it.is_a?(Hash) && it["type"] == "faq" && it.dig("data", "schema") != false }
    faqs = blocks.flat_map { affordabox_faqs(it.dig("data", "group")) }.uniq
    return if faqs.empty?

    affordabox_json_ld({"@context" => "https://schema.org", "@type" => "FAQPage",
      "mainEntity" => faqs.map { {"@type" => "Question", "name" => it.title, "acceptedAnswer" => {"@type" => "Answer", "text" => website_fields(it).answer}} }})
  end

  # A review's stars for a context ("portable", …), falling back to general ones.
  def affordabox_reviews(context, limit = nil)
    all = affordabox_entries(:reviews)
    matched = all.select { website_fields(it).tags.include?(context.to_s) }
    pool = matched.any? ? matched : all.select { website_fields(it).tags.include?("general") }
    limit.to_i.positive? ? pool.first(limit.to_i) : pool
  end

  def affordabox_faqs(group) = affordabox_entries(:faqs).select { website_fields(it).group == group.to_s }

  # "a, b and c".
  def affordabox_sentence(names)
    case names.size
    when 0 then "the surrounding communities"
    when 1 then names.first
    else "#{names[0..-2].join(", ")} and #{names.last}"
    end
  end

  SERVICE_LABELS = {"dumpster" => "Dumpster Rentals", "container-buy" => "Buy a Container", "container-rent" => "Rent a Container",
                    "portable" => "Portable Storage", "self-storage" => "Self-Storage"}.freeze
  SERVICE_PAGES = {"dumpster" => "dumpster-rentals", "container-buy" => "shipping-containers/buy", "container-rent" => "shipping-containers/rent",
                   "portable" => "portable-storage", "self-storage" => "self-storage"}.freeze

  def affordabox_service_label(key) = SERVICE_LABELS.fetch(key.to_s, key.to_s.humanize)

  def affordabox_service_href(key) = "/#{SERVICE_PAGES.fetch(key.to_s, "")}"
end
