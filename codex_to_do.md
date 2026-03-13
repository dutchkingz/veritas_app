# Codex TODO

## Current State

VERITAS has completed a first hardening pass focused on the highest-risk issues without removing unfinished product scope.

Implemented in this session:

- Hardened article scraping/rendering paths against unsafe HTML execution.
- Blocked unsafe/internal article source URLs before server-side fetch.
- Removed unsafe `marked` + `innerHTML` rendering from intelligence reports.
- Escaped RAG chat output before rendering and reduced unsafe DOM injection.
- Fixed regional analysis UX so non-admin users see a locked state instead of a broken action.
- Reduced duplicate AI analysis execution by skipping jobs already in `analyzing`.
- Prevented duplicate saved articles at the Rails validation/controller layer.
- Replaced missing-controller runtime crashes for unfinished routes with explicit feature-preview placeholders.
- Stopped leaking raw semantic-search exception messages to end users.
- Added focused regression tests for helper sanitization, dashboard role UX, saved-article duplication, and analyze-job idempotency.

Verified:

```bash
bin/rails test test/helpers/application_helper_test.rb test/controllers/pages_controller_test.rb test/models/saved_article_test.rb test/jobs/analyze_article_job_test.rb
```

Result:

- 6 runs
- 26 assertions
- 0 failures
- 0 errors

## Highest Priority Next

### 1. Add DB-Level Integrity

Current duplicate-save protection exists only in Rails validations.

Next:

- Add a unique database index on `saved_articles(user_id, article_id)`.
- Add a migration that either deduplicates existing rows safely or aborts with a clear message if duplicates exist.

Reason:

- Rails validation alone is not enough under concurrent requests.

### 2. Tighten Frontend Security Further

Current state is safer, but the app still relies on large inline scripts/styles, especially in the floating RAG widget.

Next:

- Move chat widget behavior out of inline `<script>` into a Stimulus controller.
- Gradually move inline styles into stylesheet/component files.
- Enable a real Content Security Policy in `config/initializers/content_security_policy.rb`.
- Aim to remove the need for permissive inline script execution.

Reason:

- This is the clean path to production-grade browser hardening.

### 3. Extract Article Ingestion/Scraping Into a Service

Current scraping logic still lives inside `ArticlesController#show`.

Next:

- Move article fetch + readability parsing + image normalization into a dedicated service object.
- Add explicit network/open/read timeouts.
- Keep SSRF protections and sanitization in the service.
- Add focused tests around invalid URLs, internal hosts, fallback content, and sanitization.

Reason:

- The controller is carrying too much risk-heavy logic.

### 4. Add Critical Test Coverage

Large portions of the intelligence pipeline still have little or no regression coverage.

Next:

- Add tests for `IntelligenceReportsController`.
- Add tests for `RegionalAnalysisService`.
- Add tests for `RagAgent`.
- Add tests for `NarrativeConvergenceService`.
- Add tests for role/admin behavior around unfinished admin routes and feature-preview responses.

Reason:

- The riskiest code paths are still weakly protected.

### 5. Clean Up Auth/Product Intent

Current app behavior:

- Global auth is enforced in `ApplicationController`.
- Some route comments and product framing still imply public/read-only access.

Next:

- Decide whether VERITAS is currently authenticated-only or partially public.
- Align route comments, UX copy, and controller behavior with that decision.

Reason:

- Product behavior and code intent currently do not fully match.

## Product Features Still Intentionally Unfinished

Do not remove these. They are roadmap items to complete properly:

- Real 3D globe implementation
- Solid Cable live feed updates
- Fully productionized admin surfaces
- Rich perspective-driven worldview transforms beyond RAG weighting
- Broader intelligence report workflows
- Full AI panel / operational status polish

## Recommended Next Working Session Order

1. Add DB unique index for saved articles.
2. Extract article scraping into a service and test it.
3. Convert chat widget JS into Stimulus.
4. Turn on a usable CSP.
5. Add tests for reports/RAG/convergence flows.

## Files Touched In This Session

- `app/controllers/articles_controller.rb`
- `app/controllers/pages_controller.rb`
- `app/controllers/saved_articles_controller.rb`
- `app/controllers/feature_previews_controller.rb`
- `app/controllers/admin/feature_previews_controller.rb`
- `app/helpers/application_helper.rb`
- `app/javascript/controllers/analysis_progress_controller.js`
- `app/jobs/analyze_article_job.rb`
- `app/models/saved_article.rb`
- `app/services/analysis_pipeline.rb`
- `app/views/articles/show.html.erb`
- `app/views/intelligence_reports/show.html.erb`
- `app/views/pages/home.html.erb`
- `app/views/shared/_chat_interface.html.erb`
- `config/routes.rb`
- `test/controllers/pages_controller_test.rb`
- `test/helpers/application_helper_test.rb`
- `test/jobs/analyze_article_job_test.rb`
- `test/models/saved_article_test.rb`
- `test/test_helper.rb`

## Notes

- There is also an untracked file `architecture_infos.md` in the repo that was not touched in this session.
- If resuming tomorrow, start by reading this file and `git status`.
