module ApplicationHelper
  ARTICLE_ALLOWED_TAGS = %w[
    p br h1 h2 h3 h4 h5 h6 ul ol li strong em b i blockquote
    img figure figcaption picture source span a
  ].freeze

  ARTICLE_ALLOWED_ATTRIBUTES = %w[
    href src alt title class target rel
  ].freeze

  def sanitized_article_content(content)
    sanitize(
      content.to_s,
      tags: ARTICLE_ALLOWED_TAGS,
      attributes: ARTICLE_ALLOWED_ATTRIBUTES
    )
  end

  def formatted_report_html(text)
    blocks = text.to_s.split(/\n{2,}/).map(&:strip).reject(&:blank?)

    safe_join(blocks.map { |block| format_report_block(block) })
  end

  # SECURITY FIX 1.1b: Strip ALL HTML from LLM-generated report summaries
  # Used for data-attributes and tooltips where no HTML is acceptable
  # Prevents XSS via data-content attributes with injected JavaScript
  def sanitized_report_summary(text)
    strip_tags(text.to_s)
  end

  private

  def format_report_block(block)
    if block.start_with?("## ")
      content_tag(:h2, block.delete_prefix("## ").strip, class: "veritas-report-heading")
    else
      simple_format(ERB::Util.html_escape(block), {}, sanitize: false)
    end
  end
end
