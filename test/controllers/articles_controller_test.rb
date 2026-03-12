require "test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  test "article show renders when source host resolves normally" do
    sign_in user

    region = Region.create!(name: "North America")
    country = Country.create!(name: "United States", iso_code: "US", region: region)
    article = Article.create!(
      headline: "Signal",
      content: "<p>Cached body</p>",
      source_name: "Example Source",
      source_url: "https://example.com/report",
      published_at: Time.current,
      latitude: 10.0,
      longitude: 20.0,
      country: country,
      region: region
    )

    get article_path(article)

    assert_response :success
    assert_includes response.body, "Signal"
  end

  private

  def user
    @user ||= User.create!(
      email: "articles-controller-#{SecureRandom.hex}@example.com",
      password: "password",
      password_confirmation: "password",
      role: "user"
    )
  end
end
