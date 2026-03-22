# GdeltIngestionService
# Constructs BigQuery SQL, executes it via GdeltBigQueryService, parses results
# into Article objects, and feeds them into the existing analysis pipeline.
#
# GDELT GKG table: gdelt-bq.gdeltv2.gkg_partitioned
# Always filtered by _PARTITIONTIME to stay in the BigQuery free tier.

class GdeltIngestionService
  GDELT_TABLE    = "gdelt-bq.gdeltv2.gkg_partitioned".freeze
  RESULTS_LIMIT  = 200

  # GDELT GKG theme prefixes that indicate geopolitical relevance
  GEOPOLITICAL_THEMES = %w[
    MILITARY ARMED_CONFLICT DIPLOMACY SANCTIONS CYBER PROTEST
    TERROR ELECTION GOV_LEADER REBELLION CRISISLEX
  ].freeze

  ParsedRow = Struct.new(
    :url, :source_name, :themes, :country, :latitude, :longitude,
    :location_name, :sentiment, :language, :published_at,
    keyword_init: true
  )

  def initialize
    @bq = GdeltBigQueryService.new
    @relevance_filter = GeopoliticalRelevanceFilter.new
  end

  def fetch_and_process
    hwm = last_gdelt_published_at
    if hwm
      Rails.logger.info "[GdeltIngestionService] Starting GDELT fetch (high-water mark: #{hwm.iso8601}, limit #{RESULTS_LIMIT})"
    else
      Rails.logger.info "[GdeltIngestionService] Starting GDELT fetch (no prior articles — full 24h window, limit #{RESULTS_LIMIT})"
    end

    sql = build_query(high_water_mark: hwm)
    validate_sql_safety!(sql)

    rows   = @bq.execute_query(sql)
    parsed = rows.map { |row| parse_row(row) }.compact
    Rails.logger.info "[GdeltIngestionService] Parsed #{parsed.size}/#{rows.count} usable rows"

    created = 0
    skipped = 0

    parsed.each do |data|
      article = save_article(data)
      if article
        enqueue_pipeline(article)
        created += 1
      else
        skipped += 1
      end
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info "[GdeltIngestionService] Duplicate skipped (unique index): #{data.url}"
      skipped += 1
    rescue => e
      Rails.logger.warn "[GdeltIngestionService] Skipped row (#{e.class}): #{e.message}"
      skipped += 1
    end

    Rails.logger.info "[GdeltIngestionService] ✅ Done — #{created} saved, #{skipped} skipped"

    if created > 0
      ActionCable.server.broadcast("globe", {
        type:    "articles_fetched",
        count:   created,
        message: "#{created} new GDELT intelligence articles incoming"
      })
    end

    created
  rescue GdeltBigQueryService::QueryError => e
    Rails.logger.error "[GdeltIngestionService] BigQuery query failed: #{e.message}"
    raise
  rescue => e
    Rails.logger.error "[GdeltIngestionService] Unexpected error: #{e.class}: #{e.message}"
    raise
  end

  private

  # PARANOIA CHECK: validate that the SQL is safe before sending to BigQuery.
  # Even if build_query is correct today, a future refactor could accidentally
  # drop the partition filter and scan the entire GDELT dataset.
  def validate_sql_safety!(sql)
    unless sql.include?("_PARTITIONTIME")
      raise GdeltBigQueryService::QueryError,
        "SAFETY BLOCK: Query missing _PARTITIONTIME filter. This would scan the entire GDELT dataset."
    end

    unless sql.match?(/LIMIT\s+\d+/i)
      raise GdeltBigQueryService::QueryError,
        "SAFETY BLOCK: Query missing LIMIT clause."
    end
  end

  # Returns the published_at timestamp of the most recent GDELT article in our DB.
  # Used as a high-water mark to avoid re-fetching rows we already have.
  def last_gdelt_published_at
    Article.where(data_source: "gdelt").maximum(:published_at)
  end

  def build_query(high_water_mark: nil)
    theme_conditions = GEOPOLITICAL_THEMES.map do |theme|
      "REGEXP_CONTAINS(V2Themes, r'(?:^|;)#{theme}')"
    end.join(" OR ")

    # GDELT GKG DATE column is an INTEGER in YYYYMMDDHHMMSS format.
    # Convert our Ruby timestamp to the same format for comparison.
    hwm_clause = if high_water_mark
      gdelt_date_int = high_water_mark.strftime("%Y%m%d%H%M%S").to_i
      "AND DATE > #{gdelt_date_int}"
    else
      ""
    end

    <<~SQL
      SELECT
        DocumentIdentifier,
        SourceCommonName,
        V2Themes,
        V2Locations,
        V2Tone,
        DATE,
        TranslationInfo
      FROM `#{GDELT_TABLE}`
      WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        AND (#{theme_conditions})
        #{hwm_clause}
      LIMIT #{RESULTS_LIMIT}
    SQL
  end

  # Parse a GDELT GKG row into a structured ParsedRow.
  # Returns nil if the row lacks a usable URL.
  def parse_row(row)
    url = row[:DocumentIdentifier].to_s.strip
    return nil if url.blank? || !url.start_with?("http")

    source_name   = row[:SourceCommonName].to_s.presence || "GDELT"
    themes        = parse_themes(row[:V2Themes])
    location      = parse_first_location(row[:V2Locations])
    # Skip articles with no valid geospatial coordinates — we need location data
    return nil if location[:latitude].nil? || location[:longitude].nil?

    sentiment     = parse_sentiment(row[:V2Tone])
    language      = parse_language(row[:TranslationInfo])
    published_at  = parse_date(row[:DATE])

    ParsedRow.new(
      url:           url,
      source_name:   source_name,
      themes:        themes,
      country:       location[:country],
      latitude:      location[:latitude],
      longitude:     location[:longitude],
      location_name: location[:name],
      sentiment:     sentiment,
      language:      language,
      published_at:  published_at
    )
  end

  # V2Themes: semicolon-delimited. e.g. "MILITARY;DIPLOMACY;TAX_FNCACT"
  def parse_themes(raw)
    raw.to_s.split(";").map(&:strip).reject(&:blank?)
  end

  # V2Locations: semicolon-delimited blocks, each #-delimited.
  # Format: Type#FullName#CountryCode#ADM1Code#Latitude#Longitude#FeatureID
  # Returns the first entry with valid geographic coordinates.
  #
  # IMPORTANT: The FeatureID field can be a large integer (e.g. "65104") that
  # looks like a float but is NOT a coordinate. We MUST validate that parsed
  # lat is within [-90, 90] and lon is within [-180, 180].
  def parse_first_location(raw)
    default = { country: nil, latitude: nil, longitude: nil, name: nil }
    return default if raw.blank?

    raw.to_s.split(";").each do |block|
      parts = block.split("#")
      # Expect at least 6 parts: type, name, countryCode, ADM1, lat, lon
      next unless parts.size >= 6

      # Parts 4 and 5 should be lat/lon — validate they look like real coordinates
      lat_str = parts[4].to_s.strip
      lon_str = parts[5].to_s.strip
      next if lat_str.blank? || lon_str.blank?

      lat = lat_str.to_f
      lon = lon_str.to_f

      # Strict geographic bounds validation — if outside these ranges the parser
      # grabbed the wrong field (e.g. FeatureID) or the data is corrupt
      next unless lat.between?(-90.0, 90.0) && lon.between?(-180.0, 180.0)
      next if lat.zero? && lon.zero? # null island

      return {
        country:   parts[2].presence,
        latitude:  lat,
        longitude: lon,
        name:      parts[1].presence
      }
    end

    default
  end

  # V2Tone: comma-delimited floats. First value = overall tone (-10 to +10).
  # Normalize to -1..+1 for consistency with our schema.
  def parse_sentiment(raw)
    return nil if raw.blank?
    tone = raw.to_s.split(",").first.to_f
    (tone / 10.0).round(3).clamp(-1.0, 1.0)
  rescue
    nil
  end

  # TranslationInfo: "srclc:XX;..." — extract source language code.
  def parse_language(raw)
    return nil if raw.blank?
    match = raw.to_s.match(/srclc:([a-z]{2,5})/i)
    match ? match[1].downcase : nil
  end

  # DATE field is a BigQuery DATE — coerce to Time.
  def parse_date(raw)
    return nil if raw.blank?
    raw.respond_to?(:to_time) ? raw.to_time : Time.parse(raw.to_s)
  rescue
    nil
  end

  def save_article(data)
    # GeopoliticalRelevanceFilter: use GDELT themes as description since the real
    # headline is only available after FetchArticleContentJob scrapes the URL.
    theme_text = data.themes.join(", ")
    relevance = @relevance_filter.call(
      headline:    "#{data.source_name} — GDELT",
      description: theme_text
    )
    unless relevance[:relevant]
      Rails.logger.info "[GdeltIngestionService] 🚫 Filtered (#{relevance[:method]}): #{data.url}"
      return nil
    end

    Article.find_or_create_by(source_url: data.url) do |a|
      # Placeholder headline — FetchArticleContentJob overwrites this with the
      # scraped HTML <title>, which FramingAnalysisService relies on.
      a.headline          = "#{data.source_name} — GDELT"
      a.source_name       = data.source_name
      a.data_source       = "gdelt"
      a.original_language = data.language
      a.country           = nil   # belongs_to Country — resolved by geo pipeline
      a.latitude          = data.latitude
      a.longitude         = data.longitude
      a.published_at      = data.published_at
      a.fetched_at        = Time.current
      a.raw_data          = {
        gdelt_themes:   data.themes,
        location_name:  data.location_name,
        source:         "gdelt"
      }
    end.tap { |a| return nil unless a.previously_new_record? }
  end

  def enqueue_pipeline(article)
    # FetchArticleContentJob scrapes the URL → overwrites the placeholder headline
    # → queues AnalyzeArticleJob → queues GenerateEmbeddingJob.
    # This is the exact same pipeline as NewsAPI articles (see Article#enqueue_content_fetch
    # which is triggered by after_create_commit). No extra work needed here.
    #
    # Globe broadcast also fires automatically via Article#broadcast_to_globe.
    Rails.logger.info "[GdeltIngestionService] Pipeline triggered for ##{article.id}: #{article.headline}"
  end
end
