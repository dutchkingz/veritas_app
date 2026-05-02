module GeoValidation
  extend ActiveSupport::Concern

  private

  def null_island?(lat, lng)
    lat.to_f.abs < 1.0 && lng.to_f.abs < 1.0
  end

  def valid_coordinates?(lat, lng)
    lat.to_f.between?(-90.0, 90.0) && lng.to_f.between?(-180.0, 180.0)
  end

  def degenerate_arc?(arc)
    s_lat = arc[:startLat]
    s_lng = arc[:startLng]
    e_lat = arc[:endLat]
    e_lng = arc[:endLng]

    return true if [s_lat, s_lng, e_lat, e_lng].any?(&:nil?)
    return true unless valid_coordinates?(s_lat, s_lng) && valid_coordinates?(e_lat, e_lng)
    return true if null_island?(s_lat, s_lng) || null_island?(e_lat, e_lng)

    lat_diff = (s_lat.to_f - e_lat.to_f).abs
    lng_diff = (s_lng.to_f - e_lng.to_f).abs
    return true if lat_diff < 2.0 && lng_diff < 2.0

    false
  end
end
