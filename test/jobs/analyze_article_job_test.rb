require "test_helper"

class AnalyzeArticleJobTest < ActiveJob::TestCase
  test "skips pipeline when article analysis is already running" do
    region = Region.create!(name: "Asia")
    country = Country.create!(name: "Japan", iso_code: "JP", region: region)
    article = Article.create!(
      headline: "Breaking signal",
      content: "Content",
      source_name: "Source",
      country: country,
      region: region
    )
    AiAnalysis.create!(article: article, analysis_status: "analyzing")

    fake_pipeline = Object.new
    def fake_pipeline.analyze(*)
      raise "pipeline should not run"
    end

    pipeline_singleton = AnalysisPipeline.singleton_class
    pipeline_singleton.alias_method :__original_new_for_test, :new
    pipeline_singleton.define_method(:new) { fake_pipeline }

    begin
      AnalyzeArticleJob.perform_now(article.id)
    ensure
      pipeline_singleton.alias_method :new, :__original_new_for_test
      pipeline_singleton.remove_method :__original_new_for_test
    end

    assert_equal "analyzing", article.reload.ai_analysis.analysis_status
  end
end
