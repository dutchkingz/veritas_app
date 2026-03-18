class GenerateIntelligenceBriefJob < ApplicationJob
  queue_as :intelligence

  def perform(type = "daily")
    case type
    when "daily"
      IntrospectionService.new.generate_daily_brief
    else
      Rails.logger.warn "[INTROSPECTION] Unknown brief type: #{type}"
    end
  end
end
