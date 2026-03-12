require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "sanitized_article_content removes scripts while preserving safe markup" do
    html = <<~HTML
      <p>Signal</p>
      <script>alert('xss')</script>
      <img src="https://example.com/image.jpg" onerror="alert('xss')">
    HTML

    result = sanitized_article_content(html)

    assert_includes result, "<p>Signal</p>"
    assert_includes result, '<img src="https://example.com/image.jpg">'
    refute_includes result, "<script>"
    refute_includes result, "onerror"
  end

  test "formatted_report_html escapes unsafe content and preserves section headings" do
    text = "## Executive Summary\n\n<script>alert('xss')</script>\nLine two"

    result = formatted_report_html(text)

    assert_includes result, "veritas-report-heading"
    assert_includes result, "Executive Summary"
    assert_includes result, "&lt;script&gt;alert"
    refute_includes result, "<script>"
  end
end
