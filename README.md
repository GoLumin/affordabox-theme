# Affordabox theme

affordabox.com, drawn by [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish):
the "Bold Industrial" redesign (the `redesign` branch of
[GoLumin/affordabox-marketing](https://github.com/GoLumin/affordabox-marketing)) —
its header with mega menus, footer, phone/quote bar and exit-intent popup,
a partial per block type, the 3-step lead form, the city pages, the 3-D
quote configurators, the form emails, and the same look. ERB, an
importmap, and a stylesheet built once from Tailwind and committed;
nothing builds when it's installed. How themes work: Libre Publish's
docs/themes.md.

## Installing it

In the site's Libre Publish admin: Settings › Plugins › Add a plugin, and
give `GoLumin/affordabox-theme`. It installs the latest release and
restarts; the site is at `/` while the theme is switched on (Settings ›
Themes), and the admin at `/cms`. Publish a release here (a tag like
`v0.3.0` and a GitHub release) and the theme's Update button takes it.

## The content it draws

`script/import_redesign.rb` puts the redesign into the CMS in the shape the
theme reads, and redirects the old site's addresses:

| | |
| --- | --- |
| Block types | `page_hero` (video, photo or plain; the lead form beside it), `breadcrumbs`, `trust_bar`, `product_router`, `feature_split`, `process_steps`, `reviews`, `faq`, `cta_band`, `dumpster_sizes`, `container_catalog`, `portable_sizes`, `storage_units`, `checklist`, `chips`, `card_grid`, `split`, `callout`, `facility_cards`, `facility_details`, `location_directory`, `map_embed`, `contact_details`, `prose`, `thank_you`, `service_area_teaser`, `quote_configurator` |
| Collections | `dumpsters`, `containers`, `portable-sizes`, `storage-units`, `facilities`, `locations` (each city has a page at `/locations/<city>`), `reviews`, `faqs` |
| Globals | `site_settings` (name, phones, address, hours, logos, trust items, lead form words, exit popup, 404), `nav` (the mega menus), `footer`, `scripts` |
| Form | `lead` (Forms plugin): its notification and confirmation emails, and the leads webhook |
| A page's field | Exit-intent popup (on/off) |

Words in a few fields fill from Site settings: `{ownership}`, `{rating}`,
`{phone}`, `{year}`, `{name}`; a service-area teaser's `{cities}` names the
first cities served.

It can run again (`CMS_PROFILE=<profile> REDESIGN=../affordabox-redesign ruby script/import_redesign.rb`,
with a checkout of the redesign branch for its photos): what's there is
updated, files already sent aren't sent twice. The lead form takes the
quote form's webhook and recipients unless `ADS_LEADS_WEBHOOK_URL` and
`QUOTE_RECIPIENTS` are given. `script/import_directus.rb` is the earlier
move from Directus (the pre-redesign site, theme 0.1).

## Working on it

Link it into a Libre Publish checkout and pull the site's content:

    bin/theme link ../affordabox-theme
    bin/pull <profile>
    bin/dev

After changing a template's classes, rebuild the stylesheet (and the
fonts) and commit what it builds:

    bin/css            # or bin/css --watch

Checks, from the Libre Publish checkout:

    bin/rspec themes/affordabox/spec                               # every page, from the snapshot
    bundle exec herb lint themes/affordabox --fail-level warning   # templates, accessibility included
    CMS_PROFILE=<profile> bin/rails affordabox:snapshot            # refresh the snapshot from the CMS

`spec/fixtures/cms/snapshot.json` is the CMS's content model and content.
The spec draws every page and city from it, so a template reading a field
the CMS doesn't declare fails here before it breaks a page.

Proprietary. Copyright Lumin.
