require 'net/http'
require 'uri'

namespace :veritas do
  namespace :images do
    desc "Backfill article_images for all articles that have a source_url but no images yet"
    task backfill: :environment do
      scope = Article.where("article_images = '[]'::jsonb").where.not(source_url: [nil, ''])
      total = scope.count

      puts "Found #{total} articles to backfill."
      puts "This will fetch each article URL — expected time: ~#{(total * 1.5 / 60).ceil} mins.\n\n"

      success = 0
      skipped = 0
      failed  = 0

      scope.find_each.with_index(1) do |article, i|
        print "[#{i}/#{total}] #{article.headline.truncate(60)} ... "

        begin
          html = fetch_html(article.source_url)

          unless html
            puts "SKIP (no HTML)"
            skipped += 1
            next
          end

          images = ArticleImageExtractor.new(html, article.source_url).extract
          article.update_column(:article_images, images)

          puts "OK (#{images.size} images)"
          success += 1
        rescue => e
          puts "ERROR — #{e.message}"
          failed += 1
        end

        sleep 0.5   # be polite to external servers
      end

      puts "\n━━━ Backfill complete ━━━"
      puts "  ✅ Success : #{success}"
      puts "  ⏭  Skipped : #{skipped}"
      puts "  ❌ Failed  : #{failed}"
      puts "  📊 Articles with images: #{Article.where("article_images != '[]'::jsonb").count}/#{Article.count}"
    end

    desc "Show image extraction stats"
    task stats: :environment do
      total    = Article.count
      with_img = Article.where("article_images != '[]'::jsonb").count
      puts "Articles with images : #{with_img}/#{total}"
      puts "Articles without     : #{total - with_img}"
    end
  end
end

def fetch_html(url, timeout: 10)
  uri  = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl      = uri.scheme == 'https'
  http.open_timeout = timeout
  http.read_timeout = timeout

  req = Net::HTTP::Get.new(uri)
  req['User-Agent']      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
  req['Accept']          = 'text/html,application/xhtml+xml'
  req['Accept-Language'] = 'en-US,en;q=0.5'

  res = http.request(req)
  res.code == '200' ? res.body : nil
rescue
  nil
end
