Architecture
  VERITAS is currently a server-rendered Rails 8 app with a fairly clear intelligence pipeline behind the neon dashboard veneer.

  - Entry/UI layer: the main dashboard is home.html.erb:1 driven by PagesController:1. It shows a live-feed style article list, region-level report triggers, and the floating RAG chat mounted globally from application layout.
  - Request/auth layer: all controllers inherit global authentication from ApplicationController:5, so despite route comments calling some resources “public,” the app currently behaves as a logged-in experience by default.
  - Core domain: the main entities are Article:1, AiAnalysis:1, NarrativeConvergence:1, IntelligenceReport:1, Briefing:1, SavedArticle:1, PerspectiveFilter:1, plus geographic Region:1 and Country:1.
  - AI analysis flow: article analysis is kicked off from ArticlesController#show:21, enqueued in AnalyzeArticleJob:1, then processed by AnalysisPipeline:1 using AnalystAgent:1, SentinelAgent:1, ArbiterAgent:1, and finally EmbeddingService:1.
  - Semantic/RAG layer: vector search is used in PagesController#search:7, related-article and contradiction discovery in ArticlesController:9, watchlist matching in SavedArticlesController:36, and the RAG assistant in ChatsController:1 through RagAgent:1.
  - Reporting layer: region-triggered intelligence dossiers are created in IntelligenceReportsController:10, processed by RegionalAnalysisJob:1 and RegionalAnalysisService:14, then polled from the browser by analysis_progress_controller.js:1.
  - Convergence/briefing layer: cluster detection lives in NarrativeConvergenceService:1 and scheduled dossier generation for users lives in BriefingService:1.
  - Persistence: PostgreSQL stores classic Rails records plus pgvector embeddings in db/schema.rb:1; Solid Queue tables are already installed there too.

  Review Findings

  - High: the article reader path is an SSRF and stored-XSS surface. ArticlesController:33 fetches arbitrary source_url server-side and stores third-party HTML into article.content, and articles/show.html.erb:105 renders it via raw. If a malicious or compromised source
    URL enters the DB, the server can be coerced into fetching internal targets and then persisting executable HTML/JS for users.
  - High: the intelligence dossier page renders model output as unsanitized HTML. intelligence_reports/show.html.erb:71 loads marked from a CDN and writes marked.parse(rawText) directly into innerHTML. Since @report.summary comes from LLM output in
    RegionalAnalysisService:50, prompt injection or hostile source text can become client-side script execution.
  - High: the RAG chat UI also trusts model output as HTML. In shared/_chat_interface.html.erb:281, data.response is converted and assigned with innerHTML, and the helper in the same file builds HTML with no sanitization. That gives you another model-to-DOM XSS path.
  - High: the route surface advertises controllers that do not exist. config/routes.rb:14 declares public resources for ai_analyses, narrative_arcs, regions, countries, and perspective_filters, and config/routes.rb:46 declares multiple admin resources, but the repo only
    contains admin/users_controller.rb:1 plus a handful of non-admin controllers. Hitting those routes will fail at runtime.
  - Medium: the “regional analysis” controls are visible to everyone but only work for admins. The button is rendered for every region in home.html.erb:128, while report creation and status polling are admin-only in IntelligenceReportsController:12. In
    analysis_progress_controller.js:40, a 403 leaves the button disabled and the UI in a fake failed state. That is a broken user path, not just a permission restriction.
  - Medium: the app’s auth behavior conflicts with its own route/docs framing. ApplicationController:6 forces authentication everywhere, but config/routes.rb:12 labels several resources as public/read-only and the product description reads like a browsable intelligence
    platform. If that lock-down is intentional, the route comments and UX are misleading; if not, core product access is wrong.
  - Medium: duplicate analysis work is likely under concurrent access. AnalyzeArticleJob:7 skips only when status is already complete, while AnalysisPipeline:11 marks the record as analyzing. Multiple quick requests to the same article can enqueue duplicate expensive LLM
    jobs before the first one finishes.
  - Medium: internal exception details are exposed to end users in search. PagesController:28 pushes e.message into flash.now[:alert]. Since upstream errors include vendor response bodies in OpenRouterClient:46, users can see raw API failures and internal operational
    details.
  - Low: saved articles can be duplicated indefinitely. SavedArticlesController#create:12 always builds a new record, and the schema has no uniqueness guard on user_id/article_id in db/schema.rb:271. That will pollute the watchlist signal set and degrade relevance.
  - Low: the most important logic is effectively untested. The test tree in test has model tests and one pages controller test, but none for RagAgent, AnalysisPipeline, RegionalAnalysisService, NarrativeConvergenceService, IntelligenceReportsController, or the admin
    flows. The riskiest code paths are therefore unguarded.

  Notes

  - The “triad” pipeline is described as parallel in comments, but AnalysisPipeline:16 is fully sequential. That is not a bug by itself, but it means latency and cost are higher than the naming suggests.
  - A lot of business logic is currently living in controllers and ERB, especially ArticlesController:6 and the large inline-script partial shared/_chat_interface.html.erb:139. Moving that into services/Stimulus components would make the platform easier to harden and
    test.
  - The perspective feature is partially real already through PerspectiveFilter:1 and RagAgent:10, but it currently biases retrieval only. It does not yet drive globe state, feed transformation, or report generation, so that’s a natural next architecture step.

  The highest-value next move is to harden the HTML/rendering surfaces first, then remove or implement dead routes, then add focused tests around analysis, RAG, and report generation. If you want, I can turn this into a concrete remediation plan and start fixing the top
  issues in priority order.
