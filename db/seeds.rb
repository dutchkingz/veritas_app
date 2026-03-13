require 'net/http'
require 'json'

puts "Cleaning up database..."
Briefing.destroy_all
PerspectiveFilter.destroy_all

puts "Seeding Perspective Filters..."
[
  { name: 'US Liberal Media',       filter_type: 'source',
    keywords: 'CNN,MSNBC,NPR,New York Times,Washington Post,The Guardian,Vox,HuffPost,The Atlantic,Politico,The New Yorker' },
  { name: 'US Conservative Media',  filter_type: 'source',
    keywords: 'Fox News,Breitbart,The Daily Wire,New York Post,Washington Times,Newsmax,The Federalist,Daily Caller,Epoch Times' },
  { name: 'China State Media',       filter_type: 'source',
    keywords: 'Xinhua,Global Times,CCTV,China Daily,People\'s Daily,South China Morning Post,China News Service,CGTN' },
  { name: 'Russia State Media',      filter_type: 'source',
    keywords: 'RT,TASS,Sputnik,RIA Novosti,Pravda,Rossiyskaya Gazeta,ITAR-TASS,Russia Today,Izvestia' },
  { name: 'Western Mainstream',      filter_type: 'source',
    keywords: 'Reuters,Associated Press,BBC,AFP,AP News,Financial Times,The Economist,Bloomberg,Der Spiegel,Le Monde' },
  { name: 'Global South',            filter_type: 'source',
    keywords: 'Al Jazeera,Dawn,The Hindu,Folha de S.Paulo,Nation Africa,Daily Nation,Mail & Guardian,Arab News,Middle East Eye,Telesur' }
].each { |attrs| PerspectiveFilter.create!(attrs) }
puts "Created #{PerspectiveFilter.count} perspective filters."
NarrativeConvergence.destroy_all
NarrativeArc.destroy_all
AiAnalysis.destroy_all
Article.destroy_all
Country.destroy_all
IntelligenceReport.destroy_all
Region.destroy_all
User.destroy_all

puts "Creating Admin User..."
User.create!(
  email: 'admin@veritas.de',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'admin'
)

puts "Creating Developer Users..."
%w[vince@vince.au oli@oli.com selim@selim.com].each do |email|
  User.create!(
    email: email,
    password: email,
    password_confirmation: email,
    role: 'user' # or whatever their role should be
  )
end
puts "Developers vince, oli, and selim have been successfully created!"

puts "Creating Dummy Regions and Countries..."
regions = [
  { name: 'North America', country: 'United States', lat: 37.0902, lng: -95.7129, threat: 1 },
  { name: 'Eastern Europe', country: 'Ukraine', lat: 48.3794, lng: 31.1656, threat: 3 },
  { name: 'East Asia', country: 'China', lat: 35.8617, lng: 104.1954, threat: 2 },
  { name: 'Middle East', country: 'Israel', lat: 31.0461, lng: 34.8516, threat: 3 },
  { name: 'Western Europe', country: 'Germany', lat: 51.1657, lng: 10.4515, threat: 1 }
]

created_regions = {}
regions.each do |r|
  reg = Region.create!(
    name: r[:name],
    latitude: r[:lat],
    longitude: r[:lng],
    threat_level: r[:threat],
    article_volume: 0,
    last_calculated_at: Time.now
  )
  country = Country.create!(
    region: reg,
    name: r[:country],
    iso_code: r[:country][0..2].upcase
  )
  created_regions[r[:name]] = { region: reg, country: country }
end

puts "Fetching articles from NewsAPI..."
API_KEY = ENV['NEWS_API_KEY'] || 'demo'

begin
  response = Net::HTTP.get(URI("https://newsapi.org/v2/everything?q=geopolitics&language=en&pageSize=100&apiKey=#{ENV['NEWS_API_KEY'] || 'YOUR_API_KEY'}"))
  data = JSON.parse(response)

  if data['status'] == 'ok'
    articles_data = data['articles']
    puts "Successfully fetched #{articles_data.count} articles from NewsAPI."

    articles_data.each do |item|
      random_region_key = created_regions.keys.sample
      region_data = created_regions[random_region_key]

      Article.create!(
        headline: item['title'],
        source_url: item['url'],
        source_name: item['source'] ? item['source']['name'] : 'Unknown',
        published_at: item['publishedAt'],
        fetched_at: Time.now,
        latitude: region_data[:region].latitude + rand(-2.0..2.0),
        longitude: region_data[:region].longitude + rand(-2.0..2.0),
        country: region_data[:country],
        region: region_data[:region],
        target_country: 1,
        raw_data: item
      )
    end

    puts "Seed complete! #{Article.count} articles created."
  else
    puts "Failed to fetch from NewsAPI: #{data['message']}"
    puts "Please set your NEWS_API_KEY horizontally: NEWS_API_KEY=your_key rails db:seed"
  end
rescue => e
  puts "Error during fetch: #{e.message}"
end

# -------------------------------------------------------
# NarrativeArc demo data for the 3D globe
# -------------------------------------------------------
puts "Seeding Narrative Arcs for globe visualisation..."

arc_routes = [
  # US ↔ geopolitical targets
  { origin_country: 'United States', origin_lat: 38.9072, origin_lng: -77.0369,
    target_country: 'Ukraine',       target_lat: 50.4501, target_lng: 30.5234, arc_color: '#ff2d55' },
  { origin_country: 'United States', origin_lat: 38.9072, origin_lng: -77.0369,
    target_country: 'China',         target_lat: 39.9042, target_lng: 116.4074, arc_color: '#ff9f0a' },
  { origin_country: 'United States', origin_lat: 38.9072, origin_lng: -77.0369,
    target_country: 'Israel',        target_lat: 31.7683, target_lng: 35.2137, arc_color: '#ff2d55' },
  { origin_country: 'United States', origin_lat: 38.9072, origin_lng: -77.0369,
    target_country: 'Taiwan',        target_lat: 25.0330, target_lng: 121.5654, arc_color: '#ff9f0a' },

  # Russia → targets
  { origin_country: 'Russia',  origin_lat: 55.7558, origin_lng: 37.6173,
    target_country: 'Ukraine', target_lat: 50.4501, target_lng: 30.5234, arc_color: '#ff2d55' },
  { origin_country: 'Russia',  origin_lat: 55.7558, origin_lng: 37.6173,
    target_country: 'Germany', target_lat: 52.5200, target_lng: 13.4050, arc_color: '#ff9f0a' },
  { origin_country: 'Russia',  origin_lat: 55.7558, origin_lng: 37.6173,
    target_country: 'United States', target_lat: 38.9072, target_lng: -77.0369, arc_color: '#ff2d55' },

  # China → targets
  { origin_country: 'China',  origin_lat: 39.9042, origin_lng: 116.4074,
    target_country: 'Taiwan', target_lat: 25.0330, target_lng: 121.5654, arc_color: '#ff2d55' },
  { origin_country: 'China',  origin_lat: 39.9042, origin_lng: 116.4074,
    target_country: 'Australia', target_lat: -35.2809, target_lng: 149.1300, arc_color: '#ff9f0a' },
  { origin_country: 'China',  origin_lat: 39.9042, origin_lng: 116.4074,
    target_country: 'India',  target_lat: 28.6139, target_lng: 77.2090, arc_color: '#30d158' },

  # Middle East routes
  { origin_country: 'Iran',   origin_lat: 35.6892, origin_lng: 51.3890,
    target_country: 'Israel', target_lat: 31.7683, target_lng: 35.2137, arc_color: '#ff2d55' },
  { origin_country: 'Saudi Arabia', origin_lat: 24.7136, origin_lng: 46.6753,
    target_country: 'Iran',         target_lat: 35.6892, target_lng: 51.3890, arc_color: '#ff9f0a' },

  # Europe internal
  { origin_country: 'United Kingdom', origin_lat: 51.5074, origin_lng: -0.1278,
    target_country: 'Germany',        target_lat: 52.5200, target_lng: 13.4050, arc_color: '#30d158' },
  { origin_country: 'France', origin_lat: 48.8566, origin_lng: 2.3522,
    target_country: 'Russia', target_lat: 55.7558, target_lng: 37.6173, arc_color: '#ff9f0a' },

  # Cross-continental
  { origin_country: 'Brazil', origin_lat: -15.7975, origin_lng: -47.8919,
    target_country: 'China',  target_lat: 39.9042, target_lng: 116.4074, arc_color: '#30d158' },
  { origin_country: 'India',  origin_lat: 28.6139, origin_lng: 77.2090,
    target_country: 'United States', target_lat: 38.9072, target_lng: -77.0369, arc_color: '#30d158' },
  { origin_country: 'Nigeria', origin_lat: 9.0579,  origin_lng: 7.4951,
    target_country: 'United Kingdom', target_lat: 51.5074, target_lng: -0.1278, arc_color: '#ff9f0a' },
  { origin_country: 'Japan',  origin_lat: 35.6762, origin_lng: 139.6503,
    target_country: 'China',  target_lat: 39.9042, target_lng: 116.4074, arc_color: '#ff9f0a' },
]

article_ids = Article.pluck(:id)

if article_ids.any?
  arc_routes.each do |route|
    NarrativeArc.create!(route.merge(article_id: article_ids.sample))
  end
  puts "Created #{NarrativeArc.count} narrative arcs."
else
  puts "⚠  No articles found — skipping NarrativeArc seeding."
end
