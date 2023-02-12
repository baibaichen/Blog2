# Velox: Meta’s Unified Execution Engine

## ABSTRACT
> The ad-hoc development of new specialized computation engines targeted to very specific data workloads has created a siloed data landscape. Commonly, these engines share little to nothing with each other and are hard to maintain, evolve, and optimize, and ultimately provide an inconsistent experience to data users. In order to address these issues, Meta has created Velox, a novel open source C++ database acceleration library. Velox provides reusable, extensible, high-performance, and dialect-agnostic data processing components for building execution engines, and enhancing data management systems. The library heavily relies on vectorization and adaptivity, and is designed from the ground up to support efficient computation over complex data types due to their ubiquity in modern workloads. Velox is currently integrated or being integrated with more than a dozen data systems at Meta, including analytical query engines such as Presto and Spark, stream processing platforms, message buses and data warehouse ingestion infrastructure, machine learning systems for feature engineering and data preprocessing (PyTorch), and more. It provides benefits in terms of (a) efficiency wins by democratizing optimizations previously only found in individual engines, (b) increased consistency for data users, and (c) engineering efficiency by promoting reusability.

针对非常具体的数据工作负载的新专业计算引擎的临时开发创造了一个孤立的数据环境。通常，这些引擎彼此几乎没有共享，并且难以维护、发展和优化，并最终为数据用户提供不一致的体验。为了解决这些问题，Meta 创建了 Velox，一个新颖的开源 C++ 数据库加速库。Velox 提供可重用、可扩展、高性能和方言不可知的数据处理组件，用于构建执行引擎和增强数据管理系统。该库严重依赖矢量化和自适应性，并且从头开始设计以支持对复杂数据类型的高效计算，因为它们在现代工作负载中无处不在。Velox 目前正在与 Meta 的十几个数据系统集成，包括 Presto 和 Spark 等分析查询引擎、流处理平台、消息总线和数据仓库摄取基础设施、用于特征工程和数据预处理的机器学习系统（PyTorch）等。它在以下方面提供了好处：(a) 大众化以前仅在单个引擎中发现的优化，以此来提高效率，(b) 提高数据用户的一致性，以及 (c) 通过提高可重用性来提高工程效率。

## 1 INTRODUCTION
> The increasing workload diversity in modern data use cases coupled with exponential dataset growth have led to the proliferation of specialized query and computation engines, each targeted to a very specific type of workload. Data processing requirements have grown from simple transaction processing and analytics (both batch and interactive), to ETL and bulk data movement, to realtime stream processing, to log and timeseries processing for monitoring use cases, to more recently, a plethora of artificial intelligence (AI) and machine learning (ML) use cases including data preprocessing and feature engineering.
>
> This evolution has created a siloed data ecosystem composed of dozens of specialized engines that are built using different frameworks and libraries and share little to nothing with each other, are written in different languages, and are maintained by different engineering teams. Moreover, evolving and optimizing these engines as hardware and use cases evolve, is cost prohibitive if done on a per-engine basis. For example, extending every engine to better leverage novel hardware advancements, like cache-coherent accelerators and NVRAM, supporting features like Tensor data types for ML workloads, and leveraging future innovations made by the research community are impractical and invariably lead to engines with disparate sets of optimizations and features. More importantly, this fragmentation ultimately impacts the productivity of data users, who are commonly required to interact with several different engines to finish a particular task. The available data types, functions, and aggregates vary across these systems, and the behavior of those functions, null handling, and casting can be vastly inconsistent across engines. For instance, an informal survey conducted at Meta identified at least 12 different implementations of the simple string manipulation function 𝑠𝑢𝑏𝑠𝑡𝑟 (), presenting different parameter semantics (0- vs. 1-based indices), null handling, and exception behavior.
>
> Although specialized engines, by definition, provide specialized behavior that justifies their existence, the main differences are commonly in the language frontend (SQL, dataframes, and other DSLs), the optimizer, the way tasks are distributed among worker nodes (also referred to as the runtime), and the IO layer. The execution engines at the core of these systems are all rather similar. All engines need a type system to represent scalar and complex data types, an in memory representation of these (often columnar) datasets, an expression evaluation system, operators (such as joins, aggregation, and sort), in addition to storage and network serialization, encoding formats, and resource management primitives.
>
> In order to address these issues, Meta has developed Velox, a novel C++ database acceleration library that provides reusable, extensible, and high-performance data processing components which can be used to build, enhance, or replace execution engines in existing data management systems. Velox is designed from the ground up to efficiently support complex types due to their ubiquity in modernworkloads, and heavily relies on vectorization [4] and adaptivity. Velox components are language, dialect, and engine-agnostic, and provide many extensibility points where developers can specialize the library behavior and match a particular engine’s requirements. In common usage scenarios, Velox takes a fully optimized query plan as input and performs the described computation using the resources available in the local node. As such, Velox does not provide a SQL parser, a dataframe layer, other DSLs, or a global query optimizer, and it is usually not meant to be used directly by data users.
>
> Velox’s value proposition is three-fold:
>
> - **Efficiency**: Velox democratizes runtime optimizations previously only implemented in individual engines, such as fully leveraging SIMD, lazy evaluation, adaptive predicate re-ordering and pushdown, common subexpression elimination, execution over encoded data, code generation, and more.
> - **Consistency**: by leveraging the same execution library, compute engines can expose the exact same data types and scalar/aggregate function packages, and thus provide a more consistent experience to data users due to their unified behavior.
> - **Engineering Efficiency**: all features and runtime optimizations available in Velox are developed and maintained once, thus reducing engineering duplication and promoting reusability.
>
> Velox is under active development and is already integrated or being integrated with more than a dozen data systems at Meta (and beyond), such as Presto, Spark, PyTorch, XStream (stream processing), F3 (feature engineering), FBETL (data ingestion), XSQL (distributed transaction processing), Scribe (message bus infrastructure), Saber (high QPS external serving), and others.
>
> We believe Velox to be a major step towards making data systems more modular and interoperable, with the ultimate goal of providing a more responsible implementation of the “one size does not fit all” mantra. Considering the potential impact in the community, Velox is open-source1 and backed by a fast growing community, including members such as Ahana, Intel, Voltron Data, and many other major technology companies and academic partners. Lastly, we also believe that, strategically, Velox will allow Meta to partner with hardware vendors and proactively prepare our data systems for tomorrow’s hardware, in addition to streamlining collaborations with researchers and research labs.
>
> In this paper, we make the following contributions:
>
> - We detail the Velox library, its components, extensibility points, and main optimizations.
> - We describe how Velox is being integrated with compute engines targeted at very diverse workloads, such as batch and interactive analytics, stream processing, data warehouse ingestion, ML, and more.
> - We highlight how Velox is transforming Meta’s data landscape, which has traditionally been composed of siloed and specialized engines providing inconsistent semantics for data users.
> - We present micro-benchmarks to motivate Velox’s main optimizations, in addition to experimental results with Velox’s integration with Presto.
> - We discuss lessons learned during this journey, future work, and open questions with the hope of motivating further research and fostering collaboration.

现代数据用例中工作负载的多样性不断增加，加上数据集呈指数级增长，导致专用查询和计算引擎激增，每个引擎都针对一种非常特定类型的工作负载。数据处理需求已经从简单的事务处理和分析（批处理和交互式）发展到 ETL 和批量数据移动，再到实时流处理，再到用于监控用例的日志和时间序列处理，再到最近大量的人工智能（ AI) 和机器学习 (ML) 用例，包括数据预处理和特征工程。

这种演变创造了一个由数十个专用引擎组成的孤立数据生态系统，这些引擎使用不同的框架和库构建，彼此之间几乎没有共享，用不同的语言编写，并由不同的工程团队维护。此外，随着硬件和用例的发展，对这些引擎进行改进和优化，如果以每个引擎为基础，则成本过高。例如，扩展每一个引擎以更好地利用新的硬件进步，如缓存一致加速器和 NVRAM，支持用于 ML 工作负载的 Tensor 数据类型等功能，并利用研究界未来的创新，这不切实际，并且总是导致引擎具有不同的优化和功能集。更重要的是，这种碎片化最终会影响数据用户的生产力，他们通常需要与几个不同的引擎交互才能完成特定任务。在这些系统中，可用的数据类型、函数和聚合各不相同，这些函数的行为、空处理和转换在不同的引擎中可能极不一致。例如，在 Meta 进行的一项非正式调查发现，简单字符串操作函数 `𝑠𝑢𝑏𝑠𝑡r()` 至少有 12 种不同实现，有不同的参数语义（基于 0 或基于 1 的索引）、空值处理和处理异常的行为。

尽管根据定义，专用引擎提供了证明其存在合理性的专用行为，但主要区别通常在于语言前端（SQL、Dataframe 和其他 DSL）、优化器、任务在工作节点之间的分布方式（也称为 运行时）和 IO 层。这些系统核心的执行引擎都非常相似。除了存储和网络序列化、<u>==编码格式==</u>和资源管理原语之外，所有引擎都需要一个类型系统来表示标量和复杂数据类型、这些数据集的内存表示（通常是列式）、表达式评估系统、运算符（例如连接、聚合和排序）。

为了解决这些问题，Meta 开发了 Velox，这是一种新颖的 C++ 数据库加速库，它提供可重用、可扩展和高性能的数据处理组件，可用于构建、增强或替换现有数据管理系统中的执行引擎。 Velox 的设计初衷是为了有效支持复杂类型，因为它们在现代工作负载中无处不在，并且在很大程度上依赖于向量化 [4] 和自适应性。 Velox 组件与语言、方言和引擎无关，并提供许多可扩展点，开发人员可以在其中专门化库行为并满足特定引擎的要求。 在常见的使用场景中，Velox 将完全优化的查询计划作为输入，并使用本地节点中可用的资源执行所描述的计算。 因此，Velox 不提供 SQL 解析器、DataFrame、其他 DSL 或全局查询优化器，通常数据用户不会直接使用它。

Velox 的<u>==价值主张==</u>有三方面：

- **效率**：Velox 大众化了以前只在单个引擎中实现的运行时优化，例如充分利用 SIMD，延迟计算，自适应谓词重排和下推，公共子表达式消除，<u>==编码数据执行==</u>，代码生成等。
- **一致性**：通过利用相同的执行库，计算引擎可以公开完全相同的数据类型和标量/聚合函数包，从而为数据用户提供更加一致的体验，因为它们的行为是统一的。
- **工程效率**：Velox 中可用的所有功能和运行时优化都是一次开发和维护，从而减少了重复工做，提高可重用性。

Velox 正在积极开发中，已经或正在与 Meta（及其他）的十多个数据系统集成，如 Presto、Spark、PyTorch、XStream（流处理）、F3(特征工程)、FBETL（数据输入）、XSQL（分布式事务处理）、Scribe（消息总线基础设施）、Saber（高 QPS 外部服务）等。

我们相信 Velox 是朝着使数据系统更加模块化和可互操作的方向迈出的重要一步，**其最终目标是提供更负责任的“一刀切”方案**。考虑到对社区的潜在影响，Velox 是开源的，并得到了一个快速增长的社区的支持，其中包括 Ahana、Intel、Voltron Data 以及许多其他主要技术公司和学术合作伙伴。最后，我们还相信，从战略上讲，除了简化与研究人员和研究实验室的合作外，Velox 还将允许 Meta 与硬件供应商合作，并主动为未来的硬件准备我们的数据系统。

在本文中，我们做出以下贡献：

- 我们详细介绍了 Velox 库、其组件、扩展点和主要优化。

- 我们描述了 Velox 如何与<u>针对各种工作负载的</u>计算引擎集成，例如批处理和交互式分析、流处理、数据仓库摄取、ML 等。
- 我们重点介绍了 Velox 如何改变 Meta 的数据环境，传统上 Meta 的数据环境由孤立的专用引擎组成，为数据用户提供不一致的语义。
- 除了 Velox 与 Presto 集成的实验结果外，<u>==我们还提供了微基准来推动 Velox 的主要优化==</u>。
- 我们讨论在这次旅程中吸取的教训、未来的工作和未解决的问题，以期激发进一步的研究和促进合作。

## 2 LIBRARY OVERVIEW

Velox is an open source C++ database acceleration library that provides high-performance, reusable, and extensible data processing components, which can be used to accelerate, extend, and enhance data computation engines. Velox does not provide a language frontend, such as a SQL parser, dataframe layer, or other DSLs; instead, it expects a fully optimized query plan as input describing the computation to be performed, and executes it locally using the resources available in the local host. 

Furthermore, Velox does not provide a global query optimizer, but at execution time leverages numerous adaptivity techniques, such as filter and conjunct reordering, dynamic filter pushdown, and adaptive column prefetching. In other words, the components provided by Velox usually sit on the data-plane, while individual engines are responsible for providing the control-plane. The highlevel components provided by Velox are:

- **Type**: a generic type system that allows users to represent scalar, complex, and nested data types, including structs, maps, arrays, tensors, and more.
- **Vector**: an Arrow-compatible2 columnar memory layout module, supporting multiple encodings, such as Flat, Dictionary, Constant, Sequence/RLE, and Bias (frame of reference), in addition to a lazy materialization pattern and support for out-of-order result buffer population.
- **Expression Eval**: a fully vectorized expression evaluation engine built based on Vector-encoded data, leveraging techniques such as common subexpression elimination, constant folding, efficient null propagation, encoding-aware evaluation, and dictionary memoization.
- **Functions**: APIs that can be used by developers to build custom functions, providing a simple (row-by-row) and vectorized (batch-by-batch) interface for scalar functions, and APIs for aggregate functions. Function packages compatible with popular SQL dialects are also provided by the library (currently, for Presto and Spark).
- **Operators**: implementation of common data processing operators such as TableScan, Project, Filter, Aggregation, Exchange/ Merge, OrderBy, HashJoin, MergeJoin, Unnest, and more.
- **I/O**: a generic connector interface that allows for pluggable file format encoders/decoders and storage adapters. Support for popular formats such as ORC and Parquet, and S3 and HDFS storage systems are included in the library.
- **Serializers**: a serialization interface targeting network communication where different wire protocols can be implemented, supporting PrestoPage and Spark’s UnsafeRow formats.
- **Resource Management**: a collection of primitives for handling computational resources, such as memory arenas and buffer management, tasks, drivers, and thread pools for CPU and thread execution, spilling, and caching.

Engines integrating with Velox can choose which components to use based on the functionality required. For instance, engines with simple data representation and serialization requirements can leverage Type, Vector, and Serializer only, while a complete SQL analytical query engine would require the full extent of operators and resource management primitives available.

In addition to being modular, Velox also provides extensibility APIs that can be used to customize the library. Developers can use these APIs to add plugins to support custom data types, scalar and aggregate functions, engine-specific operators, new serialization formats, file encodings, and storage adapters. The decision about whether a particular plugin will be provided as part of the main library or not is based on its genericity: if it is used by multiple engines (e.g. Parquet and ORC file encoders, and common operators such as Aggregate, OrderBy, and HashJoin), they are included in the main library; otherwise, they are provided as part of the client’s engine codebase (e.g. ML-specific functions and stream processing operators).
