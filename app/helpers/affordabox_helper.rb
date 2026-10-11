# frozen_string_literal: true

# The theme's own vocabulary on top of WebsiteHelper: the globals the site
# is built around, its buttons, a page's choice of bars, and the quote form.
module AffordaboxHelper
  # The button the Astro site drew everywhere (src/components/ui/Button.astro).
  BUTTON = "rounded-md px-4.5 capitalize py-2.5 text-sm font-semibold flex justify-center items-center shadow-sm " \
    "focus-visible:outline-2 focus-visible:outline-offset-2 transition-colors"
  BUTTONS = {
    solid: "bg-secondary text-white hover:bg-secondary/90 focus-visible:outline-secondary",
    outline: "border-2 border-primary !px-3 !py-2 text-primary hover:bg-primary hover:text-white focus-visible:outline-secondary"
  }.freeze

  NAVBARS = %w[standard compact none].freeze

  # Site settings (the "site_settings" global): the favicon, the listing
  # sidebar's words, the 404's.
  def affordabox_settings = website_global(:site_settings)

  # The "sidebar" global: the logo, the phone number and the main links.
  def affordabox_sidebar = website_global(:sidebar)

  # A button: a link with an href, else a <button>.
  def affordabox_button(label, href = nil, variant: :solid, **options)
    options[:class] = [BUTTON, BUTTONS.fetch(variant), options[:class]].compact.join(" ")
    content = tag.span(label)
    href ? link_to(content, href, **options) : button_tag(content, type: :button, **options)
  end

  # Which bars a page has, from its fields (Top bar, Hide the sidebar), as
  # {navbar:, hide_sidebar:}. A page made without those fields has the
  # standard ones.
  def affordabox_bars(page)
    fields = page.respond_to?(:frontmatter) ? page.frontmatter.to_h : {}
    navbar = fields["navbar"].to_s
    {navbar: NAVBARS.include?(navbar) ? navbar : "standard", hide_sidebar: website_truthy?(fields["hide_sidebar"])}
  end

  # A link field's href, or "#" (the Astro site's fallback for a link left blank).
  def affordabox_href(link) = website_href(link) || "#"

  # A phone number as a tel: link.
  def affordabox_tel(phone) = "tel:#{phone.to_s.gsub(/[^\d+]/, "")}"

  # An asset's address at full size, for a video or a CSS background.
  def affordabox_file_url(id)
    return if id.blank?

    asset = MediaLibrary.find(id)
    rails_storage_proxy_path(asset.file) if asset&.file&.attached?
  end

  # An image's address at the largest size the site offers (a resized copy),
  # for a CSS background.
  def affordabox_background_url(id) = website_image(id)&.dig(:src) || affordabox_file_url(id)

  # Markdown as website_markdown draws it, but a single line break is a
  # space, as on the Astro site (marked): Commonmarker otherwise makes it a <br>.
  def affordabox_markdown(text)
    return "" if text.blank?

    html = Commonmarker.to_html(text.to_s, options: Markdown::OPTIONS.deep_merge(render: {unsafe: true, hardbreaks: false}), plugins: {syntax_highlighter: nil})
    website_html Cms::Hooks.apply("website.markdown", sanitize(html, tags: Markdown::TAGS, attributes: Markdown::ATTRIBUTES), text: text)
  end

  # A heading that may carry <span class="highlighted-title">, and nothing else.
  def affordabox_title(text) = sanitize(text.to_s, tags: %w[span br strong em b i], attributes: %w[class])

  # The footer's copyright line ("{year}" is this year).
  def affordabox_copyright(text) = text.to_s.gsub("{year}", Date.current.year.to_s)

  # The "quote" form (the Forms plugin), drawn by the quote_form block.
  def affordabox_quote_form
    return @affordabox_quote_form if defined?(@affordabox_quote_form)

    @affordabox_quote_form = defined?(Form) ? Form.find_by(slug: "quote", status: "published") : nil
  end

  # A quote form field's choices, as the form defines them.
  def affordabox_options(form, name) = Array(website_form_field(form, name)["options"])

  # Cloudflare Turnstile ({site_key:, theme:}) when Settings › Forms has it
  # set up (the Forms plugin then refuses a submission without its token).
  def affordabox_turnstile
    captcha = Forms.public_captcha if defined?(Forms) && Forms.respond_to?(:public_captcha)
    {site_key: captcha[:site_key], theme: captcha[:theme] || "light"} if captcha && captcha[:provider] == "turnstile"
  end

  # Container filters (the listing's left column), from the containers it
  # lists: each value once, numbers in order, "ft" dropped as the Astro site did.
  def affordabox_filter_values(entries, field)
    values = entries.filter_map { affordabox_filter_value(website_fields(it)[field]) }.uniq
    values.sort_by { |value| value.match?(/\A[-+]?(\d|\.\d)/) ? [0, value.to_f, value] : [1, 0, value] }
  end

  def affordabox_filter_value(value) = value.to_s.sub(/\s*ft\z/i, "").strip.presence
end
