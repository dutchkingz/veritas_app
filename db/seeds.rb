require "securerandom"

puts "Cleaning up database..."
Briefing.destroy_all
PerspectiveFilter.destroy_all
NarrativeConvergence.destroy_all
NarrativeArc.destroy_all
AiAnalysis.destroy_all
Article.destroy_all
Country.destroy_all
IntelligenceReport.destroy_all
Region.destroy_all
User.destroy_all

def create_perspective_filters!
  puts "Seeding Perspective Filters..."

  [
    { name: "US Liberal Media",      filter_type: "source",
      keywords: "CNN,MSNBC,NPR,New York Times,Washington Post,The Guardian,Vox,HuffPost,The Atlantic,Politico,The New Yorker" },
    { name: "US Conservative Media", filter_type: "source",
      keywords: "Fox News,Breitbart,The Daily Wire,New York Post,Washington Times,Newsmax,The Federalist,Daily Caller,Epoch Times" },
    { name: "China State Media",     filter_type: "source",
      keywords: "Xinhua,Global Times,CCTV,China Daily,People's Daily,South China Morning Post,China News Service,CGTN" },
    { name: "Russia State Media",    filter_type: "source",
      keywords: "RT,TASS,Sputnik,RIA Novosti,Pravda,Rossiyskaya Gazeta,ITAR-TASS,Russia Today,Izvestia" },
    { name: "Western Mainstream",    filter_type: "source",
      keywords: "Reuters,Associated Press,BBC,AFP,AP News,Financial Times,The Economist,Bloomberg,Der Spiegel,Le Monde" },
    { name: "Global South",          filter_type: "source",
      keywords: "Al Jazeera,Dawn,The Hindu,Folha de S.Paulo,Nation Africa,Daily Nation,Mail & Guardian,Arab News,Middle East Eye,Telesur" }
  ].each { |attrs| PerspectiveFilter.create!(attrs) }

  puts "Created #{PerspectiveFilter.count} perspective filters."
end

def create_users!
  puts "Creating Admin User..."
  User.create!(
    email: "admin@veritas.de",
    password: "password123",
    password_confirmation: "password123",
    role: "admin"
  )

  puts "Creating Developer Users..."
  %w[vince@vince.au oli@oli.com selim@selim.com].each do |email|
    User.create!(
      email: email,
      password: email,
      password_confirmation: email,
      role: "user"
    )
  end
end

def create_regions_and_countries!
  puts "Creating Regions and Countries..."

  regions = [
    { name: "North America", country: "United States", iso_code: "USA", lat: 37.0902, lng: -95.7129, threat: 1 },
    { name: "Eastern Europe", country: "Ukraine", iso_code: "UKR", lat: 48.3794, lng: 31.1656, threat: 3 },
    { name: "East Asia", country: "China", iso_code: "CHN", lat: 35.8617, lng: 104.1954, threat: 2 },
    { name: "Middle East", country: "Israel", iso_code: "ISR", lat: 31.0461, lng: 34.8516, threat: 3 },
    { name: "Western Europe", country: "Germany", iso_code: "DEU", lat: 51.1657, lng: 10.4515, threat: 1 }
  ]

  regions.each_with_object({}) do |attrs, result|
    region = Region.create!(
      name: attrs[:name],
      latitude: attrs[:lat],
      longitude: attrs[:lng],
      threat_level: attrs[:threat],
      article_volume: 0,
      last_calculated_at: Time.current
    )

    country = Country.create!(
      region: region,
      name: attrs[:country],
      iso_code: attrs[:iso_code]
    )

    result[attrs[:name]] = { region: region, country: country }
  end
end

def news_api_articles
  return [] if ENV["NEWS_API_KEY"].blank?

  puts "Fetching live articles from NewsAPI..."
  NewsApiService.new.fetch_latest(page_size: 100)
end

def fallback_articles(created_regions, count:)
  sources = [
    "Reuters", "BBC", "Associated Press", "Bloomberg", "Financial Times",
    "Al Jazeera", "Fox News", "CNN", "Xinhua", "RT"
  ]

  story_templates = [
    "Oil shipping routes face renewed pressure after regional escalation",
    "Cyber campaign targets transport infrastructure across allied states",
    "Military drills trigger diplomatic backlash in contested waters",
    "Election narrative intensifies as rival blocs accuse each other of manipulation",
    "Trade restrictions deepen strategic tensions between major powers",
    "Satellite imagery fuels speculation over troop movements near border zones",
    "Sanctions debate reshapes alliance messaging across multiple capitals",
    "State media push diverging narratives after overnight strike reports",
    "Supply chain chokepoints raise fears of coordinated economic pressure",
    "Intelligence officials warn of narrative amplification across proxy outlets"
  ]

  created_regions.values.cycle.take(count).each_with_index.map do |geo, idx|
    headline = "#{story_templates[idx % story_templates.length]} ##{idx + 1}"
    source   = sources[idx % sources.length]
    time     = Time.current - ((idx % 72) * 1.hour)
    body     = <<~HTML
      <p>DEMO INTELLIGENCE SIGNAL</p>
      <p>#{headline}</p>
      <p>
        This fallback article exists to keep the VERITAS demo operational when live NewsAPI
        coverage is thin. It is a seeded narrative signal associated with #{geo[:region].name}
        and source profile #{source}.
      </p>
    HTML

    {
      headline:       headline,
      source_url:     nil,
      source_name:    source,
      content:        body,
      published_at:   time,
      fetched_at:     Time.current,
      latitude:       geo[:region].latitude + rand(-2.0..2.0),
      longitude:      geo[:region].longitude + rand(-2.0..2.0),
      country:        geo[:country],
      region:         geo[:region],
      target_country: 1,
      raw_data:       { "seed_mode" => "fallback_demo", "source" => source, "description" => headline }
    }
  end
end

def seed_articles!(created_regions)
  live_articles = news_api_articles
  created = 0

  if live_articles.any?
    puts "NewsAPI returned #{live_articles.size} articles. Importing..."

    live_articles.each do |attrs|
      Article.create!(attrs)
      created += 1
    rescue StandardError => e
      Rails.logger.warn "[db:seed] Skipping article #{attrs[:source_url]}: #{e.class} #{e.message}"
    end
  else
    puts "NewsAPI unavailable or returned no articles."
  end

  remaining = [100 - created, 0].max
  if remaining.positive?
    puts "Backfilling #{remaining} deterministic demo articles so the app is demo-ready..."
    fallback_articles(created_regions, count: remaining).each do |attrs|
      Article.create!(attrs)
    rescue StandardError => e
      Rails.logger.warn "[db:seed] Failed fallback article #{attrs[:source_url]}: #{e.class} #{e.message}"
    end
  end

  puts "Seed complete! #{Article.count} articles created."
end

def seed_narrative_arcs!
  puts "Seeding Narrative Arcs for globe visualisation..."

  arc_routes = [
    { origin_country: "United States", origin_lat: 38.9072, origin_lng: -77.0369, target_country: "Ukraine", target_lat: 50.4501, target_lng: 30.5234, arc_color: "#ff2d55" },
    { origin_country: "United States", origin_lat: 38.9072, origin_lng: -77.0369, target_country: "China", target_lat: 39.9042, target_lng: 116.4074, arc_color: "#ff9f0a" },
    { origin_country: "United States", origin_lat: 38.9072, origin_lng: -77.0369, target_country: "Israel", target_lat: 31.7683, target_lng: 35.2137, arc_color: "#ff2d55" },
    { origin_country: "Russia", origin_lat: 55.7558, origin_lng: 37.6173, target_country: "Ukraine", target_lat: 50.4501, target_lng: 30.5234, arc_color: "#ff2d55" },
    { origin_country: "Russia", origin_lat: 55.7558, origin_lng: 37.6173, target_country: "Germany", target_lat: 52.52, target_lng: 13.4050, arc_color: "#ff9f0a" },
    { origin_country: "China", origin_lat: 39.9042, origin_lng: 116.4074, target_country: "Taiwan", target_lat: 25.0330, target_lng: 121.5654, arc_color: "#ff2d55" },
    { origin_country: "China", origin_lat: 39.9042, origin_lng: 116.4074, target_country: "India", target_lat: 28.6139, target_lng: 77.2090, arc_color: "#30d158" },
    { origin_country: "Iran", origin_lat: 35.6892, origin_lng: 51.3890, target_country: "Israel", target_lat: 31.7683, target_lng: 35.2137, arc_color: "#ff2d55" },
    { origin_country: "United Kingdom", origin_lat: 51.5074, origin_lng: -0.1278, target_country: "Germany", target_lat: 52.5200, target_lng: 13.4050, arc_color: "#30d158" },
    { origin_country: "India", origin_lat: 28.6139, origin_lng: 77.2090, target_country: "United States", target_lat: 38.9072, target_lng: -77.0369, arc_color: "#30d158" }
  ]

  article_ids = Article.pluck(:id)
  if article_ids.empty?
    puts "No articles found — skipping NarrativeArc seeding."
    return
  end

  arc_routes.each do |route|
    NarrativeArc.create!(route.merge(article_id: article_ids.sample))
  end

  puts "Created #{NarrativeArc.count} narrative arcs."
end

create_perspective_filters!
create_users!
created_regions = create_regions_and_countries!
seed_articles!(created_regions)
seed_narrative_arcs!

puts "Final counts: #{Article.count} articles, #{NarrativeArc.count} arcs, #{Region.count} regions."
