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

  # GDELT V2Locations type codes → human-readable names
  LOCATION_TYPES = {
    "1" => "country",
    "2" => "us_state",
    "3" => "us_city",
    "4" => "world_city",
    "5" => "world_state"
  }.freeze

  # Country centroid fallback for GDELT articles with valid country codes but
  # broken/missing coordinates. GDELT uses FIPS 10-4 country codes.
  # rubocop:disable Layout/HashAlignment
  COUNTRY_CENTROIDS = {
    "US" => [39.83, -98.58],   "CA" => [56.13, -106.35],  "UK" => [55.38, -3.44],
    "FR" => [46.23, 2.21],     "GM" => [51.17, 10.45],    "IT" => [41.87, 12.57],
    "SP" => [40.46, -3.75],    "PL" => [51.92, 19.15],    "UP" => [48.38, 31.17],
    "RS" => [61.52, 105.32],   "CH" => [35.86, 104.20],   "JA" => [36.20, 138.25],
    "KS" => [35.91, 127.77],   "TW" => [23.70, 120.96],   "IN" => [20.59, 78.96],
    "PK" => [30.38, 69.35],    "IR" => [32.43, 53.69],    "IS" => [31.05, 34.85],
    "TU" => [38.96, 35.24],    "SA" => [23.89, 45.08],    "IZ" => [33.22, 43.68],
    "SY" => [34.80, 38.99],    "AF" => [33.94, 67.71],    "EG" => [26.82, 30.80],
    "NI" => [9.08, 8.68],      "SF" => [-30.56, 22.94],   "KE" => [-0.02, 37.91],
    "BR" => [-14.24, -51.93],   "AS" => [-25.27, 133.78], "MX" => [23.63, -102.55],
  }.freeze
  # rubocop:enable Layout/HashAlignment

  ParsedRow = Struct.new(
    :url, :source_name, :themes, :themes_categorized, :country, :latitude, :longitude,
    :location_name, :all_locations, :tone, :language, :published_at,
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
  # Returns nil if the row lacks a usable URL or valid coordinates.
  def parse_row(row)
    url = row[:DocumentIdentifier].to_s.strip
    return nil if url.blank? || !url.start_with?("http")

    source_name          = row[:SourceCommonName].to_s.presence || "GDELT"
    raw_themes           = parse_themes(row[:V2Themes])
    themes_categorized   = categorize_themes(raw_themes)
    location             = parse_first_location(row[:V2Locations])
    # Skip articles with no valid geospatial coordinates — we need location data
    return nil if location[:latitude].nil? || location[:longitude].nil?

    all_locations        = parse_all_locations(row[:V2Locations])
    tone                 = parse_tone(row[:V2Tone])
    language             = parse_language(row[:TranslationInfo])
    published_at         = parse_date(row[:DATE])

    ParsedRow.new(
      url:                url,
      source_name:        source_name,
      themes:             raw_themes,
      themes_categorized: themes_categorized,
      country:            location[:country],
      latitude:           location[:latitude],
      longitude:          location[:longitude],
      location_name:      location[:name],
      all_locations:      all_locations,
      tone:               tone,
      language:           language,
      published_at:       published_at
    )
  end

  # V2Themes: semicolon-delimited. e.g. "MILITARY;DIPLOMACY;GCAM_SML_POLARITY_NEGATIVE"
  def parse_themes(raw)
    raw.to_s.split(";").map(&:strip).reject(&:blank?)
  end

  # Categorize raw themes into geopolitical, gcam, and other buckets.
  # geopolitical: matches our GEOPOLITICAL_THEMES filter list
  # gcam:         GCAM sentiment/cognitive analysis codes (prefix GCAM_)
  # other:        all remaining topic/taxonomy themes
  def categorize_themes(raw_themes)
    geopolitical = []
    gcam         = []
    other        = []

    raw_themes.each do |theme|
      if GEOPOLITICAL_THEMES.any? { |g| theme.start_with?(g) }
        geopolitical << theme
      elsif theme.start_with?("GCAM_")
        gcam << theme
      else
        other << theme
      end
    end

    result = {}
    result["geopolitical"] = geopolitical unless geopolitical.empty?
    result["gcam"]         = gcam         unless gcam.empty?
    result["other"]        = other        unless other.empty?
    result
  end

  # V2Locations: semicolon-delimited blocks, each #-delimited.
  # Format: Type#FullName#CountryCode#ADM1Code#Latitude#Longitude#FeatureID
  # Returns the first entry with valid geographic coordinates (used as primary lat/lon).
  #
  # IMPORTANT: The FeatureID field can be a large integer (e.g. "65104") that
  # looks like a float but is NOT a coordinate. We MUST validate that parsed
  # lat is within [-90, 90] and lon is within [-180, 180].
  def parse_first_location(raw)
    default = { country: nil, latitude: nil, longitude: nil, name: nil }
    return default if raw.blank?

    # Track the first valid country code seen — used as centroid fallback
    # when all coordinate fields are broken/missing.
    fallback_country = nil
    fallback_name    = nil

    raw.to_s.split(";").each do |block|
      parts = block.split("#")
      # Expect at least 6 parts: type, name, countryCode, ADM1, lat, lon
      next unless parts.size >= 6

      # Capture country code for fallback even if coordinates are bad
      if fallback_country.nil? && parts[2].presence
        fallback_country = parts[2]
        fallback_name    = parts[1].presence
      end

      lat_str = parts[4].to_s.strip
      lon_str = parts[5].to_s.strip
      next if lat_str.blank? || lon_str.blank?

      lat = lat_str.to_f
      lon = lon_str.to_f

      next unless lat.between?(-90.0, 90.0) && lon.between?(-180.0, 180.0)
      next if lat.zero? || lon.zero? # exact 0.0 = empty/missing GDELT field parsed as float

      return {
        country:   parts[2].presence,
        latitude:  lat,
        longitude: lon,
        name:      parts[1].presence
      }
    end

    # No valid coordinates found — fall back to country centroid so the
    # article still appears on the globe at approximate location.
    if fallback_country && (centroid = COUNTRY_CENTROIDS[fallback_country])
      Rails.logger.info "[GdeltIngestionService] Using country centroid for #{fallback_country} (#{fallback_name})"
      return {
        country:   fallback_country,
        latitude:  centroid[0],
        longitude: centroid[1],
        name:      fallback_name
      }
    end

    default
  end

  # Parse ALL valid locations from V2Locations into a structured array for raw_data.
  # Unlike parse_first_location, this collects every entry with valid bounds —
  # useful for multi-theatre stories (e.g. Iran + Israel + US all in one article).
  # Entries with coordinates of exactly (0,0) are skipped (GDELT missing-data sentinel).
  def parse_all_locations(raw)
    return [] if raw.blank?

    raw.to_s.split(";").filter_map do |block|
      parts = block.split("#")
      next unless parts.size >= 6

      lat = parts[4].to_s.strip.to_f
      lon = parts[5].to_s.strip.to_f
      next unless lat.between?(-90.0, 90.0) && lon.between?(-180.0, 180.0)
      next if lat.zero? && lon.zero?

      {
        "type"         => LOCATION_TYPES.fetch(parts[0].to_s, "unknown"),
        "name"         => parts[1].presence,
        "country_code" => parts[2].presence,
        "lat"          => lat,
        "lon"          => lon
      }.compact
    end
  end

  # V2Tone: 7 comma-delimited floats in this order:
  #   overall tone, positive score, negative score, polarity,
  #   activity reference density, self/group reference density, word count
  #
  # overall tone is normalized from GDELT's -10..+10 range to our -1..+1 scale
  # to match the convention used elsewhere in the platform.
  # The other sub-scores are stored as-is (their ranges vary; callers should
  # treat them as relative indicators, not absolute values).
  def parse_tone(raw)
    return nil if raw.blank?

    parts = raw.to_s.split(",")
    return nil if parts.empty?

    {
      "overall"               => (parts[0].to_f / 10.0).round(3).clamp(-1.0, 1.0),
      "positive"              => parts[1]&.to_f&.round(3),
      "negative"              => parts[2]&.to_f&.round(3),
      "polarity"              => parts[3]&.to_f&.round(3),
      "activity_ref_density"  => parts[4]&.to_f&.round(3),
      "self_group_ref_density" => parts[5]&.to_f&.round(3),
      "word_count"            => parts[6]&.to_i
    }.compact
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
        # Structured GDELT metadata — single source of truth for raw signal data.
        # AI-triad (sentiment_label etc.) remains the authoritative sentiment source.
        "source"             => "gdelt",
        "location_name"      => data.location_name,
        "gdelt_themes"       => data.themes,
        "gdelt_themes_by_category" => data.themes_categorized,
        "gdelt_locations"    => data.all_locations,
        "gdelt_tone"         => data.tone
      }.compact
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
