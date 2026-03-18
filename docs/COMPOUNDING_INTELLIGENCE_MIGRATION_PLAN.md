# VERITAS Compounding Intelligence — Model & Migration Plan

> Blueprint for making VERITAS self-aware. Each section defines a model, its schema, relationships, the service that drives it, and how it plugs into the existing pipeline.

---

## Migration Order

The migrations are ordered by dependency — each builds on the previous:

```
1. NarrativeSignature        (standalone, uses existing embeddings)
2. SourceCredibility          (standalone, uses existing source_name)
3. ContradictionLog           (depends on articles + embeddings)
4. IntelligenceBrief          (depends on all above)
5. ConfidenceScore concern    (no migration — adds methods to existing models)
6. EmbeddingDrift snapshots   (depends on existing embeddings)
```

---

## 1. NarrativeSignature

**Purpose:** Compressed vector fingerprints of recurring narrative patterns. When new articles arrive, compare against known signatures to detect recycled narratives vs. genuinely novel events.

### Migration

```ruby
# db/migrate/XXXX_create_narrative_signatures.rb
class CreateNarrativeSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :narrative_signatures do |t|
      t.string   :label,            null: false          # AI-generated label (e.g., "IRAN NUCLEAR THREAT")
      t.vector   :centroid,         limit: 1536          # average embedding of all matched articles
      t.integer  :match_count,      default: 0, null: false  # how many articles matched this signature
      t.float    :avg_trust_score,  default: 0.0         # rolling average trust across matches
      t.string   :dominant_threat_level                   # most common threat level in cluster
      t.jsonb    :source_distribution, default: {}        # { "Reuters" => 12, "RT" => 8, ... }
      t.jsonb    :country_distribution, default: {}       # { "US" => 15, "RU" => 9, ... }
      t.datetime :first_seen_at,    null: false
      t.datetime :last_seen_at,     null: false
      t.boolean  :active,           default: true, null: false
      t.timestamps
    end

    add_index :narrative_signatures, :active
    add_index :narrative_signatures, :last_seen_at
    add_index :narrative_signatures, :match_count

    # Join table: which articles belong to which signature
    create_table :narrative_signature_articles do |t|
      t.references :narrative_signature, null: false, foreign_key: true
      t.references :article,             null: false, foreign_key: true
      t.float      :cosine_distance                      # how close this article was to the centroid
      t.datetime   :matched_at,          null: false
    end

    add_index :narrative_signature_articles,
              [:narrative_signature_id, :article_id],
              unique: true,
              name: "idx_sig_articles_unique"
  end
end
```

### Model

```ruby
# app/models/narrative_signature.rb
class NarrativeSignature < ApplicationRecord
  has_neighbors :centroid

  has_many :narrative_signature_articles, dependent: :destroy
  has_many :articles, through: :narrative_signature_articles

  scope :active,  -> { where(active: true) }
  scope :recent,  -> { order(last_seen_at: :desc) }
  scope :dormant, -> { where(last_seen_at: ..30.days.ago) }

  # Recalculate centroid from current member articles
  def recompute_centroid!
    embeddings = articles.where.not(embedding: nil).pluck(:embedding)
    return if embeddings.empty?

    avg = embeddings.first.zip(*embeddings[1..]).map { |dims| dims.sum / dims.size.to_f }
    update!(centroid: avg, match_count: embeddings.size)
  end
end
```

```ruby
# app/models/narrative_signature_article.rb
class NarrativeSignatureArticle < ApplicationRecord
  belongs_to :narrative_signature, counter_cache: :match_count
  belongs_to :article
end
```

### Service: `NarrativeSignatureService`

**When it runs:** After every embedding generation (Phase 4 of AnalysisPipeline).

```ruby
# app/services/narrative_signature_service.rb
class NarrativeSignatureService
  MATCH_THRESHOLD = 0.18  # cosine distance — tighter than convergence (0.15) to avoid false merges
  MIN_SEED_CLUSTER = 3    # minimum articles to birth a new signature

  def classify(article)
    return unless article.embedding.present?

    # Find closest existing signature
    match = NarrativeSignature.active
              .nearest_neighbors(:centroid, article.embedding, distance: "cosine")
              .first

    if match && match.neighbor_distance < MATCH_THRESHOLD
      # Article matches an existing narrative — VERITAS recognizes this pattern
      absorb(match, article)
    else
      # No match — potentially novel. Queue for signature creation if cluster forms.
      queue_for_clustering(article)
    end
  end

  private

  def absorb(signature, article)
    NarrativeSignatureArticle.find_or_create_by!(
      narrative_signature: signature,
      article: article
    ) do |nsa|
      nsa.cosine_distance = signature.nearest_neighbors(:centroid, article.embedding, distance: "cosine").first&.neighbor_distance
      nsa.matched_at = Time.current
    end

    signature.update!(last_seen_at: Time.current)
    signature.recompute_centroid!  # signature evolves with each new article

    Rails.logger.info "[SIGNATURE] Article ##{article.id} matched signature '#{signature.label}' (#{signature.match_count} total)"
  end

  def queue_for_clustering(article)
    # Periodically, a background job clusters unmatched articles into new signatures
    # For now, just log — the NarrativeSignatureClusterJob handles bulk creation
    Rails.logger.info "[SIGNATURE] Article ##{article.id} — no signature match, queued for clustering"
  end
end
```

### Pipeline Integration

In `AnalysisPipeline#analyze`, after Phase 4 (embedding generation):

```ruby
# ━━━ PHASE 4b: Narrative Signature Classification ━━━
NarrativeSignatureService.new.classify(article)
```

---

## 2. SourceCredibility

**Purpose:** Rolling trust profile per news source. Updated every time an article from that source is analyzed. Over time, VERITAS learns which sources are reliable and which consistently produce low-trust, high-threat content.

### Migration

```ruby
# db/migrate/XXXX_create_source_credibilities.rb
class CreateSourceCredibilities < ActiveRecord::Migration[8.1]
  def change
    create_table :source_credibilities do |t|
      t.string   :source_name,          null: false
      t.integer  :articles_analyzed,    default: 0, null: false
      t.float    :rolling_trust_score,  default: 0.0, null: false  # weighted moving average
      t.float    :anomaly_rate,         default: 0.0               # % of articles flagged anomalous
      t.integer  :high_threat_count,    default: 0                 # articles rated HIGH/CRITICAL
      t.integer  :low_threat_count,     default: 0                 # articles rated LOW/NEGLIGIBLE
      t.jsonb    :topic_distribution,   default: {}                # what topics this source covers
      t.jsonb    :sentiment_distribution, default: {}              # sentiment breakdown
      t.jsonb    :coordination_flags,   default: []                # source pairs that publish in sync
      t.float    :credibility_grade,    default: 50.0, null: false # 0-100 composite score
      t.datetime :first_analyzed_at
      t.datetime :last_analyzed_at
      t.timestamps
    end

    add_index :source_credibilities, :source_name, unique: true
    add_index :source_credibilities, :credibility_grade
    add_index :source_credibilities, :rolling_trust_score
  end
end
```

### Model

```ruby
# app/models/source_credibility.rb
class SourceCredibility < ApplicationRecord
  GRADE_LABELS = {
    (80..100) => "TRUSTED",
    (60..79)  => "RELIABLE",
    (40..59)  => "MIXED",
    (20..39)  => "QUESTIONABLE",
    (0..19)   => "UNRELIABLE"
  }.freeze

  scope :trusted,      -> { where(credibility_grade: 80..100) }
  scope :questionable,  -> { where(credibility_grade: 0..39) }
  scope :by_grade,      -> { order(credibility_grade: :desc) }

  def grade_label
    GRADE_LABELS.find { |range, _| range.cover?(credibility_grade.to_i) }&.last || "UNKNOWN"
  end

  def grade_color
    case credibility_grade.to_i
    when 80..100 then "#22c55e"
    when 60..79  then "#38bdf8"
    when 40..59  then "#eab308"
    when 20..39  then "#f97316"
    else              "#ef4444"
    end
  end

  # Called after every article analysis completes
  def ingest_analysis!(ai_analysis)
    self.articles_analyzed += 1
    self.last_analyzed_at = Time.current
    self.first_analyzed_at ||= Time.current

    # Exponential moving average for trust (alpha = 0.1 — slow to change, hard to game)
    alpha = 0.1
    new_trust = ai_analysis.trust_score.to_f
    self.rolling_trust_score = (alpha * new_trust) + ((1 - alpha) * rolling_trust_score)

    # Track threat distribution
    threat = ai_analysis.threat_level.to_s.upcase
    if %w[CRITICAL HIGH].include?(threat)
      self.high_threat_count += 1
    elsif %w[LOW NEGLIGIBLE].include?(threat)
      self.low_threat_count += 1
    end

    # Track anomaly rate
    if ai_analysis.linguistic_anomaly_flag
      total_anomalies = (anomaly_rate * (articles_analyzed - 1)) + 1
      self.anomaly_rate = total_anomalies / articles_analyzed
    end

    # Recompute composite grade
    recompute_grade!

    save!
  end

  private

  def recompute_grade!
    # Composite: 50% trust, 25% inverse anomaly rate, 25% threat balance
    trust_component   = rolling_trust_score * 10  # trust is 0-10, scale to 0-100
    anomaly_component = (1 - anomaly_rate) * 100
    threat_ratio      = articles_analyzed > 0 ? (low_threat_count.to_f / articles_analyzed) : 0.5
    threat_component  = threat_ratio * 100

    self.credibility_grade = [
      (trust_component * 0.5) + (anomaly_component * 0.25) + (threat_component * 0.25),
      100
    ].min.round(1)
  end
end
```

### Service: `SourceCredibilityService`

```ruby
# app/services/source_credibility_service.rb
class SourceCredibilityService
  def update_for(article)
    return unless article.ai_analysis&.analysis_status == "complete"
    return if article.source_name.blank?

    credibility = SourceCredibility.find_or_create_by!(source_name: article.source_name)
    credibility.ingest_analysis!(article.ai_analysis)

    Rails.logger.info "[CREDIBILITY] #{article.source_name}: grade=#{credibility.credibility_grade} trust=#{credibility.rolling_trust_score.round(2)} (#{credibility.articles_analyzed} articles)"
  end
end
```

### Pipeline Integration

In `AnalysisPipeline#analyze`, after Phase 3 (final record):

```ruby
# ━━━ PHASE 3b: Source Credibility Update ━━━
SourceCredibilityService.new.update_for(article)
```

---

## 3. ContradictionLog

**Purpose:** Detects when sources contradict themselves over time, or when articles within the same narrative make opposing claims. This is VERITAS's long-term memory for inconsistency.

### Migration

```ruby
# db/migrate/XXXX_create_contradiction_logs.rb
class CreateContradictionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :contradiction_logs do |t|
      t.references :article_a,       null: false, foreign_key: { to_table: :articles }
      t.references :article_b,       null: false, foreign_key: { to_table: :articles }
      t.string     :contradiction_type, null: false  # "self_contradiction", "cross_source", "temporal_shift"
      t.text       :description                      # AI-generated explanation of the contradiction
      t.float      :severity,        default: 0.0    # 0.0–1.0
      t.float      :embedding_similarity              # cosine similarity between the two articles
      t.string     :source_a
      t.string     :source_b
      t.jsonb      :metadata,        default: {}
      t.timestamps
    end

    add_index :contradiction_logs, :contradiction_type
    add_index :contradiction_logs, :severity
    add_index :contradiction_logs, [:article_a_id, :article_b_id], unique: true, name: "idx_contradiction_pair"
  end
end
```

### Model

```ruby
# app/models/contradiction_log.rb
class ContradictionLog < ApplicationRecord
  belongs_to :article_a, class_name: "Article"
  belongs_to :article_b, class_name: "Article"

  TYPES = %w[self_contradiction cross_source temporal_shift].freeze

  validates :contradiction_type, inclusion: { in: TYPES }

  scope :severe,          -> { where(severity: 0.7..1.0) }
  scope :self_contradictions, -> { where(contradiction_type: "self_contradiction") }
  scope :recent,          -> { order(created_at: :desc) }

  # Self-contradiction: same source, opposing claims
  # Cross-source: different sources on same topic, opposing claims
  # Temporal shift: same source changed position over time
end
```

### Service: `ContradictionDetectionService`

**When it runs:** As a periodic background job (e.g., every 6 hours), not per-article.

```ruby
# app/services/contradiction_detection_service.rb
class ContradictionDetectionService
  SIMILARITY_THRESHOLD = 0.12  # cosine distance — very similar articles (same topic)
  LOOKBACK_DAYS = 30

  def initialize
    @client = OpenRouterClient.new
  end

  def detect
    detect_self_contradictions
    detect_temporal_shifts
  end

  private

  def detect_self_contradictions
    # For each source, find article pairs that are topically similar but have
    # opposing sentiments (one positive, one negative on the same topic)
    sources = Article.where(published_at: LOOKBACK_DAYS.days.ago..)
                     .where.not(embedding: nil)
                     .distinct.pluck(:source_name).compact

    sources.each do |source|
      articles = Article.where(source_name: source, published_at: LOOKBACK_DAYS.days.ago..)
                        .where.not(embedding: nil)
                        .joins(:ai_analysis)
                        .where(ai_analyses: { analysis_status: "complete" })
                        .includes(:ai_analysis)

      articles.each do |article|
        neighbors = article.nearest_neighbors(:embedding, distance: "cosine")
                           .where(source_name: source)
                           .where.not(id: article.id)
                           .limit(5)

        neighbors.each do |neighbor|
          next if neighbor.neighbor_distance > SIMILARITY_THRESHOLD
          next unless sentiment_opposes?(article, neighbor)
          next if ContradictionLog.exists?(article_a: article, article_b: neighbor)

          log_contradiction(article, neighbor, "self_contradiction", neighbor.neighbor_distance)
        end
      end
    end
  end

  def detect_temporal_shifts
    # Find cases where the same source covered the same topic but trust/threat
    # scores shifted dramatically over time
    # (Implementation follows same pattern — compare older vs newer articles per source)
  end

  def sentiment_opposes?(a, b)
    return false unless a.ai_analysis&.sentiment_label && b.ai_analysis&.sentiment_label
    sentiments = [a.ai_analysis.sentiment_label.downcase, b.ai_analysis.sentiment_label.downcase]
    (sentiments.include?("positive") && sentiments.include?("negative")) ||
      (sentiments.include?("supportive") && sentiments.include?("critical"))
  end

  def log_contradiction(article_a, article_b, type, distance)
    description = generate_description(article_a, article_b, type)

    ContradictionLog.create!(
      article_a: article_a,
      article_b: article_b,
      contradiction_type: type,
      description: description,
      severity: 1.0 - distance,  # closer articles with opposing sentiment = more severe
      embedding_similarity: 1.0 - distance,
      source_a: article_a.source_name,
      source_b: article_b.source_name
    )
  end

  def generate_description(article_a, article_b, type)
    prompt = <<~PROMPT
      Article A: "#{article_a.headline}" (#{article_a.source_name}, #{article_a.published_at&.strftime('%Y-%m-%d')})
      Summary A: #{article_a.ai_analysis&.summary}
      Sentiment A: #{article_a.ai_analysis&.sentiment_label}

      Article B: "#{article_b.headline}" (#{article_b.source_name}, #{article_b.published_at&.strftime('%Y-%m-%d')})
      Summary B: #{article_b.ai_analysis&.summary}
      Sentiment B: #{article_b.ai_analysis&.sentiment_label}

      Type: #{type}
    PROMPT

    system = "You are an intelligence analyst. In 1-2 sentences, explain the contradiction between these two articles. Be specific about what changed or conflicts."

    @client.chat(:arbiter, system, prompt, expect_json: false)&.strip
  rescue StandardError => e
    Rails.logger.error "[CONTRADICTION] Description generation failed: #{e.message}"
    nil
  end
end
```

### Background Job

```ruby
# app/jobs/detect_contradictions_job.rb
class DetectContradictionsJob < ApplicationJob
  queue_as :intelligence

  def perform
    ContradictionDetectionService.new.detect
  end
end
```

---

## 4. IntelligenceBrief (The Introspection Loop)

**Purpose:** Periodic system-authored summaries of what VERITAS has learned. This is VERITAS reflecting on its own knowledge state — the HAL moment.

### Migration

```ruby
# db/migrate/XXXX_create_intelligence_briefs.rb
class CreateIntelligenceBriefs < ActiveRecord::Migration[8.1]
  def change
    create_table :intelligence_briefs do |t|
      t.string   :brief_type,       null: false  # "daily", "weekly", "alert"
      t.string   :title,            null: false
      t.text     :executive_summary                # 2-3 paragraph overview
      t.jsonb    :narrative_trends,  default: []   # rising/falling signatures
      t.jsonb    :source_alerts,     default: []   # sources with credibility changes
      t.jsonb    :contradictions,    default: []   # notable contradictions detected
      t.jsonb    :blind_spots,       default: []   # regions/topics with low coverage
      t.jsonb    :confidence_map,    default: {}   # topic => confidence level
      t.integer  :articles_processed, default: 0
      t.integer  :signatures_active,  default: 0
      t.integer  :contradictions_found, default: 0
      t.string   :status,           default: "generating", null: false
      t.datetime :period_start
      t.datetime :period_end
      t.timestamps
    end

    add_index :intelligence_briefs, :brief_type
    add_index :intelligence_briefs, :created_at
    add_index :intelligence_briefs, :status
  end
end
```

### Model

```ruby
# app/models/intelligence_brief.rb
class IntelligenceBrief < ApplicationRecord
  TYPES = %w[daily weekly alert].freeze

  validates :brief_type, inclusion: { in: TYPES }
  validates :title, presence: true

  scope :daily,   -> { where(brief_type: "daily") }
  scope :weekly,  -> { where(brief_type: "weekly") }
  scope :latest,  -> { order(created_at: :desc) }
  scope :complete, -> { where(status: "complete") }
end
```

### Service: `IntrospectionService`

```ruby
# app/services/introspection_service.rb
class IntrospectionService
  def initialize
    @client = OpenRouterClient.new
  end

  def generate_daily_brief
    brief = IntelligenceBrief.create!(
      brief_type: "daily",
      title: "VERITAS Daily Intelligence Brief — #{Date.current.strftime('%d %b %Y')}",
      period_start: 24.hours.ago,
      period_end: Time.current,
      status: "generating"
    )

    # Gather system state
    narrative_trends   = analyze_narrative_trends
    source_alerts      = analyze_source_changes
    contradictions     = recent_contradictions
    blind_spots        = detect_blind_spots
    confidence_map     = build_confidence_map

    # Generate executive summary via AI
    executive_summary = generate_executive_summary(
      narrative_trends, source_alerts, contradictions, blind_spots
    )

    brief.update!(
      executive_summary:    executive_summary,
      narrative_trends:     narrative_trends,
      source_alerts:        source_alerts,
      contradictions:       contradictions,
      blind_spots:          blind_spots,
      confidence_map:       confidence_map,
      articles_processed:   Article.where(created_at: 24.hours.ago..).count,
      signatures_active:    NarrativeSignature.active.count,
      contradictions_found: ContradictionLog.where(created_at: 24.hours.ago..).count,
      status:               "complete"
    )

    brief
  end

  private

  def analyze_narrative_trends
    # Compare signature match_counts over last 24h vs previous 24h
    # Rising = gaining articles faster, Falling = slowing down
    NarrativeSignature.active.map do |sig|
      recent = sig.narrative_signature_articles.where(matched_at: 24.hours.ago..).count
      previous = sig.narrative_signature_articles.where(matched_at: 48.hours.ago..24.hours.ago).count
      delta = recent - previous
      direction = delta.positive? ? "RISING" : (delta.negative? ? "FALLING" : "STABLE")

      { label: sig.label, match_count: sig.match_count, recent: recent, delta: delta, direction: direction }
    end.sort_by { |t| -t[:recent] }
  end

  def analyze_source_changes
    # Sources whose credibility grade changed significantly in last 24h
    SourceCredibility.where(last_analyzed_at: 24.hours.ago..).map do |sc|
      { source: sc.source_name, grade: sc.credibility_grade, label: sc.grade_label }
    end
  end

  def recent_contradictions
    ContradictionLog.where(created_at: 24.hours.ago..).severe.limit(10).map do |cl|
      { type: cl.contradiction_type, source_a: cl.source_a, source_b: cl.source_b,
        description: cl.description, severity: cl.severity }
    end
  end

  def detect_blind_spots
    # Regions with < N articles in last 7 days = blind spots
    Region.all.filter_map do |region|
      count = Article.where(region: region, published_at: 7.days.ago..).count
      { region: region.name, article_count: count, status: "LOW_COVERAGE" } if count < 5
    end
  end

  def build_confidence_map
    # Per geopolitical topic: how much data do we have?
    topics = AiAnalysis.where(analysis_status: "complete")
                       .where.not(geopolitical_topic: [nil, ""])
                       .group(:geopolitical_topic)
                       .count

    topics.transform_values do |count|
      case count
      when 50.. then "HIGH"
      when 20..49 then "MODERATE"
      when 5..19 then "LOW"
      else "MINIMAL"
      end
    end
  end

  def generate_executive_summary(trends, source_alerts, contradictions, blind_spots)
    rising = trends.select { |t| t[:direction] == "RISING" }.first(5)
    falling = trends.select { |t| t[:direction] == "FALLING" }.first(3)

    context = <<~CTX
      VERITAS SYSTEM STATE — #{Date.current}

      RISING NARRATIVES: #{rising.map { |t| "#{t[:label]} (+#{t[:delta]})" }.join(", ")}
      FALLING NARRATIVES: #{falling.map { |t| "#{t[:label]} (#{t[:delta]})" }.join(", ")}
      CONTRADICTIONS DETECTED: #{contradictions.size} (#{contradictions.count { |c| c[:severity] > 0.8 }} severe)
      BLIND SPOTS: #{blind_spots.map { |b| b[:region] }.join(", ")}
      SOURCE ALERTS: #{source_alerts.size} sources updated
    CTX

    system = <<~SYS
      You are VERITAS, an intelligence platform. Write a 2-3 paragraph executive briefing
      summarizing today's intelligence landscape. Be direct, analytical, and specific.
      Flag anything that warrants analyst attention. Write in first person as the system.
    SYS

    @client.chat(:arbiter, system, context, expect_json: false)
  end
end
```

### Background Job

```ruby
# app/jobs/generate_intelligence_brief_job.rb
class GenerateIntelligenceBriefJob < ApplicationJob
  queue_as :intelligence

  def perform(type = "daily")
    IntrospectionService.new.generate_daily_brief
  end
end
```

### Solid Queue Recurring Schedule

```yaml
# config/recurring.yml (add to existing)
generate_daily_brief:
  class: GenerateIntelligenceBriefJob
  schedule: every day at 6am
  args: ["daily"]

detect_contradictions:
  class: DetectContradictionsJob
  schedule: every 6 hours
```

---

## 5. ConfidenceScore Concern (No Migration)

**Purpose:** Any model that produces a verdict/analysis can express how confident it is, based on data density.

```ruby
# app/models/concerns/confidence_scoreable.rb
module ConfidenceScoreable
  extend ActiveSupport::Concern

  def confidence_assessment(topic: nil, region: nil, source: nil)
    factors = {}

    if topic.present?
      count = AiAnalysis.where(geopolitical_topic: topic, analysis_status: "complete").count
      factors[:topic_depth] = { count: count, level: confidence_level(count) }
    end

    if region.present?
      count = Article.where(region: region, published_at: 30.days.ago..).count
      sources = Article.where(region: region, published_at: 30.days.ago..).distinct.count(:source_name)
      factors[:region_coverage] = { articles: count, sources: sources, level: confidence_level(count) }
    end

    if source.present?
      cred = SourceCredibility.find_by(source_name: source)
      factors[:source_credibility] = cred ? { grade: cred.credibility_grade, label: cred.grade_label } : { grade: 0, label: "UNKNOWN" }
    end

    overall = factors.values.map { |f| confidence_to_numeric(f[:level] || f[:label]) }.compact
    {
      factors: factors,
      overall: overall.any? ? (overall.sum / overall.size).round(1) : 0,
      label: confidence_level(overall.sum / [overall.size, 1].max)
    }
  end

  private

  def confidence_level(count)
    case count.to_i
    when 50.. then "HIGH"
    when 20..49 then "MODERATE"
    when 5..19 then "LOW"
    else "MINIMAL"
    end
  end

  def confidence_to_numeric(level)
    { "HIGH" => 90, "TRUSTED" => 90, "RELIABLE" => 75, "MODERATE" => 60,
      "MIXED" => 50, "LOW" => 30, "QUESTIONABLE" => 20, "MINIMAL" => 10,
      "UNRELIABLE" => 5, "UNKNOWN" => 0 }[level.to_s] || 0
  end
end
```

Include in relevant models:
```ruby
class AiAnalysis < ApplicationRecord
  include ConfidenceScoreable
  # ...
end

class IntelligenceReport < ApplicationRecord
  include ConfidenceScoreable
  # ...
end
```

---

## 6. EmbeddingDrift Snapshots

**Purpose:** Track how the vector space evolves over time. Detect emerging clusters, dissolving narratives, and sudden shifts.

### Migration

```ruby
# db/migrate/XXXX_create_embedding_snapshots.rb
class CreateEmbeddingSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :embedding_snapshots do |t|
      t.datetime :captured_at,       null: false
      t.integer  :article_count,     null: false
      t.integer  :cluster_count,     default: 0
      t.jsonb    :cluster_summary,   default: []   # [{ centroid_label, size, avg_distance, top_sources }]
      t.jsonb    :drift_metrics,     default: {}   # { new_clusters: N, dissolved: N, merged: N }
      t.jsonb    :outlier_ids,       default: []   # article IDs that don't fit any cluster
      t.timestamps
    end

    add_index :embedding_snapshots, :captured_at
  end
end
```

### Background Job

```ruby
# app/jobs/capture_embedding_snapshot_job.rb
class CaptureEmbeddingSnapshotJob < ApplicationJob
  queue_as :intelligence

  def perform
    EmbeddingDriftService.new.capture_snapshot
  end
end
```

---

## Updated AnalysisPipeline

After all migrations, the pipeline becomes:

```ruby
class AnalysisPipeline
  def analyze(article)
    # ... existing lock + status logic ...

    # ━━━ PHASE 1: Parallel AI Analysis (Analyst + Sentinel) ━━━
    # ... unchanged ...

    # ━━━ PHASE 2: Cross-Verification (Arbiter) ━━━
    # ... unchanged ...

    # ━━━ PHASE 3: Final Record ━━━
    # ... unchanged ...

    # ━━━ PHASE 3b: Source Credibility Update ━━━  [NEW]
    SourceCredibilityService.new.update_for(article)

    # ━━━ PHASE 4: Semantic Intelligence (Embedding) ━━━
    EmbeddingService.new.generate(article)

    # ━━━ PHASE 4b: Narrative Signature Classification ━━━  [NEW]
    NarrativeSignatureService.new.classify(article)

    # ━━━ PHASE 5: Entity Extraction ━━━
    # ... unchanged ...
  end
end
```

Background jobs (not per-article, periodic):
- `DetectContradictionsJob` — every 6 hours
- `GenerateIntelligenceBriefJob` — daily at 6am
- `CaptureEmbeddingSnapshotJob` — every 12 hours

---

## Data Flow Diagram

```
                    ┌─────────────────────────────┐
                    │       New Article Batch      │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │     AnalysisPipeline         │
                    │  (Analyst→Sentinel→Arbiter)  │
                    └──────────────┬──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                     │
    ┌─────────▼─────────┐  ┌──────▼───────┐  ┌─────────▼──────────┐
    │ SourceCredibility  │  │  Embedding   │  │ Entity Extraction  │
    │    (per source)    │  │ Generation   │  │                    │
    └────────────────────┘  └──────┬───────┘  └────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  NarrativeSignature Match   │
                    │  (classify or queue)         │
                    └──────────────┬──────────────┘
                                   │
        ═══════════════════════════╪═══════════════════════
        PERIODIC BACKGROUND JOBS   │
        ═══════════════════════════╪═══════════════════════
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                     │
    ┌─────────▼─────────┐  ┌──────▼───────┐  ┌─────────▼──────────┐
    │  Contradiction     │  │  Embedding   │  │  Intelligence      │
    │  Detection (6h)    │  │  Drift (12h) │  │  Brief (daily)     │
    └────────────────────┘  └──────────────┘  └────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │    VERITAS Knowledge State   │
                    │   "What the system knows"    │
                    └─────────────────────────────┘
```

---

## Implementation Sequence

| Step | What | Estimated Migrations | Dependencies |
|------|------|---------------------|--------------|
| 1 | `SourceCredibility` model + service + pipeline hook | 1 migration | None — simplest, immediate value |
| 2 | `NarrativeSignature` + join table + service | 1 migration | Existing embeddings |
| 3 | `ContradictionLog` + detection service + job | 1 migration | Existing embeddings + analyses |
| 4 | `IntelligenceBrief` + introspection service + job | 1 migration | Steps 1-3 (reads from all) |
| 5 | `ConfidenceScoreable` concern | No migration | Steps 1-2 |
| 6 | `EmbeddingSnapshot` + drift service + job | 1 migration | Existing embeddings |

**Total: 5 migrations, 5 new models, 4 new services, 3 new background jobs, 1 concern.**
