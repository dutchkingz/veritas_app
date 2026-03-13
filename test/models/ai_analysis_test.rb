require "test_helper"

class AiAnalysisTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
require "test_helper"

class AiAnalysisTest < ActiveSupport::TestCase
  test "completed analysis does not raise when globe broadcast fails" do
    region = Region.create!(name: "North Africa")
    country = Country.create!(name: "Egypt", iso_code: "EG", region: region)
    article = Article.create!(
      headline: "Broadcast Resilience",
      content: "<p>Body</p>",
      source_name: "Example Source",
      source_url: "https://example.com/broadcast",
      published_at: Time.current,
      latitude: 30.04,
      longitude: 31.23,
      country: country,
      region: region
    )
    analysis = AiAnalysis.create!(article: article, analysis_status: "analyzing")

    server_singleton = ActionCable.server.singleton_class
    server_singleton.alias_method :__original_broadcast_for_test, :broadcast
    server_singleton.define_method(:broadcast) { |*| raise ArgumentError, "No unique index found for id" }

    begin
      analysis.update!(analysis_status: "complete", sentiment_color: "#22c55e")
    ensure
      server_singleton.alias_method :broadcast, :__original_broadcast_for_test
      server_singleton.remove_method :__original_broadcast_for_test
    end

    assert_equal "complete", analysis.reload.analysis_status
  end
end
