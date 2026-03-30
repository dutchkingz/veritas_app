# GdeltEventIngestionService
# Queries the GDELT Events table (gdelt-bq.gdeltv2.events_partitioned) for conflict events
# and persists them as GdeltEvent records, linked to Articles where possible.
#
# The Events table is distinct from GKG: it uses CAMEO event codes (Actor1 → Actor2
# action taxonomy) rather than themes/tone. Together they give a complete picture:
#   GKG  → what is being said, who is mentioned, sentiment
#   Events → what is happening, who is acting against whom, intensity
#
# High-water mark: GLOBALEVENTID (monotonically increasing integer).
# We store the max GLOBALEVENTID seen and use it in the WHERE clause.
# NOTE: BigQuery still scans the full 24h partition (GLOBALEVENTID > X is not
# partition-pruning) — the HWM prevents INSERT duplicates, not scan cost.
#
# Estimated scan size per call (24h partition, selected columns):
#   ~500 MB - 1.5 GB depending on GDELT daily event volume
#   This may trigger the COST WARNING threshold in GdeltBigQueryService — that is
#   expected and acceptable for this query. The 5 GB hard limit remains the backstop.

class GdeltEventIngestionService
  # GDELT v2 events use a single ingestion-time partitioned table.
  # _PARTITIONTIME is the correct cost-safe filter (same pattern as GKG).
  GDELT_EVENTS_TABLE = "gdelt-bq.gdeltv2.events_partitioned".freeze
  RESULTS_LIMIT      = 500

  # Filter: only ingest high-signal conflict events.
  # QuadClass 3 = Verbal Conflict, 4 = Material Conflict
  # GoldsteinScale < -5 catches significant destabilizing events regardless of QuadClass
  # NumSources >= 3 filters noise (single-source reports are unreliable)
  CONFLICT_QUAD_CLASSES = [3, 4].freeze
  GOLDSTEIN_THRESHOLD   = -5.0
  MIN_SOURCES           = 3

  def initialize
    @bq = GdeltBigQueryService.new
  end

  def fetch_and_process
    hwm = last_event_id
    Rails.logger.info "[GdeltEventIngestionService] Starting Events fetch " \
                      "(HWM globaleventid: #{hwm || 'none'}, limit: #{RESULTS_LIMIT})"

    sql = build_query(high_water_mark: hwm)
    validate_sql_safety!(sql)

    rows = @bq.execute_query(sql)
    Rails.logger.info "[GdeltEventIngestionService] Received #{rows.count} rows from BigQuery"

    created = 0
    skipped = 0

    rows.each do |row|
      event = save_event(row)
      if event
        created += 1
      else
        skipped += 1
      end
    rescue ActiveRecord::RecordNotUnique
      skipped += 1
    rescue => e
      Rails.logger.warn "[GdeltEventIngestionService] Skipped row (#{e.class}): #{e.message}"
      skipped += 1
    end

    Rails.logger.info "[GdeltEventIngestionService] ✅ Done — #{created} saved, #{skipped} skipped"
    created
  rescue GdeltBigQueryService::QueryError => e
    Rails.logger.error "[GdeltEventIngestionService] BigQuery query failed: #{e.message}"
    raise
  rescue => e
    Rails.logger.error "[GdeltEventIngestionService] Unexpected error: #{e.class}: #{e.message}"
    raise
  end

  private

  def validate_sql_safety!(sql)
    unless sql.include?("_PARTITIONTIME")
      raise GdeltBigQueryService::QueryError,
        "SAFETY BLOCK: Events query missing _PARTITIONTIME filter. This would scan the entire GDELT events dataset."
    end

    unless sql.match?(/LIMIT\s+\d+/i)
      raise GdeltBigQueryService::QueryError,
        "SAFETY BLOCK: Events query missing LIMIT clause."
    end
  end

  # Returns the maximum GLOBALEVENTID we have stored — used as HWM.
  # If nil, we fall back to a pure time-window query.
  def last_event_id
    GdeltEvent.maximum(:globaleventid)
  end

  def build_query(high_water_mark: nil)
    quad_list  = CONFLICT_QUAD_CLASSES.join(", ")
    hwm_clause = high_water_mark ? "AND GLOBALEVENTID > #{high_water_mark.to_i}" : ""

    <<~SQL
      SELECT
        GLOBALEVENTID,
        SQLDATE,
        Actor1Name,
        Actor1CountryCode,
        Actor1Type1Code,
        Actor2Name,
        Actor2CountryCode,
        Actor2Type1Code,
        EventCode,
        EventRootCode,
        QuadClass,
        GoldsteinScale,
        NumMentions,
        NumSources,
        NumArticles,
        AvgTone,
        Actor1Geo_Lat,
        Actor1Geo_Long,
        Actor2Geo_Lat,
        Actor2Geo_Long,
        ActionGeo_Lat,
        ActionGeo_Long,
        ActionGeo_CountryCode,
        ActionGeo_FullName,
        SOURCEURL
      FROM `#{GDELT_EVENTS_TABLE}`
      WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        AND (QuadClass IN (#{quad_list}) OR GoldsteinScale < #{GOLDSTEIN_THRESHOLD})
        AND NumSources >= #{MIN_SOURCES}
        #{hwm_clause}
      ORDER BY GLOBALEVENTID ASC
      LIMIT #{RESULTS_LIMIT}
    SQL
  end

  def save_event(row)
    globaleventid = row[:GLOBALEVENTID].to_i
    return nil if globaleventid.zero?

    source_url            = row[:SOURCEURL].to_s.strip.presence
    source_url_normalized = normalize_url(source_url)

    # Try to link to an existing Article by normalized URL.
    # GDELT URLs are messy — normalization strips scheme, www, trailing slashes,
    # and common tracking parameters so http vs https differences don't break matching.
    matched_article_id = if source_url_normalized
      Article.where(data_source: "gdelt")
             .find_by("lower(source_url) LIKE ?", "%#{source_url_normalized}%")
             &.id
    end

    event_date = parse_sqldate(row[:SQLDATE])

    GdeltEvent.create!(
      globaleventid:            globaleventid,
      sqldate:                  row[:SQLDATE].to_i,
      event_date:               event_date,
      actor1_name:              row[:Actor1Name].to_s.presence,
      actor1_country_code:      row[:Actor1CountryCode].to_s.presence,
      actor1_type1_code:        row[:Actor1Type1Code].to_s.presence,
      actor2_name:              row[:Actor2Name].to_s.presence,
      actor2_country_code:      row[:Actor2CountryCode].to_s.presence,
      actor2_type1_code:        row[:Actor2Type1Code].to_s.presence,
      event_code:               row[:EventCode].to_s.presence,
      event_root_code:          row[:EventRootCode].to_s.presence,
      quad_class:               row[:QuadClass].to_i.presence,
      goldstein_scale:          row[:GoldsteinScale]&.to_f,
      num_mentions:             row[:NumMentions].to_i,
      num_sources:              row[:NumSources].to_i,
      num_articles:             row[:NumArticles].to_i,
      avg_tone:                 row[:AvgTone]&.to_f,
      action_geo_lat:           safe_coord(row[:ActionGeo_Lat], -90.0, 90.0),
      action_geo_long:          safe_coord(row[:ActionGeo_Long], -180.0, 180.0),
      action_geo_country_code:  row[:ActionGeo_CountryCode].to_s.presence,
      action_geo_full_name:     row[:ActionGeo_FullName].to_s.presence,
      source_url:               source_url,
      source_url_normalized:    source_url_normalized,
      article_id:               matched_article_id,
      raw_data: {
        "actor1_geo_lat"  => safe_coord(row[:Actor1Geo_Lat], -90.0, 90.0),
        "actor1_geo_long" => safe_coord(row[:Actor1Geo_Long], -180.0, 180.0),
        "actor2_geo_lat"  => safe_coord(row[:Actor2Geo_Lat], -90.0, 90.0),
        "actor2_geo_long" => safe_coord(row[:Actor2Geo_Long], -180.0, 180.0)
      }.compact
    )
  end

  # Normalize a URL for matching:
  #   1. Lowercase
  #   2. Strip scheme (http/https)
  #   3. Strip www. prefix
  #   4. Strip common tracking/UTM parameters
  #   5. Strip trailing slashes and fragments
  # Returns nil if the URL is blank or unparseable.
  def normalize_url(url)
    return nil if url.blank?

    uri = URI.parse(url.strip.downcase)
    host = uri.host.to_s.sub(/\Awww\./, "")
    path = uri.path.to_s.gsub(/\/+$/, "")

    if uri.query.present?
      tracking_prefixes = %w[utm_ ref source fbclid gclid msclkid]
      pairs = URI.decode_www_form(uri.query).reject do |k, _|
        tracking_prefixes.any? { |p| k.downcase.start_with?(p) }
      end
      query = pairs.empty? ? nil : URI.encode_www_form(pairs)
      "#{host}#{path}#{"?#{query}" if query}"
    else
      "#{host}#{path}"
    end
  rescue URI::InvalidURIError
    # Fallback: strip scheme and query string manually
    url.downcase.strip
       .gsub(%r{\Ahttps?://(?:www\.)?}, "")
       .gsub(/\?.*\z/, "")
       .gsub(/\/+\z/, "")
  end

  # Parse GDELT SQLDATE (YYYYMMDD integer) to a Ruby Date.
  def parse_sqldate(raw)
    return nil if raw.blank?
    Date.parse(raw.to_s)
  rescue Date::Error
    nil
  end

  # Validate a coordinate is within bounds; return nil for sentinel 0.0 values
  # and out-of-range values (GDELT uses 0.0 for missing geo data).
  def safe_coord(raw, min, max)
    return nil if raw.blank?
    v = raw.to_f
    return nil if v.zero?
    return nil unless v.between?(min, max)
    v
  end
end
