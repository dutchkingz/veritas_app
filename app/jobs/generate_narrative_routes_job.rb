class GenerateNarrativeRoutesJob < ApplicationJob
  queue_as :default
  
  # Retry on failure with exponential backoff
  retry_on ActiveRecord::Deadlocked, wait: ->(attempt) { (attempt ** 4).minutes }
  
  def perform(limit: 50)
    Rails.logger.info "[JOB] GenerateNarrativeRoutesJob started (limit: #{limit})"
    
    service = NarrativeRouteGeneratorService.new
    routes_created = service.generate_routes(limit: limit)
    
    Rails.logger.info "[JOB] GenerateNarrativeRoutesJob complete: #{routes_created} routes created"
    
    # Broadcast to Globe channel if routes were created
    if routes_created > 0
      ActionCable.server.broadcast('GlobeChannel', {
        type: 'routes_updated',
        count: routes_created,
        message: "#{routes_created} new narrative routes generated"
      })
    end
    
    routes_created
  rescue StandardError => e
    Rails.logger.error "[JOB] GenerateNarrativeRoutesJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end
end
