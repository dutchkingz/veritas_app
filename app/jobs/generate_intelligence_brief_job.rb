class GenerateIntelligenceBriefJob < ApplicationJob
  queue_as :intelligence

  def perform(type = "daily")
    if VeritasMode.demo?
      Rails.logger.info "[GenerateIntelligenceBriefJob] Demo mode — skipping."
      return
    end

    case type
    when "daily"
      IntrospectionService.new.generate_daily_brief
    when "periodic"
      IntrospectionService.new.generate_periodic_reassessment
    else
      Rails.logger.warn "[INTROSPECTION] Unknown brief type: #{type}"
    end
  end
end
