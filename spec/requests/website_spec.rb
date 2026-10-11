# frozen_string_literal: true

require "rails_helper"

# The theme against the CMS it draws: spec/fixtures/cms/snapshot.json is the
# content model and content of affordabox.com (block types, the collections,
# the globals and the lead form, with their fields, and every page and
# entry). Every page and city is drawn from it, so a template that reads a
# field the CMS doesn't declare (Website::Fields) or a form field the form
# doesn't have fails here. Refresh the snapshot from the CMS with
# bin/rails affordabox:snapshot when its content model changes.
RSpec.describe "The Affordabox website", type: :request, website: true do
  SNAPSHOT = JSON.parse(Affordabox::Engine.root.join("spec/fixtures/cms/snapshot.json").read)
  PARTIALS = Affordabox::Engine.root.glob("app/views/website/blocks/_*.html.erb").map { it.basename.to_s[/\A_(\w+)\./, 1] }
  TEMPLATES = Affordabox::Engine.root.glob("app/views/website/entries/*.html.erb").map { it.basename.to_s[/\A(\w[\w-]*)\./, 1] }
  # A page's own field (script/import_redesign.rb gives every page it).
  PAGE_FIELDS = [{"name" => "exit_modal", "label" => "Exit-intent popup", "type" => "select", "options" => %w[on off]}].freeze
  LEAD = {"zip" => "55376", "service" => "Dumpster", "first_name" => "Ann", "phone" => "555-123-4567"}.freeze

  before do
    switch_plugin :forms, on: true
    SNAPSHOT["block_types"].each { BlockType.find_or_initialize_by(slug: it["slug"]).update!(it) }
    # A collection's fields can point at another (nearby cities, facilities): all of them first, then their fields.
    SNAPSHOT["collections"].each { Collection.create!(it.merge("schema" => {"fields" => []})) }
    SNAPSHOT["collections"].each { Collection.find_by!(slug: it["slug"]).update!(schema: it["schema"]) }
    SNAPSHOT["globals"].each do |global|
      Global.find_or_initialize_by(slug: global["slug"]).update!(global.except("fields").merge("schema" => {"fields" => global["fields"]}))
    end
    SNAPSHOT["forms"].each { Form.create!(it.merge("status" => "published")) }
    SNAPSHOT["pages"].sort_by { it["path"].count("/") }.each do |page|
      parent = page["path"].include?("/") ? Page.find_by!(path: page["path"].rpartition("/").first) : nil
      Page.create!(page.except("path").merge("status" => "published", "parent" => parent, "schema" => {"fields" => PAGE_FIELDS}))
    end
    SNAPSHOT["entries"].each do |entry|
      Collection.find_by!(slug: entry["collection"]).entries.create!(entry.except("collection").merge("status" => "published"))
    end
    Setting.set("general", {"title" => SNAPSHOT.dig("site", "name"), "description" => SNAPSHOT.dig("site", "description")})
  end

  def html = Nokogiri::HTML5(response.body)

  def site_settings = SNAPSHOT["globals"].find { it["slug"] == "site_settings" }["data"]

  SNAPSHOT["pages"].each do |page|
    path = page["path"] == "home" ? "/" : "/#{page["path"]}"

    it "draws #{path}, every one of its blocks" do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<title>#{ERB::Util.h(page.dig("seo", "meta_title").presence || page["title"])}")
      page["blocks"].each { expect(PARTIALS).to include(it["type"]) }
    end
  end

  SNAPSHOT["entries"].group_by { it["collection"] }.each do |collection, entries|
    drawn = TEMPLATES.include?(collection)

    it "#{drawn ? "draws" : "has no pages for"} every #{collection} entry" do
      entries.each do |entry|
        get "/#{collection}/#{entry["slug"]}"

        expect(response).to have_http_status(drawn ? :ok : :not_found)
        expect(response.body).to include(ERB::Util.h(entry.dig("frontmatter", "city"))) if drawn
      end
    end
  end

  it "has a partial only for block types the CMS has" do
    expect(PARTIALS - SNAPSHOT["block_types"].map { it["slug"] }).to be_empty
  end

  it "draws its header and footer from the Menu, Footer and Site settings globals" do
    get "/"

    nav = SNAPSHOT["globals"].find { it["slug"] == "nav" }["data"]
    expect(html.css("header nav[aria-label=Primary] > div > a").map { it.text.strip }).to eq(nav["megas"].map { it["label"] })
    expect(html.at_css("footer").text).to include(site_settings["toll_free"], site_settings["address"]["street"])
    expect(html.css("script[type='application/ld+json']").map { JSON.parse(it.text)["@type"] }).to include("LocalBusiness", "FAQPage")
  end

  it "puts breadcrumbs from the page tree on a nested page" do
    get "/shipping-containers/buy"

    expect(html.css("nav[aria-label=Breadcrumb] li").map { it.text.gsub("/", "").strip }).to eq(["Home", "Shipping Containers", "Buy"])
  end

  it "leaves the exit-intent popup off where a page asks" do
    get "/"
    expect(html.at_css("[data-exit-modal]")).to be_present

    get "/thank-you"
    expect(html.at_css("[data-exit-modal]")).to be_nil
  end

  it "draws its 404 from Site settings" do
    get "/no-such-page"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include(site_settings.dig("not_found", "heading"))
  end

  it "posts the lead form to the Forms plugin, naming only fields the form has" do
    get "/get-a-quote"
    form = html.at_css("form[data-lead-form]")
    names = form.css("input, select, textarea").map { it["name"] }.compact.uniq - [Form::HONEYPOT_FIELD]
    lead = Form.find_by!(slug: "lead")

    expect(names - lead.fields.map { it["name"] }).to be_empty
    expect(form.css("select[name=service] option").map { it["value"] }.compact_blank).to eq(lead.fields.find { it["name"] == "service" }["options"].map { it["value"] })
    expect(JSON.parse(form["data-areas"])).to include("55376" => "St. Michael")

    post form["action"], params: LEAD.merge("use_case" => "Moving", "gclid" => "abc"), as: :json
    expect(response).to have_http_status(:created)
    expect(FormSubmission.last.data).to include("service" => "Dumpster", "use_case" => "Moving", "gclid" => "abc")

    post form["action"], params: LEAD.except("phone"), as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "picks a page's service in its lead form" do
    get "/dumpster-rentals"

    expect(html.at_css("form[data-lead-form] select[name=service] option[selected]")["value"]).to eq("Dumpster")
  end

  it "shows Cloudflare Turnstile on the lead form when Settings › Forms has the keys, and loads it only then" do
    get "/get-a-quote"
    expect(response.body).not_to include("cf-turnstile", "challenges.cloudflare.com")

    Setting.set(Forms::SETTING_KEY, {"captcha_provider" => "turnstile", "turnstile_site_key" => "0x4AAA-site", "turnstile_secret_key" => "0x4AAA-secret"})
    get "/get-a-quote"

    expect(html.at_css("form[data-lead-form] .cf-turnstile")["data-sitekey"]).to eq("0x4AAA-site")
    expect(response.body.scan("challenges.cloudflare.com/turnstile/v0/api.js").size).to eq(1)
  end

  it "designs the form's emails, filled in per submission" do
    form = Form.find_by!(slug: "lead")
    email = form.emails.find_or_initialize_by(kind: "notification")
    email.update!(subject: "New Quote: {{service}} — {{zip}}", enabled: true, recipients: "team@example.com", blocks: [
      {"type" => "email_heading", "version" => 1, "data" => {"text" => "New quote request", "level" => "h1"}},
      {"type" => "email_submission", "version" => 1, "data" => {"title" => "Request details", "skip_empty" => true}}
    ])
    submission = form.submissions.create!(data: LEAD.merge("message" => "Clay <b>soil</b>"), meta: {}, ip: "127.0.0.1")

    mail = FormSubmissionMailer.with(form_email: email, submission:, recipients: ["team@example.com"]).deliver.message
    body = mail.body.decoded

    expect(email.site_template_status).to eq(:theme)
    expect(mail.subject).to eq("New Quote: Dumpster — 55376")
    expect(body).to include("New quote request", "555-123-4567", "Clay &lt;b&gt;soil&lt;/b&gt;", "#349d41")
    expect(body.scan("data-cms-repeat").size + body.scan("{{").size).to eq(0)
  end

  it "loads its own scripts, stylesheet and fonts, none of the admin's" do
    get "/"

    importmap = JSON.parse(html.at_css("script[type=importmap]").text)["imports"]
    expect(importmap.keys).to all(start_with("affordabox"))
    expect(importmap.keys).to include("affordabox/lead_form", "affordabox/configurator")
    expect(response.body).to include("/assets/affordabox/site-", "/assets/affordabox/inter-")
    expect(response.body).not_to include("litewind", "/assets/application-", "fonts.googleapis.com")
  end
end
