class GdeltEvent < ApplicationRecord
  belongs_to :article, optional: true

  scope :conflicts,    -> { where(quad_class: [3, 4]) }
  scope :high_impact,  -> { where("goldstein_scale < ?", -5.0) }
  scope :recent,       -> { where("event_date >= ?", 7.days.ago) }
  scope :credible,     -> { where("num_sources >= ?", 3) }

  # Human-readable event description using CAMEO codes.
  # Returns the full description if available, falls back to root code description,
  # then to the raw code string.
  def event_description
    cameo = self.class.cameo_codes
    cameo.dig("codes", event_code) ||
      cameo.dig("codes", event_root_code) ||
      cameo.dig("root_codes", event_root_code) ||
      event_code
  end

  def quad_class_label
    self.class.cameo_codes.dig("quad_classes", quad_class.to_s) || "Unknown"
  end

  # Return a compact actor string for UI display:
  # "Russia → Ukraine", "US Military → Iran", etc.
  def actor_summary
    a1 = actor1_name.presence || actor1_country_code.presence || "Unknown"
    a2 = actor2_name.presence || actor2_country_code.presence || "Unknown"
    "#{a1} → #{a2}"
  end

  def self.cameo_codes
    @cameo_codes ||= begin
      path = Rails.root.join("config", "cameo_codes.yml")
      YAML.load_file(path).with_indifferent_access
    rescue => e
      Rails.logger.error "[GdeltEvent] Failed to load cameo_codes.yml: #{e.message}"
      {}
    end
  end
end
