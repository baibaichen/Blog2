# Crystal: A Unified Cache Storage System for Analytical Databases

> **ABSTRACT** Cloud analytical databases employ a **disaggregated storage model**, where the elastic compute layer accesses data persisted on remote cloud storage in block-oriented columnar formats. Given the high latency and low bandwidth to remote storage and the limited size of fast local storage, caching data at the compute node is important and has resulted in a renewed interest in caching for analytics. Today, each DBMS builds its own caching solution, usually based on file or block-level LRU. In this paper, we advocate a new architecture of a smart cache storage system called *Crystal*, that is co-located with compute. Crystal’s clients are DBMS-specific “data sources” with push-down predicates. Similar in spirit to a DBMS, Crystal incorporates query processing and optimization components **==focusing on efficient caching and serving of single-table hyper-rectangles called <u>regions</u>==**. Results show that Crystal, with a small DBMS-specific data source connector, can significantly improve query latencies on unmodified Spark and Greenplum while also saving on bandwidth from remote storage.

**摘要**   云分析数据库采用**==分解存储模型==**，其中弹性计算层访问远程云存储上持久化的数据。考虑到远程存储的高延迟和低带宽以及有限的本地快速存储，在计算节点上缓存数据非常重要，**并导致了对缓存进行分析的新兴趣**。今天，每个 DBMS 都构建自己的缓存解决方案，通常基于文件或块级 LRU。我们在本文中，提出了一种新的智能缓存存储架构，称为 *Crystal*，与计算共存。***Crystal*** 的客户端是`特定 DBMS 的数据源`，带有下推谓词。本质上与 DBMS 类似，Crystal 包含查询处理和优化组件，**==专注于高效缓存和服务称为 <u>region</u> 的单表超矩形==**。结果表明，Crystal 带有一个特定于 DBMS 的小型数据源连接器，可以显着提高原生 Spark 和 Greenplum 上的查询延迟，同时还节省远程存储的带宽。

## 1   INTRODUCTION

> We are witnessing a paradigm shift of analytical database systems to the cloud, driven by its flexibility and **pay-as-you-go** capabilities. Such databases employ a tiered or disaggregated storage model, where the elastic *compute tier* accesses data persisted on independently scalable remote *cloud storage*, such as Amazon S3 [3] and Azure Blobs [36]. Today, nearly all big data systems including Apache Spark, Greenplum, Apache Hive, and Apache Presto support querying cloud storage directly. Cloud vendors also offer cloud services such as AWS Athena, Azure Synapse, and Google BigQuery to meet this increasingly growing demand.
>
> Given the relatively high latency and low bandwidth to remote storage, *caching data* at the compute node has become important. As a result, we are witnessing a <u>==renewed spike==</u> in caching technology for analytics, where the hot data is kept at the compute layer in fast local storage (e.g., SSD) of limited size. Examples include the Alluxio [1] analytics accelerator, the Databricks Delta Cache [9, 15], and the Snowflake cache layer [13].

在**灵活性**和**即用即付**功能的推动下，我们正在见证分析数据库系统向云模式的转变。此类数据库采用分层或分解的存储模型，其中弹性**计算层**访问保存在独立可扩展远程*云存储*上的数据，例如 Amazon S3 [3] 和 Azure Blob [36]。如今，包括 Apache Spark、Greenplum、Apache Hive 和 Apache Presto 在内的几乎所有大数据系统都支持直接查询云存储。云供应商还提供 AWS Athena、Azure Synapse 和 Google BigQuery 等云服务来满足这种日益增长的需求。

由于远程存储相对较高的延迟和较低的带宽，在计算节点上**缓存数据**变得很重要。因此，我们看到用于分析的缓存技术出现了新的高峰，其中热数据保存在计算层的快速本地存储（例如，SSD）中，大小有限。示例包括 Alluxio [1] 分析加速器、Databricks Delta 缓存 [9, 15] 和 Snowflake 缓存层 [13]。

### 1.1   Challenges

> These caching solutions usually operate as a black-box at the file or block level for simplicity, employing standard cache replacement policies such as LRU to manage the cache. In spite of their simplicity, these solutions have not solved several architectural and performance challenges for cloud databases:
>
> - Every DBMS today implements its own caching layer tailored to its specific requirements, resulting in a lot of work duplication across systems, reinventing choices such as what to cache, where to cache, when to cache, and how to cache.
>
> - Databases increasingly support analytics over raw data formats such as CSV and JSON, and row-oriented binary formats such as Apache Avro [6] – all very popular in the data lake [16]. Compared to binary columnar formats such as Apache Parquet [7], data processing on these formats is slower and results in increased costs, even when data has been cached at compute nodes. At the same time, it is expensive (and often less desirable to users) to convert all data into a binary columnar format on storage, particularly because only a small and changing fraction of data is actively used and accessed by queries.
>
> - 
>   Cache utilization (i.e., value per cached byte) is low in existing solutions, as even one needed record or value in a page makes it necessary to retrieve and cache the entire page, wasting valuable space in the cache. This is true even for optimized columnar formats, which often build per-block *zone maps* [21, 40, 48] (min and max value per column in a block) to avoid accessing irrelevant blocks. While zone maps are cheap to maintain and potentially useful, their effectiveness at block skipping is limited by the fact that even one interesting record in a block makes it necessary to retrieve it from storage and scan for completeness.
>
> - Recently, cloud storage systems are offering predicate push-down as a native capability, for example, AWS S3 Select [4] and Azure Query Acceleration [35]. Push-down allows us to send predicates to remote storage and avoid retrieving all blocks, but exacerbates the problem of how to leverage it for effective local caching.
>

为简单起见，这些缓存解决方案通常在文件或块级别作为黑盒运行，采用标准缓的存替换策略（如 LRU）来管理缓存。尽管简单，但这些解决方案**==并没有解决云数据库的几个架构和性能挑战==**：

- 今天，每个 DBMS 都实现了自己的缓存层，根据其特定需求量身定制，导致了系统间大量的重复工作，重新设计了缓存那些内容、何处缓存、何时缓存和如何缓存等选项。
- 越来越多的数据库支持分析原始数据格式（如 CSV 和 JSON）和面向行的二进制格式（如 Apache Avro [6]）—— 所有这些格式在数据湖 [16] 中都非常流行。与**二进制列格式**（如 Apache Parquet [7]）相比，这些格式的数据处理速度较慢并导致成本增加，即使数据已缓存在计算节点上也是如此。同时，将所有数据转换为二进制列格式存储成本很高（用户通常不太愿意），特别是因为查询总是访问一小部分不断变化的数据。
- 现有解决方案中的缓存利用率（即每个缓存字节的值）很低，即使只需要页面中一个记录或值也需要检索和缓存整个页面，从而浪费了宝贵缓存的空间。对于优化的列格式也是如此，这些格式通常为每个块构建 **zone map** [21, 40, 48]（块中每列的最小值和最大值）以避免访问不相关的块。虽然维护 **zone map** 的成本低且可能有用，但它们在块跳过方面的有效性受到以下事实的限制：即使只访问块中一条记录，也需要从存储中检索并扫描完整性。
- 最近，云存储系统提供原生的谓词下推功能，例如 AWS S3 Select [4] 和 Azure Query Acceleration [35]。 下推允许我们将谓词发送到远程存储以避免取回所有块，但加剧了利用谓词提高本地缓存效率的问题。

### 1.2   Opportunities

> In an effort to alleviate some of these challenges, several design trends are now becoming commonplace. Database systems such as Spark are adopting the model of a plug-in “data source” that serves as an input adapter to support data in different formats. These data sources allow the *push-down* of table-level predicates to the data source. While push-down was developed with the intention of data pruning at the source, we find that it opens up a new opportunity to leverage semantics and cache data in more efficient ways.
>
> Moreover, there is rapid convergence in the open-source community on Apache Parquet as a columnar data format, along with highly efficient techniques to apply predicates on them using LLVM with Apache Arrow [5, 8]. This opens up the possibility of system designs that perform a limited form of data processing and transformation *outside* the core DBMS easily and without sacrificing performance. Further, because most DBMSs support Parquet, it gives us an opportunity to cache data in a DBMS-agnostic way.
>

为了缓解其中一些挑战，某些设计趋势越来越趋同。像 Spark 这类数据库系统为支持不同格式的数据，提供 `DataSource` 插件作为输入适配器。这些数据源插件支持表级谓词**下推**。虽然**谓词下推**是为了在数据源进行数据裁剪而开发，但我们发现它提供了新的机会，能以更有效的方式利用语义和缓存数据。

此外，Apache Parquet 在开源社区中作为一种列式数据格式得到了快速的融合，以及 Apache Arrow 使用 LLVM 对 Parquet 应用谓词的高效技术[5,8]。这为系统设计提供了一种可能性，在不牺牲性能的情况下，**在核心 DBMS 之外**轻松地执行有限形式的数据处理和转换。同时因为大多数 DBMS 都支持 Parquet，这让我们有机会以与 DBMS 无关的方式缓存数据。

### 1.3   Introducing Crystal

> We propose a new “smart” storage middleware called *Crystal*, that is decoupled from the database and sits between the DB and raw storage. Crystal may be viewed as a mini-DBMS, or *cache management* *system* (CMS), for storage. It runs as two sub-components:
>
> - The Crystal CMS runs on the compute node, accessible to local “clients” and able to interact with remote storage.
>
> - Crystal’s clients, called *connectors*, are DB-specific adapters that themselves implement the data source API with push-down predicates, similar to today’s CSV and Parquet data sources.
>
> Crystal manages fast local storage (SSD) as a cache and talks to remote storage to retrieve data as needed. Unlike traditional file caches, it determines which *regions* (parts of each table) to transform and cache locally in columnar form. Data may be cached in more than one region if necessary. Crystal receives “queries” from clients, as requests with push-down predicates. It responds with local (in cache) or remote (on storage) paths for ==files that cover the request==. The connectors pass data to the *unmodified* DBMS for post-processing as usual. Benefits of this architecture include:
>
> - It can be shared across multiple unmodified databases, requiring only a lightweight DBMS-specific client connector component. 
> - It can download and transform data into automatically chosen ==semantic regions== in the cache, in a DBMS-agnostic columnar format, reusing new tools such as Parquet and Arrow to do so. 
> - It can independently optimize what data to transform, filter, and cache locally, allowing multiple views of the same data, and efficiently match and serve clients at query time.
>
> These architectural benefits come with technical challenges (Section 2 provides a system overview) that we address in this paper:
>
> - (Sections 2 & 3) Defining an API and protocol to communicate region requests and data between Crystal and its connector clients. 
>
> - (Section 3) Efficiently downloading and transforming data to regions in the local cache, managing cache contents, and storing meta-data for matching regions with push-down predicates over diverse data types, without impacting query latency.
>
> - (Section 4) Optimizing the contents of the cache while: (1) balancing short-term needs (e.g., a burst of new queries) vs. long-term query history; (2) handling queries that are not identical but often overlap; (3) exploiting the benefit of duplicating frequently accessed subsets of data in more than one region; and (4) taking into account the overhead incurred by creating many small files in block columnar format, instead of fewer larger ones; and (5) managing statistics necessary for the above tasks.
>
> Using Crystal, we get ***lower query latencies and more efficient use of the bandwidth between compute and storage***, as compared to state-of-the-art solutions. We validate this by implementing Crystal with Spark and Greenplum connectors (Section 5). Our evaluation using common workload patterns shows Crystal’s ability to outperform block-based caching schemes with lower cache sizes, improve query latencies by up to 20x for individual queries (and up to 8x on average), adapt to workload changes, and save bandwidth from remote storage by up to 41% on average (Section 6). 
>
> We note that Crystal’s cached regions may be considered as materialized views [20, 27, 44, 45] or semantic caches [14, 29, 30, 41– 43, 47], thereby inheriting from this rich line of work. Our caches have the additional restriction that they are strictly the result of single-table predicates (due to the nature of the data source API). <u>==Specifically, Crystal’s regions are **disjunctions** of **conjunctions** of predicates over each individual table==</u>. This restriction is exploited in our solutions to the technical challenges, allowing us to match better, generalize better, and search more efficiently for the best set of cached regions. As data sources mature, we expect them to push down cross-table predicates and aggregates in future, e.g., via *data-* *induced* *predicates* [28]. Such developments will require a revisit of our algorithms in future; for instance, our region definitions will need to represent cross-table predicates. We focus on readonly workloads in this paper; updates can be handled by view invalidation (easy) or refresh (more challenging), and are left as future work. Finally, we note that Crystal can naturally benefit from remote storage supporting push-down predicates; a detailed study is deferred until the technology matures to support columnar formats natively (only CSV files are supported in the current generation). We cover related work in Section 7 and conclude in Section 8.
>

我们提出了一种名为 *Crystal* 的新“智能”存储中间件，它与数据库分离并位于数据库和原始存储之间。 Crystal 可被视为用于存储的小型 DBMS，或**缓存管理系统** (CMS)。 它作为两个子组件运行：

- Crystal CMS 在计算节点上运行，能够与远程存储进行交互；本地**客户端**访问 CMS。
- Crystal 的客户端，称为 *connectors*，是特定于 DB 的适配器，实现数据源 API，且支持谓词下推，类似于今天 Spark 里支持 CSV 的 Parquet 数据源。

Crystal 将本地快速存储 (SSD) 作为缓存管理，并与远程存储通信以根据需要取回数据。与传统的文件缓存不同，它会判断哪些 **region**（表的一部分）会被转换为列格式缓存在本地。如有必要，数据可以缓存在多个 **region** 中。Crystal 从客户端接收带有谓词下推的**查询**。它以本地（缓存）或远程（存储）中的==文件==来响应请求，连接器像往常一样将数据传递给**未修改的** DBMS 进行后处理。 这种架构的好处包括：

- 可以在多个未修改的数据库之间共享，只需一个特定 DBMS 的轻量级客户端连接器组件。
- 可以下载并转换数据为缓存中自动选择的 ==semantic regions==，采用与 DBMS 无关的列格式，重用 Parquet 和 Arrow 等新工具来执行此操作。
- 可以独立优化哪些数据在本地进行转换、过滤和缓存，允许同一数据的多个视图，并在查询时高效地匹配和服务于客户端。

这些体系结构优势带来了技术挑战（第2节提供了系统概述），我们将在本文中讨论这些挑战：

- （第 2 和第 3 节）定义 API 和协议，以便 Crystal 连接器客户端向其请求 **region** 和数据。
- （第 3 节）高效下载和转换数据到本地缓存中的 **region**、管理缓存内容、存储元数据，以便在各种数据类型上使用谓词下推匹配 **region**，而不影响查询延迟。
- （第 4 节）优化缓存内容：（1）平衡短期需求（例如，突发的新查询）与长期历史查询；(2) 处理不完全相同但经常重叠的查询； (3) 利用在多个 **region** 复制频繁访问的数据子集的好处；(4) 考虑到所产生的开销，按块以列格式创建许多小文件而不是更少的大文件；(5) 管理上述任务所需的统计数据。

与最先进的解决方案相比，使用 Crystal 可以获得**更低的查询延迟**，**更有效地利用计算和存储之间的带宽**。我们通过使用 Spark 和 Greenplum 连接器实现 Crystal 来验证这一点（第 5 节）。 通过评估常见的工作负载模式表明，Crystal 能够以较小的缓存大小超越基于块的缓存方案，将单个查询的查询延迟提高多达 20 倍（平均多达 8 倍），适应工作负载变化，平均节省 41% 的远程存储带宽（第6节）。

我们注意到 Crystal 的缓存 **region** 可以被视为**物化视图** [20, 27, 44, 45] 或**语义缓存** [14, 29, 30, 41-43, 47]，从而继承了这一丰富的工作。由于数据源 API 的性质，我们的缓存有一个额外的限制，即它们只是单表谓词的结果。<u>==具体来说，Crystal 的 **region** 是每张表上谓词连接的析取==</u>。我们在解决技术挑战的方案中利用了这一限制，使我们能够更好地匹配、更好地概括并更有效地搜索最佳缓存 region 集。随着数据源的成熟，我们希望在未来可以下推跨表谓词和聚合，例如，通过 *data-induced predicates* [28]。这样的发展将需要在未来重新审视我们的算法；例如，我们 region 的定义需要支持**跨表谓词**。本文主要关注只读工作负载；更新可以通过视图失效（简单）或刷新（更具挑战性）来处理，并留作未来的工作。最后，我们注意到 Crystal 自然而然地能从支持**谓词下推**的远程存储中受益；当前只支持 CSV 格式的文件，详细研究被推迟到技术成熟以支持原生列格式。我们在第 7 节介绍相关工作并在第 8 节总结。


## 2   SYSTEM OVERVIEW

> Figure 1 shows where Crystal fits in today’s cloud analytics ecosystem. Each compute node runs a DBMS instance; Crystal is colocated on the compute node and serves these DBMS instances via data source connectors. The aim is to serve as a caching layer between big data systems and cloud storage, exploiting fast local storage in compute nodes to reduce data accesses to remote storage.

图 1 显示了 Crystal 在当今云分析生态系统中的位置。 每个计算节点运行一个 DBMS 实例； Crystal 位于计算节点上，并通过数据源连接器为这些 DBMS 实例提供服务。目的是作为大数据系统和云存储之间的缓存层，利用计算节点中的快速本地存储来减少对远程存储的数据访问。

### 2.1   Architecture

> A key design goal is to make Crystal sufficiently generic so that it can be plugged into an existing big data system with minimum engineering effort. Therefore, Crystal is architected as two separate components: a light DBMS-specific data source connector and the Crystal CMS process. These are described next.
>
> **2.1.1     Data Source Connector**. Modern big data systems (e.g., Spark, Hive, and Presto) provide a *data source API* to support a variety of data sources and formats. A data source receives push-down filtering and column pruning requests from the DBMS through this API. Thus, the data source has the flexibility to leverage this additional information to reduce the amount of data that needs to be sent back to the DBMS, e.g., via block-level pruning in Parquet. In this paper, we refer to such push-down information as a *query* or *requested region*. A Crystal connector is integrated into the unmodified DBMS through this data source API. It is treated as another data source from the perspective of the DBMS, and as a client issuing queries from the perspective of the Crystal CMS.
>
> **2.1.2     Crystal CMS**. Figure 2 shows the Crystal CMS in detail. It maintains two local caches – a small *requested region* (RR) cache and a large *oracle region* (OR) cache – corresponding to shortand long-term knowledge respectively. Both caches store data in an efficient columnar open format such as Parquet. Crystal receives “queries” from connectors via the Crystal API. <u>==A query consists of a request for a file (remote path) with push-down predicates==</u>. Crystal first checks with the Matcher to see if it can cover the query using one or more cached regions. If yes (cache hit), it returns a set of file paths from local storage. If not (cache miss), there are two options:
>
> 1. It responds with the remote path so that the connector can process it as usual. Crystal optionally requests the connector to store the downloaded and filtered region in its RR cache.
> 2. It downloads the data from remote, applies predicates, stores the result in the RR cache, and returns this path to the connector.
>
> Thus, the RR cache is populated **eagerly** by either Crystal or the DBMS. Not every requested region is cached eagerly; instead an LRU-2 based decision is taken per request.
>
> More importantly, in the background, Crystal collects a historical trace of queries and invokes a caching Oracle Plugin module to compute the best content for the OR cache. The new content is populated using a combination of remote storage and existing content in the RR and OR caches. Section 3 covers region processing in detail, while Section 4 covers cache optimization.

一个关键的设计目标是使 Crystal 具有足够的通用性，以便它能以最少的工程量接入到现有的大数据系统中。因此，Crystal 被构建为两个独立的组件：一个特定 DBMS 的轻量级数据源连接器和 Crystal CMS 进程：

**2.1.1 数据源连接器**。 现代大数据系统（例如 Spark、Hive 和 Presto）提供了**数据源 API** 来支持各种数据源和格式。 数据源通过此 API 从 DBMS 接收谓词下推和列裁剪请求。因此，数据源可以灵活地利用这些附加信息来减少需要返回 DBMS 的数据量，例如，通过 Parquet 中的块级裁剪。本文将此类下推信息称为 **query** 或 **requested region**。 Crystal 连接器通过此数据源 API 集成到未修改的 DBMS 中。从 DBMS 的角度来看，它被视为另一个数据源，从 Crystal CMS 的角度来看，它被视为发出查询的客户端。

**2.1.2     Crystal CMS**。 图 2 详细显示了 Crystal CMS。 它维护两个本地缓存 —— 一个小的 **requested region**（RR）缓存和一个大的 **oracle region**（OR）缓存 —— 分别对应于短期和长期缓存。两个缓存都以 Parquet 格式存储数据。 Crystal 通过 Crystal API 从连接器接收**查询**。<u>==查询由对带有下推谓词（远程路径）文件的请求组成==</u>。 Crystal 首先检查**匹配器**以查看它是否可以使用一个或多个缓存 **region** 覆盖查询。 如果（缓存命中），它会从本地存储返回一组文件路径。 如果没有（缓存未命中），则有两种选择：

1. 以远程路径响应，连接器可以照常处理它。 Crystal 可选择请求连接器将下载和过滤的 region 存储在 RR 缓存中。
2. 从远程下载数据，应用谓词并将结果存储在 RR 缓存中，并将此路径返回给连接器。

因此，RR 缓存由 Crystal 或 DBMS  **热切地**填充。 并非每个请求的 region 都被**急切地**缓存；相反，每个请求都会基于 LRU-2 做出决定。

‼️更重要的是在后台，Crystal 收集查询历史并调用 **oracle cache** 插件模块来计算放置在 OR 缓存中的最佳内容。使用远程存储和 RR 和 OR 缓存中现有内容的组合填充新内容。第 3 节详细介绍了 region 处理，而第 4 节介绍了缓存优化。

### 2.2   Generality of the Crystal Design

As mentioned above, Crystal is architected with a view to making it easy to use with any cloud analytics system. Crystal offers three extensibility points. **First**, users can replace the caching oracle with a custom implementation that is tailored to their workload. Second, the remote storage adapter may be replaced to work with any cloud remote storage. Third, a custom connector may be implemented for each DBMS that needs to use Crystal.

The connector interfaces with Crystal with a generic protocol based simply on file paths. Cached regions are stored in an open format (Parquet) rather than the internal format of a specific DBMS, making it DBMS-agnostic. Further, a connector can feed the cached region to the DBMS by simply invoking its built-in data source for the open format (e.g., the built-in Parquet reader in Spark) to read the region. Thus, the connector developer does not need to manually implement the conversion, making its implementation a fairly straightforward process. In Section 5, we discuss our connectors for Spark and Greenplum, which take less than 350 lines of code.

如上所述，Crystal 的架构旨在使其易于与任何云分析系统一起使用。 Crystal 提供了三个扩展点。**首先**，用户可以使用根据其工作负载定制自定义的实现以替换 oracle cache。**其次**，可以更换**远程存储适配器**以与**远程云存储**一起使用。第三，可以为每个需要使用 Crystal 的 DBMS 实现自定义连接器。

连接器通过基于文件路径的通用协议与 Crystal 交互。缓存区域以开放格式 (Parquet) 而不是特定 DBMS 的内部格式存储，使其与 DBMS 无关。

此外，连接器可以简单地调用其内置的数据源（例如，Spark 中内置的 Parquet reader）来读取该 **region**，从而将缓存的 region 提供给 DBMS。

因此，连接器开发人员不需要手动实现转换，从而使其实现过程相当简单。在第 5 节中，我们讨论了用于 Spark 和 Greenplum 的连接器，它们只需要不到 350 行代码。

因此，连接器开发人员不需要手动实现转换，从而使其实现成为一个相当简单的过程。在第5节中，我们将讨论Spark和Greenplum的连接器，它们只需要不到350行代码。

### 2.3   Revisiting the Caching Problem

Leveraging push-down predicates, Crystal caches different subsets of data called regions. Regions can be considered as views on the table, and are a form of semantic caching [14, 29, 30, 42, 43, 47]. Compared to traditional file caching, the advantage of semantic caching is two-fold. First, it usually returns a much tighter view to the DBMS, and thus reduces the need to post-process the data, saving I/O and CPU cost. Second, regions can be much smaller than the original files, resulting in better cache space utilization and higher hit ratios. For example, Figure 3 shows a case where regions capture all views of all queries, whereas LRU-based file caching can only keep less than half of these views.

Cached regions in Crystal may overlap. In data warehouses and data lakes, it is common to see that a large number of queries access a few tables or files, making overlapping queries the norm rather than the exception at the storage layer. Therefore, Crystal has to take overlap into account when deciding which cached data should be evicted. To the best of our knowledge, previous work on replacement policies for semantic caching does not consider overlap of cached regions (see more details in Section 7).

With overlapping views, the replacement policy in Crystal becomes a very challenging optimization problem (details in Section 4). Intuitively, when deciding if a view should be evicted from the cache, all other views that are overlapping with this view should also be taken into consideration. As a result, traditional replacement policies such as LRU that evaluate each view independently are not suitable for Crystal, as we will show in the evaluation (Section 6). 

Recall that we split the cache into two regions: requested region (RR) and oracle region (RR). The OR cache models and solves the above problem as an optimization problem, which aims to find the nearly optimal set of overlapping regions that should be retained in the cache. Admittedly, solving the optimization problem is expensive and thus cannot be performed on a per-request basis. Instead, the OR cache recomputes its contents periodically, and thus mainly targets queries that have sufficient statistics in history. In contrast, the RR cache is optimized for new queries, and can react immediately to workload changes. Intuitively, the RR cache serves as a “buffering” region to temporarily store the cached views for recent queries, before the OR cache collects sufficient statistics to make longer-term decisions. This approach is analogous to the CStore architecture [46], where a writable row store is used to absorb newly updated data before it is moved to a highly optimized column store in batches. Collectively, the two regions offer an efficient and reactive solution for caching.

## 3   REGION PROCESSING

In this section, we focus on region matching and the creation of cached regions. Before we explain the details of the process of creating regions and matching cached regions to requests, we first show how to transform client requests into region requests.

### 3.1   API

Crystal acts as a storage layer of the DBMS. It runs outside the DBMS and transfers information via a minimalistic socket connection and shared space in the filesystem (e.g., SSDs, ramdisk). During a file request, the DBMS exchanges information about the file and the required region with Crystal. Because access to remote files is expensive, Crystal tries to satisfy the request with cached files.

The overall idea is that Crystal overwrites the accessed file path such that the DBMS is pointed to a local file. For redirecting queries, Crystal relies on query metadata such as the file path, push-down predicates, and accessed fields. Crystal evaluates the request and returns a cached local file or downloads the requested file. Afterward, the location of the local file is sent to the DBMS which redirects the scan to this local file. Crystal guarantees the completeness for a given set of predicates and fields. Internally, Crystal matches the query metadata with local cache metadata and returns a local file if it satisfies the requirements.

We use a tree string representation for push-down predicates in our API. Since predicates are conventionally stored as an AST in DBMS, we traverse the AST to build the string representation. Each individual item uses the syntax similar to *operation(left, right)*. We support binary operators, unary operators, and literals which are the leaf nodes of the tree. The binary operation is either a combination function of multiple predicates (such as *and*, *or*) or an atomic predicate (such as *gt*, *lt*, *eq*, . . . ). Atomic predicates use the same binary syntax form in which *left* represents the column identifier and *right* the compare value. To include the negation of sub-trees, our syntax allows *operation(exp)* with the operation *not*.

### 3.2   Transformation & Caching Granularity
Crystal receives the string of push-down predicates and transforms it back to an internal AST. Because arguing on arbitrarily nested logical expressions (with *and* and *or*) is hard, Crystal transforms the AST to Disjunctive Normal Form (DNF). In the DNF, all conjunctions are pushed down into the expression tree, and conjunctions and disjunctions are no longer interleaved. In Crystal, regions are identified by their disjunction of conjunctions of predicates. Regions also contain their sources (i.e., the remote files) and the projection of the schema. This allows us to easily evaluate equality, superset, and intersection between regions which we show in Section 3.3.

The construction of the DNF follows two steps. First, all negations are pushed as far as possible into the tree which results in Negation Normal Form (NNF). Besides using the De-Morgan rules to push down negations, Crystal pushes the negations inside the predicates. For example, *not(lt(id, 1))* will be changed to *gteq(id, 1)*.

After receiving the NNF, Crystal distributes conjunctions over disjunctions. The distributive law pushes *or*s higher up in the tree which results in the DNF. It transforms *and(a, or(b, c))* to *or(and(a, b), and(a, c))*. Although this algorithm could create 2*𝑛* leaves in theory, none of our experiments indicate issues with blow-up.

Because the tree is in DNF, the regions store the pushed-down conjunctions as a list of column restrictions. These conjunctions of restrictions can be seen as individual geometric hyper-rectangles. Regions are fully described by the disjunction of these hyperrectangles. Figure 4 shows the process of creating the DNF and extracting the individual hyper-rectangles. Although we use the term hyper-rectangles, the restrictions can have different shapes. Crystal supports restrictions, such as *noteq*, *isNull*, and *isNotNull*, that are conceptually different from hyper-rectangles.

Crystal’s base granularity of items is on the level of regions, thus all requests are represented by a disjunction of conjunctions. However, individual conjunctions of different regions can be combined to satisfy an incoming region request. Some previous work on semantic caching (e.g., [14, 17]) considers only non-overlapping hyper-rectangles. Non-overlapping regions can help reduce the complexity of the decision-making process. Although this is desirable, non-overlapping regions impose additional constraints.

Splitting the requests into sets of non-overlapping regions is expensive. In particular, the number of non-overlapping hyperrectangles grows combinatorial. To demonstrate this issue, we evaluated three random queries in the lineitem space which we artificially restrict to 8 dimensions [23]. If we use these three random hyper-rectangles as input, 16 hyper-rectangles are needed to store all data non-overlapping. This issue arises from the number of dimensions that allow for multiple intersections of hyper-rectangles. 

Each intersection requires the split of the rectangle. In the worst case, this grows combinatorial in the number of hyper-rectangles. Because all extracted regions need statistics during the cache optimization phase, the sampling of this increased number of regions is not practical. Further, the runtime of the caching policies is increased due to the larger input which leads to outdated caches. 

Moreover, smaller regions require that more cached files are returned to the client. Figure 5 shows that each additional region incurs a linear overhead of roughly 50ms in Spark. The preliminary experiment demonstrates that splitting is infeasible due to the combinatorial growth of non-overlapping regions. Therefore, Crystal does not impose restrictions on the semantic regions themselves. This raises an additional challenge during the optimization phase of the oracle region cache, which we address in Section 4.5.

### 3.3   Region Matching

With the disjunction of conjunctions, Crystal determines the relation between different regions. Crystal detects equality, superset, intersections, and partial supersets relations. Partial supersets contain a non-empty number of conjunctions fully.

Crystal uses intersections and supersets of conjunctions to argue about regions. Conjunctions contain restrictions that specify the limits of a column. Every conjunction has exactly one restriction for each predicated column. Restrictions are described by their column identifier, their range (*min, max*), their potential equal value, their set of non-equal values and whether *isNull* or *isNotNull* is set. If two restrictions 𝑝*𝑥* and 𝑝*𝑦* are on the same column, Crystal computes if 𝑝*𝑥* completely satisfies 𝑝*𝑦* or if 𝑝*𝑥* has an intersection with 𝑝*𝑦* . For determining the superset, we first check if the null restrictions are not contradicting. Second, we test whether the (*min, max*) interval of 𝑝*𝑥* is a superset of 𝑝*𝑦* . Afterward, we check whether 𝑝*𝑥* has restricting non-equal values that discard the superset property and if all additional equal values of 𝑝*𝑦* are also included in 𝑝*𝑥* .                                 

For two conjunctions 𝑐*𝑥* and 𝑐*𝑦* , 𝑐*𝑥* ⊃  𝑐*𝑦* if 𝑐*𝑥* only contains restrictions that are all less restrictive than the restrictions on the same column of 𝑐*𝑦* . Thus, 𝑐*𝑥* must have an equal number or fewer restrictions which are all satisfying the matched restrictions of 𝑐*𝑦* . Otherwise, 𝑐*𝑥* ⊅ 𝑐*𝑦* . 𝑐*𝑥* can have fewer restrictions because the absence of a restriction shows that the column is not predicated. 

In the following, we show the algorithms to determine the relation between two regions 𝑟*𝑥* and 𝑟*𝑦* .

- `𝑟𝑥 ⊃ 𝑟y`  holds if all conjunctions of 𝑟*𝑦* find a superset in 𝑟*𝑥* .
- `𝑟𝑥 ∩  𝑟𝑦 ≠ ∅` holds if at least one conjunction of 𝑟*𝑥* finds an intersecting conjunction of 𝑟*𝑦* .
- `∃ conj ⊂  𝑟𝑥 : conj ⊂  𝑟𝑦` (partial superset) holds if at least one conjunctions of 𝑟*𝑦* finds a superset in 𝑟*𝑥* .
- `𝑟𝑥 = 𝑟𝑦 : 𝑟𝑥 ⊃ r𝑦 ∧ 𝑟𝑦 ⊃ 𝑟𝑥`

Figure 6 shows an example that matches a query that consists of two hyper-rectangles to two of the stored regions.

### 3.4   Request Matching

During region requests, Crystal searches the caches to retrieve a local superset. Figure 7 shows the process of matching the request. First, the oracle region cache is scanned for matches. If the request is not fully cached, Crystal tries to match it with the requested region cache. If the query was not matched, the download manager fetches the remote files (optionally from a file cache).

During the matching, a full superset is prioritized. Only if no full superset is found, Crystal tries to satisfy the individual conjunctions. The potential overlap of multiple regions and the overhead shown in Section 3.2 are the reasons to prefer full supersets. If an overlap is detected between 𝐴 and 𝐵, Crystal needs to create a reduced temporary file. Otherwise, tuples are contained more than once which would lead to incorrect results. For example, it could return 𝐴 and 𝐵 − 𝐴 to the client. The greedy algorithm, presented in Algorithm 1 reduces the number of regions if multiple choices are possible. We choose the region that satisfies most of the currently unsatisfied conjunctions and continue until all have been satisfied. 

We optimize the matching of regions by partitioning the cache according to the remote file names and the projected schema. The file names are represented as (bit-)set of the remote file catalog. This set is sharded by the tables. Similarly, the schema can be represented as a (bit-)set. The partitioning is done in multiple stages. After the fast file name superset check, all resulting candidates are tested for a superset of the schema. Only within this partition of superset regions, we scan for a potential match. Although no performance issues arise during region matching, multi-dimensional indexes (e.g., R-trees) can be used to further accelerate lookups.

### 3.5   Creating Regions

The cached regions of Crystal are stored as Apache Parquet files. Crystal leverages Apache Arrow for reading and writing snappy encoded Parquet files. Internally, Parquet is transformed into Arrow tables before Crystal creates the semantic regions.

Gandiva, which is a newly developed execution engine for Arrow, uses LLVM compiled code to filter Arrow tables [8]. As this promises superior performance in comparison to executing tuple-at-a-time filters, Crystal translates its restrictions to Gandiva filters. When Crystal builds new Parquet files to cache, the filters are compiled to LLVM and executed on the in-memory Arrow data. Afterward, the file is written to disk as snappy compressed Parquet file. If a file is accessed the first time, Crystal creates a sample that is used to predict region sizes and to speed up the client’s query planning.

### 3.6   Client Database Connector

Database systems are often able to access data from different formats and storage layers. Many systems implement a connection layer that is used as an interface between the DBMS and the different formats. For example, Spark uses such an abstraction layer known as data source.

Crystal is connected to the DBMS by implementing such a small data source connector. As DBMSs can process Parquet files already, we can easily adapt this connector for Crystal. Crystal interacts with the DBMS via a socket connection and transfers files via shared disk space or ramdisk. Since Crystal returns Parquet files, the DBMS can already process them without any code modifications.

The only additional implementation needed is the exchange of control messages. These consist of only three different messages and the responses of Crystal. One of the messages is optional and is used to speed up query planning. The scan request message and the message that indicates that a scan has finished are required by all Crystal clients. The first message includes the path of the remote file, the push-down predicates, and the required fields of the schema. Crystal replies with a collection of files that can be used instead of the original remote file. The finish message is required to delete cached files safely that are no longer accessed by the client. The optional message inquires a sample of the original data to prevent storage accesses during query planning.

### 3.7   Cloud Connection

Crystal itself also has an interface similar to the data source. This interface is used to communicate with various cloud connectors. The interface implements simple file operations, such as listings of directories and accesses to files. For blob storage, the later operation basically downloads the file from remote storage to the local node. 

Recently, cloud providers have been adding predicate push-down capabilities to their storage APIs, e.g., S3 Select [4]. Clients can push down filters to storage and receive the predicated subset. This feature can incur additional monetary costs, as well as a per-request latency. Crystal complements this feature naturally, as it is aware of semantic regions and can use predicate push-down to populate its cache efficiently. As Crystal can reuse cached results locally, it can save on future push-down costs as well.

Crystal implements a download manager that fetches blobs from remote and stores them into ramdisk. The client is pointed to this location, and as soon as it finishes accessing it, the file is deleted again. Multiple accesses can be shared by reference counting.

## 4   CACHE OPTIMIZATION

This section summarizes the architecture of our caches, followed by more details on caching. Finally, we explain our algorithms that explore and augment the overlapping search space.

### 4.1   Requested Region and Oracle Region Cache 

Recall that Crystal relies on two region caches to capture shortand long-term trends. The *RR* cache is an eager cache that stores the result of recently processed regions. The long-term insights of the query workload are captured by the *OR* cache. This cache leverages the history of region requests to compute the ideal set of regions to cache locally for best performance. Crystal allows users to plug-in a custom oracle; we provide a default oracle based on a variant of Knapsack (covered later). After the oracle determines a new set of regions to cache, Crystal computes these regions in the background and updates the *OR* cache. The creation in the background allows to schedule more expensive algorithms (runtime) to gather meaningful insights. This allows for computing (near-) optimal results and the usage of machine learning in future work. The oracle runs in low priority, consuming as little CPU as possible during high load.

An interesting opportunity emerges from the collaboration between the two caches. If the *OR* cache decided on a set of long-term relevant regions, the requested region cache does not need to compute any subset of the already cached long-term regions. On the other hand, if the requested region cache has regions that are considered for long-term usage, the *OR* cache can take control over these regions and simply move them to the new cache.

### 4.2   Metadata Management

A key component for predicting cached regions is the history of requested regions. To recognize patterns, the previously accessed regions are stored within Crystal. We use a ring-buffer to keep the most recent history. Each buffer element represents a single historic region request which has been computed by a collection of (remote) data files. These files are associated with schema information, tuple count, and size. The selectivity of the region is captured by result statistics. The database can either provide result statistics, or Crystal will compute them. Crystal leverages previously created samples to generate result statistics. In conjunction with the associated schema information, Crystal predicts the tuple count and the result size.

### 4.3   Oracle Region Cache

Long-term trends are detected by using the oracle region cache. An oracle decides according to the seen history which regions need to be created. The history is further used as a source of candidate regions that are considered to be cached.

The quality of the cached items is evaluated with the recent history of regions. Each cached region is associated with a benefit value. This value is the summation of bytes that do not need to be downloaded if the region is stored on the DBMS node. In other words, how much network traffic is saved by processing the history elements locally. Further, we need to consider the costs of storing candidate regions. The costs of a region are simply given by the size it requires to be materialized. The above caching problem can be expressed as the knapsack problem: maximize $\sum\nolimits_{i=1}^nb_ix_i$ subject to $\sum\nolimits_{i=1}^nw_ix_i \leqslant W$ Where $x_i \in \{0, 1\}$. The saved bandwidth by caching a region is denoted by 𝑏, the size of the materialized cache by 𝑤 . If the region is picked 𝑥 = 1, otherwise 𝑥 = 0. The goal is to maximize the benefit while staying within the capacity 𝑊 .

However, the current definition cannot capture potential overlap in regions well. As the benefit value is static, history elements that occur in multiple regions would be added more than once to the overall value. Thus the maximization would result in a suboptimal selection of regions. In Section 4.5, we show the adaptations of our proposed algorithm to compensate for the overlapping issue.

### 4.4   Knapsack Algorithms

Dynamic programming (DP) can be used to solve the knapsack optimally in pseudo-polynomial time. The most widespread algorithm iterates over the maximum number of considered items and the cache size to solve the knapsack optimal for each sub-problem instance. Combining the optimally solved sub-problems results in the optimal knapsack, but the algorithm lies in the complexity of O( 𝑛 ∗ 𝑊). Another possible algorithm iterates over the items and benefit values, and lies in O(𝑛 ∗ 𝐵 ) (𝐵 denotes maximum benefit). 
In our caching scenario, we face two challenges with the DP approach. First, both 𝑊 (bytes needed for storing the regions) and 𝐵 (bytes the cached element saves from being downloaded) are large. Relaxing these values by rounding to mega-bytes or gigabytes reduces the complexity, however, the instances are not solved optimally anymore. Second, the algorithm considers that each subproblem was solved optimally. To solve the overlapping issue, only one region is allowed to take the benefit of a single history element. An open question is to decide which sub-problem receives the benefit of an item that can be processed with several regions.

Since many knapsack instances face a large capacity 𝑊 and unbound benefit 𝐵, approximation algorithms were explored. In particular, the algorithm that orders items according to the benefitcost ratio has guaranteed bounds and a low runtime complexity of O(𝑛 ∗𝑙𝑜𝑔(𝑛)). The algorithm first calculates all benefit ratios 𝑣 = *𝑏/w* and orders the items accordingly. In the next step, it greedily selects the items as long as there is space in the knapsack. Thus, the items with the highest cost to benefit ratio 𝑣 are contained in the knapsack. This algorithm solves the relaxed problem of the fractional knapsack optimal which loosens `𝑥 ∈ {0, 1}` to `𝑥 ∈ [0, 1]` [24].

### 4.5   Overlap-aware Greedy Algorithm

> - [ ] TODO

### 4.6   Region Augmentation

> - [ ] TODO

### 4.7   Requested Region Cache

The requested region cache is similar to a traditional cache but with semantic regions instead of pages. It decides in an online fashion whether the requested region should be cached. The algorithm must be simple to reduce decision latencies. Traditional algorithms, such as LRU and its variants, are good fits in terms of accuracy and efficiency. Besides the classic LRU cache, experiments showed the benefit of caching regions after the second (k-th in general) occurrence. With the history already available for *OR*, this adaption is simple and does not introduce additional latency. For combined *OR* and *RR* with *LRU-k*, it is beneficial to reduce the history size by the *RR/OR* split as long-term effects are captured by *OR*.

One of the biggest advantages of the *RR* cache is the fast reaction to changes in the queried workload. In comparison to the *OR* cache that only refreshes periodically, the request cache is updated constantly. This eager caching, however, might result in overhead due to additional writing of the region file. To overcome this issue, the client DBMS can simultaneously work on the raw data and provide the region as a file for Crystal; this extension is left as future work.

## 5   IMPLEMENTATION DETAILS

Crystal is implemented as a stand-alone and highly parallel process that sits between the DBMS and blob storage. This design helps to accelerate workloads across different database systems. Crystal is a fully functional system that works with diverse data types and query predicates, and is implemented in C++ for optimal performance. **Parallel Processing within Crystal.** Latency critical parts of Crystal are optimized for multiple connections. Each new connection uses a dedicated thread for building the predicate tree and matching cached files. If a file needs to be downloaded, it is retrieved by a pool of download threads to saturate the bandwidth. All operations are either implemented lock-free, optimistically, or with fine-grained shared locks. Liveness of objects and their managed cached files is tracked with smart pointers. Therefore, Crystal parallelizes well and can be used as a low latency DBMS middleware.

Crystal also handles large files since some systems do not split Parquet files into smaller chunks. During matching we recognize which parts of the original file would have been read and translate it to the corresponding region in the cached files. Further, we are able to parallelize reading and processing Parquet files.

**Spark Data Source.** For our evaluation, we built a data source to communicate between Spark and Crystal, by extending the existing Parquet connector of Spark with less than 350 lines of Scala code. The connector overrides the scan method of Parquet to retrieve the files suggested by Crystal. Because Spark pushes down predicates to the data source, we have all information available for using the Crystal API. As Spark usually processes one row iterator per file, we developed a meta-iterator that combines multiple file iterators transparently (Crystal may return multiple regions). The connector is packaged as a small and dynamically loaded Java jar.

**Greenplum Data Source.** Further, we built a connector for Greenplum which is a cloud scale PostgreSQL derivative with an external extension framework – called PXF [34, 51]. PXF allows one to access Parquet data from blob storage [52]. We modified the Parquet reader such that it automatically uses Crystal if available. Our changes to the Greenplum connector consist of less than 150 lines of code. Without recompiling the core database, Crystal accelerates Greenplum by dynamically attaching the modified PXF module.

Both connectors currently do not support sending regions back to Crystal; instead, Crystal itself handles additions to the RR cache.

**Azure Cloud Connection.** We use Azure Blob Storage to store remote data, using a library called azure-storage-cpplite [37] to implement the storage connector. The library just translates the file accesses to CURL (HTTPS) requests. Other cloud providers have similar libraries with which connections can be easily established. Crystal infers the cloud provider from the remote file path. The file path also gives insights into the file owner (user with pre-configured access token) and the blob container that includes the file.

## 6   EXPERIMENTAL EVALUATION

## 7   RELATED WORK

The basic idea behind Crystal is to cache and reuse computations across multiple queries. This idea has been explored in a large body of research work including at least four broad lines of research: materialized view, semantic caching, intermediate results reusing, and mid-tier database caching. In general, Crystal differs from previous work in some or all of the following ways: 1) integrating Crystal with a DBMS requires no modification to the DBMS; 2) Crystal focuses on caching views at the storage layer, and can be used across multiple DBMSs; 3) Crystal can automatically choose cached views based on a replacement policy, which takes into account the semantic dependencies among queries. Below, we discuss the key differences between Crystal and previous work in each line of the four aforementioned research areas.

**Materialized View.** Materialized view is a well-known technique that caches the results of a query as a separate table [20, 44, 45]. However, unlike Crystal, views that need to be cached or materialized are often defined manually by users (e.g., a DBA). Additionally, implementing materialized views in a DBMS is a timeconsuming process, requiring advanced algorithms in the query optimizer to decide: 1) if a given query can be evaluated with a materialized view; and 2) if a materialized view needs to be updated when the base table is changed.

**Semantic Caching.** Semantic caching was first proposed in Postgres [47], and was later extended and improved by a large body of work [11, 14, 17, 29, 30, 42, 43]. This technique also aims to cache the results of queries to accelerate repeated queries. Similarly to Crystal, a semantic cache can automatically decide which views to keep in the cache, within a size budget. This decision is often made based on a cost-based policy that takes several properties of views into consideration such as size, access frequency, materialization cost. However, this approach caches the end results of entire queries, while Crystal caches only the intermediate results of the selection and projection operators of queries. The cached view of an entire query is especially beneficial for repeated queries, but on the other hand decreases the reusability of the cached view, i.e., the chance that this view can be reused by future queries. While most work in this area does not take into account overlap of cached views, some work [14, 17] does explore this opportunity. Dar et al. proposed to split overlapping queries into non-overlapping regions, and thus enable semantic cache to use traditional replacement policies to manage the (non-overlapping) regions [14]. However, this approach could result in a large number of small views, incurring significant overhead to process as we showed in Sec 3.2. Maintaining nonoverlapping views is also expensive, as access to an overlapping view may lead to splitting the view and rewriting the cached files. Chunk-based semantic caching [17] was proposed to solve this problem, by chunking the hyper space into a large number of regions that are independent to queries. However, the chunking is pre-defined and thus is static with respect to the query patterns.

**Intermediate Results Reusing.** Many techniques have also been developed to explore the idea of reusing intermediate results rather than end results of queries. Some of these techniques [49, 50] share the intermediate results across concurrent queries only, and thus impose limitations on the temporal locality of overlapping queries. Other work [19, 25–27, 38, 41] allows intermediate results to be stored so that they can be reused by subsequent queries. Similarly to Crystal, these techniques also use a replacement policy to evict intermediate results when the size limit is reached. However, these techniques require extensive effort to be integrated with a DBMS, whereas integrating Crystal requires only a lightweight database-specific connector. Additionally, a Crystal cache can be used with and share data across multiple DBMSs.

**Mid-tier Database Caching.** Another area where views can be cached and reused is in the context of multi-tier database architecture, where mid-tier caches [2, 10, 31] are often deployed at the mid-tier application servers to reduce the workload for the backend database servers. As mid-tier caches are not co-located with DBMSs, they usually include a shadow database at the mid-tier servers that mirrors the backend database but without actual content, and rely on materialized views in the shadow database to cache the results of queries. Unlike Crystal, the definition of the cached views in a mid-tier cache needs to be pre-defined manually by users, and it is difficult to change the cached views adaptively.

Finally, many vendors have developed cache solutions for big data systems to keep hot data in fast local storage (e.g., SSDs). Examples include the Databricks Delta Cache [9, 15], the Alluxio [1] analytics accelerator, and the Snowflake Cache Layer [13]. These solutions are based on standard techniques that simply cache files at the page or block level and employ standard replacement policies such as LRU. Compared to these standard approaches, Crystal is also a generic cache layer that can be easily integrated with unmodified big data systems, but has the flexibility to cache data in a more efficient layout (i.e., re-organizing rows based on queries) and format (i.e., Parquet), which speeds up subsequent query processing.

## 8   CONCLUSION

Cloud analytical databases employ a disaggregated storage model, where the elastic compute layer accesses data on remote cloud storage in columnar formats. Smart caching is important due to the high latency and low bandwidth to remote storage and the limited size of fast local storage. Crystal is a smart cache storage system that colocates with compute and can be used by any unmodified database via data source connector clients. Crystal operates over semantic data regions, and continuously adapts what is cached locally for maximum benefit. Results show that Crystal can significantly improve query latencies on unmodified Spark and Greenplum, while also saving on bandwidth from remote storage.

