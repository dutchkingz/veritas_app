# VERITAS OSINT Globe – Roadmap & Vision

_Last updated: 2026-03-16 by Tal 🦞_

---

## 🎯 Core Vision
**"Palantir for the People"** – A real‑time OSINT platform that tracks narrative flows, detects manipulation, and visualizes information warfare across global media.

---

## ✅ **PHASE 1: Foundation – COMPLETE**
### Technical Base
- [x] Rails 8.1.2 + PostgreSQL + pgvector
- [x] NewsAPI integration (300 articles)
- [x] AI Analysis Pipeline (Analyst, Sentinel, Arbiter agents)
- [x] Globe.gl + Three.js visualization
- [x] Semantic search with embeddings
- [x] Narrative route auto‑generation

### Current Status (March 2026)
- **300 articles** in database (16 with full content, 284 need content fetch)
- **6 narrative routes** (13 hops) – needs expansion
- **Search & trending topics** UI ready
- **Bundle/Ruby 3.3.5** fixed and running

---

## 🔥 **PHASE 2: Data Completion – IN PROGRESS**
### Immediate Goals
- [ ] **Content Fetch** for 284 articles without full text
  - `FetchArticleContentJob` deployed
  - Needs debugging (currently stalled at 16/300)
- [ ] **Embeddings Generation** for all 300 articles
  - `GenerateEmbeddingJob` ready
  - Rake task `veritas:embeddings:generate_all`
- [ ] **Narrative Route Explosion**
  - Target: **50–100+ routes** from 300 articles
  - Dynamic similarity matching (no fixed limits)
- [ ] **Globe Visualization Enhancement**
  - Live packet animation with real data
  - Hop‑timeline sidebar with details
  - Search‑filtered arcs

### Success Metrics
- 300/300 articles with content ✅
- 300/300 articles with embeddings ✅
- 50+ narrative routes ✅
- Globe shows 100+ segments ✅

---

## 🚀 **PHASE 3: Real‑Time Intelligence**
### Social Media & Messaging Integration
- [ ] **Telegram Bot & Channel Monitoring**
  - `gem 'telegram-bot-ruby'`
  - Monitor public channels for emerging narratives
  - Alert system for high‑threat keywords
- [ ] **Twitter/X API Integration**
  - Free tier usage (Academic API if available)
  - Track trending hashtags, detect amplification
  - Sentiment + framing shift detection
- [ ] **Reddit API Integration**
  - `gem 'httparty'` or `reddit‑api`
  - Monitor subreddits (r/worldnews, r/geopolitics)
  - Detect cross‑platform narrative spreading

### Features
- **Unified Search**: Query across NewsAPI + Telegram + Twitter + Reddit
- **Cross‑Platform Correlation**: Same narrative appearing on multiple platforms
- **Real‑Time Alerts**: ActionCable notifications for breaking stories

---

## 🧠 **PHASE 4: Advanced Intelligence**
### AI Enhancement
- [ ] **Multi‑Language Support**
  - Translation via DeepL API
  - Cross‑lingual embedding alignment
- [ ] **Network Graph Analysis**
  - Gephi‑style visualization of source relationships
  - "Influence score" for media outlets
- [ ] **Predictive Analytics**
  - Which narratives will amplify next?
  - Early warning system for disinformation campaigns
- [ ] **User Feedback Loop**
  - "Is this analysis helpful?" → improve trust scores
  - Crowd‑sourced credibility ratings

### Data Enrichment
- [ ] **Historical Trends**
  - Timeline visualization of narrative evolution
  - "How Ukraine coverage changed over 30 days"
- [ ] **Source Credibility Database**
  - Track reliability scores over time
  - Fact‑checking integration

---

## 📱 **PHASE 5: Productization**
### User Experience
- [ ] **Mobile‑First Interface**
  - Responsive PWA (Progressive Web App)
  - Native‑like experience on phones/tablets
- [ ] **Export & Reporting**
  - PDF briefings (already exists)
  - CSV/JSON data export
  - API access for third‑party tools
- [ ] **Dashboard & Customization**
  - Personalized threat alerts
  - Saved searches / watchlists
  - Custom globe perspectives

### Deployment & Scale
- [ ] **VPS Migration** (Oliver's plan)
  - 48GB RAM, 12 CPU cores
  - 24/7 availability
- [ ] **Multi‑Tenant Architecture**
  - Support for multiple organizations
  - Role‑based access control
- [ ] **Performance Optimization**
  - Segment culling, LOD, animation pooling
  - Database indexing, query optimization

---

## 🌍 **LONG‑TERM VISION**
### "Global Narrative Immune System"
- **Automated Trust Scoring**: Every source, every article, every claim
- **Collaborative Intelligence**: Journalists, researchers, citizens contributing
- **Transparent Methodology**: Open‑source algorithms, explainable AI
- **Crisis Response**: Real‑time monitoring during elections, conflicts, disasters

### Ethical Principles
- **Privacy First**: No personal data collection
- **Transparency**: All analysis methods documented
- **Bias Mitigation**: Regular audits for algorithmic fairness
- **Public Good**: Free for journalists, NGOs, researchers

---

## 🛠️ **TECHNICAL DEBT & FIXES**
### Immediate Issues
1. **Solid Queue Job Processing**
   - Jobs stalled at 16/300 content fetch
   - Need to debug `FetchArticleContentJob` failures
2. **URL Validity**
   - Many articles may have invalid/missing URLs
   - Need fallback strategy
3. **Rate Limiting**
   - OpenRouter API, NewsAPI, social media APIs
   - Implement proper backoff/queuing

### Code Quality
- [ ] **Test Coverage** (RSpec + Capybara)
- [ ] **API Documentation** (Swagger/OpenAPI)
- [ ] **Monitoring & Logging** (Sentry, Lograge)

---

## 🤝 **COLLABORATION OPPORTUNITIES**
### Potential Integrations
- **Mastodon/Fediverse**: Decentralized social media
- **Bluesky**: AT Protocol integration
- **Wikipedia/ Wikidata**: Fact‑checking references
- **Academic Databases**: Peer‑reviewed research correlation

### Open Source
- **GitHub Repository**: Public codebase
- **Community Plugins**: Extendable architecture
- **Dataset Sharing**: Anonymized narrative routes

---

## 📅 **TIMELINE (Estimated)**
- **March 2026**: Phase 2 completion (300 articles, 50+ routes)
- **April 2026**: Telegram/Twitter/Reddit integration
- **May 2026**: Advanced AI features, mobile UI
- **June 2026**: VPS migration, production readiness
- **H2 2026**: Public beta, community launch

---

**Maintained by Tal 🦞 – Oliver's AI Assistant**  
_"Building tools that make the world's information flows transparent and accountable."_