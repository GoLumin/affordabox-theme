# frozen_string_literal: true

# Corrections from checking the brand facts against affordabox.com (2026-10):
# the office hours (Mon–Fri 8AM–4PM CT, the only hours affordabox.com wrote
# for Affordabox itself), the St. Michael storage facility's own address
# (10959 30th St NE, off Highway 19, not the 43rd St NE yard), no same-day
# promises, and the delivery clearances affordabox.com gives (about 60 ft for
# a 20', 100 ft for a 40'). Each pair replaces text wherever it appears.
FACT_FIXES = [
  ["Mon–Fri 8AM–5PM CT", "Mon–Fri 8AM–4PM CT"],
  ["\"close\":\"17:00\"", "\"close\":\"16:00\""],
  ["12231 43rd St NE, St. Michael, MN 55376. Reserve", "10959 30th St NE, St. Michael, MN 55376. Reserve"],
  ["at 12231 43rd St NE in St. Michael, MN. Reserve online with no card to hold, month-to-month.",
   "at 10959 30th St NE in St. Michael, MN, off Highway 19. Reserve online, month-to-month."],
  ["shares our 12231 43rd St NE delivery yard in the heart of Wright County", "sits at 10959 30th St NE, just off Highway 19 in Wright County"],
  ["you'll find drive-up, indoor, and climate-controlled units right where your crew already operates.", "you'll find drive-up, indoor, and climate-controlled units close to home."],
  ["At the heart of our St. Michael yard, this facility pairs", "Just off Highway 19 with easy access from 30th Street, our St. Michael facility pairs"],
  ["Co-located with our delivery yard", "Easy access off Highway 19"],
  ["Well-lit, secure facility\"]", "Electronic gate access & security cameras\"]"],
  ["St. Michael (at our 43rd St NE yard)", "St. Michael (10959 30th St NE, off Highway 19)"],
  ["\"meta\":\"43rd St NE\"", "\"meta\":\"30th St NE\""],
  [", and same-day is often available near our St. Michael yard. Tell us", ". Tell us"],
  ["As soon as next-day across our service area, with same-day often available near our St. Michael yard.",
   "As soon as next-day across our service area — tell us your ZIP and we'll confirm the soonest window."],
  ["we offer same-day and next-day delivery across St. Michael", "we deliver as soon as next-day across St. Michael"],
  ["Our home county — same-day and next-day delivery from our St. Michael yard.", "Our home county — delivery as soon as next-day from our St. Michael yard."],
  ["Same-day delivery", "Next-day delivery"],
  ["Same-day available", "As soon as next-day"],
  ["about 60 feet of straight clearance for a 20' and more for a 40'",
   "about 60 feet of straight clearance for a 20' and about 100 feet for a 40', at least 10 feet wide with 14 feet overhead"],
  ["about 60 feet of straight clearance for a 20', and more for a 40'.",
   "about 60 feet of straight clearance for a 20' and about 100 feet for a 40', at least 10 feet wide."]
].freeze

# The facilities' coordinates (OpenStreetMap), for their maps and structured data.
FACILITY_GEO = {"st-michael" => {"street" => "10959 30th St NE", "lat" => "45.1956", "lng" => "-93.6659"},
                "monticello" => {"lat" => "45.2957", "lng" => "-93.8098"}}.freeze

# Apply the fixes to any JSON-able value.
def fix_facts(value)
  json = JSON.generate(value)
  FACT_FIXES.each { |from, to| json = json.gsub(from, to) }
  JSON.parse(json)
end
