module Api
  class TrendingTopicsController < ApplicationController
    # GET /api/trending_topics
    def index
      topics = extract_trending_topics
      
      render json: {
        topics: topics,
        generated_at: Time.current.iso8601
      }
    end
    
    private
    
    # Extract trending topics from recent articles
    def extract_trending_topics
      # Get articles from last 7 days
      recent_articles = Article
        .joins(:ai_analysis)
        .where("articles.published_at >= ?", 7.days.ago)
        .where.not(ai_analysis: { geopolitical_topic: nil })
        .group("ai_analyses.geopolitical_topic")
        .order(count: :desc)
        .limit(10)
        .count(:all)
      
      # Assign colors based on topic patterns
      topic_colors = {
        'Ukraine' => '#3b82f6',
        'Russia' => '#ef4444',
        'China' => '#f59e0b',
        'Iran' => '#ef4444',
        'Israel' => '#3b82f6',
        'US Election' => '#6366f1',
        'NATO' => '#0ea5e9',
        'Taiwan' => '#f97316',
        'Climate' => '#22c55e'
      }
      
      topics = recent_articles.map do |topic, count|
        {
          keyword: topic || 'Geopolitics',
          count: count,
          color: topic_colors[topic] || '#38BDF8'
        }
      end
      
      # Fallback if no topics found
      if topics.empty?
        topics = [
          { keyword: 'Ukraine', count: 0, color: '#3b82f6' },
          { keyword: 'Russia', count: 0, color: '#ef4444' },
          { keyword: 'China', count: 0, color: '#f59e0b' },
          { keyword: 'Iran', count: 0, color: '#ef4444' },
          { keyword: 'Middle East', count: 0, color: '#f97316' }
        ]
      end
      
      topics
    end
  end
end