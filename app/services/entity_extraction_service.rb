# EntityExtractionService
#
# Extracts named entities (people, organizations, countries, events) from a
# single Article via LLM. Persists Entity records and EntityMention join rows.
# Designed to be called as Phase 5 of AnalysisPipeline — non-blocking, never
# raises so a failure here cannot crash the analysis pipeline.
#
# Usage:
#   EntityExtractionService.new.extract(article)
#   => { entities_created: 3, mentions_created: 5 }

class EntityExtractionService
  MAX_TEXT_CHARS = 600

  SYSTEM_PROMPT = <<~PROMPT.strip.freeze
    You are a named-entity extractor for an intelligence platform.
    Extract named entities from the provided news headline and text.
    Return ONLY a JSON object with this exact structure:
    {
      "entities": [
        { "name": "entity name", "type": "person|organization|country|event" }
      ]
    }
    Rules:
    - Maximum 10 entities total
    - Only clearly named, specific entities — no generic terms
    - person: named individuals (politicians, executives, public figures)
    - organization: companies, agencies, political parties, military units, NGOs
    - country: nation-states and territories
    - event: named operations, conflicts, summits, elections, crises
    - Omit anything vague or generic (e.g. "officials", "sources", "the government")
  PROMPT

  def initialize
    @client = OpenRouterClient.new
  end

  def extract(article)
    text = build_input(article)
    return { entities_created: 0, mentions_created: 0 } if text.blank?

    raw = @client.chat(:entity_extractor, SYSTEM_PROMPT, text, expect_json: true)
    entities_data = Array(raw["entities"]).first(10)

    entities_created = 0
    mentions_created = 0

    entities_data.each do |item|
      name = item["name"].to_s.strip
      type = item["type"].to_s.strip.downcase
      next if name.blank? || !Entity::TYPES.include?(type)

      entity = Entity.find_or_create_normalized(name: name, entity_type: type)
      next unless entity

      entities_created += 1 if entity.previously_new_record?

      mention = EntityMention.find_or_create_by(entity: entity, article: article)
      mentions_created += 1 if mention.previously_new_record?
    end

    Rails.logger.info "[EntityExtraction] Article ##{article.id}: #{entities_created} new entities, #{mentions_created} new mentions"
    { entities_created: entities_created, mentions_created: mentions_created }

  rescue JSON::ParserError => e
    Rails.logger.warn "[EntityExtraction] JSON parse error for Article ##{article.id}: #{e.message}"
    { entities_created: 0, mentions_created: 0 }
  rescue StandardError => e
    Rails.logger.error "[EntityExtraction] Failed for Article ##{article.id}: #{e.class} #{e.message}"
    { entities_created: 0, mentions_created: 0 }
  end

  private

  def build_input(article)
    headline    = article.headline.to_s.strip
    description = article.raw_data&.dig("description").to_s.strip
    content     = article.content.to_s.strip

    body = (description.presence || content).first(MAX_TEXT_CHARS)
    [headline, body].reject(&:blank?).join(". ")
  end
end
