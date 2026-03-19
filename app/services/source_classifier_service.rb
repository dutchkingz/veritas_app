# SourceClassifierService
#
# Maps article source names to one of the 6 VERITAS perspective slugs.
# Used to tag globe points/arcs with their perspective identity so the
# frontend can dim non-active-perspective content without server round-trips.
#
# Usage:
#   SourceClassifierService.classify("CNN International")
#   # => { slug: "us_liberal", confidence: "fuzzy_match" }
#
#   SourceClassifierService.sources_for("china_state")
#   # => ["xinhua", "global times", ...]

class SourceClassifierService
  PERSPECTIVE_SLUGS = %w[
    western_mainstream us_liberal us_conservative
    china_state russia_state global_south
  ].freeze

  # Each entry: [slug, [exact_patterns], [fuzzy_patterns]]
  # exact_patterns  — full source name (downcased), matched with ==
  # fuzzy_patterns  — substrings checked with String#include? in both directions
  MAPPINGS = [
    [
      "western_mainstream",
      ["reuters", "afp", "ap news", "associated press", "bbc", "bbc news", "bbc world",
       "france 24", "france24", "deutsche welle", "dw", "nhk", "nhk world",
       "abc australia", "abc news australia", "bloomberg", "financial times",
       "the economist", "wall street journal", "wsj"],
      ["reuters", "afp", "bbc", "france 24", "france24", "deutsche welle",
       "associated press", "nhk", "bloomberg", "financial times", "economist",
       "wall street journal"]
    ],
    [
      "us_liberal",
      ["cnn", "msnbc", "npr", "new york times", "the new york times",
       "washington post", "the washington post", "the guardian", "guardian us",
       "vox", "huffpost", "huffington post", "the atlantic", "politico",
       "the new yorker", "mother jones", "daily beast", "salon", "slate",
       "the intercept", "propublica", "time magazine", "time"],
      ["cnn", "msnbc", "npr ", "new york times", "washington post",
       "the guardian", "huffpost", "huffington", "politico", "the atlantic",
       "mother jones", "daily beast"]
    ],
    [
      "us_conservative",
      ["fox news", "foxnews", "fox business", "the daily wire", "daily wire",
       "breitbart", "new york post", "nypost", "daily caller", "the daily caller",
       "newsmax", "the federalist", "washington times", "epoch times",
       "one america news", "oann", "national review", "the blaze", "blaze media",
       "townhall", "american thinker", "western journal"],
      ["fox news", "foxnews", "fox business", "breitbart", "daily wire",
       "new york post", "daily caller", "newsmax", "the federalist",
       "washington times", "epoch times", "one america", "national review"]
    ],
    [
      "china_state",
      ["xinhua", "global times", "cgtn", "cctv", "people's daily", "peoples daily",
       "china daily", "china news service", "south china morning post", "scmp",
       "caixin", "caixin global", "china news", "china media group"],
      ["xinhua", "global times", "cgtn", "cctv", "people's daily", "peoples daily",
       "china daily", "south china morning post", "caixin"]
    ],
    [
      "russia_state",
      ["rt", "rt news", "russia today", "tass", "sputnik", "sputnik news",
       "ria novosti", "izvestia", "pravda", "rossiyskaya gazeta",
       "itar-tass", "russia-1", "first channel russia", "novaya gazeta"],
      ["tass", "sputnik", "ria novosti", "izvestia", "pravda",
       "russia today", "rossiyskaya", "itar-tass", "novaya gazeta"]
    ],
    [
      "global_south",
      ["al jazeera", "al-jazeera", "trt world", "trt", "anadolu agency",
       "press tv", "presstv", "wion", "times of india", "the hindu",
       "hindustan times", "daily maverick", "nation africa", "daily nation",
       "mail & guardian", "mail and guardian", "arab news", "middle east eye",
       "telesur", "dawn", "dawn pakistan", "the dawn", "deccan herald",
       "indian express", "ndtv", "the wire india", "scroll.in",
       "africa news", "the east african", "business day", "citizen digital",
       "cna", "channel newsasia", "the star online", "new straits times",
       "bangkok post", "vietnam news", "jakarta post", "philippine daily inquirer"],
      ["al jazeera", "al-jazeera", "trt world", "anadolu", "press tv",
       "wion", "times of india", "the hindu", "daily maverick",
       "nation africa", "arab news", "middle east eye", "telesur",
       "dawn", "deccan herald", "ndtv", "channel newsasia", "bangkok post",
       "jakarta post", "vietnam news"]
    ]
  ].freeze

  # Classify a source name.
  # Returns: { slug: String, confidence: "exact_match" | "fuzzy_match" | "unclassified" }
  def self.classify(source_name)
    return { slug: "unclassified", confidence: "unclassified" } if source_name.blank?

    normalized = source_name.downcase.strip

    # Short-string exact overrides must run BEFORE the fuzzy loop, because short
    # strings like "rt" (2 chars) accidentally match as substrings of longer fuzzy
    # patterns (e.g. "breitbart".include?("rt") => true → wrong us_conservative hit).
    return { slug: "russia_state", confidence: "exact_match" } if normalized == "rt" || normalized == "rt news"

    MAPPINGS.each do |slug, exact_patterns, fuzzy_patterns|
      # 1. Exact match
      return { slug: slug, confidence: "exact_match" } if exact_patterns.include?(normalized)

      # 2. Fuzzy: pattern inside source_name OR source_name inside pattern
      # Guard: skip reverse-direction check for very short normalized strings (< 4 chars)
      # to prevent accidental substring hits (e.g. "rt" inside "breitbart").
      fuzzy_patterns.each do |pattern|
        forward  = normalized.include?(pattern)
        backward = normalized.length >= 4 && pattern.include?(normalized)
        return { slug: slug, confidence: "fuzzy_match" } if forward || backward
      end
    end

    { slug: "unclassified", confidence: "unclassified" }
  end

  # Returns the full mapping hash: slug => array of canonical source names
  def self.all_mappings
    MAPPINGS.each_with_object({}) do |(slug, exact, _fuzzy), hash|
      hash[slug] = exact
    end
  end

  # Returns canonical source names for a given slug
  def self.sources_for(slug)
    mapping = MAPPINGS.find { |s, _, _| s == slug }
    mapping ? mapping[1] : []
  end

  # Returns the display label for a slug
  def self.display_name(slug)
    {
      "western_mainstream" => "Western Mainstream",
      "us_liberal"         => "US Liberal",
      "us_conservative"    => "US Conservative",
      "china_state"        => "China State",
      "russia_state"       => "Russia State",
      "global_south"       => "Global South",
      "unclassified"       => "Other"
    }[slug] || slug.humanize
  end
end
