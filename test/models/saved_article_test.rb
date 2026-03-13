require "test_helper"

class SavedArticleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
require "test_helper"

class SavedArticleTest < ActiveSupport::TestCase
  test "same user cannot save the same article twice" do
    user = User.create!(
      email: "saved-article-#{SecureRandom.hex}@example.com",
      password: "password",
      password_confirmation: "password",
      role: "user"
    )
    region = Region.create!(name: "Europe")
    country = Country.create!(name: "Germany", iso_code: "DE", region: region)
    article = Article.create!(
      headline: "Headline",
      content: "Body",
      source_name: "Source",
      country: country,
      region: region
    )

    SavedArticle.create!(
      user: user,
      article: article,
      headline: article.headline,
      content: article.content,
      source_name: article.source_name
    )

    duplicate = SavedArticle.new(
      user: user,
      article: article,
      headline: article.headline,
      content: article.content,
      source_name: article.source_name
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:article_id], "has already been taken"
  end
end
