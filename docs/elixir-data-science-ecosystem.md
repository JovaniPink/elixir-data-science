# Elixir for Data Science and Machine Learning

_Research snapshot verified August 16, 2026._

Elixir now has a coherent, actively maintained data-science and machine
learning stack. It is especially compelling when analysis or inference must
become a concurrent, fault-tolerant production application.

This brief describes the external ecosystem. It does not claim that this
repository contains a runnable Elixir project, notebook, model, or experiment.

## Current ecosystem snapshot

At the verification date, the published documentation included
[Nx 0.13.1](https://nx.hexdocs.pm/Nx.html),
[Explorer 0.12.0](https://explorer.hexdocs.pm/Explorer.html),
[Axon 0.8.1](https://elixir-nx.github.io/axon/guides.html),
[Bumblebee 0.7.1](https://bumblebee.hexdocs.pm/readme.html),
[Scholar 0.4.1](https://scholar.hexdocs.pm/readme.html), and
[EXLA 0.13.1](https://exla.hexdocs.pm/). The core repositories also showed
recent July 2026 activity in the
[Numerical Elixir organization](https://github.com/elixir-nx).

Versions and repository activity are dated observations, not permanent
compatibility guarantees. Recheck package constraints before implementing an
experiment.

## Ecosystem map

| Need | Elixir tool | What it provides |
|---|---|---|
| Notebooks | [Livebook](https://livebook.dev/) | Reproducible `.livemd` notebooks, collaboration, interactive controls, and deployable notebook apps |
| Dataframes | [Explorer](https://explorer.hexdocs.pm/Explorer.html) | Polars-backed dataframes; CSV, Parquet, Arrow, NDJSON, S3, and database access through ADBC |
| Numerical computing | [Nx](https://nx.hexdocs.pm/Nx.html) | Typed tensors, broadcasting, linear algebra, automatic differentiation, and compiled numerical functions |
| CPU/GPU execution | [EXLA](https://exla.hexdocs.pm/) and [Torchx](https://torchx.hexdocs.pm/) | XLA or LibTorch acceleration instead of the reference binary backend |
| Classical ML | [Scholar](https://scholar.hexdocs.pm/readme.html) | Regression, classification, clustering, preprocessing, metrics, dimensionality reduction, and nearest-neighbor algorithms |
| Boosted trees | [EXGBoost](https://exgboost.hexdocs.pm/EXGBoost.html) | XGBoost training and prediction over Nx tensors |
| Neural networks | [Axon](https://elixir-nx.github.io/axon/guides.html) | Model construction, training loops, custom layers, metrics, and serialization |
| Pretrained models | [Bumblebee](https://github.com/elixir-nx/bumblebee) | Supported Hugging Face models for text, vision, audio, embeddings, generation, and diffusion |
| Portable model inference | [Ortex](https://ortex.hexdocs.pm/Ortex.html) | ONNX Runtime inference using Nx tensors |
| Production inference | [Nx.Serving](https://nx.hexdocs.pm/Nx.Serving.html) | Request batching, concurrency, distribution, and multi-device partitioning |
| Visualization | [Kino](https://kino.hexdocs.pm/) and [VegaLite](https://vega-lite.hexdocs.pm/VegaLite.html) | Interactive tables, charts, maps, controls, and PNG/SVG/PDF export |
| Streaming data | [Broadway](https://broadway.hexdocs.pm/Broadway.html) and [Flow](https://flow.hexdocs.pm/Flow.html) | Backpressure, batching, fault tolerance, parallel processing, windows, and event streams |
| Computer vision | [Evision](https://evision.hexdocs.pm/readme.html) | OpenCV bindings with Nx interoperability |
| Python escape hatch | [Pythonx](https://pythonx.hexdocs.pm/Pythonx.html) | Embedded Python with Elixir/Python value conversion |

Explorer is more than a CSV wrapper. Its default backend uses native Polars
bindings and supports lazy transformations, joins, grouped aggregation,
Parquet, Arrow, S3, and database queries. See the
[Explorer feature and design documentation](https://explorer.hexdocs.pm/Explorer.html).

## Where Elixir is unusually strong

### ML inside a production application

A model can live directly in a Phoenix supervision tree. `Nx.Serving` batches
simultaneous requests and can distribute them across nodes or devices without
requiring a separate Python inference service. Bumblebee includes
[Phoenix and LiveView integration examples](https://bumblebee.hexdocs.pm/readme.html).

### Real-time and streaming intelligence

Broadway supplies backpressure, acknowledgements, batching, rate limiting, and
failure isolation for Kafka, Amazon SQS, Google Cloud Pub/Sub, and RabbitMQ
pipelines. An Nx or Scholar model can be placed inside the same supervised data
pipeline.

### Native training

Nx provides automatic differentiation and compilation, Axon trains neural
networks, Scholar implements classical algorithms as numerical definitions,
and EXGBoost trains boosted trees. Elixir is not limited to calling an external
machine-learning API.

### Operational notebooks

Livebook notebooks are versionable, reproducible, attachable to existing
Elixir nodes, and deployable as internal applications. Published
[Livebook integrations](https://livebook.dev/integrations/) include PostgreSQL,
MySQL, Microsoft SQL Server, SQLite, BigQuery, Snowflake, Hugging Face,
VegaLite, and MapLibre.

### Edge and embedded systems

Nx can complement Nerves applications, making on-device inference, signal
processing, and sensor analysis credible Elixir use cases. The Numerical
Elixir overview describes both
[Nerves and production application scenarios](https://github.com/elixir-nx).

## Honest limitations

- Python remains substantially broader for frontier research libraries, newly
  published architectures, specialized statistics, experiment tracking, and
  academic reference implementations.
- Bumblebee does not automatically support every Hugging Face repository. The
  model architecture must be implemented in Bumblebee, and tokenization
  normally depends on a compatible `tokenizer.json`. See Bumblebee's
  [model-support explanation](https://github.com/elixir-nx/bumblebee).
- Scholar requires JIT compilation for many algorithms, and its numerical
  definition design cannot represent every model family. Its documentation
  directs decision-tree and random-forest cases toward EXGBoost.
- Native backends introduce operational details: XLA or LibTorch binaries,
  CUDA or ROCm compatibility, compilation latency, tensor transfers, bounded
  input shapes, and model-cache management.
- Pythonx helps with gradual migration or a missing library, but embedding
  CPython does not remove the global interpreter lock. Its
  [concurrency guidance](https://pythonx.hexdocs.pm/Pythonx.html) warns that
  ordinary Python code called from multiple Elixir processes may become a
  bottleneck.

## Practical fit

- **Excellent fit:** production inference, streaming classification, anomaly
  detection, recommendation, embeddings, internal analytical applications,
  telemetry, edge ML, and data-heavy Phoenix systems.
- **Good fit:** tabular analysis, classical ML, custom neural networks, and
  fine-tuning supported transformer architectures.
- **Usually not the first choice:** frontier model research, highly specialized
  scientific packages, or workflows that depend on many Python-only libraries.

## Candidate starting path

A future reactivation PR could start with a Livebook exploration using a setup
cell like the following:

```elixir
Mix.install([
  {:explorer, "~> 0.12"},
  {:nx, "~> 0.13"},
  {:exla, "~> 0.13"},
  {:scholar, "~> 0.4"}
])

Nx.global_default_backend(EXLA.Backend)
Nx.Defn.global_default_options(compiler: EXLA, client: :host)

require Explorer.DataFrame, as: DF

Explorer.Datasets.iris()
|> DF.group_by("species")
|> DF.summarise(mean_petal_length: mean(petal_length))
```

This is a research example, not a command that is currently runnable from this
repository. Before adopting it, an implementation PR must establish supported
Elixir and Erlang/OTP versions, resolve and commit dependency versions, test
the exact notebook, and provide deterministic run instructions.

A reasonable progression would be:

1. clean and visualize a small, rights-cleared dataset with Explorer;
2. establish a Scholar baseline model;
3. compare it with an Axon neural network;
4. evaluate supported Bumblebee or ONNX inference; and
5. place the selected model behind `Nx.Serving` in Phoenix or Broadway.

## Learning resource

Sean Moriarity's 2024 book,
[*Machine Learning in Elixir*](https://pragprog.com/titles/smelixir/machine-learning-in-elixir/),
covers Nx, classical machine learning, Axon, transformers, visualization, and
Phoenix integration.

## Evidence and data boundaries

- Package documentation and repository activity establish observed ecosystem
  capabilities; they do not prove compatibility with a future experiment's
  operating system, accelerator, Elixir version, or dependency graph.
- Technical access to a dataset is not permission to retrieve, store, model,
  redistribute, or publish it. Any future dataset must document its original
  source, license or terms, retrieval date, and permitted use.
- A runnable experiment requires separate implementation, dependency locking,
  tests, and exact run instructions under the repository's reactivation
  contract.
