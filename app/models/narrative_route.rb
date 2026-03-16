class NarrativeRoute < ApplicationRecord
  belongs_to :narrative_arc
  belongs_to :article, optional: true
  
  validates :hops, presence: true
  validates :total_hops, numericality: { greater_than_or_equal_to: 0 }
  validates :manipulation_score, numericality: { in: 0.0..1.0 }
  validates :amplification_score, numericality: { in: 0.0..1.0 }
  
  before_save :calculate_derived_fields
  after_save :update_arc_metadata
  
  # ARCWEAVER 2.0: Globe visualization data
  def as_globe_data
    return simple_globe_data if hops.empty?
    
    # Multi-hop visualization with segments
    segments = []
    hops.each_with_index do |hop, index|
      next_hop = hops[index + 1]
      next unless next_hop
      
      # Calculate thickness based on manipulation score (0.3–3.0)
      # More manipulation = thicker arc (more important to visualize)
      thickness = [(manipulation_score || 0.5) * 3.0, 0.3].max.round(2)
      
      segments << {
        startLat: hop['lat'],
        startLng: hop['lng'],
        endLat: next_hop['lat'],
        endLng: next_hop['lng'],
        color: segment_color(hop['framing_shift']),
        thickness: thickness,
        sourceName: hop['source_name'],
        targetSourceName: next_hop['source_name'],
        delaySeconds: hop['delay_from_previous'] || 0,
        publishedAt: hop['published_at'],
        confidenceScore: hop['confidence_score'] || 0.5,
        segmentIndex: index,
        totalSegments: hops.length - 1
      }
    end
    
    {
      id: id,
      name: name,
      arcId: narrative_arc_id,
      segments: segments,
      totalHops: total_hops,
      propagationSpeed: propagation_speed,
      manipulationScore: manipulation_score,
      amplificationScore: amplification_score,
      timeline: timeline,
      isComplete: is_complete,
      # For backward compatibility
      startLat: origin_lat,
      startLng: origin_lng,
      endLat: target_lat,
      endLng: target_lng,
      color: arc_color || '#00f0ff'
    }
  end
  
  # For simple arc visualization (fallback)
  def simple_globe_data
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
  
  private
  
  def calculate_derived_fields
    return if hops.blank?
    
    self.total_hops = hops.length
    self.first_hop_at = hops.first['published_at']
    self.last_hop_at = hops.last['published_at']
    
    # Calculate duration
    if first_hop_at && last_hop_at
      # Convert to DateTime if strings
      first_time = first_hop_at.is_a?(String) ? DateTime.parse(first_hop_at) : first_hop_at.to_datetime
      last_time = last_hop_at.is_a?(String) ? DateTime.parse(last_hop_at) : last_hop_at.to_datetime
      self.total_duration_seconds = (last_time - first_time).to_i
    end
    
    # Calculate propagation speed (km/h between first and last hop)
    if hops.length >= 2
      first = hops.first
      last = hops.last
      distance_km = haversine_distance(first['lat'], first['lng'], last['lat'], last['lng'])
      hours = total_duration_seconds.to_f / 3600
      self.propagation_speed = hours > 0 ? distance_km / hours : 0
    end
    
    # Calculate manipulation score (how much framing changed)
    framing_shifts = hops.map { |h| h['framing_shift'] }.uniq
    self.manipulation_score = (framing_shifts.length - 1) / [hops.length - 1, 1].max.to_f
    
    # Calculate amplification score (how many countries reached)
    countries = hops.map { |h| h['source_country'] }.compact.uniq
    self.total_reach_countries = countries.length
    self.amplification_score = total_reach_countries.to_f / [hops.length, 1].max
    
    # Build timeline array for fast queries
    self.timeline = hops.map do |hop|
      {
        timestamp: hop['published_at'],
        lat: hop['lat'],
        lng: hop['lng'],
        source_name: hop['source_name'],
        country: hop['source_country'],
        framing_shift: hop['framing_shift']
      }
    end
    
    # Mark as complete if we have confidence in all hops
    self.is_complete = hops.all? { |h| (h['confidence_score'] || 0) > 0.7 }
  end
  
  def update_arc_metadata
    update_hash = {}
    
    if hops.first
      update_hash[:origin_country] = hops.first['source_country']
      update_hash[:origin_lat] = hops.first['lat']
      update_hash[:origin_lng] = hops.first['lng']
    end
    
    if hops.last
      update_hash[:target_country] = hops.last['source_country']
      update_hash[:target_lat] = hops.last['lat']
      update_hash[:target_lng] = hops.last['lng']
    end
    
    narrative_arc.update(update_hash) if update_hash.any?
  end
  
  # Haversine distance calculation in km
  def haversine_distance(lat1, lng1, lat2, lng2)
    rad_per_deg = Math::PI / 180
    earth_radius_km = 6371
    
    lat1_rad = lat1 * rad_per_deg
    lat2_rad = lat2 * rad_per_deg
    
    dlat = (lat2 - lat1) * rad_per_deg
    dlng = (lng2 - lng1) * rad_per_deg
    
    a = Math.sin(dlat/2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng/2)**2
    c = 2 * Math.asin(Math.sqrt(a))
    
    earth_radius_km * c
  end
  
  def segment_color(framing_shift)
    case framing_shift
    when 'original'
      '#22c55e' # green
    when 'amplified'
      '#f59e0b' # yellow
    when 'distorted'
      '#ef4444' # red
    when 'neutralized'
      '#3b82f6' # blue
    else
      '#6b7280' # gray
    end
  end
end