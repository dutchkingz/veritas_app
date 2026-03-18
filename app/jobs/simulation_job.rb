class SimulationJob < ApplicationJob
  queue_as :default

  def perform
    # Simulate a new article every few seconds
    loop do
      create_simulated_article
      sleep rand(5..15)
    end
  end

  private

  def create_simulated_article
    region = Region.all.sample
    country = region.countries.sample || Country.all.sample
    
    article = Article.create!(
      headline: "SIMULATED: Narrative Shift detected in #{country.name}",
      content: "Auto-generated intelligence signal for dashboard testing. High volume of coordinate-linked data detected.",
      source_name: "VERITAS_SENTINEL",
      source_url: "https://veritas.local/signals",
      latitude: region.latitude + rand(-2.0..2.0),
      longitude: region.longitude + rand(-2.0..2.0),
      region: region,
      country: country,
      published_at: Time.current,
      source_type: :news_api
    )

    # Simulate an intelligence report
    IntelligenceReport.create!(
      region: region,
      status: "completed",
      verdict: IntelligenceReport::VALID_VERDICTS.sample,
      summary: "Simulated intelligence analysis for testing purposes.",
      analyzed_article_ids: [article.id],
      signal_stats: {
        avg_trust: rand(0.4..0.9).round(2),
        anomaly_count: rand(1..10),
        high_count: rand(1..5),
        source_diversity: rand(2..8)
      }
    )
  end
end
