class SourceCredibility < ApplicationRecord
  GRADE_LABELS = {
    (80..100) => "TRUSTED",
    (60..79)  => "RELIABLE",
    (40..59)  => "MIXED",
    (20..39)  => "QUESTIONABLE",
    (0..19)   => "UNRELIABLE"
  }.freeze

  scope :trusted,       -> { where(credibility_grade: 80..100) }
  scope :questionable,  -> { where(credibility_grade: 0..39) }
  scope :by_grade,      -> { order(credibility_grade: :desc) }

  validates :source_name, presence: true, uniqueness: true

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

    # Track topic distribution
    topic = ai_analysis.geopolitical_topic
    if topic.present?
      self.topic_distribution = topic_distribution.merge(topic => (topic_distribution[topic] || 0) + 1)
    end

    # Track sentiment distribution
    sentiment = ai_analysis.sentiment_label
    if sentiment.present?
      self.sentiment_distribution = sentiment_distribution.merge(sentiment => (sentiment_distribution[sentiment] || 0) + 1)
    end

    recompute_grade!
    save!
  end

  private

  def recompute_grade!
    # Composite: 50% trust, 25% inverse anomaly rate, 25% threat balance
    trust_component   = rolling_trust_score  # trust is already 0-100 scale
    anomaly_component = (1 - anomaly_rate) * 100
    threat_ratio      = articles_analyzed > 0 ? (low_threat_count.to_f / articles_analyzed) : 0.5
    threat_component  = threat_ratio * 100

    self.credibility_grade = [
      (trust_component * 0.5) + (anomaly_component * 0.25) + (threat_component * 0.25),
      100
    ].min.round(1)
  end
end
