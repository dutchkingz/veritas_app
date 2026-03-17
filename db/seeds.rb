require "securerandom"

puts "Cleaning up database..."
BreakingAlert.destroy_all
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
  %w[vince.mohanna@gmail.com olivertilke@me.com smazliah15@gmail.com].each do |email|
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

  puts "Fetching up to 300 demo articles from NewsAPI..."
  NewsApiService.new.fetch_demo_batch(limit: 300)
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

  remaining = [300 - created, 0].max
  if remaining.positive?
    puts "Backfilling #{remaining} deterministic demo articles so the app is demo-ready..."
    fallback_articles(created_regions, count: remaining).each do |attrs|
      Article.create!(attrs)
    rescue StandardError => e
      Rails.logger.warn "[db:seed] Failed fallback article #{attrs[:source_url]}: #{e.class} #{e.message}"
    end
  end

  puts "Creating initial AI Analyses for demo articles..."
  Article.find_each do |a|
    threat = rand(1..3)
    trust = rand(60..98)
    label = ['Bullish', 'Bearish', 'Neutral'].sample
    color = case label
            when 'Bullish' then '#22c55e'
            when 'Bearish' then '#ef4444'
            else '#38bdf8'
            end

    analyst_trust = [[trust + rand(-5..5), 100].min, 1].max
    sentinel_trust = [[trust + rand(-8..8), 100].min, 1].max

    a.create_ai_analysis!(
      threat_level: threat.to_s,
      trust_score: trust.to_f,
      sentiment_label: label,
      sentiment_color: color,
      analysis_status: 'complete',
      summary: "AI generated summary for #{a.headline}",
      analyst_response: {
        "trust_score" => analyst_trust,
        "sentiment_label" => label,
        "geopolitical_topic" => ["Military", "Trade", "Diplomacy", "Cyber"].sample,
        "threat_level" => threat.to_s,
        "reasoning" => "Initial automated analyst scan complete."
      },
      sentinel_response: {
        "independent_trust_score" => sentinel_trust,
        "bias_direction" => ["LEFT", "RIGHT", "CENTER", "NEUTRAL"].sample,
        "linguistic_anomaly_flag" => [true, false].sample,
        "independent_threat_assessment" => threat.to_s,
        "reasoning" => "Initial automated forensic scan complete."
      },
      arbiter_response: {
        "agreement_level" => ["FULL_CONSENSUS", "PARTIAL_AGREEMENT", "SIGNIFICANT_DISAGREEMENT"].sample,
        "final_trust_score" => trust,
        "final_threat_level" => threat.to_s,
        "final_summary" => "Cross-verified intelligence assessment for #{a.source_name}. Consensus reached on threat posture and narrative framing.",
        "linguistic_anomaly_flag" => [true, false].sample,
        "arbitration_notes" => "Both agents evaluated independently. Weighted judgment applied based on source credibility and bias indicators."
      }
    )
  end

  puts "Seed complete! #{Article.count} articles and #{AiAnalysis.count} analyses created."
end

def seed_narrative_arcs!
  # First, generate embeddings for ALL articles (real ARCWEAVER intelligence)
  puts "\n==== ARCWEAVER 2.0 INITIALIZATION ===="
  puts "Generating 1536-dimensional semantic embeddings for #{Article.count} articles..."

  embedding_service = EmbeddingService.new
  success_count = 0

  Article.find_each do |article|
    success = embedding_service.generate(article)
    success_count += 1 if success
    print "."
  end
  puts "\nGenerated embeddings for #{success_count} articles."

  # Then, run the REAL Route Generator to connect them organically!
  puts "\nGenerating Organic Narrative Tracks via Semantic Clustering..."
  route_service = NarrativeRouteGeneratorService.new
  # limit: nil = process all, force: true = process them even if already connected
  routes_created = route_service.generate_routes(limit: nil, force: true)

  puts "Generated #{routes_created} real narrative routes."
end

create_perspective_filters!
create_users!
created_regions = create_regions_and_countries!
seed_articles!(created_regions)
seed_narrative_arcs!

puts "Final counts: #{Article.count} articles, #{NarrativeArc.count} arcs, #{Region.count} regions."
