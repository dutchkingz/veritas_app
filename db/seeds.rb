require 'net/http'
require 'json'

puts "Cleaning up database..."
Briefing.destroy_all
PerspectiveFilter.destroy_all
NarrativeConvergence.destroy_all
NarrativeArc.destroy_all
AiAnalysis.destroy_all
Article.destroy_all
Country.destroy_all
Region.destroy_all
User.destroy_all

puts "Creating Admin User..."
User.create!(
  email: 'admin@veritas.com',
  password: 'password123',
  password_confirmation: 'password123',
  role: 'admin'
)

puts "Creating Developer Users..."
%w[vince@vince.com oli@oli.com selim@selim.com].each do |email|
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
