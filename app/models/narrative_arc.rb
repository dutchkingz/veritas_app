class NarrativeArc < ApplicationRecord
  belongs_to :article
  has_many :narrative_routes, dependent: :destroy
  
  before_save :sync_with_article
  
  private
  
  def sync_with_article
    return unless article
    
    # Force origin coordinates to match the article's location
    self.origin_lat = article.latitude
    self.origin_lng = article.longitude
  end
  
  # Backward compatibility: simple arc visualization
  def as_globe_data
    {
      startLat: origin_lat,
      startLng: origin_lng,
      endLat: target_lat,
      endLng: target_lng,
      color: arc_color || '#00f0ff',
      originCountry: origin_country,
      targetCountry: target_country,
      articleId: article_id
    }
  end
  
  # ARCWEAVER 2.0: Best route (most complete/highest confidence)
  def best_route
    narrative_routes.where(is_complete: true).order(manipulation_score: :desc).first
  end
  
  # Return routes for globe visualization (animated packets)
  def routes_as_globe_data
    narrative_routes.map(&:as_globe_data)
  end
end
