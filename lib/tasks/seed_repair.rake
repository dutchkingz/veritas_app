namespace :veritas do
  desc "Repair legacy fallback demo articles that still point to demo.veritas.local"
  task repair_fallback_articles: :environment do
    relation = Article.where("source_url LIKE ?", "https://#{Article::DEMO_SOURCE_HOST}/%")
    repaired = 0

    relation.find_each do |article|
      body = article.content.presence || <<~HTML
        <p>DEMO INTELLIGENCE SIGNAL</p>
        <p>#{ERB::Util.html_escape(article.headline)}</p>
        <p>
          This fallback article was repaired after legacy seed data pointed to a non-existent
          demo source host. It remains available as a local demo narrative signal.
        </p>
      HTML

      raw_data = article.raw_data.is_a?(Hash) ? article.raw_data.deep_dup : {}
      raw_data["seed_mode"] ||= "fallback_demo"
      raw_data["source"] ||= article.source_name
      raw_data["description"] ||= article.headline

      article.update!(
        source_url: nil,
        content: body,
        raw_data: raw_data
      )
      repaired += 1
    end

    puts "Repaired #{repaired} fallback demo articles."
  end
end
