# frozen_string_literal: true

# The pages' titles, descriptions and H1s after the SEO audit (2026-10):
# titles of 60 characters or fewer, descriptions of 120–158, a target keyword
# and the place in each. import_redesign.rb and seo_pass.rb read it.
SEO_COPY = {
  "home" => {title: "Dumpsters, Containers & Storage in Minnesota | AffordABox",
    description: "Dumpsters, shipping containers and portable storage priced online and delivered next-day across St. Michael, Wright County and the NW Twin Cities.",
    h1: "Dumpsters, Containers & Storage in Minnesota — Priced Online, Delivered Local."},
  "get-a-quote" => {title: "Free Quote: Dumpsters, Containers & Storage | AffordABox",
    description: "Get a free quote in about 2 minutes. A real local person replies and you pay $0 until delivery. Dumpsters, containers and portable storage in Minnesota."},
  "dumpster-rentals" => {title: "Roll-Off Dumpster Rentals in Minnesota | AffordABox",
    description: "Flat-rate 10–25 yard roll-off dumpsters from $419, delivered next-day across Wright County and the NW Twin Cities. Disposal included, $0 until delivery."},
  "shipping-containers" => {title: "Shipping Containers for Sale & Rent in MN | AffordABox",
    description: "New and used 20ft and 40ft shipping containers in Minnesota to buy or rent. Wind- and water-tight, delivered to your site as soon as next-day."},
  "shipping-containers/buy" => {title: "Shipping Containers for Sale in Minnesota | AffordABox",
    description: "New one-trip and used cargo-worthy 20ft and 40ft shipping containers for sale in Minnesota from $1,800. Wind- and water-tight, delivered to your site."},
  "shipping-containers/rent" => {title: "Shipping Container Rentals in Minnesota | AffordABox",
    description: "Rent a 20ft or 40ft shipping container in Minnesota month-to-month. Delivered and picked up, wind- and water-tight, available as soon as next-day."},
  "portable-storage" => {title: "Portable Storage Containers in Minnesota | AffordABox",
    description: "Portable storage delivered to your driveway by the Mule, from $149/mo plus $79 delivery. Month-to-month, $0 until it arrives, across the NW metro.",
    h1: "Portable Storage Delivered to Your Driveway — Loaded on Your Schedule."},
  "self-storage" => {title: "Self-Storage in Monticello & St. Michael, MN | AffordABox",
    description: "Drive-up and climate-controlled self-storage in Monticello and St. Michael, MN. Reserve online with no card to hold, with units for boats and campers."},
  "self-storage/monticello" => {title: "Self-Storage in Monticello, MN | AffordABox",
    description: "Drive-up, climate-controlled and oversized storage units at 10111 Innsbrook Drive in Monticello, MN, near I-94. Reserve online, month-to-month."},
  "self-storage/st-michael" => {title: "Self-Storage in St. Michael, MN | AffordABox",
    description: "Drive-up, indoor and climate-controlled storage units at 12231 43rd St NE in St. Michael, MN. Reserve online with no card to hold, month-to-month."},
  "locations" => {title: "Service Areas: NW Twin Cities & Wright County | AffordABox",
    description: "The Minnesota cities we serve in Wright, Sherburne, Hennepin and Anoka counties, with next-day dumpsters, containers and storage from St. Michael."},
  "about" => {title: "About AffordABox | Locally Owned in St. Michael, MN",
    description: "AffordABox is a locally owned dumpster, container and storage company in St. Michael, MN, serving Wright County and the NW Twin Cities metro.",
    h1: "About AffordABox — Locally Owned, Built for Minnesota"},
  "contact" => {title: "Contact AffordABox | St. Michael, MN | (833) 468-2269",
    description: "Call or message AffordABox in St. Michael, MN and reach a real local person, never a call center. Dumpsters, containers and storage in the NW metro."},
  "reviews" => {title: "AffordABox Reviews | Dumpsters & Storage in Minnesota",
    description: "Verified Google reviews from AffordABox customers across St. Michael, Wright County and the NW Twin Cities, on delivery, pricing and service.",
    h1: "AffordABox Customer Reviews"},
  "faq" => {title: "Dumpster, Container & Storage FAQs | AffordABox",
    description: "Answers about dumpster rentals, buying and renting shipping containers, portable storage and self-storage from AffordABox in Minnesota.",
    h1: "Dumpster, Container & Storage FAQs"},
  "cold-storage" => {title: "Refrigerated Container Rentals in Minnesota | AffordABox",
    description: "Refrigerated container rentals holding -20°F to 70°F for restaurants, events, agriculture and pharmaceuticals, delivered across Minnesota."},
  "privacy" => {title: "Privacy Policy | AffordABox", description: "How AffordABox collects, uses and protects the information you share when you request a quote or contact us."},
  "terms" => {title: "Terms of Service | AffordABox", description: "The terms and conditions for using the AffordABox website and requesting dumpsters, containers and storage."},
  "thank-you" => {title: "Thank You | AffordABox", description: "Thanks for your request — a real local person from AffordABox will be in touch shortly."},
  "thank-you-quote-dumpsters" => {title: "Your Dumpster Quote | AffordABox", description: "See your AffordABox roll-off dumpster in 3-D and price it live. Flat-rate — delivery, pickup and disposal included, $0 until delivery."},
  "thank-you-quote-portable-storage" => {title: "Your Portable Storage Quote | AffordABox", description: "See your AffordABox portable storage unit in 3-D and price it live. From $149/mo, $79 delivery, $0 until delivery, month-to-month."},
  "thank-you-quote-shipping-containers" => {title: "Your Shipping Container Quote | AffordABox", description: "See your shipping container in 3-D and price it live. New and used 20ft and 40ft containers, delivered local."}
}.freeze

# Alt text for photos first uploaded without it.
ALTS = {
  "cms/container-40hc.jpg" => "New beige 40-foot high-cube shipping container on a gravel lot",
  "cms/container-20-stacked.jpg" => "Two stacked grey 20-foot shipping containers",
  "cms/proud-owners.jpg" => "Two people standing in front of an AffordABox roll-off dumpster topped with a portable storage unit",
  "cold-storage/blocks/4/value/image.webp" => "White refrigerated shipping container on yellow container jacks in a loading bay"
}.freeze
