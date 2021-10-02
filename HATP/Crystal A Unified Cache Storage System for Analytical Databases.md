#  **Crystal**: A Unified Cache Storage System for Analytical Databases

> **ABSTRACT** Cloud analytical databases employ a **disaggregated storage model**, where the elastic compute layer accesses data persisted on remote cloud storage in block-oriented columnar formats. Given the high latency and low bandwidth to remote storage and the limited size of fast local storage, caching data at the compute node is important and has resulted in a renewed interest in caching for analytics. Today, each DBMS builds its own caching solution, usually based on file or block-level LRU. In this paper, we advocate a new architecture of a smart cache storage system called *Crystal*, that is co-located with compute. Crystal’s clients are DBMS-specific “data sources” with push-down predicates. Similar in spirit to a DBMS, Crystal incorporates query processing and optimization components **==focusing on efficient caching and serving of single-table hyper-rectangles called <u>regions</u>==**. Results show that Crystal, with a small DBMS-specific data source connector, can significantly improve query latencies on unmodified Spark and Greenplum while also saving on bandwidth from remote storage.

**摘要**   云分析数据库采用**==分解存储模型==**，其中弹性计算层访问远程云存储上持久化的数据。考虑到远程存储的高延迟和低带宽以及有限的本地快速存储，在计算节点上缓存数据非常重要，**并导致了对缓存进行分析的新兴趣**。今天，每个 DBMS 都构建自己的缓存解决方案，通常基于文件或块级 LRU。我们在本文中，提出了一种新的智能缓存存储架构，称为 *Crystal*，与计算共存。***Crystal*** 的客户端是`特定 DBMS 的数据源`，带有下推谓词。本质上与 DBMS 类似，Crystal 包含查询处理和优化组件，**==专注于高效缓存和服务称为 <u>region</u> 的单表超矩形==**。结果表明，Crystal 带有一个特定于 DBMS 的小型数据源连接器，可以显着提高原生 Spark 和 Greenplum 上的查询延迟，同时还节省远程存储的带宽。

## 1   ✅ INTRODUCTION

> We are witnessing a paradigm shift of analytical database systems to the cloud, driven by its flexibility and **pay-as-you-go** capabilities. Such databases employ a tiered or disaggregated storage model, where the elastic *compute tier* accesses data persisted on independently scalable remote *cloud storage*, such as Amazon S3 [3] and Azure Blobs [36]. Today, nearly all big data systems including Apache Spark, Greenplum, Apache Hive, and Apache Presto support querying cloud storage directly. Cloud vendors also offer cloud services such as AWS Athena, Azure Synapse, and Google BigQuery to meet this increasingly growing demand.
>
> Given the relatively high latency and low bandwidth to remote storage, *caching data* at the compute node has become important. As a result, we are witnessing a <u>==renewed spike==</u> in caching technology for analytics, where the hot data is kept at the compute layer in fast local storage (e.g., SSD) of limited size. Examples include the Alluxio [1] analytics accelerator, the Databricks Delta Cache [9, 15], and the Snowflake cache layer [13].

在**灵活性**和**即用即付**功能的推动下，我们正在见证分析数据库系统向云模式的转变。此类数据库采用分层或分解的存储模型，其中弹性**计算层**访问远程可独立扩展的**云存储**上的数据，例如 Amazon S3 [3] 和 Azure Blob [36]。如今，包括 Apache Spark、Greenplum、Apache Hive 和 Apache Presto 在内的几乎所有大数据系统都支持直接查询云存储。云供应商还提供 AWS Athena、Azure Synapse 和 Google BigQuery 等云服务来满足这种日益增长的需求。

由于远程存储相对较高的延迟和较低的带宽，在计算节点上**缓存数据**变得很重要。因此，我们看到用于分析的缓存技术出现了新的高峰，其中热数据保存在计算层的快速本地存储（例如，SSD）中，大小有限。包括 Alluxio [1] 分析加速器、Databricks Delta 缓存 [9, 15] 和 Snowflake 缓存层 [13]。

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

> As mentioned above, Crystal is architected with a view to making it easy to use with any cloud analytics system. Crystal offers three extensibility points. **First**, users can replace the caching oracle with a custom implementation that is tailored to their workload. Second, the remote storage adapter may be replaced to work with any cloud remote storage. **Third**, a custom connector may be implemented for each DBMS that needs to use Crystal.
>
> The connector interfaces with Crystal with a generic protocol based simply on file paths. Cached regions are stored in an open format (Parquet) rather than the internal format of a specific DBMS, making it DBMS-agnostic. Further, a connector can feed the cached region to the DBMS by simply invoking its built-in data source for the open format (e.g., the built-in Parquet reader in Spark) to read the region. Thus, the connector developer does not need to manually implement the conversion, making its implementation a fairly straightforward process. In Section 5, we discuss our connectors for Spark and Greenplum, which take less than 350 lines of code.
>

如上所述，Crystal 的架构旨在使其易于与任何云分析系统一起使用。 Crystal 提供了三个扩展点。**首先**，用户可以使用根据其工作负载定制自定义的实现以替换 oracle cache。**其次**，可以更换**远程存储适配器**以与**远程云存储**一起使用。**第三**，可以为每个需要使用 Crystal 的 DBMS 实现自定义连接器。

连接器通过基于文件路径的通用协议与 Crystal 交互。缓存区域以开放格式 (Parquet) 而不是特定 DBMS 的内部格式存储，使之与 DBMS 无关。此外，将缓存的 **region** 提供给 DBMS，连接器可以简单地调用其内置的 `DataSource`（例如，Spark 中内置的 Parquet reader）来读取。连接器开发人员不需要手动实现转换，因此实现过程相当简单。第 5 节，我们用不到 350 行代码实现了 Spark 和 Greenplum 连接器。

### 2.3   Revisiting the Caching Problem

> Leveraging push-down predicates, Crystal caches different subsets of data called regions. Regions can be considered as views on the table, and are a form of semantic caching [14, 29, 30, 42, 43, 47]. Compared to traditional file caching, the advantage of semantic caching is two-fold. **First**, it usually returns a much tighter view to the DBMS, and thus reduces the need to post-process the data, saving I/O and CPU cost. **Second**, regions can be much smaller than the original files, resulting in better cache space utilization and higher hit ratios. For example, Figure 3 shows a case where regions capture all views of all queries, whereas LRU-based file caching can only keep less than half of these views.
>
> Cached regions in Crystal may overlap. In data warehouses and data lakes, it is common to see that a large number of queries access a few tables or files, making overlapping queries the norm rather than the exception at the storage layer. Therefore, Crystal has to take overlap into account when deciding which cached data should be evicted. To the best of our knowledge, previous work on replacement policies for semantic caching does not consider overlap of cached regions (see more details in Section 7).
>
> With overlapping views, the replacement policy in Crystal becomes a very challenging optimization problem (details in Section 4). **Intuitively**, when deciding if a view should be evicted from the cache, all other views that are overlapping with this view should also be taken into consideration. As a result, traditional replacement policies such as LRU that evaluate each view independently are not suitable for Crystal, as we will show in the evaluation (Section 6). 
>
> Recall that we split the cache into two regions: requested region (RR) and oracle region (OR). The OR cache models and solves the above problem as an optimization problem, which aims to find the nearly optimal set of overlapping regions that should be retained in the cache. Admittedly, solving the optimization problem is expensive and thus cannot be performed on a per-request basis. Instead, the OR cache recomputes its contents periodically, and thus mainly targets queries that have sufficient statistics in history. In contrast, the RR cache is optimized for new queries, and can react immediately to workload changes. Intuitively, the RR cache serves as a “buffering” region to temporarily store the cached views for recent queries, before the OR cache collects sufficient statistics to make longer-term decisions. This approach is analogous to the CStore architecture [46], where a writable row store is used to absorb newly updated data before it is moved to a highly optimized column store in batches. Collectively, the two regions offer <u>==an efficient and reactive solution==</u> for caching.

利用**谓词下推**，Crystal 缓存称为 **region** 的不同数据子集。**Region** 可以被视为表上的视图，是**语义缓存**的一种形式[14,29,30,42,43,47]。与传统的文件缓存相比，语义缓存的优势有两方面。首先，它通常会向 DBMS 返回更严格的视图，从而减少对数据进行后处理的需要，从而节省 I/O 和 CPU 成本。**其次**，**region** 可以比原始文件小得多，从而获得更好的缓存空间利用率和更高的命中率。例如，图 3 显示了 region 捕获所有查询的所有视图的情况，而基于LRU的文件缓存只能保留不到一半的视图。

Crystal 中的缓存 **region** 可能会重叠。在数据仓库和数据湖中，经常会看到大量查询访问几个表或文件，这使得重叠查询成为存储层的常态，而不是例外。因此，Crystal 在决定应该驱逐哪些缓存数据时必须考虑重叠。据我们所知，之前关于语义缓存替换策略的工作没有考虑缓存 **region** 的重叠（请参阅第 7 节中的更多详细信息）。

由于视图重叠，Crystal 中的替换策略成为一个非常具有挑战性的优化问题（详见第 4 节）。直观地说，在决定是否应该从缓存中驱逐一个视图时，还应该考虑与该视图重叠的所有其他视图。因此，独立评估每个视图的 LRU 等传统替换策略不适用于 Crystal，我们将在评估（第 6 节）中展示这一点。

回想一下，我们将缓存分为两个 **region** ：请求 **region**  (RR) 和 Oracle  **region**  (RR)。OR 缓存将上述问题作为一个优化问题进行建模和求解，其目的是找到应该保留在缓存中的重叠 **region** 的近似最优集合。显然，解决优化问题的成本很高，因此不能按每个请求执行。所以，OR 缓存会定期重新计算其内容，因此主要针对具有足够统计信息的历史查询。相比之下，RR 缓存针对新查询进行了优化，可以立即对工作负载的变化做出反应。从直觉上，在 OR 缓存收集足够的统计信息以做出更长期的决策之前，RR 缓存用作“缓冲”区域来临时存储最近查询的缓存视图。这种方法类似于 CStore 架构 [46]，其中一个可写的行存用于吸收新更新的数据，然后将其分批移动到高度优化的列存。总的来说，这两个 **region** 为缓存提供了<u>==一种高效且反应性的解决方案==</u>。

## 3   REGION PROCESSING

> In this section, we focus on region matching and the creation of cached regions. Before we explain the details of the process of creating regions and matching cached regions to requests, we first show how to transform client requests into region requests.

本节，我们专注于 **region** 匹配和创建缓存 region。在我们解释创建 **region** 和将缓存 **region** 与请求匹配的过程的细节之前，我们首先展示如何将客户端请求转换为 **region** 请求。

### 3.1   ✅ API

> **Crystal acts as a storage layer of the DBMS**. It runs outside the DBMS and transfers information via a minimalistic `socket` connection and shared space in the filesystem (e.g., SSDs, ramdisk). During a file request, the DBMS exchanges information about the file and the required region with Crystal. Because access to remote files is expensive, Crystal tries to satisfy the request with cached files.
>
> The overall idea is that Crystal overwrites the accessed file path such that the DBMS is pointed to a local file. For redirecting queries, Crystal relies on query metadata such as the file path, push-down predicates, and accessed fields. Crystal evaluates the request and returns a cached local file or downloads the requested file. Afterward, the location of the local file is sent to the DBMS which redirects the scan to this local file. Crystal guarantees the completeness for a given set of predicates and fields. Internally, Crystal matches the query metadata with local cache metadata and returns a local file if it satisfies the requirements.
>
> We use a tree string representation for push-down predicates in our API. Since predicates are conventionally stored as an AST in DBMS, we traverse the AST to build the string representation. Each individual item uses the syntax similar to *operation(left, right)*. We support binary operators, unary operators, and literals which are the leaf nodes of the tree. The binary operation is either a combination function of multiple predicates (such as *and*, *or*) or an atomic predicate (such as *gt*, *lt*, *eq*, . . . ). Atomic predicates use the same binary syntax form in which *left* represents the column identifier and *right* the compare value. To include the negation of sub-trees, our syntax allows *operation(exp)* with the operation *not*.

**Crystal 充当 DBMS 的存储层**，在 DBMS 之外运行，并通过极简的 `socket` 连接和文件系统中的共享空间（例如，SSD、ramdisk）传输信息。请求文件期间，DBMS 与 Crystal 交换有关文件和所需 **region** 的信息。由于访问远程文件的成本很高，因此 Crystal 尝试使用缓存文件来满足请求。

**总体思路是 Crystal 覆盖访问的文件路径，以便 DBMS 指向本地文件**。Crystal 依赖于查询元数据（例如文件路径、下推谓词和访问字段）重定向查询。Crystal 根据请求返回本地缓存的文件或下载远程文件。之后，本地文件的位置被发送到 DBMS，数据库将扫描这个重定向的本地文件。对于给定的<u>谓词</u>和<u>字段集</u>，Crystal 保证其完整性。Crystal 在内部将查询元数据与本地缓存元数据进行匹配，并在满足要求时返回本地文件。

我们在 API 中使用树字符串表示来表示下推谓词。由于谓词通常作为 AST 保存在 DBMS 中，因此我们遍历 AST 以构建字符串表示。每个单独的谓词使用类似于 `operation(left, right)` 的语法。支持<u>二元运算符</u>、<u>一元运算符</u>和作为<u>树的叶节点的常量</u>。二元运算要么是多个谓词（如`and`、`or`）的组合函数，要么是一个原子谓词（如`gt`、`lt`、`eq`、...）。原子谓词使用相同的二进制语法形式，其中 `left` 表示列标识符，`right` 表示用于比较的常量。为了包括对子树的**否**，我们的语法允许 `operation(exp)` 与 `not` 组合。

### 3.2   Transformation & Caching Granularity

> Crystal receives the string of push-down predicates and transforms it back to an internal AST. Because <u>==arguing on==</u> arbitrarily nested logical expressions (with *and* and *or*) is hard, Crystal transforms the AST to <u>==Disjunctive Normal Form==</u> (DNF). In the DNF, all <u>==conjunctions==</u> are pushed down into the expression tree, and <u>==conjunctions==</u> and <u>==disjunctions==</u> are no longer interleaved. In Crystal, regions are identified <u>==by their disjunction of conjunctions of predicates==</u>. Regions also contain their sources (i.e., the remote files) and the projection of the schema. This allows us to easily evaluate equality, superset, and intersection between regions which we show in Section 3.3.
>
> The construction of the DNF follows two steps. **First**, all negations are pushed as far as possible into the tree which results in Negation Normal Form (NNF). Besides using the <u>==De-Morgan rules==</u> to push down negations, Crystal pushes the negations inside the predicates. For example, *not(lt(id, 1))* will be changed to *gteq(id, 1)*.
>
> After receiving the NNF, Crystal distributes conjunctions over disjunctions. The distributive law pushes *or*s higher up in the tree which results in the DNF. It transforms *and(a, or(b, c))* to *or(and(a, b), and(a, c))*. Although this algorithm could create 2*𝑛* leaves in theory, none of our experiments indicate issues with blow-up.
>
> Because the tree is in DNF, the regions store the pushed-down conjunctions as a list of column restrictions. These conjunctions of restrictions can be seen as individual <u>==geometric hyper-rectangles==</u>. Regions are fully described by the disjunction of these hyperrectangles. Figure 4 shows the process of creating the DNF and extracting the individual hyper-rectangles. Although we use the term hyper-rectangles, the restrictions can have different shapes. Crystal supports restrictions, such as *noteq*, *isNull*, and *isNotNull*, that are conceptually different from hyper-rectangles.
>
> Crystal’s base granularity of <u>==items==</u> is on the level of regions, thus all requests are represented by a disjunction of conjunctions. However, individual conjunctions of different regions can be combined to satisfy an incoming region request. Some previous work on semantic caching (e.g., [14, 17]) considers only non-overlapping hyper-rectangles. Non-overlapping regions can help reduce the complexity of the decision-making process. Although this is desirable, non-overlapping regions impose additional constraints.
>
> Splitting the requests into sets of non-overlapping regions is expensive. In particular, the number of non-overlapping hyperrectangles grows combinatorial. To demonstrate this issue, we evaluated three random queries in the lineitem space which we artificially restrict to 8 dimensions [23]. If we use these three random hyper-rectangles as input, 16 hyper-rectangles are needed to store all data non-overlapping. This issue arises from <u>==the number of dimensions that allow for multiple intersections of hyper-rectangles==</u>. 
>
> Each intersection requires the split of the rectangle. In the worst case, <u>==this grows combinatorial in the number of hyper-rectangles==</u>. Because all extracted regions need statistics during the cache optimization phase, the sampling of this increased number of regions is not practical. Further, the runtime of the caching policies is increased due to the larger input which leads to outdated caches. 
>
> Moreover, smaller regions require that more cached files are returned to the client. Figure 5 shows that each additional region incurs a linear overhead of roughly 50ms in Spark. The preliminary experiment demonstrates that splitting is infeasible due to the combinatorial growth of non-overlapping regions. Therefore, Crystal does not impose restrictions on the **semantic regions** themselves. This raises an additional challenge during the optimization phase of the oracle region cache, which we address in Section 4.5.

✅**Crystal 接收下推谓词字符串并将其转换回内部 AST**。由于对任意嵌套的逻辑表达式（使用 `and` 和 `or`）进行<u>==证明==</u>很困难，因此 Crystal 将 AST 转换为<u>==[析取范式](https://zh.wikipedia.org/wiki/%E6%9E%90%E5%8F%96%E8%8C%83%E5%BC%8F)==</u> (DNF)。 在 DNF 中，所有<u>==连词==</u>都被下推到表达式树中，<u>==连词==</u>和<u>==析取==</u>不再交错。**region** 在 Crystal 中是<u>==通过谓词连接的析取==</u>来识别。**Region** 还包含它们的源（即远程文件）和 schema 的投影。这使我们能够轻松评估 **region** 之间的相等、超集和交集（在第 3.3 节中展示）。

✅分为两步构建 DNF 。**首先**，尽可能地将所有否定都推入树中，从而产生否定范式（NNF）。 除了使用 <u>==[De-Morgan 规则](https://baike.baidu.com/item/%E5%BE%B7%C2%B7%E6%91%A9%E6%A0%B9%E5%AE%9A%E5%BE%8B/489073)==</u>来下推否定之外，Crystal 还会在谓词中下推否定。 例如，`not(lt(id, 1))` 将更改为 `gteq(id, 1)`。

✅得到 NNF 后，Crystal 在<u>==析取==</u>下分配<u>==连接==</u>。分配法则将 `and(a, or(b, c))` 转换为 `or(and(a, b), and(a, c))`，也就是将 `or` 提到树中更高的位置得到 DNF。尽管该算法理论上会创建 **2𝑛** 叶子，但我们的实验均未发现存在爆炸问题。

由于<u>==树==</u>在 DNF 中，**region** 将下推<u>==连接==</u>存储为**==一组列的限制==**。这些限制的<u>==连接==</u>可以看作是单独的<u>==几何超矩形==</u>。**region** 完全由这些<u>==超矩形==</u>的<u>==析取==</u>来描述。 图 4 显示了创建 DNF 和提取单个超矩形的过程。 虽然我们使用术语**超矩形**，但限制可以有不同的形状。Crystal 支持在概念上与超矩形不同的限制，例如 `noteq`、`isNull` 和 `isNotNull`。

Crystal 的基本粒度是 **region**，因此所有请求都由<u>==连接==</u>的<u>==析取==</u>表示。但是，可以组合不同 **region** 的某些<u>==连接==</u>来满足传入的 **region** 请求。之前关于语义缓存的一些工作（例如，[14, 17]）只考虑非重叠的超矩形。非重叠 region 有助于降低决策过程的复杂性。尽管这也需要，但非重叠 **region** 会施加额外的约束。

将请求拆分为非重叠 **region** 的集合是昂贵的。特别地，不重叠的超矩形的数量随着组合的增加而增加。 为了演示这个问题，我们评估了 `lineitem` 空间中的三个随机查询，人为地将其限制为 8 个维度 [[23](https://kholub.com/projects/overlapped_hyperrectangles.html)]。 如果我们使用这三个随机超矩形作为输入，则需要 16 个超矩形来存储所有不重叠的数据。这个问题源于<u>==允许多个超矩形相交的维数==</u>。

每个交集都需要分割矩形。最坏的情况，<u>==这会增加超矩形的组合数量==</u>。由于所有提取的 **region** 在缓存优化阶段都需要统计，因此对这种增加的 region 数量进行采样不切实际。此外，由于较大的输入导致缓存过期，增加了缓存策略的运行时间。

> - [ ] 图 5

**此外，较小的 region 需要向客户端返回更多缓存文件**。图 5 显示，每个额外的 region 在 Spark 中都会产生大约 50 毫秒的线性开销。初步实验表明，由于非重叠region 的组合增长，分裂不可行。因此，Crystal 不会对**语义 region** 本身施加限制。这在 **Oracle region** 缓存的优化阶段提出了另一个挑战，我们将在第 4.5 节中对此进行讨论。

### 3.3   Region Matching



> With the disjunction of conjunctions, Crystal determines the relation between different regions. Crystal detects equality, superset, intersections, and **partial supersets** relations. Partial supersets contain a non-empty number of conjunctions fully.
>
> Crystal uses intersections and supersets of conjunctions to <u>**argue about**</u> regions. Conjunctions contain restrictions that specify the limits of a column. Every conjunction has exactly one restriction for each predicated column. Restrictions are described by their column identifier, their range (`min`, `max`), their potential equal value, their set of non-equal values and whether `isNull` or `isNotNull` is set. If two restrictions 𝑝~𝑥~ and 𝑝~𝑦~ are on the same column, Crystal computes if 𝑝~𝑥~ completely satisfies 𝑝~𝑦~ or if 𝑝~𝑥~ has an intersection with 𝑝~𝑦~ . For determining the superset, we **first** check if the <u>**null restrictions**</u> are not contradicting. **Second**, we test whether the (`min`, `max`) interval of 𝑝~𝑥~ is a superset of 𝑝~𝑦~. Afterward, we check whether 𝑝~𝑥~ has restricting non-equal values that discard the superset property and if all additional equal values of 𝑝~y~ are also included in 𝑝~𝑥~ .                                 
>
> For two conjunctions 𝑐~𝑥~ and 𝑐~y~ , 𝑐~𝑥~ ⊃  𝑐~y~ if 𝑐~𝑥~ only contains restrictions that are all less restrictive than the restrictions on the same column of 𝑐~y~. Thus, 𝑐~𝑥~ must have an equal number or fewer restrictions which are all satisfying the matched restrictions of 𝑐~y~. Otherwise, 𝑐~𝑥~ ⊅ 𝑐~y~ . 𝑐~𝑥~ can have fewer restrictions because <u>the absence of a restriction shows that the column is not predicated</u>. 
>
> In the following, we show the algorithms to determine the relation between two regions 𝑟~𝑥~ and 𝑟~y~ .
>
> - 𝑟~𝑥~ ⊃ 𝑟~y~  holds if all conjunctions of 𝑟~y~ find a superset in 𝑟~𝑥~ .
> - 𝑟~𝑥~ ∩  𝑟~𝑦~ ≠ ∅ holds if at least one conjunction of 𝑟~𝑥~ finds an intersecting conjunction of 𝑟~y~ .
> - ∃ conj ⊂  𝑟~𝑥~ : conj ⊂  𝑟~𝑦~ (partial superset) holds if at least one conjunctions of 𝑟~y~ finds a superset in 𝑟~𝑥~ .
> - 𝑟~𝑥~ = 𝑟~𝑦~ : 𝑟~𝑥~ ⊃ r~𝑦~ ∧ 𝑟~𝑦~ ⊃ 𝑟~𝑥~
>
> Figure 6 shows an example that matches a query that consists of two hyper-rectangles to two of the stored regions.

Crystal 通过<u>==一组合取谓词的析取==</u>来确定不同 **region** 之间的关系。Crystal 检测相等、超集、交集和**部分超集**关系。 部分超集完全包含非空数量的<u>==连词==</u>。

Crystal 使用交集和连接超集来<u>**讨论**</u> region。 <u>==合取==</u>包含指定列的限制。每个 <u>==合取==</u>对每个谓词列都只有一个限制。**限制**由列标识符、范围（`min`、`max`）、潜在的相等值、非相等值集以及是否设置了  `isNull` 或 `isNotNull` 来描述。如果两个限制 𝑝~𝑥~ 和 𝑝~𝑦~ 在同一列，Crystal 计算 𝑝~𝑥~ 是否完全满足 𝑝~𝑦~ 或者 𝑝~𝑥~ 与 𝑝~𝑦~ 有交集。为了确定超集，**首先**检查<u>**空限制**</u>是否相互矛盾。**其次**，我们测试 𝑝~𝑥~ 的（`min`、`max`）区间是不是 𝑝~𝑦~ 的超集。之后，我们检查 𝑝~𝑥~ 是否有不等值的限制，这会 <u>==discard==</u> 超集属性，以及 𝑝~y~ 的所有其他等值是否也包含在 𝑝~𝑥~ 中。

两个<u>==合取==</u> 𝑐~𝑥~ 和 𝑐~y~ ，如果对于同一列，𝑐~𝑥~ 包含的限制都比 𝑐~y~ 的限制要少，则  𝑐~𝑥~ ⊃ 𝑐~y~ 。因此，𝑐~𝑥~ 必须具有相同数量或更少的限制，这些限制都满足 𝑐~y~ 匹配的限制，否则，𝑐~𝑥~ ⊅ 𝑐~y~ 。 𝑐~𝑥~ 可以有更少的限制，因为<u>没有限制表明该列不是谓词</u>。

下面，我们展示了确定两个区域 𝑟~𝑥~ 和 𝑟~y~ 之间关系的算法。

- 如果 𝑟~y~ 的所有<u>==合取==</u>在 𝑟~𝑥~ 中找到超集，则 𝑟~𝑥~ ⊃ 𝑟~y~。
- 如果至少有一个 𝑟~𝑥~ 的<u>==合取==</u>和 𝑟~y~ 的<u>==合取==</u>有交集，𝑟~𝑥~ ∩ 𝑟~𝑦~ ≠ ∅。
- 如果 𝑟~y~ 至少有一个<u>==合取==</u>在 𝑟~𝑥~ 中找到一个超集，则 ∃ conj ⊂ 𝑟~𝑥~ : conj ⊂ 𝑟~𝑦~（部分超集）成立。
- 𝑟~𝑥~ = 𝑟~𝑦~ : 𝑟~𝑥~ ⊃ r~𝑦~ ∧ 𝑟~𝑦~ ⊃ 𝑟~𝑥~

图 6 显示了一个示例，该示例将包含两个超矩形的查询与两个存储 region 相匹配。

> - [ ] 图 6

### 3.4   Request Matching

> During region requests, Crystal searches the caches to retrieve a local superset. Figure 7 shows the process of matching the request. First, the oracle region cache is scanned for matches. If the request is not fully cached, Crystal tries to match it with the requested region cache. If the query was not matched, the download manager fetches the remote files (optionally from a file cache).
>
> During the matching, a full superset is prioritized. Only if no full superset is found, Crystal tries to <u>==satisfy==</u> the individual conjunctions. The potential overlap of multiple regions and the overhead shown in Section 3.2 are the reasons to prefer full supersets. <u>If an overlap is detected between 𝐴 and 𝐵, Crystal needs to create a reduced temporary file. Otherwise, tuples are contained more than once which would lead to incorrect results</u>. For example, it could return 𝐴 and 𝐵 − 𝐴 to the client. The greedy algorithm, presented in Algorithm 1 reduces the number of regions if multiple choices are possible. We choose the region that satisfies most of the currently unsatisfied conjunctions and continue until all have been satisfied. 
>
> We optimize the matching of regions by partitioning the cache according to the remote file names and the projected schema. The file names are represented as (bit-)set of the remote file catalog. This set is sharded by the tables. Similarly, the schema can be represented as a (bit-)set. **The partitioning is done in multiple stages**. After the fast file name superset check, all resulting candidates are tested for a superset of the schema. Only within this partition of superset regions, we scan for a potential match. Although no performance issues arise during region matching, multi-dimensional indexes (e.g., R-trees) can be used to further accelerate lookups.
>

请求 region 时，Crystal 搜索缓存以取回本地超集。图 7 显示了匹配请求的过程。首先，扫描 oracle region 缓存以查找匹配项。如果不能满足请求，Crystal 会尝试将其与 **RR** 缓存进行匹配。如果匹配失败，下载管理器将读取远程文件（可选择从文件缓存中读取）。

**匹配时，优先考虑一个完整的超集**。只有在没有找到完整的超集时，Crystal 才会尝试<u>==满足==</u>各个<u>==合取==</u>。在第 3.2 节中显示的多个 region 潜在重叠的开销，是首选完整超集的原因。如果在 𝐴 和 𝐵 之间检测到重叠，Crystal 需要创建一个简化的临时文件。否则，元组会被多次包含，这会导致不正确的结果。例如，它可以将 𝐴 和 𝐵 − 𝐴 返回给客户端。算法 1 中的贪婪算法减少了可能出现多种选择时 region 的数量。我们选择满足大多数当前未满足的<u>**==合取==**</u>的区域，并继续，直到所有**==合取==**都满足为止。

```c++
/** Algorithm 1: Greedy reduction of multiple matches
input  : Region requestedRegion, List<Regions> partialMatches
output : List<Regions> regions,
         BitSet<requestedRegion.disjunctionCount> matches(0);
*/
while true do {
  if matches.isAllBitsSet() {
    return regions;
  }
  bestRegion = {}; bestVal = 0;
  
  foreach p ∈ partialMatches {
    curval = additionalMatches(p, matches);
    if curVal > bestVal {
      bestRegion = p; bestVal = curVal;
    }
  }
  if !bestRegion 
      return {}
  partialMatches = partialMatches \ bestRegion
  regions = regions ∪ buildTempFile(bestRegion, regions)
  matches.setAll(requestedRegion.satisfiedConjunctions(bestRegion)) 
}
```

我们通过根据远程文件名和 `schema` 投影对缓存进行分区来优化 region 匹配。**文件名表示为远程文件目录的（位）集**。该集合由表分片。类似地，`schema` 可以表示为（位）集。<u>**分区在多个阶段完成**</u>。在快速文件名超集检查之后，将针对 `schema` 的超集测试所有结果候选。只有在超集 region 的这个分区内，我们才会扫描潜在的匹配。尽管在 region 匹配期间不会出现性能问题，但可以使用多维索引（例如，R 树）来进一步加速查找。

### 3.5   Creating Regions

> The cached regions of Crystal are stored as Apache Parquet files. Crystal leverages Apache Arrow for reading and writing snappy encoded Parquet files. Internally, Parquet is transformed into Arrow tables before Crystal creates the semantic regions.
>
> Gandiva, which is a newly developed execution engine for Arrow, uses LLVM compiled code to filter Arrow tables [8]. As this promises superior performance in comparison to executing <u>==tuple-at-a-time==</u> filters, Crystal translates its <u>==restrictions==</u> to Gandiva filters. When Crystal builds new Parquet files to cache, the filters are compiled to LLVM and executed on the in-memory Arrow data. Afterward, the file is written to disk as snappy compressed Parquet file. If a file is accessed the first time, Crystal creates a sample that is used to predict region sizes and to speed up the client’s query planning.

Crystal 的缓存区域存储为 Apache Parquet 文件。 Crystal 利用 Apache Arrow 读取和写入 snappy 编码的 Parquet 文件。 在内部，Parquet 在 Crystal 创建语义 region 之前被转换为 Arrow 表。

Gandiva 是 Arrow 新开发的执行引擎，使用 LLVM 编译代码过滤 Arrow 表 [8]。与<u>==一次处理一个元组==</u>的过滤器相比，性能卓越，因此 Crystal <u>==限制==</u>转换为 Gandiva 过滤器。当 Crystal 在缓存中构建新的 Parquet 时，过滤器被编译为 LLVM 并在内存中的 Arrow 数据上执行，写入磁盘的 Parquet 文件用 snappy 压缩。Crystal 第一次访问文件时会采样，用于预测 region 大小并加快客户端的查询计划。

### 3.6   Client Database Connector

> Database systems are often able to access data from different formats and storage layers. Many systems implement a connection layer that is used as an interface between the DBMS and the different formats. For example, Spark uses such an abstraction layer known as data source.
>
> Crystal is connected to the DBMS by implementing such a small data source connector. As DBMSs can process Parquet files already, we can easily adapt this connector for Crystal. Crystal interacts with the DBMS via a socket connection and transfers files via **shared disk space** or **ramdisk**. Since Crystal returns Parquet files, the DBMS can already process them without any code modifications.
>
> The only additional implementation needed is the exchange of control messages. These consist of only three different messages and the responses of Crystal. One of the messages is optional and is used to speed up query planning. The scan request message and the message that indicates that a scan has finished are required by all Crystal clients. The first message includes the path of the remote file, the push-down predicates, and the required fields of the schema. Crystal replies with a collection of files that can be used instead of the original remote file. The finish message is required to delete cached files safely that are no longer accessed by the client. The optional message inquires a sample of the original data to prevent storage accesses during query planning.
>

数据库系统通常能够访问来自不同格式和存储层的数据。许多系统实现了一个连接层，用作 DBMS 和不同格式之间的接口。例如，Spark 这样的抽象层称为数据源。

Crystal 通过实现这样一个小的数据源连接器来和 DBMS互联。由于 DBMS 已经可以处理 Parquet 文件，因此 Crystal 可以简单地使用此连接器。Crystal 通过 **socket** 与 DBMS 交互，并通过**共享磁盘空间**或 **ramdisk** 传输文件。由于 Crystal 返回 Parquet 文件，DBMS 可以在不修改任何代码的情况下处理它们。

唯一需要额外实现的是交换控制消息。仅包含三个 Crystal 相关的消息和响应。其中一条消息可选，用于加速查询计划。所有 Crystal 客户端都需要**扫描请求**消息和**指示扫描已完成**的消息。第一条消息包括远程文件的路径、下推谓词和必需的**Schema** 字段。Crystal 回复一组可以代替原始远程文件的文件。**完成消息**用于安全地删除客户端不再访问的缓存文件。可选消息用于获取原始数据的采样，以防止在查询计划期间进行存储访问。

### 3.7   Cloud Connection

> Crystal itself also has an interface similar to the data source. This interface is used to communicate with various cloud connectors. The interface implements simple file operations, such as listings of directories and accesses to files. For blob storage, the later operation basically downloads the file from remote storage to the local node. 
>
> Recently, cloud providers have been adding predicate push-down capabilities to their storage APIs, e.g., S3 Select [4]. Clients can push down filters to storage and receive the predicated subset. <u>This feature can incur additional monetary costs, as well as a per-request latency</u>. Crystal complements this feature naturally, as it is aware of semantic regions and can use predicate push-down to populate its cache efficiently. As Crystal can reuse cached results locally, it can save on future push-down costs as well.
>
> Crystal implements a download manager that fetches blobs from remote and stores them into ramdisk. The client is pointed to this location, and as soon as it finishes accessing it, the file is deleted again. Multiple accesses can be shared by reference counting.
>

Crystal本身也有一个类似于数据源的接口，用于与各种云连接器进行通信。该接口实现简单的文件操作，例如**目录列表**和**文件访问**。对于 Blob 存储，后面的操作基本上是将文件从远程存储下载到本地节点。

最近，云提供商一直在为其存储 API 添加谓词下推功能，例如 S3 Select [4]。客户端可以将过滤器下推到存储并接收过滤后的子集。<u>此功能可能会产生额外的成本以及提高每个请求的延迟</u>。由于 Crystal 知道语义 region，可以使用**谓词下推**来有效填充缓存，自然而然加强了该特性。Crystal 可以重用本地的缓存结果，因此它可以节省后续的下推成本。

Crystal 实现了一个下载管理器，可以从远程获取 blob 并将它们存储到 ramdisk 中。客户端指向此位置，一旦完成访问，将删除该文件，可以通过引用计数共享多个访问。

## 4   CACHE OPTIMIZATION

> This section summarizes the architecture of our caches, followed by more details on caching. Finally, we explain our algorithms that explore and augment the overlapping search space.

本节总结了缓存的体系结构，介绍了更多的缓存细节。最后，我们解释了**探索和扩展重叠搜索空间**的算法。

### 4.1   Requested Region and Oracle Region Cache 

> Recall that Crystal relies on two region caches to capture shortand long-term trends. The *RR* cache is an **eager** cache that stores the result of recently processed regions. The **long-term insights** of the query workload are captured by the *OR* cache. This cache leverages the history of region requests to compute the ideal set of regions to cache locally for best performance. Crystal allows users to plug-in a custom oracle; we provide a default oracle based on a variant of Knapsack (covered later). After the oracle determines a new set of regions to cache, Crystal computes these regions in the background and updates the *OR* cache. The creation in the background allows to schedule more expensive algorithms (runtime) to gather **meaningful insights**. This allows for computing (near-) optimal results and the usage of machine learning in future work. The oracle runs in low priority, consuming as little CPU as possible during high load.
>
> An interesting opportunity emerges from the collaboration between the two caches. If the *OR* cache decided on a set of long-term relevant regions, the requested region cache does not need to compute any subset of the already cached long-term regions. <u>==On the other hand, if the requested region cache has regions that are considered for long-term usage, the *OR* cache can take control over these regions and simply move them to the new cache==</u>.
>

回想一下，Crystal 依靠两个 region  缓存来控制短期和长期趋势。 *RR* 缓存是一种 **eager** 缓存，用于存储最近处理的 region。查询工作负载的**长期缓存**由 *OR*  控制。 此缓存利用 region 请求的历史记录来计算理想的 **region 集**以在本地缓存以获得最佳性能。Crystal 允许用户插入自定义的 oracle； 我们提供了一个基于 Knapsack 变体的默认 oracle（稍后介绍）。 oracle 确定要缓存一组新 region 后，Crystal 在后台计算这些区域并更新 *OR* 缓存。后台可以使用更好（较慢）的算法（运行时）来收集**有意义的洞察**。 这可以获得（接近）最佳的结果，<u>==并在未来的工作中使用机器学习==</u>。 oracle 以低优先级运行，在高负载时尽可能少的消耗 CPU。

两个缓存之间的合作带来了一个有趣的机会。 如果 *OR* 缓存决定了一组长期相关的 region，则 *RR* 缓存不需要计算已经长期缓存的 region 的任何子集。 <u>==另一方面，如果*RR*  缓存考虑长期使用某些 region，*OR* 缓存可以控制这些 region 并将它们移动到新缓存==</u>。

### 4.2   ✅Metadata Management

> A key component for predicting cached regions is the history of requested regions. To recognize patterns, the previously accessed regions are stored within Crystal. We use a ring-buffer to keep the most recent history. Each buffer element represents a single historic region request which has been computed by a collection of (remote) data files. These files are associated with schema information, tuple count, and size. <u>==The selectivity of the region is captured by result statistics==</u>. The database can either provide result statistics, or Crystal will compute them. Crystal leverages previously created samples to generate result statistics. In conjunction with the associated schema information, Crystal predicts the tuple count and the result size.

预测缓存 region 的一个关键组件是请求 region 的历史记录。为了识别模式，先前访问的 region 存储在 Crystal 中。我们使用环形缓冲区来保存最近的历史记录。每个缓冲区元素代表一个 region 请求历史，由一组（远程）数据文件计算得出。 这些文件与 schema 信息、元组数量和（所占存储空间的）大小相关联。<u>==region 的选择性记录在结果统计信息中==</u>。 结果统计数据可以由数据库提供，或者 Crystal 由计算。Crystal 利用先前的采样来生成结果统计信息。 结合关联的 schema  信息，Crystal 预测元组计数和结果（所占内存）大小。 

### 4.3   Oracle Region Cache

> Long-term trends are detected by using the oracle region cache. An oracle decides according to the seen history which regions need to be created. The history is further used as a source of candidate regions that are considered to be cached.
>
> The quality of the cached items is evaluated with the recent history of regions. Each cached region is associated with a benefit value. This value is the summation of bytes that do not need to be downloaded if the region is stored on the DBMS node. In other words, how much network traffic is saved <u>==by processing the history elements locally==</u>. Further, we need to consider the costs of storing candidate regions. The costs of a region are simply given by the size it requires to be materialized. The above caching problem can be expressed as the knapsack problem: maximize $\sum\nolimits_{i=1}^nb_ix_i$ subject to $\sum\nolimits_{i=1}^nw_ix_i \leqslant W$ Where $x_i \in \{0, 1\}$. The saved bandwidth by caching a region is denoted by 𝑏, the size of the materialized cache by 𝑤 . If the region is picked 𝑥 = 1, otherwise 𝑥 = 0. The goal is to maximize the benefit while staying within the capacity 𝑊 .
>
> However, the current definition cannot capture potential overlap in regions well. As the benefit value is static, <u>==history elements==</u> that occur in multiple regions would be added more than once to the overall value. Thus the maximization would result in a suboptimal selection of regions. In Section 4.5, we show the adaptations of our proposed algorithm to compensate for the overlapping issue.
>

使用 **OR** 缓存检测长期趋势，根据请求历史决定需要创建哪些 region。请求历史进而被视为要缓存的候选 region 的来源。

根据 region 最近的历史来评估缓存的质量，每个缓存 region 都与一个**收益值**相关联。该值是无须下载的字节总和（如果 region 存储在 DBMS 节点上），换句话说，<u>==如果在本地处理历史请求==</u>，可以节省多少网络流量？此外，我们需要考虑存储候选 region 的成本，由它所需的存储空间来简单表示。上述缓存问题可以表示为背包问题：根据 $\sum\nolimits_{i=1}^nw_ix_i \leqslant W$，最大化 $\sum\nolimits_{i=1}^nb_ix_i$，$x_i \in \{0, 1\}$。缓存一个 region 节省的带宽用 𝑏 表示，缓存的存储空间用 𝑤 表示。如果选择缓存 region，则 𝑥 = 1，否则 𝑥 = 0。目标是基于容量 𝑊 最大化收益。

然而，这个定义不能很好地表示潜在的 region 重叠。由于收益是静态值，出现在多个 region 的<u>==历史元素==</u>将多次添加到整体值中。因此，最大化将导致 region 的次优选择。我们在 4.5 节展示了算法的适应性，以补偿重叠问题。

### 4.4   ☹Knapsack Algorithms

Dynamic programming (DP) can be used to solve the knapsack optimally in <u>==pseudo-polynomial time==</u>. The most widespread algorithm iterates over the maximum number of considered items and the cache size to solve the knapsack optimal for each sub-problem instance. Combining the optimally solved sub-problems results in the optimal knapsack, but the algorithm lies in the complexity of O( 𝑛 ∗ 𝑊). Another possible algorithm iterates over the items and benefit values, and lies in O(𝑛 ∗ 𝐵 ) (𝐵 denotes maximum benefit). 

In our caching scenario, we face two challenges with the DP approach. First, both 𝑊 (bytes needed for storing the regions) and 𝐵 (bytes the cached element saves from being downloaded) are large. Relaxing these values by rounding to mega-bytes or gigabytes reduces the complexity, however, the instances are not solved optimally anymore. <u>Second, the algorithm considers that each subproblem was solved optimally. To solve the overlapping issue, only one region is allowed to take the benefit of a single history element</u>. An open question is to decide which sub-problem receives the benefit of an <u>==item==</u> that can be processed with several regions.

Since many knapsack instances face a large capacity 𝑊 and unbound benefit 𝐵, approximation algorithms were explored. In particular, the algorithm that orders items according to the benefit cost ratio has guaranteed bounds and a low runtime complexity of O(𝑛 ∗𝑙𝑜𝑔(𝑛)). The algorithm first calculates all benefit ratios 𝑣 = *𝑏/w* and orders the items accordingly. In the next step, it greedily selects the items as long as there is space in the knapsack. Thus, the items with the highest cost to benefit ratio 𝑣 are contained in the knapsack. <u>This algorithm solves the relaxed problem of the fractional knapsack optimal which loosens `𝑥 ∈ {0, 1}` to `𝑥 ∈ [0, 1]` [24].</u>

动态规划（DP）用于在**伪多项式时间**内求解背包问题（最优解）。最普遍的算法迭代考虑的项目的最大数量和缓存大小，以解决每个子问题实例的最佳背包。结合最优解的子问题得到最优背包，但算法的复杂度在于 O( 𝑛 ∗ 𝑊)。另一种可能的算法迭代项目和收益值，并且位于 O(𝑛 ∗ 𝐵 )（𝐵 表示最大收益）。

我们的缓存场景面临着 DP 算法的两个挑战。首先，𝑊（存储区域所需的字节）和 𝐵（缓存元素从下载中保存的字节）都很大。通过四舍五入到 MB 字节或 GB 字节来放宽这些值会降低复杂性，但不再以最佳方式求解该问题。<u>其次，算法认为每个子问题都得到了最优解。为了解决重叠问题，只允许一个区域利用单个历史元素</u>。一个悬而未决的问题是决定哪个子问题可以获得可以用多个区域处理的项目的好处。

由于许多背包实例面临大容量 𝑊 和无限收益 𝐵，因此探索了近似算法。特别是，根据收益成本比对项目进行排序的算法有保证的边界和 O(𝑛 ∗𝑙𝑜𝑔(𝑛)) 的低运行时复杂度。该算法首先计算所有收益比率 𝑣 = *𝑏/w* 并相应地对项目进行排序。下一步，只要背包有空间，它就会贪婪地选择物品。因此，具有最高成本效益比𝑣 的物品都包含在背包中。该算法解决了分数背包最优解的松弛问题，该问题将`𝑥 ∈ {0, 1}` 松散到`𝑥 ∈ [0, 1]` [24]。

### 4.5   Overlap-aware Greedy Algorithm

> This greedy knapsack algorithm is used as the basis of our adaptations. In contrast to DP, this approach gives us an order of the picked items which allows us to incorporate the benefit changes. 
>
> Algorithm 2 shows the adapted greedy knapsack algorithm. The ==general idea== is that we recompute the benefit ratio for each picked item. For each iteration step, we reevaluate the benefit and size of the current candidate set. The evaluation function sorts the input according to this benefit ratio. Thus, regions that result in higher returns in comparison to the caching size are picked earlier. Note that we only consider regions that have a benefit ratio *>* 1 to reduce unnecessary computation for one-time requests. The runtime complexity of the adapted algorithm is O(𝑛^2^ ∗ 𝑙𝑜𝑔(𝑛)).
>
> The evaluation of the benefit ratio is adapted according to the previously chosen regions. We define three geometric rules which change the ratio of unpicked elements.
>
> 1.  if a candidate is a superset of a picked item, we reduce the weight and the benefit by the values of the picked elements.
> 2. if a candidate is a subset of an already picked item, we reduce the benefit to 0 as it does not provide any additional value.
> 3. if a candidate is intersected with an already picked item, we reduce the benefit by the history elements that are covered completely by both regions.
>
> (1) A container region 𝑟~𝑐~ = {𝑟~1~, 𝑟~2~, . . . , 𝑟~𝑛~, 𝑟~𝑥~ } fully contains 𝑛 stand-alone regions and the ==remainder== region 𝑟~𝑥~ . The cost of 𝑟~𝑐~ is computed by $ 𝑤_𝑐 = 𝑤_𝑥 + \sum\nolimits_{i=1}^nw_i$ and the benefit $𝑏_𝑐 = 𝑏_𝑥 + \sum\nolimits_{i=1}^n𝑏_𝑖$ . If a region 𝑟~𝑘~ is fully contained in another region 𝑟~𝑐~ , we reduce both the ==weight== and benefit of 𝑟~𝑐~ when 𝑟~𝑘~ is picked. Thereby, we simulate 𝑟′~𝑐~ which is a non overlapping version of 𝑟~𝑐~ with $𝑣_𝑘 >= 𝑣_𝑐 >= 𝑣_{𝑐′}$ . In the case, the greedy algorithm picks 𝑟′~𝑐~ in a future iteration, we actually add 𝑟~𝑐~ and remove the previously picked item 𝑟~𝑘~ .
>
> (2) If 𝑟~𝑐~ is picked, all the other included regions in 𝑟~𝑐~ are fully contained with their benefits and weights. Since the greedy algorithm picks 𝑟~𝑐~ ⇒ ∀𝑟 ∈ 𝑟~𝑐~ : 𝑣~𝑐~ >= 𝑣~𝑟~ . The benefit of all contained 𝑟 is reduced to 0 as all history elements are included in 𝑟~𝑐~ .
>
> (3) Besides full containment, regions can have partial overlap. Assume that 𝑟~𝑥~ and 𝑟~𝑦~ overlap partially, and 𝑟~𝑥~ is picked. Our algorithm reduces the benefit 𝑏~𝑦~ by all history elements that are covered by both 𝑟~𝑥~ and 𝑟~𝑦~. However, we cannot reduce the costs of caching 𝑟~𝑦~ as we would need to compute the non-overlapping part of the regions. This is in direct contradiction to the goal of minimizing region splits as shown in Section 3.2. For retaining optimality, all interleaving regions must be considered as the potentially picked item in an individual branch of the problem. The branch that yields the maximum benefit is chosen as the winner. Unfortunately, this introduces exponential growth of the search space. Our experiments show that even without considering all paths, our greedy algorithm produces highly effective *OR* caches. Although this revokes the fractional knapsack optimality guarantee, our greedy algorithm only picks the locally optimal choice and does not branch.

这个贪心背包算法被用作我们改写的基础。与 DP 相比，这种方法为我们提供了一个挑选项目的顺序，这使我们能够合并收益变化。

算法 2 显示了自适应贪婪背包算法。一般的想法是我们重新计算每个选择的项目的收益比率。对于每个迭代步骤，我们重新评估当前候选集的好处和大小。评估函数根据这个收益比例对输入进行排序。 因此，与缓存大小相比导致更高回报的 region 会更早地被挑选出来。请注意，我们只考虑具有**收益比率 > 1** 的区域，以减少一次性请求的不必要计算。 改写算法的运行时复杂度为 O(𝑛^2^ ∗ 𝑙𝑜𝑔(𝑛))。

```Java
/** Algorithm 2: Overlap Greedy Knapsack
input : List<Region> history, List<Region> candidates, Int maxCacheSize
output : List<Region> cache
*/
List<Region> cache = List<Region>();
Integer currentCacheSize = 0;
Map<Float, Region> benefitRatioMap = evaluate(candidates, history, cache);
foreach {benefit, region} ∈ benefitRatioMap {
    if currentCacheSize + region.size > maxCacheSize {
        return cache;
    }
    foreach item ∈ cache {
        if item ⊆ region 
            cache = cache \ item
    }
    cache = cache ∪ region;
    benefitRatioMap = evaluate(candidates, history, cache);
    currentCacheSize += region.size
}
return cache
```

收益比率的评估根据先前选择的 region 进行调整。 我们定义了三个几何规则来改变未选取元素的比例。

1. 如果一个候选是一个被选择项的超集，我们通过被选择元素的值来减少权重和收益。
2. 如果候选人是已经挑选的项目的子集，我们将收益减少到 0，因为它不提供任何额外的价值。
3. 如果一个候选与一个已经选择的项目相交，我们通过两个区域完全覆盖的历史元素来减少收益。

(1) 一个容器 region 𝑟~𝑐~ = {𝑟~1~, 𝑟~2~, . . . , 𝑟~𝑛~, 𝑟~𝑥~ } 完全包含 𝑛 个独立的 region 和==剩余==的 region 𝑟~𝑥~。由 $ 𝑤_𝑐 = 𝑤_𝑥 + \sum\nolimits_{i=1}^nw_i$ 表示 𝑟~𝑐~ 的成本，由 $𝑏_𝑐 = 𝑏_𝑥 + \sum\nolimits_{i=1}^n𝑏_𝑖$ 表示 𝑟~𝑐~ 的收益。如果一个区域 𝑟~𝑘~ 完全包含在另一个区域 𝑟~𝑐~ 中，当 𝑟~𝑘~ 被选中时，我们减少 𝑟~𝑐~ 的==权重==和收益。因此，我们用 $𝑣_𝑘 >= 𝑣_𝑐 >= 𝑣_{𝑐′}$ 模拟 𝑟′~𝑐~，它是 𝑟~𝑐~ 的非重叠版本。在这种情况下，贪心算法在后续的迭代中选择 𝑟′~𝑐~ ，我们实际上添加了 𝑟~𝑐~ 并删除了之前选择的 𝑟~𝑘~ 。

(2) 如果选择 𝑟~𝑐~，则 𝑟~𝑐~ 包含的所有 region，它们的收益和权重都被 𝑟~𝑐~ 包含。由于贪心算法选择 𝑟~𝑐~ ⇒ ∀𝑟 ∈ 𝑟~𝑐~ : 𝑣~𝑐~ >= 𝑣~𝑟~ 。由于所有历史元素都包含在 𝑟~𝑐~ 中，所有包含 𝑟 的收益减少到 0。

(3) 除了完全包容之外，region 还可以有**部分重叠**。假设𝑟~𝑥~ 和𝑟~𝑦~ 部分重叠，并且𝑟~𝑥~ 被选中。我们的算法减少了 𝑟~𝑥~ 和 𝑟~𝑦~ 所涵盖的所有历史元素的收益 𝑏~𝑦~。但是，我们无法降低缓存 𝑟~𝑦~ 的成本，因为我们需要计算 region 的非重叠部分。这与 3.2 节所示的最小化 region 分裂的目标直接矛盾。为了保持最优性，必须将所有交错区域视为问题的单个分支中可能选择的项目。产生最大收益的分支被选为获胜者。不幸的是，这引入了搜索空间的指数增长。我们的实验表明，即使不考虑所有路径，我们的贪心算法也能产生高效的 *OR* 缓存。虽然这取消了分数背包最优性保证，但我们的贪心算法只选择局部最优并且不进行分支。

### 4.6   Region Augmentation

> To predict regions that are accessed in the future, the oracle needs to generalize. If the candidate set of the decision-making solely consists of the seen history elements, the oracle will overfit. <u>==Thus, a crucial part is the augmentation of the candidate set to include unseen regions that are evaluated according to the seen history==</u>.
>
> To find generalized candidate sets, we developed the approximative merging algorithm. **This algorithm tries to merge intersecting regions to find the generalized region of interest**. In particular, we combine two predicates and for each predicate the global min and global max are used as new dimension restrictions. As this introduces 𝑛^2^ new regions, we only merge <u>==conjunctions==</u> if they intersect in at least one dimension. To overcome the issue of non-intersecting but neighboring hyper-rectangles (e.g., 𝑥 *<* 1, 𝑥  ≥  1), we allow for approximative intersections that add a small delta to the boundaries. 
>
> The full approximative merging procedure is presented in Algorithm 3. **First**, we compute enlarged regions from the history and consider the ones that match the previously described criteria. After determining new enlarged regions, each enlarged region is assigned a quality and size saving value. Quality counts how many history regions can be processed with this enlarged region. <u>The overall sum of the size required by each region, that can be processed with this new enlarged region</u>, denotes the size saving. With these properties, Crystal ranks the new regions according to quality and adds the highest ranked ones to the candidate set. We only add new regions if these cannot be represented by already existing regions and their size overhead is either smaller than a defined maximum size or the size saving is larger than the region itself. The sizes of the enlarged regions are computed with the help of the samples already collected for each file. In the experimental evaluation, we add at most 20% of additional regions (according to the history size) and define a maximum size of 20% of the total semantic cache size.

为了预测未来访问的 **region**，oracle 需要进行泛化。如果决策的候选集仅由可见的历史元素组成，则 oracle 将[过拟合](https://zhuanlan.zhihu.com/p/72038532)。<u>==因此，关键部分是扩充候选集，包括根据所见历史评估的未见 region==</u>。

为了找到广义候选集，我们开发了近似合并算法。**尝试合并相交 region 以找到感兴趣的广义 region**。特别是，我们组合了两个谓词，对于每个谓词，全局最小值和全局最大值用作新的维度限制。由于这引入了 𝑛^2^ 个新 region，我们只合并至少在一个维度上相交的<u>==合取==</u>。为了克服不相交但相邻的超矩形（例如，𝑥 *<* 1，𝑥 ≥ 1）的问题，我们允许在边界上添加一个小增量，以获得近似相交。

算法 3 中给出了完整的近似合并过程。**首先**，我们从历史中计算扩大的 region，并考虑与先前描述的标准相匹配的 region。在确定新的放大 region 后，每个放大 region 都被分配一个 **quality** 和 **size** 节省值。**Quality** 统计可以用这个扩大的 region 处理多少历史 region；<u>可使用这个新放大的 region 处理的所有 region 所需大小的总和</u>表示节省的 **size**。有了这些属性，Crystal 根据 **quality** 对新 region 进行排名，并将排名最高的 region 添加到候选集中。只有在新 region 不能由现有 region 表示，并且它们的 **size** 开销小于定义的最大 size 或节省的 size 大于 region 本身，我们才会添加 region。放大 region  的 size 是通过为每个文件收集的样本来计算的。在实验评估中，我们最多添加 20% 的附加 region（根据历史 **size**），并定义最大 size 为总语义缓存大小的 20%。

```c++
/**Algorithm 3: Approximative Merging Augmentation
input  : List<Region> history, Int maxRegions, Int maxSize, Int maxCacheSize
output : List<Region> resultRegions
*/
// RegionStruct consists of Region, Quality (0), and Size Savings (0)
List< RegionStruct<Region, Int, Int> > enlargedRegions;
foreach 𝑟 ∈ history {
    foreach 𝑟′ ∈ history \ {𝑟0, . . . , 𝑟 } {
        𝑟.enlargeAll(𝑟 ′, enlargedRegions)
    }
}
foreach 𝑟 ∈ enlargedRegions{
    foreach 𝑟′ ∈ history {
        if 𝑟.region.satisfies(𝑟′){
            𝑟.quality += 1; 
            𝑟.sizeSavings += 𝑟 ′.size;
        }
    }
}
sort(enlargedRegions, 𝜆 (r1, r2) { r1.quality > r2.quality })
while !enlargedRegions.empty() ∧ maxRegions > 0 do {
    𝑟 = enlargedRegions.pop();
    considered = true;
    foreach 𝑟′ ∈ resultRegions {
        if r’.satisfies(𝑟.region) ∧ 𝑟′.size < maxSize 
            considered = false;
    }
    if !considered
        continue;
    𝑟 .region.computeStatisticsWithSample();
    if 𝑟.region.size < 
        maxSize ∨ (𝑟.region.size < 𝑟.sizeSavings ∧ 𝑟.region.size < maxCacheSize)
        resultRegions = resultRegions ∪ 𝑟 .region; maxRegions -= 1
}
return resultRegions;
```



### 4.7   Requested Region Cache

> The requested region cache is similar to a traditional cache but with semantic regions instead of pages. It decides in an online fashion whether the requested region should be cached. The algorithm must be simple to reduce decision latencies. Traditional algorithms, such as LRU and its variants, are good fits in terms of accuracy and efficiency. Besides the classic LRU cache, experiments showed the benefit of caching regions after the second (k-th in general) occurrence. With the history already available for *OR*, this adaption is simple and does not introduce additional latency. For combined *OR* and *RR* with *LRU-k*, it is beneficial to reduce the history size by the *RR/OR* split as long-term effects are captured by *OR*.
>
> One of the biggest advantages of the *RR* cache is the fast reaction to changes in the queried workload. In comparison to the *OR* cache that only refreshes periodically, the request cache is updated constantly. This eager caching, however, might result in overhead due to additional writing of the region file. To overcome this issue, the client DBMS can simultaneously work on the raw data and provide the region as a file for Crystal; this extension is left as future work.
>

请求的 region 缓存类似于传统缓存，但使用语义缓存而不是 page 缓存。以在线方式决定是否应缓存请求的 region。算法必须简单以减少决策延迟。传统算法，例如 LRU 及其变体，在准确性和效率方面都非常适合。除了经典的 LRU 缓存外，实验还显示了LUR-2（通用版是 LRU-k ）策略的好处。由于*OR* 的历史记录已经可用，因此这种调整很简单并且不会引入额外的延迟。对于*OR* 和 *RR* 与 *LRU-k* 的组合，由于*OR* 捕获了长期影响，通过*RR/OR* 拆分减少历史大小是有益的。

*RR* 缓存的最大优势之一是对查询工作负载变化的快速反应。与仅周期刷新的 *OR* 缓存相比，*RR* 缓存是不断更新的。但 **egaer** 缓存由于额外写入 region 文件而带来开销。要解决这个问题，客户端 DBMS 可以同时处理原始数据并将 region 作为文件提供给 Crystal；这个扩展留作未来的工作。

## 5   IMPLEMENTATION DETAILS

Crystal is implemented as a stand-alone and highly parallel process that sits between the DBMS and blob storage. This design helps to accelerate workloads across different database systems. Crystal is a fully functional system that works with diverse data types and query predicates, and is implemented in C++ for optimal performance. 

**Parallel Processing within Crystal**. Latency critical parts of Crystal are optimized for multiple connections. Each new connection uses a dedicated thread for building the predicate tree and matching cached files. If a file needs to be downloaded, it is retrieved by a pool of download threads to saturate the bandwidth. All operations are either implemented lock-free, optimistically, or with fine-grained shared locks. Liveness of objects and their managed cached files is tracked with smart pointers. Therefore, Crystal parallelizes well and can be used as a low latency DBMS middleware.

Crystal also handles large files since some systems do not split Parquet files into smaller chunks. During matching we recognize which parts of the original file would have been read and translate it to the corresponding region in the cached files. Further, we are able to parallelize reading and processing Parquet files.

**Spark Data Source**. For our evaluation, we built a data source to communicate between Spark and Crystal, by extending the existing Parquet connector of Spark with less than 350 lines of Scala code. The connector overrides the scan method of Parquet to retrieve the files suggested by Crystal. Because Spark pushes down predicates to the data source, we have all information available for using the Crystal API. As Spark usually processes one row iterator per file, we developed a meta-iterator that combines multiple file iterators transparently (Crystal may return multiple regions). The connector is packaged as a small and dynamically loaded Java jar.

**Greenplum Data Source**. Further, we built a connector for Greenplum which is a cloud scale PostgreSQL derivative with an external extension framework – called PXF [34, 51]. PXF allows one to access Parquet data from blob storage [52]. We modified the Parquet reader such that it automatically uses Crystal if available. Our changes to the Greenplum connector consist of less than 150 lines of code. Without recompiling the core database, Crystal accelerates Greenplum by dynamically attaching the modified PXF module.

Both connectors currently do not support sending regions back to Crystal; instead, Crystal itself handles additions to the RR cache.

**Azure Cloud Connection**. We use Azure Blob Storage to store remote data, using a library called azure-storage-cpplite [37] to implement the storage connector. The library just translates the file accesses to CURL (HTTPS) requests. Other cloud providers have similar libraries with which connections can be easily established. Crystal infers the cloud provider from the remote file path. The file path also gives insights into the file owner (user with pre-configured access token) and the blob container that includes the file.

Crystal 是作为一个独立的、高度并行的进程实现的，它位于 DBMS 和 Blob 存储之间。这种设计有助于加速不同数据库系统的工作负载。Crystal 是一个功能齐全的系统，可以处理不同的数据类型和查询谓词，并用 C++ 实现以获得最佳性能。 

**Crystal 内的并行处理**。Crystal 的延迟关键部分针对多个连接进行了优化。每个新连接都使用一个专用线程来构建谓词树和匹配缓存文件。如果需要下载文件，则由下载线程池检索该文件以使带宽饱和。所有操作要么是无锁的、乐观的，要么是细粒度的共享锁。使用智能指针跟踪对象及其托管缓存文件的活跃度。因此，Crystal 可以很好地并行化，可以用作低延迟 DBMS 中间件。

Crystal 还处理大文件，因为某些系统不会将 Parquet 文件拆分为更小的块。在匹配过程中，我们识别原始文件的哪些部分将被读取，并将其转换为缓存文件中的相应区域。此外，我们能够并行读取和处理 Parquet 文件。

**Spark 数据源**。对于我们的评估，我们通过使用少于 350 行的 Scala 代码扩展 Spark 的现有 Parquet 连接器，构建了一个数据源来在 Spark 和 Crystal 之间进行通信。连接器覆盖 Parquet 的扫描方法来检索 Crystal 建议的文件。由于 Spark 将谓词下推到数据源，因此我们拥有可用于使用 Crystal API 的所有信息。由于 Spark 通常每个文件处理一个行迭代器，我们开发了一个元迭代器，它透明地组合了多个文件迭代器（Crystal 可能返回多个区域）。连接器被打包为一个小的动态加载的 Java jar。

**Greenplum 数据源**。此外，我们为 Greenplum 构建了一个连接器，它是一个云规模的 PostgreSQL 衍生产品，具有外部扩展框架——称为 PXF [34, 51]。 PXF 允许从 blob 存储中访问 Parquet 数据 [52]。我们修改了 Parquet 阅读器，使其在可用时自动使用 Crystal。我们对 Greenplum 连接器的更改包含不到 150 行代码。无需重新编译核心数据库，Crystal 通过动态附加修改后的 PXF 模块来加速 Greenplum。

两个连接器目前都不支持将区域发送回 Crystal；相反，Crystal 本身处理对 RR 缓存的添加。

**Azure 云连接**。我们使用 Azure Blob 存储来存储远程数据，使用名为 azure-storage-cpplite [37] 的库来实现存储连接器。该库只是将文件访问转换为 CURL (HTTPS) 请求。其他云提供商也有类似的库，可以轻松建立连接。 Crystal 从远程文件路径推断云提供商。文件路径还提供了对文件所有者（具有预配置访问令牌的用户）和包含该文件的 blob 容器的深入了解。

## 6   EXPERIMENTAL EVALUATION

## 7   RELATED WORK

> The basic idea behind Crystal is to cache and reuse computations across multiple queries. This idea has been explored in a large body of research work including at least four broad lines of research: materialized view, semantic caching, intermediate results reusing, and mid-tier database caching. In general, Crystal differs from previous work in some or all of the following ways: 1) integrating Crystal with a DBMS requires no modification to the DBMS; 2) Crystal focuses on caching views at the storage layer, and can be used across multiple DBMSs; 3) Crystal can automatically choose cached views based on a replacement policy, which takes into account the semantic dependencies among queries. Below, we discuss the key differences between Crystal and previous work in each line of the four aforementioned research areas.
>
> **Materialized View**. Materialized view is a well-known technique that caches the results of a query as a separate table [20, 44, 45]. However, unlike Crystal, views that need to be cached or materialized are often defined manually by users (e.g., a DBA). Additionally, implementing materialized views in a DBMS is a timeconsuming process, requiring advanced algorithms in the query optimizer to decide: 1) if a given query can be evaluated with a materialized view; and 2) if a materialized view needs to be updated when the base table is changed.
>
> **Semantic Caching**. Semantic caching was first proposed in Postgres [47], and was later extended and improved by a large body of work [11, 14, 17, 29, 30, 42, 43]. This technique also aims to cache the results of queries to accelerate repeated queries. Similarly to Crystal, a semantic cache can automatically decide which views to keep in the cache, within a size budget. This decision is often made based on a cost-based policy that takes several properties of views into consideration such as size, access frequency, materialization cost. However, this approach caches the end results of entire queries, while Crystal caches only the intermediate results of the selection and projection operators of queries. The cached view of an entire query is especially beneficial for repeated queries, but on the other hand decreases the reusability of the cached view, i.e., the chance that this view can be reused by future queries. While most work in this area does not take into account overlap of cached views, some work [14, 17] does explore this opportunity. Dar et al. proposed to split overlapping queries into non-overlapping regions, and thus enable semantic cache to use traditional replacement policies to manage the (non-overlapping) regions [14]. However, this approach could result in a large number of small views, incurring significant overhead to process as we showed in Sec 3.2. Maintaining nonoverlapping views is also expensive, as access to an overlapping view may lead to splitting the view and rewriting the cached files. Chunk-based semantic caching [17] was proposed to solve this problem, by chunking the **hyper space** into a large number of regions that are independent to queries. However, the chunking is pre-defined and thus is static with respect to the query patterns.
>
> **Intermediate Results Reusing**. Many techniques have also been developed to explore the idea of reusing intermediate results rather than end results of queries. Some of these techniques [49, 50] share the intermediate results across concurrent queries only, and thus impose limitations on the temporal locality of overlapping queries. Other work [19, 25–27, 38, 41] allows intermediate results to be stored so that they can be reused by subsequent queries. Similarly to Crystal, these techniques also use a replacement policy to evict intermediate results when the size limit is reached. However, these techniques require extensive effort to be integrated with a DBMS, whereas integrating Crystal requires only a lightweight database-specific connector. Additionally, a Crystal cache can be used with and share data across multiple DBMSs.
>
> **Mid-tier Database Caching**. Another area where views can be cached and reused is in the context of multi-tier database architecture, where mid-tier caches [2, 10, 31] are often deployed at the mid-tier application servers to reduce the workload for the backend database servers. As mid-tier caches are not co-located with DBMSs, they usually include a shadow database at the mid-tier servers that mirrors the backend database but without actual content, and rely on materialized views in the shadow database to cache the results of queries. Unlike Crystal, the definition of the cached views in a mid-tier cache needs to be pre-defined manually by users, and it is difficult to change the cached views adaptively.
>
> Finally, many vendors have developed cache solutions for big data systems to keep hot data in fast local storage (e.g., SSDs). Examples include the Databricks Delta Cache [9, 15], the Alluxio [1] analytics accelerator, and the Snowflake Cache Layer [13]. These solutions are based on standard techniques that simply cache files at the page or block level and employ standard replacement policies such as LRU. Compared to these standard approaches, Crystal is also a generic cache layer that can be easily integrated with unmodified big data systems, but has the flexibility to cache data in a more efficient layout (i.e., re-organizing rows based on queries) and format (i.e., Parquet), which speeds up subsequent query processing.

---

Crystal 背后的基本思想是在多个查询中和重用缓存和计算。有大量研究工作探索这个想法，包括至少四大研究领域：物化视图、语义缓存、中间结果重用和数据库中间缓存层。总的来说，Crystal 在以下部分或全部方面不同于以前的工作： 1) 将 Crystal 与 DBMS 集成不需要对 DBMS 进行修改； 2）Crystal 专注于存储层的缓存视图，可以跨多个DBMS使用； 3) Crystal 可以根据替换策略自动选择缓存视图，该策略考虑了查询之间的语义依赖关系。下面，我们将在上述四个研究领域的每一行中讨论 Crystal 与之前工作之间的主要区别。

**物化视图**。 物化视图是一种众所周知的技术，它将查询结果缓存为单独的表 [20, 44, 45]，但需要缓存或物化的视图通常由用户（例如 DBA）手动定义。 此外，在 DBMS 中实现物化视图是一个耗时的过程，需要查询优化器中的高级算法来决定：1) 是否可以使用物化视图评估给定的查询； 2) 基础表发生变化时是否需要更新实体化视图。

**语义缓存**。语义缓存首先在 Postgres [47] 中提出，后来通过大量工作 [11, 14, 17, 29, 30, 42, 43] 进行了扩展和改进。该技术还旨在缓存查询结果以加速重复查询。与 Crystal 类似，语义缓存可以在容量预算内自动决定将哪些视图保留在缓存中。通常基于成本策略做出决策，成本策略考虑了视图的多个属性，例如大小、访问频率、物化成本。但是，这种方法缓存整个查询的最终结果，而 Crystal **==仅缓存查询的选择和投影运算符的中间结果==**。缓存整个查询视图对于重复查询特别有益，但另一方面降低了缓存视图的可重用性，即该视图可以被未来查询重用的机会。虽然该领域的大多数工作都没有考虑重叠的缓存视图，但一些工作 [14, 17] 确实探索了这个机会。达尔等人建议将重叠查询拆分为非重叠区域，从而使语义缓存能够使用传统的替换策略来管理（非重叠）区域 [14]。然而，这种方法可能会导致大量的小视图，如我们在第 3.2 节中展示的那样，会产生大量的处理开销。维护非重叠视图也很昂贵，因为访问重叠视图可能会导致拆分视图并重写缓存文件。基于块的语义缓存 [17] 被提出来解决这个问题，通过将**超空间**分块成大量独立于查询的区域。然而，分块是预定义的，因此对于查询模式是静态的。

**中间结果重用**。还开发了许多技术来探索重用中间结果而不是查询的最终结果的想法。其中一些技术 [49, 50] 仅在并发查询之间共享中间结果，因此对重叠查询的时间局部性施加了限制。其他工作 [19, 25–27, 38, 41] 允许存储中间结果，以便后续查询可以重用它们。与 Crystal 类似，这些技术也使用替换策略在达到大小限制时驱逐中间结果。然而，这些技术需要付出大量努力才能与 DBMS 集成，而集成 Crystal 只需要一个轻量级的特定于数据库的连接器。此外，Crystal 缓存可与多个 DBMS 一起使用并共享数据。

**数据库中间层缓存**。另一个可以缓存和重用视图的领域是在多层数据库架构的上下文中，中间层缓存 [2, 10, 31] 通常部署在中间层应用服务器上，以减少后端数据库的工作量服务器。由于中间层缓存不与 DBMS 共存，它们通常在中间层服务器上包含一个影子数据库，该影子数据库镜像后端数据库但没有实际内容，并依赖影子数据库中的物化视图来缓存查询结果.与 Crystal 不同的是，中间层缓存中缓存视图的定义需要用户手动预先定义，并且很难自适应地更改缓存视图。

最后，许多供应商已经为大数据系统开发了缓存解决方案，以将热数据保存在快速本地存储（例如 SSD）中。示例包括 Databricks Delta Cache [9, 15]、Alluxio [1] 分析加速器和 Snowflake Cache Layer [13]。这些解决方案基于标准技术，这些技术只是在页面或块级别缓存文件，并采用标准替换策略，例如 LRU。与这些标准方法相比，Crystal 也是一个通用的缓存层，可以很容易地与未经修改的大数据系统集成，但具有以更高效的布局（即，根据查询重新组织行）和格式来缓存数据的灵活性（即 Parquet），它加快了后续的查询处理。

## 8   CONCLUSION

Cloud analytical databases employ a disaggregated storage model, where the elastic compute layer accesses data on remote cloud storage in columnar formats. Smart caching is important due to the high latency and low bandwidth to remote storage and the limited size of fast local storage. Crystal is a smart cache storage system that colocates with compute and can be used by any unmodified database via data source connector clients. Crystal operates over semantic data regions, and continuously adapts what is cached locally for maximum benefit. Results show that Crystal can significantly improve query latencies on unmodified Spark and Greenplum, while also saving on bandwidth from remote storage.

云分析数据库采用分解存储模型，其中弹性计算层以列格式访问远程云存储上的数据。 由于远程存储的高延迟和低带宽以及快速本地存储的大小有限，智能缓存很重要。 Crystal 是一个智能缓存存储系统，它与计算并置，可以由任何未修改的数据库通过数据源连接器客户端使用。 Crystal 对语义数据区域进行操作，并不断调整本地缓存的内容以获得最大收益。 结果表明，Crystal 可以显着改善未修改的 Spark 和 Greenplum 的查询延迟，同时还可以节省远程存储的带宽。
