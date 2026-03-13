require "test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  test "legacy fallback demo article heals instead of trying to fetch demo host" do
    sign_in user

    region = Region.create!(name: "Western Europe")
    country = Country.create!(name: "Germany", iso_code: "DE", region: region)
    article = Article.create!(
      headline: "Fallback Demo Signal",
      content: nil,
      source_name: "Demo Feed",
      source_url: "https://demo.veritas.local/articles/1",
      published_at: Time.current,
      latitude: 52.52,
      longitude: 13.40,
      country: country,
      region: region,
      raw_data: { "seed_mode" => "fallback_demo" }
    )

    get article_path(article)

    assert_response :success
    assert_includes response.body, "Fallback Demo Signal"
    assert_not_includes response.body, "Could not parse document stream"
    assert_not_includes response.body, "ACCESS ORIGINAL SOURCE"
    assert_nil article.reload.source_url
    assert_includes article.content, "DEMO INTELLIGENCE SIGNAL"
  end

  test "analysis status returns queued when ai analysis is missing" do
    sign_in user

    region = Region.create!(name: "Middle East")
    country = Country.create!(name: "Israel", iso_code: "IL", region: region)
    article = Article.create!(
      headline: "Queued Signal",
      content: "<p>Body</p>",
      source_name: "Example Source",
      source_url: "https://example.com/queued",
      published_at: Time.current,
      latitude: 31.76,
      longitude: 35.21,
      country: country,
      region: region
    )

    get analysis_status_article_path(article), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "queued", body["status"]
    assert_equal false, body["complete"]
  end

  test "analysis status returns complete when triad finished" do
    sign_in user

    region = Region.create!(name: "East Asia")
    country = Country.create!(name: "China", iso_code: "CN", region: region)
    article = Article.create!(
      headline: "Completed Signal",
      content: "<p>Body</p>",
      source_name: "Example Source",
      source_url: "https://example.com/completed",
      published_at: Time.current,
      latitude: 35.86,
      longitude: 104.19,
      country: country,
      region: region
    )
    AiAnalysis.create!(article: article, analysis_status: "complete")

    get analysis_status_article_path(article), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "complete", body["status"]
    assert_equal true, body["complete"]
  end

  test "article show re-enqueues triad analysis when previous run failed" do
    sign_in user

    region = Region.create!(name: "South Asia")
    country = Country.create!(name: "India", iso_code: "IN", region: region)
    article = Article.create!(
      headline: "Retry Signal",
      content: "<p>Body</p>",
      source_name: "Example Source",
      source_url: "https://example.com/retry",
      published_at: Time.current,
      latitude: 28.61,
      longitude: 77.20,
      country: country,
      region: region
    )
    AiAnalysis.create!(article: article, analysis_status: "failed")

    assert_enqueued_with(job: AnalyzeArticleJob, args: [article.id]) do
      get article_path(article)
    end

    assert_response :success
    assert_includes response.body, "RETRYING"
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
