# Veritas DB Schema Update

This diagram displays the current database schema. Tables and fields representing recent core architectural elements—such as geopolitical AI analysis and narrative tracking—are highlighted.

```mermaid
erDiagram
    USERS ||--o{ BRIEFINGS : generates
    REGIONS ||--o{ COUNTRIES : contains
    REGIONS ||--o{ ARTICLES : context
    COUNTRIES ||--o{ ARTICLES : context
    ARTICLES ||--o{ AI_ANALYSES : receives
    ARTICLES ||--o{ NARRATIVE_ARCS : tracks

    USERS {
        bigint id PK
        string email
        string encrypted_password
        string role "default: 'user'"
        boolean admin
    }

    REGIONS {
        bigint id PK
        string name
        float latitude
        float longitude
        integer threat_level
        integer article_volume
        datetime last_calculated_at
    }

    COUNTRIES {
        bigint id PK
        string name
        string iso_code
        bigint region_id FK
    }

    ARTICLES {
        bigint id PK
        string headline
        text content
        string source_name
        string source_url
        float latitude
        float longitude
        integer target_country
        datetime published_at
        datetime fetched_at
        jsonb raw_data
        bigint country_id FK
        bigint region_id FK
    }

    AI_ANALYSES {
        bigint id PK
        string analysis_status "default: 'pending'"
        string geopolitical_topic
        string threat_level
        float trust_score
        string sentiment_label
        string sentiment_color
        boolean linguistic_anomaly_flag
        string anomaly_notes
        string summary
        jsonb sentinel_response "NEW"
        jsonb analyst_response "NEW"
        jsonb arbiter_response "NEW"
        bigint article_id FK
    }

    NARRATIVE_ARCS {
        bigint id PK
        string origin_country
        float origin_lat
        float origin_lng
        string target_country
        float target_lat
        float target_lng
        string arc_color
        bigint article_id FK
    }

    NARRATIVE_CONVERGENCES {
        bigint id PK
        string topic_keyword
        float convergence_percentage
        integer article_count
        datetime calculated_at
    }

    BRIEFINGS {
        bigint id PK
        string threat_summary
        string top_narratives
        string pdf_url
        datetime generated_at
        bigint user_id FK
    }

    PERSPECTIVE_FILTERS {
        bigint id PK
        string name
        string filter_type
        string keywords
    }
    
    PAGES {
        bigint id PK
        string title
        text content
    }

    %% Highlight newer/Core AI tables
    style AI_ANALYSES fill:#f9d0c4,stroke:#333,stroke-width:2px
    style NARRATIVE_ARCS fill:#f9d0c4,stroke:#333,stroke-width:2px
    style NARRATIVE_CONVERGENCES fill:#f9d0c4,stroke:#333,stroke-width:2px
    style BRIEFINGS fill:#e1f5fe,stroke:#333,stroke-width:2px
```
