require "securerandom"

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
      puts "[db:seed] Skipping article #{attrs[:source_url]}: #{e.class} #{e.message}"
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
      puts "[db:seed] Failed fallback article #{attrs[:source_url]}: #{e.class} #{e.message}"
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
    "person" => %w[Volodymyr\ Zelensky Vladimir\ Putin Xi\ Jinping Joe\ Biden
                    Narendra\ Modi Emmanuel\ Macron Olaf\ Scholz Benjamin\ Netanyahu
                    Mohammad\ bin\ Salman Recep\ Tayyip\ Erdogan],
    "organization" => %w[NATO UN EU BRICS OPEC WHO IMF Wagner\ Group Hezbollah Hamas
                         CIA Mossad FSB IAEA G7 ASEAN African\ Union],
    "country" => %w[Ukraine Russia China Taiwan United\ States Iran Israel
                     Saudi\ Arabia North\ Korea India Pakistan Turkey Syria],
    "event" => ["Ukraine Conflict", "Gaza War", "Taiwan Strait Tensions",
                "BRICS Expansion", "US Election 2026", "Iran Nuclear Talks",
                "Red Sea Shipping Crisis", "Sahel Insurgency", "AI Arms Race",
                "Sanctions Escalation"]
  }

  entities = {}
  entity_pool.each do |entity_type, names|
    names.each do |name|
      entities[name] = Entity.create!(
        name: name,
        normalized_name: name.downcase.strip,
        entity_type: entity_type,
        first_seen_at: rand(72).hours.ago
      )
    end
  end

  # Link entities to articles via EntityMention
  all_entity_names = entities.keys
  Article.find_each do |article|
    headline = article.headline.to_s
    # Match entities that appear in headline or assign 2-4 random ones
    matched = all_entity_names.select { |name| headline.downcase.include?(name.downcase) }
    matched = all_entity_names.sample(rand(2..4)) if matched.empty?

    matched.each do |name|
      EntityMention.create!(entity: entities[name], article: article)
    rescue ActiveRecord::RecordInvalid
      next # skip duplicates
    end
  end
  puts "Created #{Entity.count} entities with #{EntityMention.count} mentions."

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
  contradiction_descriptions = [
    "Source A reports ceasefire agreement while Source B reports continued hostilities",
    "Casualty figures differ by order of magnitude between state and independent media",
    "Timeline of events contradicts between Eastern and Western outlets",
    "Attribution of attack claimed by multiple conflicting sources",
    "Economic impact assessment varies drastically across ideological lines",
    "Diplomatic stance reported as both conciliatory and aggressive by different outlets",
    "Troop movement reports contradict satellite imagery analysis",
    "Election interference claims sourced to opposing intelligence agencies"
  ]

  articles = Article.where.not(source_name: nil).to_a
  20.times do |i|
    a, b = articles.sample(2)
    next unless a && b && a.id != b.id

    ContradictionLog.create!(
      article_a_id: a.id,
      article_b_id: b.id,
      contradiction_type: %w[cross_source temporal_shift self_contradiction].sample,
      severity: rand(0.3..0.95).round(2),
      embedding_similarity: rand(0.4..0.85).round(4),
      source_a: a.source_name,
      source_b: b.source_name,
      description: contradiction_descriptions[i % contradiction_descriptions.size],
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
    executive_summary: "VERITAS has processed #{Article.count} articles across #{SourceCredibility.count} profiled sources in the past 24 hours. #{NarrativeSignature.count} active narrative patterns detected with #{ContradictionLog.count} cross-source contradictions flagged for analyst review. Elevated threat posture observed in Eastern Europe and Middle East corridors.",
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

create_perspective_filters!
create_users!
created_regions = create_regions_and_countries!
seed_articles!(created_regions)
seed_narrative_arcs!
seed_compounding_intelligence!

puts "\n==== FINAL COUNTS ===="
puts "#{Article.count} articles, #{AiAnalysis.count} analyses, #{NarrativeArc.count} arcs"
puts "#{Region.count} regions, #{Country.count} countries"
puts "#{Entity.count} entities, #{EntityMention.count} entity mentions"
puts "#{SourceCredibility.count} source profiles, #{NarrativeSignature.count} signatures"
puts "#{ContradictionLog.count} contradictions, #{IntelligenceBrief.count} briefs"
