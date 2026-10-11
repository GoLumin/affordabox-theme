# Affordabox theme

affordabox.com, drawn by [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish):
a mirror of the Astro site in [GoLumin/affordabox-marketing](https://github.com/GoLumin/affordabox-marketing),
with the same sidebar and top bars, a partial per block type, the quote
form, its emails, and the same look. ERB, an importmap, and a stylesheet
built once from Tailwind and committed; nothing builds when it's installed.
How themes work: Libre Publish's docs/themes.md.

## Installing it

In the site's Libre Publish admin: Settings › Plugins › Add a plugin, and
give `GoLumin/affordabox-theme`. It installs the latest release and
restarts; the site is at `/` while the theme is switched on, and the admin
at `/cms`. Publish a release here (a tag like `v0.2.0` and a GitHub
release) and the theme's Update button takes it.

The colors are Settings › Themes › Customize (primary and secondary).

## The content it draws

`script/import_directus.rb` moved the Astro site's content out of
Directus (cms.affordabox.com) into the CMS, in the shape the theme reads:

| | |
| --- | --- |
| Block types | `main_hero`, `container_slider`, `bento_grid`, `two_col`, `quote_form`, `logo_slider`, `photo_gallery`, `two_col_banner`, `image_cta`, `products`, `single_hero`, `title_bar`, `rich_text`, `faqs`, `container_listing`, `locations`, `image_gallery`, `features`, `testimonials`, `image_text`, `hours`, `thank_you` |
| Collection | `containers`: what the container listings list and filter |
| Globals | `nav` (the icon bar), `sidebar` (logo, phone, main links), `footer`, `site_settings` (favicon, the listing sidebar's words, the 404), `scripts` |
| Form | `quote` (Forms plugin): its notification and confirmation emails, and the leads webhook to ads.golumin.io |
| A page's fields | Top bar (`standard`: sidebar and icon bar, `compact`: one bar and no sidebar, `none`) and Hide the sidebar |

It can run again (`CMS_PROFILE=<profile> ruby script/import_directus.rb`):
what's there is updated, files already sent aren't sent twice, and pages
come in as drafts unless they're already published.

## Working on it

Link it into a Libre Publish checkout and pull the site's content:

    bin/theme link ../affordabox-theme
    bin/pull <profile>
    bin/dev

After changing a template's classes, rebuild the stylesheet and commit it
(it also vendors Swiper into `app/javascript/affordabox/vendor`):

    bin/css            # or bin/css --watch

Checks, from the Libre Publish checkout:

    bin/rspec themes/affordabox/spec                               # every page, from the snapshot
    bundle exec herb lint themes/affordabox --fail-level warning   # templates, accessibility included
    CMS_PROFILE=<profile> bin/rails affordabox:snapshot            # refresh the snapshot from the CMS

`spec/fixtures/cms/snapshot.json` is the CMS's content model and content.
The spec draws every page from it, so a template reading a field the CMS
doesn't declare fails here before it breaks a page.

Proprietary. Copyright Lumin.
