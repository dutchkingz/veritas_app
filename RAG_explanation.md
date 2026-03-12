**RAG (Retrieval-Augmented Generation)** is a technique that gives an AI language model access to an external knowledge base so it can look up relevant information *before* answering your question, instead of relying purely on what it learned during training. [en.wikipedia](https://en.wikipedia.org/wiki/Retrieval-augmented_generation)

## The Problem RAG Solves

A regular LLM (like GPT or Claude) is trained once on a large dataset and then "frozen." It has no idea what happened after its training cutoff, and it knows nothing about *your* private data — your company's docs, your app's database, your codebase, etc.. This causes **hallucinations** (confidently wrong answers) and outdated responses. [ibm](https://www.ibm.com/think/topics/retrieval-augmented-generation)

RAG fixes this by giving the model a dynamic, searchable knowledge source at query time. [databricks](https://www.databricks.com/glossary/retrieval-augmented-generation-rag)

## How It Works Step by Step

1. **You ask a question** — e.g., *"What's our refund policy?"*
2. **The retriever searches** a knowledge base (your documents, database, PDFs, etc.) for the most relevant chunks of information [ibm](https://www.ibm.com/think/topics/retrieval-augmented-generation)
3. **The relevant text is injected** into the prompt alongside your question, giving the LLM fresh context it didn't have before
4. **The LLM generates an answer** grounded in that retrieved content, not just its training data [blogs.nvidia](https://blogs.nvidia.com/blog/what-is-retrieval-augmented-generation/)

## The Librarian Analogy

Think of it like a librarian at a massive library. Instead of the librarian trying to recall everything from memory, they quickly run to the shelves, grab the most relevant books, read the key passages, and *then* give you a well-informed answer. The librarian's "intelligence" (the LLM) is separate from the "library" (your knowledge base). [mckinsey](https://www.mckinsey.com/featured-insights/mckinsey-explainers/what-is-retrieval-augmented-generation-rag)

## Why It Matters for Your Projects

Since you're working with LLM integrations via APIs like OpenRouter, RAG is the most practical pattern for building useful AI features in your Rails app. The core components are: [databricks](https://www.databricks.com/glossary/retrieval-augmented-generation-rag)

- **Knowledge base** — your data source (e.g., a PostgreSQL table, uploaded PDFs, markdown docs)
- **Embedding model** — converts text into vectors (numbers) so similarity search is possible
- **Vector database** — stores and searches those vectors efficiently (e.g., pgvector, Pinecone, Weaviate)
- **LLM** — generates the final response using the retrieved context

## RAG vs. Fine-Tuning

| | RAG | Fine-Tuning |
|---|---|---|
| **How it works** | Retrieves data at query time | Bakes data into model weights |
| **Best for** | Dynamic, frequently updated data | Fixed domain/style specialization |
| **Cost** | Low — no retraining needed | High — requires GPU training runs |
| **Updates** | Just update your knowledge base | Must retrain the whole model |
| **Hallucination risk** | Lower (grounded in sources) | Still possible |

RAG is almost always the right first choice for app developers, because you can update your knowledge base instantly without touching the model itself. [databricks](https://www.databricks.com/glossary/retrieval-augmented-generation-rag)
