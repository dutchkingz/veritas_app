require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "non admin users see regional analysis as locked" do
    Region.create!(name: "Europe")
    sign_in build_user(role: "user")

    get root_path

    assert_response :success
    assert_includes response.body, "LOCKED"
  end

  test "admin users can run regional analysis" do
    Region.create!(name: "Europe")
    sign_in build_user(role: "admin")

    get root_path

    assert_response :success
    assert_includes response.body, "RUN"
  end

  test "home shows the real signal count" do
    sign_in build_user(role: "admin")

    region = Region.create!(name: "Europe")
    country = Country.create!(name: "Germany", iso_code: "DE", region: region)
    3.times do |index|
      Article.create!(
        headline: "Signal #{index}",
        content: "<p>Body</p>",
        source_name: "Example Source",
        source_url: "https://example.com/#{index}",
        published_at: Time.current - index.minutes,
        latitude: 50.0 + index,
        longitude: 8.0 + index,
        country: country,
        region: region
      )
    end

    get root_path

    assert_response :success
    assert_includes response.body, "3 SIGNALS"
  end

  test "globe data applies perspective filtering to points and arcs" do
    sign_in build_user(role: "admin")

    region_one = Region.create!(name: "East Asia", latitude: 35.86, longitude: 104.19, threat_level: 2)
    region_two = Region.create!(name: "Western Europe", latitude: 51.16, longitude: 10.45, threat_level: 1)
    country_one = Country.create!(name: "China", iso_code: "CN", region: region_one)
    country_two = Country.create!(name: "Germany", iso_code: "DE", region: region_two)

    china_filter = PerspectiveFilter.create!(
      name: "China State Media",
      filter_type: "source",
      keywords: "Xinhua,Global Times"
    )

    old_article = Article.create!(
      headline: "China narrative origin",
      content: "<p>Body</p>",
      source_name: "Xinhua",
      source_url: "https://example.com/china-1",
      published_at: 2.hours.ago,
      latitude: 35.86,
      longitude: 104.19,
      country: country_one,
      region: region_one
    )
    new_article = Article.create!(
      headline: "China narrative relay",
      content: "<p>Body</p>",
      source_name: "Global Times",
      source_url: "https://example.com/china-2",
      published_at: 1.hour.ago,
      latitude: 51.16,
      longitude: 10.45,
      country: country_two,
      region: region_two
    )
    Article.create!(
      headline: "Other lens article",
      content: "<p>Body</p>",
      source_name: "Reuters",
      source_url: "https://example.com/reuters-1",
      published_at: 30.minutes.ago,
      latitude: 40.71,
      longitude: -74.0,
      country: country_two,
      region: region_two
    )
    AiAnalysis.create!(article: old_article, analysis_status: "complete", sentiment_color: "#123456")
    AiAnalysis.create!(article: new_article, analysis_status: "complete", sentiment_color: "#654321")

    get "/api/globe_data", params: { perspective_id: china_filter.id }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["points"].length
    assert_equal ["Global Times", "Xinhua"].sort, body["points"].map { |point| point["source"] }.sort
    assert body["arcs"].any?
    assert_equal "#123456", body["arcs"].first["color"].first
    assert_not_equal body["arcs"].first["color"].first, body["arcs"].first["color"].last
    assert_equal old_article.id, body["arcs"].first["articleId"]
    assert_equal "China narrative origin", body["arcs"].first["headline"]
    assert_equal "Xinhua", body["arcs"].first["source"]
    assert_equal "China", body["arcs"].first["originCountry"]
    assert_equal "Germany", body["arcs"].first["targetCountry"]
  end

  private

  def build_user(role:)
    User.create!(
      email: "#{role}-#{SecureRandom.hex}@example.com",
      password: "password",
      password_confirmation: "password",
      role: role,
      admin: (role == "admin")
    )
  end
end
