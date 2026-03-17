# GeolocatorService
# Determines the real geographic focus of an article using a 3-tier cascade:
#   Tier 1 — keyword matching on title + description
#   Tier 2 — source name mapping to known outlet countries
#   Tier 3 — unresolved fallback (nil coordinates, no DB assignment)
#
# Returns a hash with :country, :region, :latitude, :longitude, :target_country_id, :geo_method
# The :country and :region values are ActiveRecord objects or nil.

class GeolocatorService
  # ---------------------------------------------------------------------------
  # LOCATION KEYWORDS → geo data
  # Key: lowercase keyword (substring match allowed for city/landmark names)
  # Value: { country_name:, iso_code:, lat:, lng:, region_name: }
  # region_name must match one of the seeded Region names exactly (or close enough for ILIKE)
  # ---------------------------------------------------------------------------
  LOCATION_KEYWORDS = {
    # ── United States ──────────────────────────────────────────────────────
    "united states"   => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "washington dc"   => { country_name: "United States", iso_code: "USA", lat: 38.9072,  lng: -77.0369,  region_name: "North America" },
    "washington, dc"  => { country_name: "United States", iso_code: "USA", lat: 38.9072,  lng: -77.0369,  region_name: "North America" },
    "pentagon"        => { country_name: "United States", iso_code: "USA", lat: 38.8719,  lng: -77.0563,  region_name: "North America" },
    "white house"     => { country_name: "United States", iso_code: "USA", lat: 38.8977,  lng: -77.0365,  region_name: "North America" },
    "congress"        => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "u.s."            => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "american"        => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },

    # ── Canada ─────────────────────────────────────────────────────────────
    "canada"          => { country_name: "Canada", iso_code: "CAN", lat: 56.1304,  lng: -106.3468, region_name: "North America" },
    "ottawa"          => { country_name: "Canada", iso_code: "CAN", lat: 45.4215,  lng: -75.6972,  region_name: "North America" },

    # ── Mexico / Latin America ─────────────────────────────────────────────
    "mexico"          => { country_name: "Mexico", iso_code: "MEX", lat: 23.6345,  lng: -102.5528, region_name: "North America" },
    "brazil"          => { country_name: "Brazil", iso_code: "BRA", lat: -14.2350, lng: -51.9253,  region_name: "North America" },
    "venezuela"       => { country_name: "Venezuela", iso_code: "VEN", lat: 6.4238,  lng: -66.5897,  region_name: "North America" },
    "colombia"        => { country_name: "Colombia", iso_code: "COL", lat: 4.5709,  lng: -74.2973,  region_name: "North America" },
    "argentina"       => { country_name: "Argentina", iso_code: "ARG", lat: -38.4161, lng: -63.6167, region_name: "North America" },

    # ── United Kingdom ────────────────────────────────────────────────────
    "united kingdom"  => { country_name: "United Kingdom", iso_code: "GBR", lat: 55.3781,  lng: -3.4360,   region_name: "Western Europe" },
    "britain"         => { country_name: "United Kingdom", iso_code: "GBR", lat: 55.3781,  lng: -3.4360,   region_name: "Western Europe" },
    "british"         => { country_name: "United Kingdom", iso_code: "GBR", lat: 55.3781,  lng: -3.4360,   region_name: "Western Europe" },
    "london"          => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "downing street"  => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5034,  lng: -0.1276,   region_name: "Western Europe" },

    # ── Germany / Western Europe ─────────────────────────────────────────
    "germany"         => { country_name: "Germany", iso_code: "DEU", lat: 51.1657,  lng: 10.4515,   region_name: "Western Europe" },
    "german"          => { country_name: "Germany", iso_code: "DEU", lat: 51.1657,  lng: 10.4515,   region_name: "Western Europe" },
    "berlin"          => { country_name: "Germany", iso_code: "DEU", lat: 52.5200,  lng: 13.4050,   region_name: "Western Europe" },
    "france"          => { country_name: "France", iso_code: "FRA", lat: 46.2276,  lng: 2.2137,    region_name: "Western Europe" },
    "french"          => { country_name: "France", iso_code: "FRA", lat: 46.2276,  lng: 2.2137,    region_name: "Western Europe" },
    "paris"           => { country_name: "France", iso_code: "FRA", lat: 48.8566,  lng: 2.3522,    region_name: "Western Europe" },
    "elysee"          => { country_name: "France", iso_code: "FRA", lat: 48.8728,  lng: 2.3165,    region_name: "Western Europe" },
    "italy"           => { country_name: "Italy", iso_code: "ITA", lat: 41.8719,  lng: 12.5674,   region_name: "Western Europe" },
    "rome"            => { country_name: "Italy", iso_code: "ITA", lat: 41.9028,  lng: 12.4964,   region_name: "Western Europe" },
    "spain"           => { country_name: "Spain", iso_code: "ESP", lat: 40.4637,  lng: -3.7492,   region_name: "Western Europe" },
    "madrid"          => { country_name: "Spain", iso_code: "ESP", lat: 40.4168,  lng: -3.7038,   region_name: "Western Europe" },
    "netherlands"     => { country_name: "Netherlands", iso_code: "NLD", lat: 52.1326,  lng: 5.2913,    region_name: "Western Europe" },
    "sweden"          => { country_name: "Sweden", iso_code: "SWE", lat: 60.1282,  lng: 18.6435,   region_name: "Western Europe" },
    "finland"         => { country_name: "Finland", iso_code: "FIN", lat: 61.9241,  lng: 25.7482,   region_name: "Western Europe" },
    "poland"          => { country_name: "Poland", iso_code: "POL", lat: 51.9194,  lng: 19.1451,   region_name: "Eastern Europe" },
    "warsaw"          => { country_name: "Poland", iso_code: "POL", lat: 52.2297,  lng: 21.0122,   region_name: "Eastern Europe" },
    "brussels"        => { country_name: "Belgium", iso_code: "BEL", lat: 50.8503,  lng: 4.3517,    region_name: "Western Europe" },
    "nato"            => { country_name: "Belgium", iso_code: "BEL", lat: 50.8503,  lng: 4.3517,    region_name: "Western Europe" },
    "european union"  => { country_name: "Belgium", iso_code: "BEL", lat: 50.8503,  lng: 4.3517,    region_name: "Western Europe" },
    "eu summit"       => { country_name: "Belgium", iso_code: "BEL", lat: 50.8503,  lng: 4.3517,    region_name: "Western Europe" },

    # ── Russia / Eastern Europe ────────────────────────────────────────────
    "russia"          => { country_name: "Russia", iso_code: "RUS", lat: 61.5240,  lng: 105.3188,  region_name: "Eastern Europe" },
    "russian"         => { country_name: "Russia", iso_code: "RUS", lat: 61.5240,  lng: 105.3188,  region_name: "Eastern Europe" },
    "kremlin"         => { country_name: "Russia", iso_code: "RUS", lat: 55.7520,  lng: 37.6175,   region_name: "Eastern Europe" },
    "moscow"          => { country_name: "Russia", iso_code: "RUS", lat: 55.7558,  lng: 37.6173,   region_name: "Eastern Europe" },
    "putin"           => { country_name: "Russia", iso_code: "RUS", lat: 61.5240,  lng: 105.3188,  region_name: "Eastern Europe" },
    "ukraine"         => { country_name: "Ukraine", iso_code: "UKR", lat: 48.3794,  lng: 31.1656,   region_name: "Eastern Europe" },
    "ukrainian"       => { country_name: "Ukraine", iso_code: "UKR", lat: 48.3794,  lng: 31.1656,   region_name: "Eastern Europe" },
    "kyiv"            => { country_name: "Ukraine", iso_code: "UKR", lat: 50.4501,  lng: 30.5234,   region_name: "Eastern Europe" },
    "zelensky"        => { country_name: "Ukraine", iso_code: "UKR", lat: 48.3794,  lng: 31.1656,   region_name: "Eastern Europe" },
    "belarus"         => { country_name: "Belarus", iso_code: "BLR", lat: 53.7098,  lng: 27.9534,   region_name: "Eastern Europe" },
    "minsk"           => { country_name: "Belarus", iso_code: "BLR", lat: 53.9045,  lng: 27.5615,   region_name: "Eastern Europe" },
    "serbia"          => { country_name: "Serbia", iso_code: "SRB", lat: 44.0165,  lng: 21.0059,   region_name: "Eastern Europe" },
    "balkans"         => { country_name: "Serbia", iso_code: "SRB", lat: 44.0165,  lng: 21.0059,   region_name: "Eastern Europe" },

    # ── China / East Asia ──────────────────────────────────────────────────
    "china"           => { country_name: "China", iso_code: "CHN", lat: 35.8617,  lng: 104.1954,  region_name: "East Asia" },
    "chinese"         => { country_name: "China", iso_code: "CHN", lat: 35.8617,  lng: 104.1954,  region_name: "East Asia" },
    "beijing"         => { country_name: "China", iso_code: "CHN", lat: 39.9042,  lng: 116.4074,  region_name: "East Asia" },
    "xi jinping"      => { country_name: "China", iso_code: "CHN", lat: 35.8617,  lng: 104.1954,  region_name: "East Asia" },
    "shanghai"        => { country_name: "China", iso_code: "CHN", lat: 31.2304,  lng: 121.4737,  region_name: "East Asia" },
    "taiwan"          => { country_name: "Taiwan", iso_code: "TWN", lat: 23.6978,  lng: 120.9605,  region_name: "East Asia" },
    "taipei"          => { country_name: "Taiwan", iso_code: "TWN", lat: 25.0330,  lng: 121.5654,  region_name: "East Asia" },
    "hong kong"       => { country_name: "Hong Kong", iso_code: "HKG", lat: 22.3193,  lng: 114.1694,  region_name: "East Asia" },
    "south china sea" => { country_name: "China", iso_code: "CHN", lat: 15.0000,  lng: 115.0000,  region_name: "East Asia" },
    "japan"           => { country_name: "Japan", iso_code: "JPN", lat: 36.2048,  lng: 138.2529,  region_name: "East Asia" },
    "japanese"        => { country_name: "Japan", iso_code: "JPN", lat: 36.2048,  lng: 138.2529,  region_name: "East Asia" },
    "tokyo"           => { country_name: "Japan", iso_code: "JPN", lat: 35.6762,  lng: 139.6503,  region_name: "East Asia" },
    "south korea"     => { country_name: "South Korea", iso_code: "KOR", lat: 35.9078,  lng: 127.7669,  region_name: "East Asia" },
    "seoul"           => { country_name: "South Korea", iso_code: "KOR", lat: 37.5665,  lng: 126.9780,  region_name: "East Asia" },
    "north korea"     => { country_name: "North Korea", iso_code: "PRK", lat: 40.3399,  lng: 127.5101,  region_name: "East Asia" },
    "pyongyang"       => { country_name: "North Korea", iso_code: "PRK", lat: 39.0392,  lng: 125.7625,  region_name: "East Asia" },
    "kim jong"        => { country_name: "North Korea", iso_code: "PRK", lat: 40.3399,  lng: 127.5101,  region_name: "East Asia" },

    # ── South / Southeast Asia ─────────────────────────────────────────────
    "india"           => { country_name: "India", iso_code: "IND", lat: 20.5937,  lng: 78.9629,   region_name: "East Asia" },
    "indian"          => { country_name: "India", iso_code: "IND", lat: 20.5937,  lng: 78.9629,   region_name: "East Asia" },
    "new delhi"       => { country_name: "India", iso_code: "IND", lat: 28.6139,  lng: 77.2090,   region_name: "East Asia" },
    "pakistan"        => { country_name: "Pakistan", iso_code: "PAK", lat: 30.3753,  lng: 69.3451,   region_name: "East Asia" },
    "islamabad"       => { country_name: "Pakistan", iso_code: "PAK", lat: 33.6844,  lng: 73.0479,   region_name: "East Asia" },
    "myanmar"         => { country_name: "Myanmar", iso_code: "MMR", lat: 21.9162,  lng: 95.9560,   region_name: "East Asia" },
    "afghanistan"     => { country_name: "Afghanistan", iso_code: "AFG", lat: 33.9391,  lng: 67.7100,   region_name: "Middle East" },
    "kabul"           => { country_name: "Afghanistan", iso_code: "AFG", lat: 34.5553,  lng: 69.2075,   region_name: "Middle East" },
    "indonesia"       => { country_name: "Indonesia", iso_code: "IDN", lat: -0.7893,  lng: 113.9213,  region_name: "East Asia" },
    "philippines"     => { country_name: "Philippines", iso_code: "PHL", lat: 12.8797,  lng: 121.7740,  region_name: "East Asia" },

    # ── Middle East ────────────────────────────────────────────────────────
    "israel"          => { country_name: "Israel", iso_code: "ISR", lat: 31.0461,  lng: 34.8516,   region_name: "Middle East" },
    "israeli"         => { country_name: "Israel", iso_code: "ISR", lat: 31.0461,  lng: 34.8516,   region_name: "Middle East" },
    "tel aviv"        => { country_name: "Israel", iso_code: "ISR", lat: 32.0853,  lng: 34.7818,   region_name: "Middle East" },
    "gaza"            => { country_name: "Palestine", iso_code: "PSE", lat: 31.3547,  lng: 34.3088,   region_name: "Middle East" },
    "west bank"       => { country_name: "Palestine", iso_code: "PSE", lat: 31.9522,  lng: 35.2332,   region_name: "Middle East" },
    "palestine"       => { country_name: "Palestine", iso_code: "PSE", lat: 31.9522,  lng: 35.2332,   region_name: "Middle East" },
    "hamas"           => { country_name: "Palestine", iso_code: "PSE", lat: 31.3547,  lng: 34.3088,   region_name: "Middle East" },
    "hezbollah"       => { country_name: "Lebanon", iso_code: "LBN", lat: 33.8547,  lng: 35.8623,   region_name: "Middle East" },
    "lebanon"         => { country_name: "Lebanon", iso_code: "LBN", lat: 33.8547,  lng: 35.8623,   region_name: "Middle East" },
    "beirut"          => { country_name: "Lebanon", iso_code: "LBN", lat: 33.8886,  lng: 35.4955,   region_name: "Middle East" },
    "iran"            => { country_name: "Iran", iso_code: "IRN", lat: 32.4279,  lng: 53.6880,   region_name: "Middle East" },
    "iranian"         => { country_name: "Iran", iso_code: "IRN", lat: 32.4279,  lng: 53.6880,   region_name: "Middle East" },
    "tehran"          => { country_name: "Iran", iso_code: "IRN", lat: 35.6892,  lng: 51.3890,   region_name: "Middle East" },
    "irgc"            => { country_name: "Iran", iso_code: "IRN", lat: 32.4279,  lng: 53.6880,   region_name: "Middle East" },
    "iraq"            => { country_name: "Iraq", iso_code: "IRQ", lat: 33.2232,  lng: 43.6793,   region_name: "Middle East" },
    "baghdad"         => { country_name: "Iraq", iso_code: "IRQ", lat: 33.3152,  lng: 44.3661,   region_name: "Middle East" },
    "syria"           => { country_name: "Syria", iso_code: "SYR", lat: 34.8021,  lng: 38.9968,   region_name: "Middle East" },
    "damascus"        => { country_name: "Syria", iso_code: "SYR", lat: 33.5138,  lng: 36.2765,   region_name: "Middle East" },
    "saudi arabia"    => { country_name: "Saudi Arabia", iso_code: "SAU", lat: 23.8859,  lng: 45.0792,   region_name: "Middle East" },
    "riyadh"          => { country_name: "Saudi Arabia", iso_code: "SAU", lat: 24.7136,  lng: 46.6753,   region_name: "Middle East" },
    "houthis"         => { country_name: "Yemen", iso_code: "YEM", lat: 15.5527,  lng: 48.5164,   region_name: "Middle East" },
    "yemen"           => { country_name: "Yemen", iso_code: "YEM", lat: 15.5527,  lng: 48.5164,   region_name: "Middle East" },
    "turkey"          => { country_name: "Turkey", iso_code: "TUR", lat: 38.9637,  lng: 35.2433,   region_name: "Middle East" },
    "ankara"          => { country_name: "Turkey", iso_code: "TUR", lat: 39.9334,  lng: 32.8597,   region_name: "Middle East" },
    "erdogan"         => { country_name: "Turkey", iso_code: "TUR", lat: 38.9637,  lng: 35.2433,   region_name: "Middle East" },
    "qatar"           => { country_name: "Qatar", iso_code: "QAT", lat: 25.3548,  lng: 51.1839,   region_name: "Middle East" },
    "doha"            => { country_name: "Qatar", iso_code: "QAT", lat: 25.2854,  lng: 51.5310,   region_name: "Middle East" },
    "uae"             => { country_name: "UAE", iso_code: "ARE", lat: 23.4241,  lng: 53.8478,   region_name: "Middle East" },
    "dubai"           => { country_name: "UAE", iso_code: "ARE", lat: 25.2048,  lng: 55.2708,   region_name: "Middle East" },
    "abu dhabi"       => { country_name: "UAE", iso_code: "ARE", lat: 24.4539,  lng: 54.3773,   region_name: "Middle East" },
    "sudan"           => { country_name: "Sudan", iso_code: "SDN", lat: 12.8628,  lng: 30.2176,   region_name: "Middle East" },
    "khartoum"        => { country_name: "Sudan", iso_code: "SDN", lat: 15.5007,  lng: 32.5599,   region_name: "Middle East" },

    # ── Africa ─────────────────────────────────────────────────────────────
    "south africa"    => { country_name: "South Africa", iso_code: "ZAF", lat: -30.5595, lng: 22.9375,   region_name: "Middle East" },
    "nigeria"         => { country_name: "Nigeria", iso_code: "NGA", lat: 9.0820,   lng: 8.6753,    region_name: "Middle East" },
    "ethiopia"        => { country_name: "Ethiopia", iso_code: "ETH", lat: 9.1450,   lng: 40.4897,   region_name: "Middle East" },
    "somalia"         => { country_name: "Somalia", iso_code: "SOM", lat: 5.1521,   lng: 46.1996,   region_name: "Middle East" },
    "libya"           => { country_name: "Libya", iso_code: "LBY", lat: 26.3351,  lng: 17.2283,   region_name: "Middle East" },
    "egypt"           => { country_name: "Egypt", iso_code: "EGY", lat: 26.8206,  lng: 30.8025,   region_name: "Middle East" },
    "cairo"           => { country_name: "Egypt", iso_code: "EGY", lat: 30.0444,  lng: 31.2357,   region_name: "Middle East" },

    # ── UN / supranational ──────────────────────────────────────────────────
    "united nations"  => { country_name: "United States", iso_code: "USA", lat: 40.7489,  lng: -73.9680,  region_name: "North America" },
    "imf"             => { country_name: "United States", iso_code: "USA", lat: 38.8990,  lng: -77.0426,  region_name: "North America" },
    "world bank"      => { country_name: "United States", iso_code: "USA", lat: 38.8990,  lng: -77.0426,  region_name: "North America" },
    "g7"              => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "g20"             => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
  }.freeze

  # ---------------------------------------------------------------------------
  # SOURCE → country (fallback when keyword matching fails)
  # ---------------------------------------------------------------------------
  SOURCE_COUNTRY_MAP = {
    "reuters"                => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "bbc"                    => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "the guardian"           => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "financial times"        => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "the economist"          => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "sky news"               => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "cnn"                    => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "fox news"               => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "new york times"         => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "washington post"        => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "bloomberg"              => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "associated press"       => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "ap news"                => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "npr"                    => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "msnbc"                  => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "politico"               => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "breitbart"              => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "axios"                  => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "the hill"               => { country_name: "United States", iso_code: "USA", lat: 37.0902,  lng: -95.7129,  region_name: "North America" },
    "rt"                     => { country_name: "Russia", iso_code: "RUS", lat: 55.7558,  lng: 37.6173,   region_name: "Eastern Europe" },
    "russia today"           => { country_name: "Russia", iso_code: "RUS", lat: 55.7558,  lng: 37.6173,   region_name: "Eastern Europe" },
    "tass"                   => { country_name: "Russia", iso_code: "RUS", lat: 55.7558,  lng: 37.6173,   region_name: "Eastern Europe" },
    "sputnik"                => { country_name: "Russia", iso_code: "RUS", lat: 55.7558,  lng: 37.6173,   region_name: "Eastern Europe" },
    "ria novosti"            => { country_name: "Russia", iso_code: "RUS", lat: 55.7558,  lng: 37.6173,   region_name: "Eastern Europe" },
    "xinhua"                 => { country_name: "China", iso_code: "CHN", lat: 39.9042,  lng: 116.4074,  region_name: "East Asia" },
    "global times"           => { country_name: "China", iso_code: "CHN", lat: 39.9042,  lng: 116.4074,  region_name: "East Asia" },
    "cgtn"                   => { country_name: "China", iso_code: "CHN", lat: 39.9042,  lng: 116.4074,  region_name: "East Asia" },
    "china daily"            => { country_name: "China", iso_code: "CHN", lat: 39.9042,  lng: 116.4074,  region_name: "East Asia" },
    "people's daily"         => { country_name: "China", iso_code: "CHN", lat: 39.9042,  lng: 116.4074,  region_name: "East Asia" },
    "south china morning"    => { country_name: "Hong Kong", iso_code: "HKG", lat: 22.3193,  lng: 114.1694,  region_name: "East Asia" },
    "al jazeera"             => { country_name: "Qatar", iso_code: "QAT", lat: 25.2854,  lng: 51.5310,   region_name: "Middle East" },
    "arab news"              => { country_name: "Saudi Arabia", iso_code: "SAU", lat: 24.7136,  lng: 46.6753,   region_name: "Middle East" },
    "middle east eye"        => { country_name: "United Kingdom", iso_code: "GBR", lat: 51.5074,  lng: -0.1278,   region_name: "Western Europe" },
    "afp"                    => { country_name: "France", iso_code: "FRA", lat: 48.8566,  lng: 2.3522,    region_name: "Western Europe" },
    "le monde"               => { country_name: "France", iso_code: "FRA", lat: 48.8566,  lng: 2.3522,    region_name: "Western Europe" },
    "der spiegel"            => { country_name: "Germany", iso_code: "DEU", lat: 52.5200,  lng: 13.4050,   region_name: "Western Europe" },
    "nhk"                    => { country_name: "Japan", iso_code: "JPN", lat: 35.6762,  lng: 139.6503,  region_name: "East Asia" },
    "yonhap"                 => { country_name: "South Korea", iso_code: "KOR", lat: 37.5665,  lng: 126.9780,  region_name: "East Asia" },
    "dawn"                   => { country_name: "Pakistan", iso_code: "PAK", lat: 33.6844,  lng: 73.0479,   region_name: "East Asia" },
    "the hindu"              => { country_name: "India", iso_code: "IND", lat: 28.6139,  lng: 77.2090,   region_name: "East Asia" },
    "times of india"         => { country_name: "India", iso_code: "IND", lat: 28.6139,  lng: 77.2090,   region_name: "East Asia" },
    "haaretz"                => { country_name: "Israel", iso_code: "ISR", lat: 32.0853,  lng: 34.7818,   region_name: "Middle East" },
    "jerusalem post"         => { country_name: "Israel", iso_code: "ISR", lat: 32.0853,  lng: 34.7818,   region_name: "Middle East" },
  }.freeze

  def self.call(article_attrs)
    new(article_attrs).call
  end

  def initialize(article_attrs)
    # Accept both a raw NewsAPI item hash and a prepared attrs hash
    if article_attrs.key?("title") || article_attrs.key?(:title)
      # Raw NewsAPI response item
      @title       = (article_attrs["title"]       || article_attrs[:title]       || "").to_s
      @description = (article_attrs["description"] || article_attrs[:description] || "").to_s
      @source_name = (article_attrs.dig("source", "name") || article_attrs[:source_name] || "").to_s
    else
      @title       = (article_attrs[:headline] || "").to_s
      @description = (article_attrs.dig(:raw_data, "description") || "").to_s
      @source_name = (article_attrs[:source_name] || "").to_s
    end
  end

  def call
    result = keyword_match || source_match || unresolved_result

    country = find_or_nearest_country(result)
    region  = country&.region || find_nearest_region(result)

    result.merge(country: country, region: region)
  end

  private

  # ---------------------------------------------------------------------------
  # Tier 1 — Keyword matching
  # Strategy: find all keyword matches in title, pick the LAST one (= geographic
  # subject, not the actor). If title has no matches, fall through to description.
  # ---------------------------------------------------------------------------
  def keyword_match
    title_match = find_last_match_in(@title)
    return geo_result(title_match, "keyword") if title_match

    desc_match = find_last_match_in(@description)
    return geo_result(desc_match, "keyword") if desc_match

    nil
  end

  def find_last_match_in(text)
    return nil if text.blank?

    downcased = text.downcase
    last_match = nil
    last_position = -1

    LOCATION_KEYWORDS.each do |keyword, data|
      idx = downcased.rindex(keyword)  # rindex = last occurrence
      next if idx.nil?

      if idx > last_position
        last_position = idx
        last_match = data
      end
    end

    last_match
  end

  # ---------------------------------------------------------------------------
  # Tier 2 — Source name fallback
  # ---------------------------------------------------------------------------
  def source_match
    return nil if @source_name.blank?

    downcased = @source_name.downcase
    match = SOURCE_COUNTRY_MAP.find { |key, _| downcased.include?(key) }
    return nil unless match

    geo_result(match[1], "source_fallback")
  end

  # ---------------------------------------------------------------------------
  # Tier 3 — Unresolved
  # ---------------------------------------------------------------------------
  def unresolved_result
    { country_name: "Unknown", iso_code: nil, latitude: nil, longitude: nil,
      region_name: "Unknown", geo_method: "unresolved",
      country: nil, region: nil, target_country_id: nil }
  end

  def geo_result(data, method)
    { country_name: data[:country_name], iso_code: data[:iso_code],
      latitude: data[:lat], longitude: data[:lng],
      region_name: data[:region_name], geo_method: method,
      target_country_id: nil }
  end

  # ---------------------------------------------------------------------------
  # DB linkage — find Country + Region by name/iso, fall back to nearest region
  # ---------------------------------------------------------------------------
  def find_or_nearest_country(result)
    return nil if result[:iso_code].blank?

    Country.where(iso_code: result[:iso_code]).first ||
      Country.where("LOWER(name) = ?", result[:country_name].to_s.downcase).first
  end

  def find_nearest_region(result)
    return nil if result[:latitude].nil? || result[:longitude].nil?

    regions = Region.all.to_a
    return nil if regions.empty?

    regions.min_by do |r|
      haversine(result[:latitude], result[:longitude], r.latitude, r.longitude)
    end
  end

  def haversine(lat1, lon1, lat2, lon2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad
    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2
    2 * Math.asin(Math.sqrt(a))
  end
end
