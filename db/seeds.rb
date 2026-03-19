require "securerandom"
require_relative "seeds/demo_articles"

# Suppress ActionCable broadcasts for the entire seed — no users are connected
# and SolidCable's insert fails with "No unique index found for id".
Article.skip_callback(:commit, :after, :broadcast_sidebar_update)
Article.skip_callback(:commit, :after, :broadcast_to_globe)

puts "Cleaning up database..."
EmbeddingSnapshot.destroy_all
IntelligenceBrief.destroy_all
ContradictionLog.destroy_all
NarrativeSignatureArticle.destroy_all
NarrativeSignature.destroy_all
SourceCredibility.destroy_all
EntityMention.destroy_all
Entity.destroy_all
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

  region_data = {
    "North America" => { lat: 37.09, lng: -95.71, threat: 1, countries: [
      { name: "United States", iso_code: "USA" },
      { name: "Canada", iso_code: "CAN" },
      { name: "Mexico", iso_code: "MEX" }
    ]},
    "South America" => { lat: -14.24, lng: -51.93, threat: 1, countries: [
      { name: "Brazil", iso_code: "BRA" },
      { name: "Argentina", iso_code: "ARG" },
      { name: "Colombia", iso_code: "COL" },
      { name: "Venezuela", iso_code: "VEN" }
    ]},
    "Western Europe" => { lat: 48.86, lng: 2.35, threat: 1, countries: [
      { name: "Germany", iso_code: "DEU" },
      { name: "France", iso_code: "FRA" },
      { name: "United Kingdom", iso_code: "GBR" },
      { name: "Netherlands", iso_code: "NLD" },
      { name: "Spain", iso_code: "ESP" },
      { name: "Italy", iso_code: "ITA" }
    ]},
    "Eastern Europe" => { lat: 48.38, lng: 31.17, threat: 3, countries: [
      { name: "Ukraine", iso_code: "UKR" },
      { name: "Poland", iso_code: "POL" },
      { name: "Romania", iso_code: "ROU" },
      { name: "Russia", iso_code: "RUS" }
    ]},
    "Middle East" => { lat: 31.05, lng: 34.85, threat: 3, countries: [
      { name: "Israel", iso_code: "ISR" },
      { name: "Iran", iso_code: "IRN" },
      { name: "Saudi Arabia", iso_code: "SAU" },
      { name: "Turkey", iso_code: "TUR" },
      { name: "Iraq", iso_code: "IRQ" },
      { name: "Syria", iso_code: "SYR" }
    ]},
    "East Asia" => { lat: 35.86, lng: 104.20, threat: 2, countries: [
      { name: "China", iso_code: "CHN" },
      { name: "Japan", iso_code: "JPN" },
      { name: "South Korea", iso_code: "KOR" },
      { name: "Taiwan", iso_code: "TWN" },
      { name: "North Korea", iso_code: "PRK" }
    ]},
    "South Asia" => { lat: 20.59, lng: 78.96, threat: 2, countries: [
      { name: "India", iso_code: "IND" },
      { name: "Pakistan", iso_code: "PAK" },
      { name: "Bangladesh", iso_code: "BGD" }
    ]},
    "Southeast Asia" => { lat: 1.35, lng: 103.82, threat: 1, countries: [
      { name: "Indonesia", iso_code: "IDN" },
      { name: "Philippines", iso_code: "PHL" },
      { name: "Vietnam", iso_code: "VNM" },
      { name: "Thailand", iso_code: "THA" }
    ]},
    "Africa" => { lat: -1.29, lng: 36.82, threat: 2, countries: [
      { name: "Nigeria", iso_code: "NGA" },
      { name: "South Africa", iso_code: "ZAF" },
      { name: "Kenya", iso_code: "KEN" },
      { name: "Egypt", iso_code: "EGY" },
      { name: "Ethiopia", iso_code: "ETH" }
    ]},
    "Central Asia" => { lat: 41.30, lng: 69.28, threat: 2, countries: [
      { name: "Kazakhstan", iso_code: "KAZ" },
      { name: "Uzbekistan", iso_code: "UZB" },
      { name: "Afghanistan", iso_code: "AFG" }
    ]},
    "Oceania" => { lat: -25.27, lng: 133.78, threat: 1, countries: [
      { name: "Australia", iso_code: "AUS" },
      { name: "New Zealand", iso_code: "NZL" }
    ]}
  }

  region_data.each_with_object({}) do |(region_name, data), result|
    region = Region.create!(
      name: region_name,
      latitude: data[:lat],
      longitude: data[:lng],
      threat_level: data[:threat],
      article_volume: 0,
      last_calculated_at: Time.current
    )

    countries = data[:countries].map do |c|
      Country.create!(region: region, name: c[:name], iso_code: c[:iso_code])
    end

    result[region_name] = { region: region, country: countries.first }
  end
end

def news_api_articles
  return [] if ENV["NEWS_API_KEY"].blank?

  puts "Fetching up to 300 demo articles from NewsAPI..."
  NewsApiService.new.fetch_demo_batch(limit: 300, max_pages_per_query: 1)
end

def fallback_articles(created_regions, count:)
  # Build lookup tables for region/country resolution
  region_lookup = {}
  country_lookup = {}
  created_regions.each do |name, data|
    region_lookup[name] = data
    data[:region].countries.each { |c| country_lookup[c.iso_code] = c } if data[:region].respond_to?(:countries)
  end
  # Also look up countries from DB if not in the hash
  Country.find_each { |c| country_lookup[c.iso_code] ||= c }

  # Use curated DEMO_ARTICLES, cycling if more than 50 needed
  DEMO_ARTICLES.cycle.take(count).each_with_index.map do |template, idx|
    geo = region_lookup[template[:region_name]] || created_regions.values.sample
    country = country_lookup[template[:country_iso]] || geo[:country]

    # Spread articles over 7 days for timeline slider variety
    time = Time.current - (idx * 3.36.hours) # ~50 articles over 7 days

    {
      headline:       template[:headline],
      source_url:     nil,
      source_name:    template[:source_name],
      content:        template[:content],
      published_at:   time,
      fetched_at:     Time.current,
      latitude:       geo[:region].latitude + rand(-2.0..2.0),
      longitude:      geo[:region].longitude + rand(-2.0..2.0),
      country:        country,
      region:         geo[:region],
      raw_data:       {
        "seed_mode"   => "fallback_demo",
        "source"      => template[:source_name],
        "description" => template[:headline],
        "topic"       => template[:topic],
        "sentiment"   => template[:sentiment],
        "threat"      => template[:threat],
        "trust"       => template[:trust]
      }
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
      puts "[db:seed] Skipping article #{attrs[:source_url]}: #{e.class} #{e.message}"
    end
  else
    puts "NewsAPI unavailable or returned no articles."
  end

  target = created > 0 ? 300 : DEMO_ARTICLES.size  # Use curated set size when no API
  remaining = [target - created, 0].max
  if remaining.positive?
    puts "Backfilling #{remaining} curated demo articles so the app is demo-ready..."
    fallback_articles(created_regions, count: remaining).each do |attrs|
      Article.create!(attrs)
    rescue StandardError => e
      puts "[db:seed] Failed fallback article #{attrs[:source_url]}: #{e.class} #{e.message}"
    end
  end

  puts "Creating initial AI Analyses for demo articles..."

  # Build a lookup from headline to template for curated data
  template_lookup = DEMO_ARTICLES.index_by { |t| t[:headline] }

  Article.find_each do |a|
    template = template_lookup[a.headline]

    # Use curated values from template if available, otherwise generate
    if template
      threat  = template[:threat]
      trust   = template[:trust]
      label   = template[:sentiment]
      topic   = template[:topic]
      summary = template[:summary]
    else
      # Fallback for NewsAPI or extra articles: use raw_data hints or randomize
      raw = a.raw_data || {}
      threat  = raw["threat"] || rand(1..3)
      trust   = raw["trust"] || rand(60..98)
      label   = raw["sentiment"] || ['Bullish', 'Bearish', 'Neutral'].sample
      topic   = raw["topic"] || ["Military", "Trade", "Diplomacy", "Cyber"].sample
      summary = "Intelligence assessment for #{a.source_name}: #{a.headline}"
    end

    color = case label
            when 'Bullish' then '#22c55e'
            when 'Bearish' then '#ef4444'
            else '#38bdf8'
            end

    # Derive bias direction from source reputation
    bias = case a.source_name
           when "Fox News", "Breitbart", "Daily Wire" then "RIGHT"
           when "CNN", "MSNBC", "New York Times", "Washington Post", "The Guardian" then "LEFT"
           when "RT", "TASS", "Sputnik", "Xinhua", "Global Times" then "STATE"
           else "CENTER"
           end

    analyst_trust = [[trust + rand(-3..3), 100].min, 1].max
    sentinel_trust = [[trust + rand(-5..5), 100].min, 1].max
    anomaly = trust < 60 || %w[RT TASS Sputnik Xinhua].include?(a.source_name) ? true : [true, false, false].sample

    agreement = if (analyst_trust - sentinel_trust).abs <= 5
                  "FULL_CONSENSUS"
                elsif (analyst_trust - sentinel_trust).abs <= 15
                  "PARTIAL_AGREEMENT"
                else
                  "SIGNIFICANT_DISAGREEMENT"
                end

    a.create_ai_analysis!(
      threat_level: threat.to_s,
      trust_score: trust.to_f,
      sentiment_label: label,
      sentiment_color: color,
      analysis_status: 'complete',
      summary: summary,
      analyst_response: {
        "trust_score" => analyst_trust,
        "sentiment_label" => label,
        "geopolitical_topic" => topic,
        "threat_level" => threat.to_s,
        "reasoning" => "Analyst assessment: #{summary}"
      },
      sentinel_response: {
        "independent_trust_score" => sentinel_trust,
        "bias_direction" => bias,
        "linguistic_anomaly_flag" => anomaly,
        "independent_threat_assessment" => threat.to_s,
        "reasoning" => "Forensic scan of #{a.source_name} content. Bias direction: #{bias}. #{anomaly ? 'Linguistic anomalies detected — possible coordinated framing.' : 'No significant linguistic anomalies.'}"
      },
      arbiter_response: {
        "agreement_level" => agreement,
        "final_trust_score" => trust,
        "final_threat_level" => threat.to_s,
        "final_summary" => summary,
        "linguistic_anomaly_flag" => anomaly,
        "arbitration_notes" => "Cross-verification complete for #{a.source_name}. #{agreement.gsub('_', ' ').downcase.capitalize} between analyst and sentinel. Trust score #{trust >= 80 ? 'within high-confidence range' : trust >= 60 ? 'moderate — recommend secondary verification' : 'below threshold — flagged for manual review'}."
      }
    )
  end

  puts "Seed complete! #{Article.count} articles and #{AiAnalysis.count} analyses created."
end

def seed_narrative_arcs!
  # First, generate embeddings for ALL articles (real ARCWEAVER intelligence)
  puts "\n==== ARCWEAVER 2.0 INITIALIZATION ===="
  puts "Generating 1536-dimensional semantic embeddings for #{Article.count} articles..."

  success_count = 0

  # Build a base vector per geopolitical topic so articles on the same topic
  # cluster together and pass the 0.65 cosine-similarity threshold.
  topics = %w[Military Trade Diplomacy Cyber]
  topic_bases = topics.each_with_index.to_h do |topic, i|
    rng = Random.new(i * 7919) # deterministic per topic
    [topic, Array.new(1536) { rng.rand(-1.0..1.0) }]
  end

  Article.find_each do |article|
    topic = article.ai_analysis&.analyst_response&.dig("geopolitical_topic") || topics.sample
    base = topic_bases[topic] || topic_bases.values.first
    # Small perturbation keeps articles distinct but close to their topic centroid
    rng = Random.new(article.id)
    vector = base.map { |v| v + rng.rand(-0.15..0.15) }
    article.update!(embedding: vector)
    success_count += 1
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

def seed_compounding_intelligence!
  puts "\n==== COMPOUNDING INTELLIGENCE SEED ===="

  # --- Entities & Mentions ---
  puts "Extracting entities from articles..."
  entity_pool = {
    "person" => [
      "Volodymyr Zelensky", "Vladimir Putin", "Xi Jinping", "Joe Biden",
      "Narendra Modi", "Emmanuel Macron", "Olaf Scholz", "Benjamin Netanyahu",
      "Mohammad bin Salman", "Recep Tayyip Erdogan", "Ali Khamenei",
      "Hossein Amir-Abdollahian", "Yoav Gallant", "Amos Yadlin",
      "Janet Yellen", "Anthony Blinken", "Jake Sullivan", "Sergei Lavrov",
      "Wang Yi", "Jens Stoltenberg", "Mark Milley", "Christopher Wray"
    ],
    "organization" => [
      "NATO", "UN", "EU", "BRICS", "OPEC", "WHO", "IMF", "IAEA", "G7", "G20",
      "Wagner Group", "Africa Corps", "Hezbollah", "Hamas", "Houthis",
      "CIA", "Mossad", "FSB", "GRU", "NSA", "CISA", "Sandworm",
      "ASEAN", "African Union", "Mandiant", "Lloyd's of London",
      "TSMC", "NVIDIA", "Samsung", "Rapidus", "Pentagon",
      "Internet Research Agency", "Stanford Internet Observatory"
    ],
    "country" => [
      "Ukraine", "Russia", "China", "Taiwan", "United States", "Iran", "Israel",
      "Saudi Arabia", "North Korea", "India", "Pakistan", "Turkey", "Syria",
      "France", "Germany", "United Kingdom", "Poland", "Qatar",
      "Japan", "South Korea", "Singapore", "Brazil", "Mali", "Niger"
    ],
    "event" => [
      "Ukraine Conflict", "Gaza War", "Taiwan Strait Tensions",
      "BRICS Expansion", "US Election 2026", "Iran Nuclear Talks",
      "Red Sea Shipping Crisis", "Sahel Insurgency", "AI Arms Race",
      "Sanctions Escalation", "Fordow Enrichment Crisis", "Black Sea Naval Standoff",
      "TIDEWRECK Cyber Attack", "Silicon Chip War", "Deepfake Election Campaign",
      "BRICS Bridge Launch", "Operation Blue Horizon", "Houthi Chokehold"
    ]
  }

  entities = {}
  entity_pool.each do |entity_type, names|
    names.each do |name|
      entities[name] = Entity.create!(
        name:            name,
        normalized_name: name.downcase.strip,
        entity_type:     entity_type,
        first_seen_at:   rand(72).hours.ago
      )
    end
  end

  # Topic → entity affinity map for richer, meaningful NEXUS connections
  topic_entity_affinity = {
    "Military"   => ["NATO", "Wagner Group", "Africa Corps", "GRU", "NSA", "CIA", "Mossad",
                      "Pentagon", "Vladimir Putin", "Benjamin Netanyahu", "Yoav Gallant",
                      "Ukraine Conflict", "Black Sea Naval Standoff", "Sahel Insurgency",
                      "Russia", "Ukraine", "Iran", "Israel"],
    "Diplomacy"  => ["IAEA", "UN", "EU", "G7", "G20", "BRICS", "Hossein Amir-Abdollahian",
                      "Anthony Blinken", "Sergei Lavrov", "Wang Yi", "Jens Stoltenberg",
                      "Iran Nuclear Talks", "Fordow Enrichment Crisis", "BRICS Expansion",
                      "BRICS Bridge Launch", "Iran", "Saudi Arabia", "China", "Russia"],
    "Cyber"      => ["NSA", "CIA", "GRU", "Sandworm", "FSB", "CISA", "Mandiant",
                      "Internet Research Agency", "Stanford Internet Observatory",
                      "Christopher Wray", "TIDEWRECK Cyber Attack", "Deepfake Election Campaign",
                      "AI Arms Race", "United States", "Russia"],
    "Trade"      => ["TSMC", "NVIDIA", "Samsung", "Rapidus", "OPEC", "IMF", "Janet Yellen",
                      "Lloyd's of London", "Silicon Chip War", "Red Sea Shipping Crisis",
                      "BRICS Bridge Launch", "Sanctions Escalation", "Houthi Chokehold",
                      "China", "Taiwan", "United States", "Japan", "South Korea"]
  }

  # Link entities to articles — headline match + topic affinity + random fill
  all_entity_names = entities.keys
  Article.includes(:ai_analysis).find_each do |article|
    headline = article.headline.to_s.downcase
    topic    = article.ai_analysis&.analyst_response&.dig("geopolitical_topic") || "Military"

    # 1. Headline keyword matches
    matched = all_entity_names.select { |name| headline.include?(name.downcase) }

    # 2. Topic-affinity entities (pick 3-5 from affinity pool)
    affinity = topic_entity_affinity[topic] || topic_entity_affinity["Military"]
    affinity_picks = (affinity & all_entity_names).sample(rand(3..5))

    # 3. Combine and ensure 5-8 total mentions for rich NEXUS graph
    combined = (matched + affinity_picks).uniq
    combined += all_entity_names.sample(rand(2..3)) while combined.size < 5
    combined = combined.first(8)

    combined.each do |name|
      EntityMention.create!(entity: entities[name], article: article)
    rescue ActiveRecord::RecordInvalid
      next
    end
  end
  puts "Created #{Entity.count} entities with #{EntityMention.count} mentions (avg #{(EntityMention.count.to_f / [Article.count, 1].max).round(1)} per article)."

  # --- Source Credibility ---
  puts "Building source credibility profiles..."
  Article.group(:source_name).count.each do |source_name, count|
    analyses = AiAnalysis.joins(:article).where(articles: { source_name: source_name })
    avg_trust = analyses.average(:trust_score)&.round(1) || 70.0
    high_threat = analyses.where(threat_level: "3").count
    low_threat = analyses.where(threat_level: "1").count
    anomaly_count = analyses.where("sentinel_response->>'linguistic_anomaly_flag' = 'true'").count

    topics = analyses.filter_map { |a| a.analyst_response&.dig("geopolitical_topic") }
    sentiments = analyses.pluck(:sentiment_label).compact

    SourceCredibility.create!(
      source_name: source_name,
      credibility_grade: avg_trust,
      rolling_trust_score: avg_trust + rand(-5.0..5.0),
      anomaly_rate: count > 0 ? (anomaly_count.to_f / count).round(3) : 0.0,
      articles_analyzed: count,
      high_threat_count: high_threat,
      low_threat_count: low_threat,
      topic_distribution: topics.tally,
      sentiment_distribution: sentiments.tally,
      coordination_flags: [],
      first_analyzed_at: rand(72).hours.ago,
      last_analyzed_at: Time.current
    )
  end
  puts "Profiled #{SourceCredibility.count} sources."

  # --- Narrative Signatures ---
  puts "Detecting narrative signatures..."
  topics = AiAnalysis.where(analysis_status: "complete")
                     .filter_map { |a| a.analyst_response&.dig("geopolitical_topic") }
                     .uniq

  topics.each do |topic|
    articles = Article.joins(:ai_analysis)
                      .where("ai_analyses.analyst_response->>'geopolitical_topic' = ?", topic)
                      .limit(50)
    next if articles.size < 3

    avg_trust = articles.joins(:ai_analysis).average("ai_analyses.trust_score")&.round(1) || 70.0
    sources = articles.pluck(:source_name).tally
    countries = articles.includes(:country).filter_map { |a| a.country&.name }.tally

    sig = NarrativeSignature.create!(
      label: "#{topic} Narrative Cluster",
      active: true,
      match_count: articles.size,
      avg_trust_score: avg_trust,
      dominant_threat_level: %w[1 2 3].sample,
      source_distribution: sources,
      country_distribution: countries,
      first_seen_at: rand(48..72).hours.ago,
      last_seen_at: rand(0..4).hours.ago
    )

    articles.each do |article|
      NarrativeSignatureArticle.create!(
        narrative_signature: sig,
        article: article,
        cosine_distance: rand(0.05..0.35).round(4),
        matched_at: Time.current
      )
    rescue ActiveRecord::RecordInvalid
      next
    end
  end
  puts "Created #{NarrativeSignature.count} narrative signatures."

  # --- Contradiction Logs ---
  puts "Seeding contradiction detections..."

  # Build headline→article lookup for curated contradiction pairs
  headline_to_article = Article.all.index_by(&:headline)

  DEMO_CONTRADICTIONS.each do |pair|
    template_a = DEMO_ARTICLES[pair[:article_a_idx]]
    template_b = DEMO_ARTICLES[pair[:article_b_idx]]
    next unless template_a && template_b

    article_a = headline_to_article[template_a[:headline]]
    article_b = headline_to_article[template_b[:headline]]
    next unless article_a && article_b

    ContradictionLog.create!(
      article_a_id: article_a.id,
      article_b_id: article_b.id,
      contradiction_type: pair[:contradiction_type],
      severity: pair[:severity],
      embedding_similarity: rand(0.55..0.82).round(4),
      source_a: article_a.source_name,
      source_b: article_b.source_name,
      description: pair[:description],
      metadata: {}
    )
  rescue ActiveRecord::RecordInvalid => e
    puts "[contradiction] Skipping: #{e.message}"
    next
  end

  # Add a few more random contradictions to fill out the dataset
  all_articles = Article.where.not(source_name: nil).to_a
  10.times do
    a, b = all_articles.sample(2)
    next unless a && b && a.id != b.id

    ContradictionLog.create!(
      article_a_id: a.id,
      article_b_id: b.id,
      contradiction_type: %w[cross_source temporal_shift].sample,
      severity: rand(0.4..0.80).round(2),
      embedding_similarity: rand(0.45..0.80).round(4),
      source_a: a.source_name,
      source_b: b.source_name,
      description: "Narrative framing diverges significantly between #{a.source_name} and #{b.source_name} on the same underlying event.",
      metadata: {}
    )
  rescue ActiveRecord::RecordInvalid
    next
  end

  puts "Logged #{ContradictionLog.count} contradictions."

  # --- Intelligence Brief ---
  puts "Generating intelligence brief..."
  sig_names = NarrativeSignature.pluck(:label)
  regions = Region.pluck(:name)

  IntelligenceBrief.create!(
    title: "VERITAS Daily Intelligence Assessment — #{Date.today.strftime('%d %b %Y')}",
    brief_type: "daily",
    status: "complete",
    executive_summary: "VERITAS has processed #{Article.count} articles across #{SourceCredibility.count} profiled sources over the past 7 days. " \
      "#{NarrativeSignature.count} active narrative signatures detected with #{ContradictionLog.count} cross-source contradictions flagged for analyst review. " \
      "THREAT POSTURE: ELEVATED. Multiple simultaneous escalation vectors detected — Black Sea naval standoff, Iran nuclear enrichment at 83.7%, " \
      "coordinated cyberattack on European ports attributed to GRU Unit 74455, and PLA encirclement exercises around Taiwan. " \
      "The IMF has warned of polycrisis cascading risks. State media narratives from Russia and China show coordinated framing patterns " \
      "that diverge significantly from independent source reporting. VERITAS recommends heightened monitoring of narrative amplification " \
      "across Eastern Europe and Indo-Pacific corridors.",
    period_start: 24.hours.ago,
    period_end: Time.current,
    articles_processed: Article.count,
    signatures_active: NarrativeSignature.count,
    contradictions_found: ContradictionLog.count,
    narrative_trends: sig_names.map { |name| { "label" => name, "direction" => %w[rising stable declining].sample, "article_count" => rand(10..50) } },
    contradictions: ContradictionLog.limit(5).map { |c| { "description" => c.description, "severity" => c.severity, "sources" => [c.source_a, c.source_b] } },
    blind_spots: regions.sample(3).map { |r| { "region" => r, "reason" => "Low article coverage (<5 articles in 24h)" } },
    source_alerts: SourceCredibility.order(:credibility_grade).limit(3).map { |s| { "source" => s.source_name, "alert" => "Below-average trust score: #{s.credibility_grade}" } },
    confidence_map: sig_names.index_with { rand(60..95) }
  )
  puts "Created #{IntelligenceBrief.count} intelligence brief."

  # --- Embedding Snapshot ---
  puts "Capturing embedding snapshot..."
  EmbeddingSnapshot.create!(
    captured_at: Time.current,
    article_count: Article.where.not(embedding: nil).count,
    cluster_count: NarrativeSignature.count,
    cluster_summary: NarrativeSignature.limit(10).map { |s| { "label" => s.label, "size" => s.match_count, "avg_trust" => s.avg_trust_score } },
    drift_metrics: { "mean_shift" => rand(0.01..0.05).round(4), "max_shift" => rand(0.05..0.15).round(4), "clusters_merged" => 0, "clusters_split" => 0 },
    outlier_ids: Article.order("RANDOM()").limit(5).pluck(:id)
  )
  puts "Snapshot captured."
end

def seed_demo_routes!
  puts "\n==== CINEMATIC NARRATIVE ROUTE INJECTION ===="

  # ── City coordinate hub map ─────────────────────────────────────────────────
  hubs = {
    vienna:     { lat: 48.21,  lng:  16.37,   country: "Austria",        city: "Vienna" },
    tehran:     { lat: 35.69,  lng:  51.39,   country: "Iran",           city: "Tehran" },
    tel_aviv:   { lat: 32.09,  lng:  34.78,   country: "Israel",         city: "Tel Aviv" },
    riyadh:     { lat: 24.69,  lng:  46.72,   country: "Saudi Arabia",   city: "Riyadh" },
    moscow:     { lat: 55.76,  lng:  37.62,   country: "Russia",         city: "Moscow" },
    beijing:    { lat: 39.90,  lng: 116.41,   country: "China",          city: "Beijing" },
    new_delhi:  { lat: 28.61,  lng:  77.21,   country: "India",          city: "New Delhi" },
    washington: { lat: 38.91,  lng: -77.04,   country: "United States",  city: "Washington DC" },
    new_york:   { lat: 40.71,  lng: -74.01,   country: "United States",  city: "New York" },
    london:     { lat: 51.51,  lng:  -0.13,   country: "United Kingdom", city: "London" },
    paris:      { lat: 48.86,  lng:   2.35,   country: "France",         city: "Paris" },
    berlin:     { lat: 52.52,  lng:  13.41,   country: "Germany",        city: "Berlin" },
    doha:       { lat: 25.29,  lng:  51.53,   country: "Qatar",          city: "Doha" },
    tokyo:      { lat: 35.68,  lng: 139.65,   country: "Japan",          city: "Tokyo" },
    seoul:      { lat: 37.57,  lng: 126.98,   country: "South Korea",    city: "Seoul" },
    taipei:     { lat: 25.04,  lng: 121.57,   country: "Taiwan",         city: "Taipei" },
    singapore:  { lat:  1.35,  lng: 103.82,   country: "Singapore",      city: "Singapore" },
    cairo:      { lat: 30.04,  lng:  31.24,   country: "Egypt",          city: "Cairo" },
    nairobi:    { lat: -1.29,  lng:  36.82,   country: "Kenya",          city: "Nairobi" },
    islamabad:  { lat: 33.68,  lng:  73.05,   country: "Pakistan",       city: "Islamabad" },
    ankara:     { lat: 39.92,  lng:  32.85,   country: "Turkey",         city: "Ankara" },
    brasilia:   { lat: -15.78, lng: -47.93,   country: "Brazil",         city: "Brasilia" },
    kyiv:       { lat: 50.45,  lng:  30.52,   country: "Ukraine",        city: "Kyiv" },
    rotterdam:  { lat: 51.92,  lng:   4.48,   country: "Netherlands",    city: "Rotterdam" },
    warsaw:     { lat: 52.23,  lng:  21.01,   country: "Poland",         city: "Warsaw" },
    bamako:     { lat: 12.65,  lng:  -8.00,   country: "Mali",           city: "Bamako" },
    dubai:      { lat: 25.20,  lng:  55.27,   country: "UAE",            city: "Dubai" },
  }

  # ── Helpers ─────────────────────────────────────────────────────────────────
  article_by_source = Article.includes(:ai_analysis, :country)
                             .group_by { |a| a.source_name.to_s.downcase }

  find_article = ->(source) {
    article_by_source[source.downcase]&.first ||
    Article.where("LOWER(source_name) LIKE ?", "%#{source.downcase}%").first
  }

  make_hop = ->(source, city_key, framing, confidence, hours_offset, base_time, headline: nil) {
    hub     = hubs[city_key]
    article = find_article.(source)
    {
      "article_id"          => article&.id,
      "source_name"         => source,
      "headline"            => headline || article&.headline,
      "source_country"      => hub[:country],
      "source_city"         => hub[:city],
      "lat"                 => hub[:lat] + rand(-0.25..0.25).round(4),
      "lng"                 => hub[:lng] + rand(-0.25..0.25).round(4),
      "published_at"        => (base_time + hours_offset.hours).iso8601,
      "framing_shift"       => framing,
      "confidence_score"    => confidence,
      "delay_from_previous" => hours_offset * 3600,
    }
  }

  create_route = ->(origin_article, hops_data, name, description, color) {
    return unless origin_article
    arc = NarrativeArc.create!(
      article_id:     origin_article.id,
      origin_country: hops_data.first["source_country"],
      origin_lat:     hops_data.first["lat"],
      origin_lng:     hops_data.first["lng"],
      target_country: hops_data.last["source_country"],
      target_lat:     hops_data.last["lat"],
      target_lng:     hops_data.last["lng"],
      arc_color:      color,
    )
    NarrativeRoute.create!(
      narrative_arc_id: arc.id,
      name:             name,
      description:      description,
      hops:             hops_data,
      is_complete:      true,
      status:           "tracking",
    )
  }

  t              = Time.current
  routes_created = 0

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 1 — Iran Nuclear Talks Collapse: "Operation Fordow Signal"
  # Vienna → Tehran → Tel Aviv → Riyadh → Moscow → Beijing → New Delhi → Washington
  # Scoring: 10 → 26 → 42 → 50 → 74 → 98 → 100 → 100
  # Labels:  ORIGINAL → AMPLIFIED → CONCERNING → CONCERNING → HOSTILE → CRITICAL THREAT
  # ────────────────────────────────────────────────────────────────────────────
  iran_origin = Article.where("headline ILIKE ?", "%Iran nuclear%").first ||
                Article.where(source_name: "Reuters").first
  if iran_origin
    hops = [
      make_hop.("Reuters",        :vienna,     "original",    0.95, 0,  t - 7.days, headline: "IAEA detects uranium enriched to 83.7% at Fordow — Vienna talks collapse"),
      make_hop.("Al Jazeera",     :tehran,     "amplified",   0.88, 6,  t - 7.days, headline: "Iran dismisses IAEA findings as politically motivated fabrications against peaceful program"),
      make_hop.("CNN",            :tel_aviv,   "amplified",   0.82, 14, t - 7.days, headline: "Israel puts IDF on heightened alert — Blue Horizon exercise simulates Iran strike"),
      make_hop.("Arab News",      :riyadh,     "neutralized", 0.76, 22, t - 7.days, headline: "Saudi Arabia fast-tracks nuclear program as Iran breakout timeline collapses to weeks"),
      make_hop.("TASS",           :moscow,     "distorted",   0.70, 32, t - 7.days, headline: "Russia accuses West of weaponising IAEA to justify military aggression against Iran"),
      make_hop.("Xinhua",         :beijing,    "distorted",   0.65, 44, t - 7.days, headline: "China urges US restraint — Iran sanctions escalation threatens global energy stability"),
      make_hop.("Times of India", :new_delhi,  "amplified",   0.79, 54, t - 7.days, headline: "IRGC vows full retaliation if Iran struck — nuclear breakout window now days, not months"),
      make_hop.("Fox News",       :washington, "distorted",   0.61, 72, t - 7.days, headline: "Biden diplomacy failure leaves world on nuclear brink — appeasement has cost us everything"),
    ]
    r = create_route.(iran_origin, hops,
      "Operation Fordow Signal",
      "Nuclear enrichment crisis explodes across 8 global media ecosystems — tracking the collapse from diplomatic to existential threat in 72 hours",
      "#a78bfa")
    routes_created += 1 if r
    puts "  ✓ Route 1: Iran Nuclear — 8 hops, Vienna → Washington (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 2 — Black Sea Naval Standoff: "Crimea Gambit"
  # London → Moscow → Kyiv → Ankara → Washington → Paris → Beijing
  # Labels: ORIGINAL → HOSTILE → AMPLIFIED → CONCERNING → AMPLIFIED → CONCERNING → HOSTILE
  # ────────────────────────────────────────────────────────────────────────────
  black_sea_origin = Article.where("headline ILIKE ?", "%NATO%Black Sea%").first ||
                     Article.where("headline ILIKE ?", "%Black Sea%").first
  if black_sea_origin
    hops = [
      make_hop.("Reuters",          :london,     "original",    0.93, 0,  t - 5.days, headline: "NATO carrier group enters Black Sea — Russia shadows with 4 corvettes and submarines"),
      make_hop.("RT",               :moscow,     "distorted",   0.72, 8,  t - 5.days, headline: "NATO provocateurs breach Russian security perimeter — Bastion-P systems on full alert"),
      make_hop.("BBC",              :kyiv,       "amplified",   0.85, 16, t - 5.days, headline: "Ukraine: NATO ships are lifeline — Russia naval attacks on civilian shipping up 40%"),
      make_hop.("TRT World",        :ankara,     "amplified",   0.78, 26, t - 5.days, headline: "Turkey's Bosphorus decision makes Istanbul flashpoint of NATO-Russia confrontation"),
      make_hop.("Associated Press", :washington, "neutralized", 0.89, 38, t - 5.days, headline: "Satellite imagery contradicts Kremlin — NATO ships 90 miles from Crimea, not encroaching"),
      make_hop.("AFP",              :paris,      "amplified",   0.83, 50, t - 5.days, headline: "European ministers alarmed as Black Sea standoff edges toward kinetic confrontation"),
      make_hop.("CGTN",             :beijing,    "distorted",   0.64, 64, t - 5.days, headline: "China condemns NATO's Cold War aggression in Russia's legitimate Black Sea security zone"),
    ]
    r = create_route.(black_sea_origin, hops,
      "Crimea Gambit",
      "Naval escalation tracked across 7 global outlets — NATO framing war plays out from London to Beijing in 64 hours",
      "#ef4444")
    routes_created += 1 if r
    puts "  ✓ Route 2: Black Sea Naval — 7 hops, London → Beijing (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 3 — Taiwan AI Chip War: "Silicon Stranglehold"
  # Washington → Beijing → Taipei → Tokyo → Seoul → Singapore → London
  # Labels: ORIGINAL → HOSTILE → AMPLIFIED → AMPLIFIED → AMPLIFIED → CONCERNING → HOSTILE
  # ────────────────────────────────────────────────────────────────────────────
  chip_origin = Article.where("headline ILIKE ?", "%AI chip%China%").first ||
                Article.where("headline ILIKE ?", "%chip%ban%").first ||
                Article.where(source_name: "Bloomberg").first
  if chip_origin
    hops = [
      make_hop.("Bloomberg",        :new_york,   "original",    0.96, 0,  t - 6.days, headline: "US expands AI chip export ban to 14 Chinese entities — $12B annual revenue wiped overnight"),
      make_hop.("Global Times",     :beijing,    "distorted",   0.68, 10, t - 6.days, headline: "China retaliates with rare earth export controls targeting F-35, precision munitions supply chains"),
      make_hop.("Financial Times",  :taipei,     "amplified",   0.87, 20, t - 6.days, headline: "TSMC caught in crossfire — Arizona fab 18 months late as both superpowers demand loyalty"),
      make_hop.("NHK World",        :tokyo,      "amplified",   0.82, 32, t - 6.days, headline: "Japan-South Korea historic chip alliance: Samsung and Rapidus ink $8B deal"),
      make_hop.("Associated Press", :seoul,      "amplified",   0.84, 46, t - 6.days, headline: "Seoul warns semiconductor decoupling accelerates — Asia enters permanent tech cold war"),
      make_hop.("Channel NewsAsia", :singapore,  "amplified",   0.76, 58, t - 6.days, headline: "Southeast Asia becomes contested battleground as US demands supply chain alignment"),
      make_hop.("The Economist",    :london,     "distorted",   0.80, 72, t - 6.days, headline: "The chip war will reshape the global order — and there are no winners, only survivors"),
    ]
    r = create_route.(chip_origin, hops,
      "Silicon Stranglehold",
      "AI chip embargo cascades across 7 Indo-Pacific media centers — trade warfare narrative escalates from commercial to civilizational conflict",
      "#f59e0b")
    routes_created += 1 if r
    puts "  ✓ Route 3: Taiwan Chip War — 7 hops, New York → London (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 4 — European Cyber Attack: "TIDEWRECK Cascade"
  # Rotterdam → Moscow → Washington → London → Berlin → Warsaw → Nairobi
  # Labels: ORIGINAL → HOSTILE → AMPLIFIED → AMPLIFIED → AMPLIFIED → CONCERNING → CONCERNING
  # ────────────────────────────────────────────────────────────────────────────
  cyber_origin = Article.where("headline ILIKE ?", "%cyberattack%port%").first ||
                 Article.where("headline ILIKE ?", "%TIDEWRECK%").first ||
                 Article.where("headline ILIKE ?", "%cyber%European%").first
  if cyber_origin
    hops = [
      make_hop.("BBC",             :rotterdam,  "original",    0.92, 0,  t - 4.days, headline: "TIDEWRECK malware cripples 6 European ports simultaneously — $2.1B daily trade paralysed"),
      make_hop.("TASS",            :moscow,     "distorted",   0.55, 6,  t - 4.days, headline: "Russia categorically denies port hack — calls EU attribution a Russophobic false flag"),
      make_hop.("Washington Post", :washington, "amplified",   0.84, 14, t - 4.days, headline: "NSA attributes TIDEWRECK to GRU Sandworm with high confidence — retaliation options on table"),
      make_hop.("Financial Times", :london,     "amplified",   0.88, 24, t - 4.days, headline: "Lloyd's faces $4B cyber war exposure — state-attack exclusion clauses tested in landmark case"),
      make_hop.("Deutsche Welle",  :berlin,     "amplified",   0.81, 36, t - 4.days, headline: "EU emergency cyber summit convenes — NATO Article 5 cyber clause invoked for first time"),
      make_hop.("Reuters",         :warsaw,     "amplified",   0.77, 50, t - 4.days, headline: "Poland places military on alert as NATO confirms Sandworm attribution — sanctions incoming"),
      make_hop.("Nation Africa",   :nairobi,    "amplified",   0.70, 66, t - 4.days, headline: "African ports brace for spillover as European cyber war disrupts global supply lanes"),
    ]
    r = create_route.(cyber_origin, hops,
      "TIDEWRECK Cascade",
      "State-sponsored cyber warfare narrative tracked from Rotterdam breach across 7 continents — incident to Article 5 in 66 hours",
      "#00f0ff")
    routes_created += 1 if r
    puts "  ✓ Route 4: Cyber Attack — 7 hops, Rotterdam → Nairobi (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 5 — Sahel Wagner Expansion: "Africa Corps Shadow"
  # Paris → Moscow → Bamako → Nairobi → Beijing → Washington
  # Labels: ORIGINAL → HOSTILE → CONCERNING → AMPLIFIED → HOSTILE → AMPLIFIED
  # ────────────────────────────────────────────────────────────────────────────
  wagner_origin = Article.where("headline ILIKE ?", "%Wagner%Sahel%").first ||
                  Article.where("headline ILIKE ?", "%Wagner%Africa%").first ||
                  Article.where(source_name: "Le Monde").first
  if wagner_origin
    hops = [
      make_hop.("Le Monde",        :paris,      "original",    0.89, 0,  t - 3.days, headline: "Wagner Africa Corps doubles Sahel presence to 3,400 — gold and lithium mines fund expansion"),
      make_hop.("Sputnik",         :moscow,     "distorted",   0.62, 12, t - 3.days, headline: "Africa Corps defends Sahel partners from French neo-colonial destabilisation operations"),
      make_hop.("Africa News",     :bamako,     "amplified",   0.71, 24, t - 3.days, headline: "Mali government hails Russian security partnership — 300% civilian death toll surge omitted"),
      make_hop.("Nation Africa",   :nairobi,    "neutralized", 0.74, 38, t - 3.days, headline: "African Union: Sahel nations have sovereign right to choose security partners"),
      make_hop.("Xinhua",          :beijing,    "distorted",   0.67, 52, t - 3.days, headline: "China: Sahel nations resist Western interference in legitimate security arrangements"),
      make_hop.("Associated Press",:washington, "amplified",   0.83, 68, t - 3.days, headline: "US-France warn Wagner Africa Corps now controls $250M annually in illicit mining"),
    ]
    r = create_route.(wagner_origin, hops,
      "Africa Corps Shadow",
      "Sahel security vacuum fractures across 6 global perspectives — Western alarm vs African sovereignty narrative war plays out in real time",
      "#22c55e")
    routes_created += 1 if r
    puts "  ✓ Route 5: Wagner Sahel — 6 hops, Paris → Washington (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 6 — Red Sea Shipping Disruption: "Houthi Chokehold"
  # Dubai → Tehran → London → Frankfurt → New York → Tokyo
  # Labels: ORIGINAL → HOSTILE → AMPLIFIED → AMPLIFIED → AMPLIFIED → CONCERNING
  # ────────────────────────────────────────────────────────────────────────────
  red_sea_origin = Article.where("headline ILIKE ?", "%Red Sea%").first ||
                   Article.where("headline ILIKE ?", "%Houthi%tanker%").first
  if red_sea_origin
    hops = [
      make_hop.("Reuters",         :dubai,      "original",    0.94, 0,  t - 2.days, headline: "Houthi missile strikes Greek tanker Sounion — 25 crew evacuated, oil spill expanding"),
      make_hop.("Press TV",        :tehran,     "distorted",   0.60, 8,  t - 2.days, headline: "Yemen's resistance strikes Zionist-linked vessel — legitimate act of Palestinian solidarity"),
      make_hop.("Bloomberg",       :london,     "amplified",   0.91, 18, t - 2.days, headline: "Red Sea crisis pushes European inflation to 18-month high — Maersk halts all transits"),
      make_hop.("Deutsche Welle",  :berlin,     "amplified",   0.85, 28, t - 2.days, headline: "ECB warns shipping disruption forces inflation add of 0.5% — rate cut delayed indefinitely"),
      make_hop.("Associated Press",:new_york,   "neutralized", 0.88, 40, t - 2.days, headline: "US Navy unable to intercept Houthi ballistic missile — capability gap now publicly exposed"),
      make_hop.("NHK World",       :tokyo,      "distorted",   0.73, 54, t - 2.days, headline: "Japan's LNG supply chain threatened as Red Sea closure reroutes 40% of Asian energy transit"),
    ]
    r = create_route.(red_sea_origin, hops,
      "Houthi Chokehold",
      "Red Sea shipping crisis amplified through 6 media ecosystems — commercial disruption weaponised into geopolitical flashpoint narrative",
      "#f97316")
    routes_created += 1 if r
    puts "  ✓ Route 6: Red Sea — 6 hops, Dubai → Tokyo (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 7 — US Election Narrative War: "Deepfake Cascade"
  # Washington → Moscow → New York → London → Berlin → Doha
  # Labels: ORIGINAL → HOSTILE → AMPLIFIED → AMPLIFIED → AMPLIFIED → CONCERNING
  # ────────────────────────────────────────────────────────────────────────────
  election_origin = Article.where("headline ILIKE ?", "%deepfake%election%").first ||
                    Article.where("headline ILIKE ?", "%Russia%troll%election%").first
  if election_origin
    hops = [
      make_hop.("CNN",            :washington, "original",    0.83, 0,  t - 1.day, headline: "FBI opens investigation into military-grade deepfake campaign across 12 swing states"),
      make_hop.("RT",             :moscow,     "distorted",   0.52, 10, t - 1.day, headline: "US blames Russia for deepfakes it manufactured itself — classic false flag for censorship"),
      make_hop.("Fox News",       :new_york,   "amplified",   0.71, 18, t - 1.day, headline: "Democrat election integrity crisis: deepfake scandal exposes regime narrative machine"),
      make_hop.("BBC",            :london,     "amplified",   0.86, 28, t - 1.day, headline: "AI deepfake election attack worst in democratic history — entire information ecosystem at risk"),
      make_hop.("Deutsche Welle", :berlin,     "amplified",   0.80, 40, t - 1.day, headline: "EU demands emergency AI regulation summit after US deepfake election interference revelation"),
      make_hop.("Al Jazeera",     :doha,       "distorted",   0.68, 54, t - 1.day, headline: "America's information collapse: no shared reality exists as election approaches"),
    ]
    r = create_route.(election_origin, hops,
      "Deepfake Cascade",
      "AI election interference narrative fractures into 6 incompatible realities — tracking disinformation as it crosses the Atlantic and back",
      "#ec4899")
    routes_created += 1 if r
    puts "  ✓ Route 7: Election Narrative — 6 hops, Washington → Doha (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # ROUTE 8 — BRICS Currency Challenge: "Dollar Siege"
  # Doha → Moscow → Beijing → New Delhi → Brasilia → New York
  # Labels: ORIGINAL → HOSTILE → HOSTILE → AMPLIFIED → AMPLIFIED → AMPLIFIED
  # ────────────────────────────────────────────────────────────────────────────
  brics_origin = Article.where("headline ILIKE ?", "%BRICS%digital%").first ||
                 Article.where("headline ILIKE ?", "%BRICS%dollar%").first ||
                 Article.where("headline ILIKE ?", "%BRICS%currency%").first
  if brics_origin
    hops = [
      make_hop.("Al Jazeera",     :doha,       "original",    0.78, 0,  t - 30.hours, headline: "BRICS Bridge digital settlement system announced — blockchain to bypass US dollar"),
      make_hop.("Sputnik",        :moscow,     "distorted",   0.58, 12, t - 30.hours, headline: "Putin: BRICS Bridge is beginning of end for dollar tyranny — new financial world order born"),
      make_hop.("Xinhua",         :beijing,    "distorted",   0.61, 24, t - 30.hours, headline: "China hails multipolar financial architecture — Western sanctions regime faces existential threat"),
      make_hop.("Times of India", :new_delhi,  "amplified",   0.74, 38, t - 30.hours, headline: "India walks tightrope — BRICS Bridge offers rupee independence without severing US ties"),
      make_hop.("Reuters",        :brasilia,   "neutralized", 0.80, 52, t - 30.hours, headline: "Brazil cautious on BRICS ambitions — Goldman says system handles less than 2% of trade by 2030"),
      make_hop.("Bloomberg",      :new_york,   "amplified",   0.91, 68, t - 30.hours, headline: "Dollar surges as markets shrug off BRICS threat — reserve currency status unassailable for decades"),
    ]
    r = create_route.(brics_origin, hops,
      "Dollar Siege",
      "BRICS currency challenge tracked across 6 financial capitals — East vs West framing diverges from declaration to market verdict",
      "#38bdf8")
    routes_created += 1 if r
    puts "  ✓ Route 8: BRICS Currency — 6 hops, Doha → New York (#{r ? 'OK' : 'SKIP'})"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # FALLBACK: guarantee every remaining article gets journey data
  # ────────────────────────────────────────────────────────────────────────────
  articles_without_routes = Article
    .includes(:narrative_arcs, :ai_analysis, :country)
    .select { |a| a.best_journey_data.nil? }

  puts "  #{articles_without_routes.size} articles still need fallback routes..."

  framing_seq = %w[original amplified amplified distorted distorted distorted]
  arc_colors  = %w[#00f0ff #f59e0b #ff3a5e #22c55e #a78bfa #38bdf8]

  articles_without_routes
    .group_by { |a| a.ai_analysis&.analyst_response&.dig("geopolitical_topic") || "General" }
    .each do |topic, group|
      group.sort_by { |a| a.published_at || Time.at(0) }.each_slice(5) do |slice|
        next if slice.size < 2
        origin = slice.first
        hops = slice.map.with_index do |article, idx|
          {
            "article_id"          => article.id,
            "source_name"         => article.source_name,
            "source_country"      => article.country&.name || "Unknown",
            "source_city"         => article.country&.name || "Unknown",
            "lat"                 => (article.latitude  || rand(-40.0..60.0)).round(4),
            "lng"                 => (article.longitude || rand(-140.0..140.0)).round(4),
            "published_at"        => (article.published_at || Time.current - (slice.size - idx).hours).iso8601,
            "framing_shift"       => framing_seq[idx % framing_seq.size],
            "confidence_score"    => (0.62 + idx * 0.06).clamp(0.0, 1.0).round(3),
            "delay_from_previous" => idx.zero? ? 0 : rand(7200..72_000),
          }
        end
        arc = NarrativeArc.create!(
          article_id:     origin.id,
          origin_country: origin.country&.name || "Unknown",
          origin_lat:     hops.first["lat"],
          origin_lng:     hops.first["lng"],
          target_country: slice.last.country&.name || "Unknown",
          target_lat:     hops.last["lat"],
          target_lng:     hops.last["lng"],
          arc_color:      arc_colors.sample,
        )
        NarrativeRoute.create!(
          narrative_arc_id: arc.id,
          name:             "#{topic} Narrative Route",
          description:      "Fallback route — #{slice.size} outlets covering #{topic}",
          hops:             hops,
          is_complete:      true,
          status:           "tracking",
        )
        routes_created += 1
      end
    end

  puts "\n✓ #{routes_created} total routes created (8 cinematic + fallbacks)."
  puts "✓ #{Article.all.count { |a| a.best_journey_data.present? }} / #{Article.count} articles BLOOM/CHRONICLE ready."
end

create_perspective_filters!
create_users!
created_regions = create_regions_and_countries!
seed_articles!(created_regions)
seed_narrative_arcs!
seed_demo_routes!
seed_compounding_intelligence!

puts "\n==== FINAL COUNTS ===="
puts "#{Article.count} articles, #{AiAnalysis.count} analyses, #{NarrativeArc.count} arcs"
puts "#{Region.count} regions, #{Country.count} countries"
puts "#{Entity.count} entities, #{EntityMention.count} entity mentions"
puts "#{SourceCredibility.count} source profiles, #{NarrativeSignature.count} signatures"
puts "#{ContradictionLog.count} contradictions, #{IntelligenceBrief.count} briefs"
