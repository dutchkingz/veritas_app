# lib/tasks/embeddings.rake
namespace :veritas do
  namespace :embeddings do
    desc "Generate embeddings for all articles that don't have them"
    task generate_all: :environment do
      articles_without_embedding = Article.where(embedding: nil)
                                          .where.not(content: nil)
                                          .includes(:ai_analysis)
      
      total = articles_without_embedding.count
      puts "🦞 Found #{total} articles without embeddings"
      
      if total.zero?
        puts "✅ All articles already have embeddings!"
        return
      end
      
      service = EmbeddingService.new
      successes = 0
      failures = 0
      
      articles_without_embedding.find_each(batch_size: 10).with_index do |article, index|
        puts "[#{index + 1}/#{total}] Processing Article ##{article.id}: #{article.headline}"
        
        begin
          if service.generate(article)
            successes += 1
            puts "  ✅ Embedding generated"
          else
            failures += 1
            puts "  ⚠️  Failed to generate embedding"
          end
        rescue => e
          failures += 1
          puts "  ❌ Error: #{e.message}"
        end
        
        # Small delay to avoid rate limiting
        sleep 0.5 if index % 10 == 0
      end
      
      puts "\n🎯 Summary:"
      puts "  ✅ Successes: #{successes}"
      puts "  ❌ Failures: #{failures}"
      puts "  📊 New total with embeddings: #{Article.where.not(embedding: nil).count}/#{Article.count}"
    end
    
    desc "Re-embed all articles (force regenerate)"
    task regenerate_all: :environment do
      total = Article.count
      puts "🦞 Re-embedding all #{total} articles..."
      
      service = EmbeddingService.new
      successes = 0
      failures = 0
      
      Article.includes(:ai_analysis).find_each(batch_size: 10).with_index do |article, index|
        puts "[#{index + 1}/#{total}] Re-embedding Article ##{article.id}: #{article.headline}"
        
        begin
          # Clear existing embedding
          article.update_column(:embedding, nil) if article.embedding.present?
          
          if service.generate(article)
            successes += 1
            puts "  ✅ Embedding regenerated"
          else
            failures += 1
            puts "  ⚠️  Failed to regenerate embedding"
          end
        rescue => e
          failures += 1
          puts "  ❌ Error: #{e.message}"
        end
        
        sleep 0.5 if index % 10 == 0
      end
      
      puts "\n🎯 Summary:"
      puts "  ✅ Successes: #{successes}"
      puts "  ❌ Failures: #{failures}"
    end
    
    desc "Show embedding statistics"
    task stats: :environment do
      total = Article.count
      with_emb = Article.where.not(embedding: nil).count
      without_emb = Article.where(embedding: nil).count
      
      puts "📊 Embedding Statistics:"
      puts "  Total articles: #{total}"
      puts "  With embeddings: #{with_emb} (#{(with_emb.to_f / total * 100).round(1)}%)"
      puts "  Without embeddings: #{without_emb}"
      
      # Show sample of articles without embeddings
      if without_emb > 0
        puts "\n📝 Sample articles without embeddings:"
        Article.where(embedding: nil).limit(5).each do |article|
          puts "  ##{article.id}: #{article.headline} (#{article.source_name})"
        end
      end
    end
    
    desc "Generate embedding for a specific article ID"
    task :generate, [:article_id] => :environment do |_t, args|
      article = Article.find(args[:article_id])
      puts "🦞 Generating embedding for Article ##{article.id}: #{article.headline}"
      
      service = EmbeddingService.new
      if service.generate(article)
        puts "✅ Embedding generated successfully"
      else
        puts "❌ Failed to generate embedding"
      end
    end
    
    desc "Ensure new searches trigger embedding generation"
    task ensure_search_triggers_embedding: :environment do
      puts "🦞 Checking search embedding triggers..."
      
      # Check PagesController#globe_data
      controller_path = Rails.root.join('app/controllers/pages_controller.rb')
      if File.exist?(controller_path)
        content = File.read(controller_path)
        
        if content.include?('search_query') && content.include?('OpenRouterClient.new.embed')
          puts "✅ PagesController#globe_data already embeds search queries"
        else
          puts "⚠️  PagesController#globe_data may not embed search queries"
        end
      end
      
      # Check if we have a background job for async embedding
      job_path = Rails.root.join('app/jobs/generate_embedding_job.rb')
      if File.exist?(job_path)
        puts "✅ GenerateEmbeddingJob exists for async processing"
      else
        puts "⚠️  No async embedding job found"
      end
    end
  end
end