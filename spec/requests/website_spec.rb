# frozen_string_literal: true

require "rails_helper"

# The theme against the CMS it draws: spec/fixtures/cms/snapshot.json is the
# content model and content of affordabox.com (block types, the containers
# collection, the globals and the quote form, with their fields, and every
# page and container). Every page is drawn from it, so a template that reads
# a field the CMS doesn't declare (Website::Fields) or a form field the form
# doesn't have fails here. Refresh the snapshot from the CMS with
# bin/rails affordabox:snapshot when its content model changes.
RSpec.describe "The Affordabox website", type: :request, website: true do
  SNAPSHOT = JSON.parse(Affordabox::Engine.root.join("spec/fixtures/cms/snapshot.json").read)
  PARTIALS = Affordabox::Engine.root.glob("app/views/website/blocks/_*.html.erb").map { it.basename.to_s[/\A_(\w+)\./, 1] }
  # A page's own fields, which choose the bars around it (script/import_directus.rb gives every page them).
  PAGE_FIELDS = [
    {"name" => "navbar", "label" => "Top bar", "type" => "select", "options" => %w[standard compact none]},
    {"name" => "hide_sidebar", "label" => "Hide the sidebar on wide screens", "type" => "boolean"}
  ].freeze
  QUOTE = {"inquiry_type" => "dumpsters", "first_name" => "Ann", "last_name" => "Lee", "email" => "ann@example.com",
           "phone" => "555-123-4567", "project_details" => "A kitchen remodel"}.freeze

  before do
    switch_plugin :forms, on: true
    SNAPSHOT["block_types"].each { BlockType.find_or_initialize_by(slug: it["slug"]).update!(it) }
    SNAPSHOT["collections"].each { Collection.create!(it) }
    SNAPSHOT["globals"].each do |global|
      Global.find_or_initialize_by(slug: global["slug"]).update!(global.except("fields").merge("schema" => {"fields" => global["fields"]}))
    end
    SNAPSHOT["forms"].each { Form.create!(it.merge("status" => "published")) }
    SNAPSHOT["pages"].each { Page.create!(it.merge("status" => "published", "schema" => {"fields" => PAGE_FIELDS})) }
    SNAPSHOT["entries"].each do |entry|
      Collection.find_by!(slug: entry["collection"]).entries.create!(entry.except("collection").merge("status" => "published"))
    end
    Setting.set("general", {"title" => SNAPSHOT.dig("site", "name"), "description" => SNAPSHOT.dig("site", "description")})
  end

  def html = Nokogiri::HTML5(response.body)

  SNAPSHOT["pages"].each do |page|
    path = page["path"] == "home" ? "/" : "/#{page["path"]}"

    it "draws #{path}, every one of its blocks" do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<title>#{ERB::Util.h(page.dig("seo", "meta_title").presence || page["title"])}")
      page["blocks"].each { expect(PARTIALS).to include(it["type"]) }
    end
  end

  it "has a partial only for block types the CMS has" do
    expect(PARTIALS - SNAPSHOT["block_types"].map { it["slug"] }).to be_empty
  end

  it "has no pages for containers: they're listed, not visited" do
    get "/containers/#{SNAPSHOT["entries"].first["slug"]}"

    expect(response).to have_http_status(:not_found)
  end

  it "frames a page with the bars its fields choose" do
    standard = SNAPSHOT["pages"].find { it.dig("frontmatter", "navbar") == "standard" }
    compact = SNAPSHOT["pages"].find { it.dig("frontmatter", "navbar") == "compact" }

    get "/#{standard["path"]}".sub(%r{\A/home\z}, "/")
    expect(html.at_css("#sidebar-wrapper")).to be_present
    expect(html.at_css("#main-header .nav-slider")).to be_present
    expect(html.css("#sidebar-wrapper .nav-item a").map(&:text).map(&:strip)).to eq(SNAPSHOT["globals"].find { it["slug"] == "sidebar" }.dig("data", "items").map { it["label"] })

    get "/#{compact["path"]}"
    expect(html.at_css("#sidebar-wrapper")).to be_nil
    expect(html.at_css("#compact-menu")).to be_present
  end

  it "lists a page's containers, with filters from their own sizes and categories" do
    page = SNAPSHOT["pages"].find { |p| p["blocks"].any? { it["type"] == "container_listing" } }
    listed = page["blocks"].find { it["type"] == "container_listing" }.dig("data", "containers")
    entries = SNAPSHOT["entries"].select { listed.include?(it["slug"]) }

    get "/#{page["path"]}"

    expect(html.css(".product-card h3").map(&:text)).to eq(listed.map { |slug| entries.find { it["slug"] == slug }["title"] })
    categories = html.css('input[name="category"]').map { it["value"] }
    expect(categories).to match_array(entries.flat_map { it.dig("frontmatter", "categories") }.compact.map(&:strip).uniq)
  end

  it "draws its 404 from Site settings" do
    get "/no-such-page"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include(SNAPSHOT["globals"].find { it["slug"] == "site_settings" }.dig("data", "not_found", "heading"))
  end

  it "posts the quote form to the Forms plugin, naming only fields the form has" do
    get "/contact-us"
    form = html.at_css("form[data-quote-form]")
    names = form.css("input, select, textarea").map { it["name"] }.compact.uniq - [Form::HONEYPOT_FIELD]

    expect(names - Form.find_by!(slug: "quote").fields.map { it["name"] }).to be_empty
    expect(form.css('select[name="inquiry_type"] option').map { it["value"] }.compact_blank)
      .to eq(Form.find_by!(slug: "quote").fields.find { it["name"] == "inquiry_type" }["options"].map { it["value"] })

    post form["action"], params: QUOTE.merge("location" => "Minnesota", "sizes_needed" => "15 yards, 20 yards", "gclid" => "abc"), as: :json
    expect(response).to have_http_status(:created)
    expect(FormSubmission.last.data).to include("inquiry_type" => "dumpsters", "sizes_needed" => "15 yards, 20 yards", "gclid" => "abc")

    post form["action"], params: QUOTE.except("project_details"), as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows Cloudflare Turnstile on the quote form when Settings › Forms has the keys, and loads it only then" do
    get "/contact-us"
    expect(response.body).not_to include("cf-turnstile", "challenges.cloudflare.com")

    Setting.set(Forms::SETTING_KEY, {"captcha_provider" => "turnstile", "turnstile_site_key" => "0x4AAA-site", "turnstile_secret_key" => "0x4AAA-secret"})
    get "/contact-us"

    expect(html.at_css("form[data-quote-form] .cf-turnstile")["data-sitekey"]).to eq("0x4AAA-site")
    expect(response.body.scan("challenges.cloudflare.com/turnstile/v0/api.js").size).to eq(1)
  end

  it "designs the form's emails, filled in per submission" do
    form = Form.find_by!(slug: "quote")
    email = form.emails.find_or_initialize_by(kind: "notification")
    email.update!(subject: "New quote from {{first_name}}", enabled: true, recipients: "team@example.com", blocks: [
      {"type" => "email_heading", "version" => 1, "data" => {"text" => "New quote request", "level" => "h1"}},
      {"type" => "email_submission", "version" => 1, "data" => {"title" => "Request details", "skip_empty" => true}}
    ])
    submission = form.submissions.create!(data: QUOTE.merge("project_details" => "Clay <b>soil</b>"), meta: {}, ip: "127.0.0.1")

    mail = FormSubmissionMailer.with(form_email: email, submission:, recipients: ["team@example.com"]).deliver.message
    body = mail.body.decoded

    expect(email.site_template_status).to eq(:theme)
    expect(mail.subject).to eq("New quote from Ann")
    expect(body).to include("New quote request", "ann@example.com", "Clay &lt;b&gt;soil&lt;/b&gt;", "#349d41")
    expect(body.scan("data-cms-repeat").size + body.scan("{{").size).to eq(0)
  end

  it "loads its own scripts and stylesheet, none of the admin's" do
    get "/"

    importmap = JSON.parse(html.at_css("script[type=importmap]").text)["imports"]
    expect(importmap.keys).to all(start_with("affordabox"))
    expect(importmap.keys).to include("affordabox/vendor/swiper", "affordabox/quote_form")
    expect(response.body).to include("/assets/affordabox/site-")
    expect(response.body).not_to include("litewind", "/assets/application-")
  end
end
