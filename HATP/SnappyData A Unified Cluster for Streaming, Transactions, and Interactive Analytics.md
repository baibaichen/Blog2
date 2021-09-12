#  SnappyData: A Unified Cluster for Streaming, Transactions, and Interactive Analytics

> **ABSTRACT**  Many modern applications are a mixture of streaming, transactional and analytical workloads. However, traditional data platforms are each designed for supporting a specific type of workload. The lack of a single platform to support all these workloads has forced users to combine disparate products in custom ways. The common practice of <u>stitching heterogeneous environments</u> has caused enormous production ==<u>woes</u>== by increasing complexity and the total cost of ownership.
>
> To support this class of applications, we present SnappyData as the first unified engine capable of delivering analytics, transactions, and stream processing in a single integrated cluster. We build this hybrid engine by carefully marrying a big data computational engine (Apache Spark) with a scale-out transactional store (Apache GemFire). We study and address the challenges involved in building such a hybrid distributed system with two conflicting components designed on drastically different philosophies: one being a lineage-based computational model designed for high-throughput analytics, the other a consensusand replication-based model designed for low-latency operations.
>

**摘要** 许多现代应用程序的工作负载混合了流、事务和分析。然而，==**传统的数据平台都是为支持特定类型的工作负载而设计**==。由于缺乏一个平台来支持所有这些工作负载，用户不得不以定制的方式组合不同的产品。<u>拼接异构环境</u>的常见做法增加了复杂性和总体拥有成本，从而导致了巨大的生产==<u>难题</u>==。

为了支持此类应用程序，我们设计并实现了 SnappyData，作为第一个能够在单个集成集群中提供分析、事务和流处理的统一引擎。我们通过将大数据计算引擎 (Apache Spark) 与横向扩展事务存储 (Apache GemFire) 小心地结合起来，构建了这个混合引擎。我们研究并解决了构建这样一个混合分布式系统所涉及的挑战，该系统包含两个相互冲突的组件，它们的设计理念截然不同：一个是为高吞吐分析设计的基于血缘系的计算模型，另一个是为低延迟操作设计的基于共识和复制的模型。

## 1.  简介

> An increasing number of enterprise applications, particularly those in financial trading and IoT (Internet of Things), produce mixed workloads with all of the following: (1) continuous stream processing, (2) online transaction processing (OLTP), and (3) online analytical processing (OLAP). These applications need to simultaneously consume high-velocity streams to trigger real-time alerts, ingest them into a write-optimized transactional store, and perform analytics to derive **deep insight** quickly. <u>Despite a flurry of data management solutions designed for one or two of these tasks, there is no single solution that is apt for all three</u>.
>
> SQL-on-Hadoop solutions (e.g., Hive, Impala/Kudu and SparkSQL) use OLAP-style optimizations and columnar formats to run OLAP queries over massive volumes of static data. While apt for batch-processing, these systems are not designed as real-time operational databases, as they lack the ability to mutate data with transactional consistency, to use indexing for efficient point accesses, or to handle high-concurrency and bursty workloads. For example, Wildfire [17] is capable of analytics and stream ingestion but lacks ACID transactions.
>
> Hybrid transaction/analytical processing (HTAP) systems, such as MemSQL, support both OLTP and OLAP queries by storing data in dual formats (row and columns), but need to be used alongside an external streaming engine (e.g., Storm [34], Kafka, Confluent) to support stream processing.
>
> Finally, there are numerous academic [20, 31, 33] and commercial [2, 8, 14, 34] solutions for stream and event processing. Although some stream processors provide some form of state management or transactions (e.g., Samza [2], Liquid [23], S-Store [27]), they only allow simple queries on streams. However, more complex analytics, such as joining a stream with a large history table, need the same optimizations used in an OLAP engine [18, 26, 33]. For example, streams in IoT are continuously ingested and correlated with large historical data. Trill [19] supports diverse analytics on streams and columnar data, but lacks transactions. DataFlow [15] focuses on logical abstractions rather than a unified query engine.
>
> Consequently, the demand for mixed workloads has resulted in several composite data architectures, exemplified in the “lambda” architecture, which requires multiple solutions to be stitched together — a difficult exercise that is time consuming and expensive. 
>
> In capital markets, for example, a real-time market surveillance application has to ingest trade streams at very high rates and <u>detect abusive trading patterns</u> (e.g., insider trading). This requires **correlating** large volumes of data by joining a stream with (1) historical records, (2) other streams, and (3) <u>==financial reference data==</u> which can change throughout the trading day. A triggered alert could in turn result in additional analytical queries, which will need to run on both ingested and historical data. In this scenario, trades arrive on a message bus (e.g., Tibco, IBM MQ, Kafka) and are processed by a stream processor (e.g., Storm) or a homegrown application, while the state is written to a key-value store (e.g., Cassandra) or an in-memory data grid (e.g., GemFire). This data is also stored in HDFS and analyzed periodically using a SQL-on-Hadoop or a traditional OLAP engine.
>
> These heterogeneous workflows, although far too common in practice, have several drawbacks (D1–D4):
>
> **D1. Increased complexity and total cost of ownership:** The use of incompatible and <u>==autonomous systems==</u> significantly increases their total cost of ownership. Developers have to master disparate APIs, data models, and tuning options for multiple products. Once in production, operational management is also a nightmare. To diagnose the root cause of a problem, highly-paid experts spend hours to correlate error logs across different products.
>
> **D2. Lower performance:** Performing analytics necessitates data movement between multiple <u>non-colocated</u> clusters, resulting in several network hops and multiple copies of data. Data may also need to be transformed when faced with incompatible data models (e.g., turning Cassandra’s ColumnFamilies into Storm’s domain objects).
>
> **D3. Wasted resources:** Duplication of data across different products wastes network bandwidth (due to increased data shuffling), CPU cycles, and memory.
>
> **D4. Consistency challenges:** The lack of a single **data governance model** makes it harder to reason about consistency semantics. For instance, a lineage-based recovery in Spark Streaming may replay data from the last checkpoint and ingest it into an external transactional store. With no common knowledge of lineage and the lack of distributed transactions across these two systems, ensuring **exactly-once** semantics is often left as an exercise for the application [4].
>
> **Our goal** — We aim to offer streaming, transaction processing, and interactive analytics in a single cluster, with better performance, fewer resources, and far less complexity than today’s solutions.
>
> **Challenges** — Realizing this goal involves overcoming significant challenges. **The first challenge** is the drastically different data structures and query processing paradigms that are optimal for each type of workload. For example, column stores are optimal for analytics, transactions need write-optimized row-stores, and <u>==infinite streams are best handled by sketches and windowed data structures==</u>. Likewise, while analytics thrive with batch-processing, transactions rely on point lookups/updates, and streaming engines use delta/incremental query processing. Marrying these conflicting mechanisms in a single system is challenging, as is **abstracting** away this heterogeneity from programmers.
>
> Another challenge is the difference in expectations of high availability (HA) across different workloads. Scheduling and resource provisioning are also harder in a mixed workload of streaming jobs, long-running analytics, and short-lived transactions. Finally, achieving interactive analytics becomes non-trivial when deriving insight requires joining a stream against massive historical data [7].
>
> **Our approach** — Our approach is a seamless integration of Apache Spark, as a computational engine, with Apache GemFire, as an in-memory transactional store. By exploiting the complementary functionalities of these two open-source frameworks, and carefully accounting for their drastically different design philosophies, SnappyData is the first unified, scale-out database cluster capable of supporting all three types of workloads. SnappyData also relies on a novel probabilistic scheme to ensure interactive analytics in the face of <u>==high-velocity streams==</u> and massive volumes of stored data.
>
> **Contributions** — We make the following contributions.
>
> 1. We discuss the challenges of marrying two breeds of distributed systems with drastically different design philosophies: a lineagebased system designed for high-throughput analytics (Spark) and a <u>==consensus-driven==</u> replication-based system designed for low latency operations (GemFire) §2.
> 2. We introduce the first unified engine to support streaming, transactions, and analytics in a single cluster. We overcome the challenges above by offering a unified API §4, utilizing a hybrid storage engine, sharing state across applications to minimize serialization §5, providing high-availability through low-latency failure detection and decoupling applications from data servers §6.1, bypassing the scheduler to interleave fine-grained and long-running jobs §6.2, and ensuring transactional consistency §6.3.
> 3. Using a mixed benchmark, we show that SnappyData delivers 1.5–2 × higher throughput and 7–142 × speedup compared to today’s state-of-the-art solutions §7.
>

越来越多的企业应用程序，尤其是金融交易和 IoT（物联网）中的应用程序，产生具有以下所有内容的混合工作负载：(1) 连续流处理，(2) 在线事务处理 (OLTP)，以及 (3) 联机分析处理 (OLAP)。 这些应用程序需要同时使用高速流来触发实时警报，将它们提取到写优化的事务存储中，并执行分析以快速获得**深度洞察**。<u>尽管为其中的一两个任务设计了一系列数据管理解决方案，但没有一种解决方案适合所有这三个任务</u>。

SQL-on-Hadoop 这类解决方案，例如 Hive、Impala/Kudu 和 SparkSQL，它们使用 OLAP 风格的优化和列格式来在大量静态数据运行 OLAP 查询。虽然适用于批处理，但这些系统并不是为**实时操作数据库**而设计，因为它们缺乏<u>通过事务一致性改变数据</u>、无法使用索引进行高效点访问，没有能力处理高并发和突发的工作负载。例如，Wildfire [17] 能够进行分析和流式导入，==**但缺乏 ACID 事务**==。

混合事务/分析处理系统 (HTAP) ，例如 MemSQL，通过以双格式（行和列）存储数据来支持 OLTP 和 OLAP 查询，但需要与外部流引擎（例如 Storm [34]、 Kafka、Confluent）一起使用，以支持流处理。

最后，有许多学术 [20, 31, 33] 和商业 [2, 8, 14, 34] 的解决方案可用于流和事件处理。尽管某些流处理器提供了某种形式的状态管理或事务（例如 Samza [2]、Liquid [23]、S-Store [27]），但它们只允许对流进行简单的查询。但是更复杂的分析，例如将流与大型历史表连接起来，需要在 OLAP 引擎中使用相同的优化 [18, 26, 33]。 例如物联网中，数据流不断地导入并与大量历史数据相关联。Trill [19] 支持对流和列数据进行各种分析，但缺乏事务。 DataFlow [15] 侧重于逻辑抽象而不是统一的查询引擎。

因此，对混合工作负载的需求导致了多种复合数据架构，以 **lambda** 架构为例，它需要将多个解决方案组合在一起 —— 这是一项既费时又费钱的困难工作。

例如，在资本市场中，实时市场监控应用程序必须以非常高的速率接收交易流，并<u>检测滥用交易模式</u>（例如内幕交易）。这需要关联大量数据，要将数据流与 (1) 历史记录、(2) 其他数据流和 (3) 在整个交易日可能发生变化的<u>==财务参考数据==</u>连接起来。触发的警报反过来可能会导致额外的分析查询，这些查询需要在导入的数据和历史数据上运行。这种情况下，到达消息总线（例如 Tibco、IBM MQ、Kafka）的交易，将由**流处理器**（例如 Storm）或自主开发的应用程序处理，同时将状态写入键值存储（例如 , Cassandra) 或内存数据网格（例如 GemFire）。这些数据也存储在 HDFS 中，并使用 SQL-on-Hadoop 或传统的 OLAP 引擎进行定期分析。

这些异构工作流虽然在实践中很常见，但有几个缺点（D1-D4）：

- **D1. 增加的复杂性和总拥有成本**：使用不兼容和<u>==自主系统==</u>会显著增加总体成本。 开发人员必须掌握多种产品的不同 API、数据模型和调优选项。一旦投入生产，运维也是一场噩梦。为了诊断问题的根本原因，高薪专家花费数小时将不同产品的错误日志关联起来。
- **D2. 性能较低**：执行分析需要在多个<u>非协同定位</u>的集群之间移动数据，所以网络会多几跳，并且会存在多个数据副本。如果数据模型不兼容，可能需要转换数据（例如，将 Cassandra 的 ColumnFamilies 转换为 Storm 的对象）。
- **D3. 资源浪费**：在不同产品之间复制数据会浪费网络带宽（由于需要 shuffle 的数据量增加）、CPU 周期和内存。
- **D4. 一致性挑战**：缺乏单一的**数据治理模型**使得推理一致性语义变得更加困难。例如，Spark Streaming 中基于血缘关系的恢复，可能会从最后一个检查点重放数据，并将其导入到外部事务存储中。 由于对血缘关系没有共同的了解，并且两个系统之间缺乏分布式事务，因此确保**恰好一次**语义通常留给应用程序 [4]去解决。

**我们的目标** —— 在单个集群中提供流、事务处理和交互式分析，与现在的解决方案相比，性能更好、资源更少、复杂性更低。

**挑战** —— 实现这一目标需要克服重大挑战。**第一个挑战**是，对于每种类型的工作负载来说，数据结构和查询处理范式都是截然不同的。例如，==列存最适合分析==，==事务需要写优化的行存==，<u>==无限流最好由草图和窗口数据结构处理==</u>。同样，虽然分析在批处理中蓬勃发展，但事务依赖于点查找/更新，而流引擎使用增量查询处理。在单个系统中结合这些相互冲突的机制是一项挑战，从程序员那里**抽象**出这种异构性也是一项挑战。

另一个挑战是不同负载对高可用性 (HA) 的期望存在差异。在流作业、长时运行的分析和短期事务的混合工作负载中，调度和资源配置也更加困难。最后为了获得洞察，流需要关联大量历史数据，实现交互式分析变得不简单[7]。

**我们的方法** ——  无缝集成计算引擎 Apache Spark 和内存事务存储的 Apache GemFire 。通过利用这两个开源框架的互补功能，并仔细考虑它们截然不同的设计理念，SnappyData 是第一个能够支持所有三种类型工作负载的统一、可横向扩展的数据库集群。 SnappyData 还依赖于一种新颖的概率方案，以确保在面对<u>==高速流==</u>和大量存储数据时进行交互式分析。

**贡献** —— 我们做出以下贡献：

1. 我们讨论了将两种设计理念截然不同的分布式系统结合起来的挑战：专为高吞吐量分析设计、基于血缘关系的 Spark 和专为低延迟操作设计、基于<u>==共识驱动复制==</u>的系统  GemFire §2 .
2. 我们是第一个引入了统一引擎在单个集群中支持流、事务和分析。通过提供统一的 API §4，利用混合存储引擎、跨应用程序共享状态以最小化序列化 §5，通过低延迟故障检测和将应用程序与数据服务器解耦提供高可用性来克服上述挑战 §6.1，绕过调度器交错执行<u>==细粒度的小查询==</u>和长时间运行的作业 §6.2，并确保事务一致性 §6.3。
3. 使用混合基准，我们表明与当今最先进的解决方案相比，SnappyData 提供 1.5-2 倍的吞吐量和 7-142 倍的加速 §7。

## 2.    概述

### 2.1    方法概述

> To support mixed workloads, SnappyData carefully fuses Apache Spark, as a computational engine, with Apache GemFire, as a transactional store.
>
> Through a common set of abstractions, Spark allows programmers to tackle a confluence of different paradigms (e.g., streaming, machine learning, SQL analytics). Spark’s core abstraction, a Resilient Distributed Dataset (RDD), provides fault tolerance by efficiently storing the lineage of all transformations instead of the data. The data itself is partitioned across nodes and if any partition is lost, it can be reconstructed using its lineage. The benefit of this approach is two-fold: avoiding replication over the network, and higher throughput by operating on data as a batch. While this approach provides efficiency and fault tolerance, it also requires that an RDD be immutable. In other words, Spark is simply designed as a computational framework, and therefore (i) does not have its own storage engine and (ii) does not support mutability semantics^1^.
>
> > ^1^Although IndexedRDD [6] offers an updatable key-value store [6], it does not support <u>==colocation for high-rate ingestions==</u>  or distributed transactions. It is also unsuitable for HA, as it relies on disk-based checkpoints for fault tolerance.
>
> On the other hand, Apache GemFire [1] (a.k.a. Geode) is one of the most widely adopted in-memory data grids in the industry^2^, which manages records in a partitioned row-oriented store with synchronous replication. It ensures consistency by integrating a **<u>dynamic group membership service</u>** and a distributed transaction service. GemFire allows for indexing and both fine-grained and batched data updates. Updates can be reliably enqueued and asynchronously written back out to an external database. In-memory data can also be persisted to disk using append-only logging with offline compaction for fast disk writes [1].
>
> > ^2^GemFire is used by major airlines, travel portals, insurance firms, and 9 out of 10 investment banks on Wall Street [1].
>
> **Best of two worlds** — To combine the best of both worlds, SnappyData seamlessly integrates Spark and GemFire runtimes, adopting Spark as the programming model with extensions to support mutability and HA (high availability) through GemFire’s replication and fine grained updates. This marriage, however, poses several non-trivial challenges.

为了支持混合工作负载，SnappyData 小心地将 Apache Spark（作为计算引擎）与 Apache GemFire（作为事务存储）融合在一起。

通过一组通用的抽象，Spark 允许程序员融合不同范式的（例如，流、机器学习、SQL 分析）工作模型。Spark 的核心抽象是弹性分布式数据集 (RDD)，它通过有效地存储所有转换的血缘关系而不是数据来提供容错能力。数据本身是跨节点分区的，如果任何分区丢失，可以使用其血缘关系进行重建。这种方法有两个好处：避免在网络间复制，以及通过批处理来提高吞吐量。虽然这种方法提供了效率和容错，但它也要求 RDD 是不可变的。换句话说，Spark 被简单地设计为一个计算框架，因此 (i) 没有自己的存储引擎，并且 (ii) 不支持可变性语义^1^。

> ^1^虽然 IndexedRDD [6] 提供了一个可更新的键值存储 [6]，但它不支持<u>==高速导入数据==</u>和分布式事务。它也不适合 HA，因为它依赖基于磁盘的检查点来实现容错。
>
> - [ ] colocation 

另一方面，Apache GemFire [1]（又名 Geode）是业界采用最广泛的内存数据网格之一^2^，在分区的行存储中同步复制记录。通过集成**<u>成员动态分组服务</u>**和分布式事务服务来确保一致性。GemFire 允许索引，可以细粒度或批量更新数据。以可靠地方式排队**更新**并异步写回外部数据库。使用**Append-only 的日志记录**，内存数据也可以持久化到磁盘；通过**离线 Compaction** 实现快速磁盘写入 [1]。

> ^2^GemFire 被大型航空公司、旅游门户网站、保险公司和华尔街 10 家投资银行中的 9 家使用 [1]。

**两全其美**  —  为了结合两者优点，SnappyData 无缝集成了 Spark 和 GemFire ，采用 Spark 作为编程模型，并通过 GemFire 的复制和细粒度更新，支持可变性和 HA（高可用性）。然而，这场婚姻带来了几个重要的挑战。

### 2.2    集成 Spark 和 GemFire 的挑战

> Each Spark application runs as an independent set of processes (i.e., executor JVMs) on the cluster.  While immutable data can be cached and reused in these JVMs within a single application, sharing data across applications requires an external storage tier (e.g., HDFS). In contrast, our goal in SnappyData is to achieve an “always-on” operational design whereby clients can connect at will, and share data across any number of concurrent connections. **The first challenge** is thus to alter the life-cycle of Spark executors so that their JVMs are *long-lived* and *de-coupled from individual applications*. This is difficult because, unlike Spark which spins up executors on-demand (using Mesos or YARN) with resources sufficient only for the current job, we need to employ a static resource allocation policy whereby the same resources are reused concurrently across several applications. Moreover, unlike Spark which assumes that all jobs are CPU-intensive and batch (or microbatch), in a hybrid workload we do not know if an operation is a long-running and CPU-intensive job or a low-latency data access.
>
> The second challenge is that in Spark a single driver orchestrates all the work done on the executors. Given the need for high concurrency in our hybrid workloads, this driver introduces (i) a single point of contention, and (ii) a barrier for HA. If the driver fails, the executors are shutdown, and any cached state has to be re-hydrated. 
>
> Due to its batch-oriented design, Spark uses a block-based memory manager and requires no synchronization primitives over these blocks. In contrast, GemFire is designed for fine-grained, highly concurrent and mutating operations. As such, GemFire uses a variety of concurrent data structures, such as distributed hashmaps, treemap indexes, and distributed locks for pessimistic transactions. SnappyData thus needs to (i) extend Spark to allow arbitrary point lookups, updates, and inserts on these complex structures, and (ii) extend GemFire’s distributed locking service to support modifications of these structures from within Spark.
>
> Spark RDDs are immutable while GemFire tables are not. Thus, Spark applications accessing GemFire tables as RDDs may experience non-deterministic behavior. A naïve approach of creating a copy when the RDD is lazily materialized is too expensive and defeats the purpose of managing local states in Spark executors.
>
> Finally, Spark’s growing community has zero tolerance for incompatible forks. This means that, to retain Spark users, SnappyData cannot change Spark’s semantics or execution model for existing APIs (i.e., all changes in SnappyData must be extensions).

每个 Spark 应用程序在集群上作为一组独立的进程（即 executor  JVM）运行。虽然可以在单个应用程序的  JVM 内缓存和重用这些不可变数据，但跨应用程序共享数据需要外部存储层（例如HDFS）。相比之下，SnappyData 的设计目标是实现“永远在线”，客户端可以随意连接，并通过任意数量的并发连接共享数据。因此，**第一个挑战**是改变 Spark executor 的生命周期，以便可以长时运行它们的 JVM ，并且与单个应用程序解耦。这很困难，因为 Spark （使用 Mesos 或 YARN）按需启动 executor，其资源仅够当前作业使用，而我们需要采用静态资源分配策略，从而在多个应用程序中同时重用相同的资源。此外，Spark 假设所有作业都是 CPU 密集型和批处理（或微批处理）；在混合工作负载中，我们无法知道作业是长时运行且 CPU 密集型的，还是低延迟的数据访问型。

第二个挑战是，Spark 使用单个 **Driver** 协调 **executor** 完成所有工作。考虑混合工作负载需要高并发性，**Driver** 引入了 (i) 单点争用，以及 (ii) HA 的障碍。如果 **Driver** 失败， 将关闭 **executor**，需要重建缓存。

由于其面向批处理的设计，Spark 使用基于块的内存管理器并且这些块不需要同步。相比之下，GemFire 是为细粒度、高并发和修改操作而设计的。所以，GemFire 使用各种并发数据结构，例如分布式 `hashmap`、`treemap` 索引和基于悲观事务的分布式锁。因此，SnappyData 需要 (i) 扩展 Spark 以允许在这些复杂结构上进行任意的点查找、更新和插入，以及 (ii) 扩展 GemFire 的分布式锁定服务以便从 Spark 内部修改这些结构。

Spark RDD 是不可变的，而 GemFire 表不是。因此，Spark 应用程序使用 RDD 访问 GemFire 表时可能会遇到不确定性行为。延迟物化 RDD 时，创建副本的简单方法代价太高，并且违背了在 Spark executor 中管理本地状态的目的。

最后，不断壮大的 Spark 社区对不兼容的分支采取零容忍度。这意味着，为了留住 Spark 用户，SnappyData 不能更改 现有 Spark API 的语义和执行模型（即，SnappyData 必须采用扩展的方式修改 Spark）。

## 3.    架构

> Figure 1 depicts SnappyData’s core components (the original components from Spark and GemFire are highlighted).
>
> > - [ ] Figure 1
>
> SnappyData’s hybrid storage layer is primarily in-memory, and can manage data in row, column, or probabilistic stores. SnappyData’s column format is derived from Spark’s RDD implementation.  SnappyData’s row-oriented tables extend GemFire’s table and thus support indexing, and fast reads/writes on indexed keys §5.1. In addition to these “exact” stores, SnappyData can also summarize data in **probabilistic** data structures, such as **stratified samples** and **other forms of ==synopses==**. SnappyData’s query engine has built-in support for approximate query processing (AQP), which can exploit these probabilistic structures. This allows applications to trade accuracy for interactive-speed analytics on streams or massive datasets §5.2.
>
> SnappyData supports two programming models—SQL (by extending SparkSQL dialect) and Spark’s API. Thus, one can perceive SnappyData as a SQL database that uses Spark’s API as its language for stored procedures. Stream processing in SnappyData is primarily through Spark Streaming, but it is modified to run *in-situ* with SnappyData’s store §4.
>
> SQL queries are federated between Spark’s Catalyst and GemFire’s OLTP engine. An initial query plan determines if the query is a low latency operation (e.g., a key-based lookup) or a high latency one (scans/aggregations). SnappyData avoids scheduling overheads for OLTP operations by immediately routing them to appropriate data partitions §6.2.
>
> To support replica consistency, fast point updates, and instantaneous detection of failure conditions in the cluster, SnappyData relies on GemFire’s P2P (peer-to-peer) cluster membership service [1]. Transactions follow a 2-phase commit protocol using GemFire’s Paxos implementation to ensure consensus and view consistency across the cluster.
>

图1描述了 SnappyData 的核心组件（Spark 和 GemFire 的原始组件高亮显示）。

> - [ ] 图一

SnappyData 的混合存储层主要在内存中，可管理行存、列存或概率存储中的数据。SnappyData 的列格式源自 Spark RDD 的实现。SnappyData 行存扩展至 GemFire 的表，因此支持索引，以及对索引键的快速读/写 §5.1。 除了这些“精确”存储之外，SnappyData 还可以将数据汇总为**概率**数据结构，例如**分层样本**或**其他形式的==概要==**。 SnappyData 的查询引擎内置了对近似查询处理 (AQP) 的支持，可以利用这些概率结构。 这允许应用程序在流或海量数据集上平衡准确性和速度以进行交互式分析 §5.2 。

SnappyData 支持两种编程模型 —— SQL（通过扩展 SparkSQL 方言）和 Spark API。这样可以视 SnappyData 为使用 Spark API 作为其存储过程语言的 SQL 数据库。SnappyData 主要是通过 Spark Streaming 进行流处理，但它被修改为与 SnappyData 的存储一起**就地**运行§4。

SQL 查询是在 Spark 的 Catalyst 和 GemFire 的 OLTP 引擎之间联邦查询。首先确定查询计划是低延迟操作（例如，基于键的查找）还是高延迟操作（扫描/聚合）。SnappyData 通过立即将 OLTP 操作路由到适当的数据分区 §6.2 来避免调度开销。

为了支持副本一致性、快速点更新和集群中故障条件的即时检测，SnappyData 依赖 GemFire 的 P2P（点对点）集群成员服务 [1]。 事务遵循两阶段提交协议，使用 GemFire 的 Paxos 实现来确保整个集群的共识和视图一致性。

## 4.    统一的API

> Spark offers a rich procedural API for querying and transforming disparate data formats (e.g., JSON, Java Objects, CSV). Likewise, to retain a consistent programming style, SnappyData offers its mutability functionalities as extensions of SparkSQL’s dialect and its DataFrame API. These extensions are backward compatible, i.e., applications that do not use them observe Spark’s original semantics.
>
> A DataFrame in Spark is a distributed collection of data organized into named columns. A DataFrame can be accessed from a `SQLContext`, which itself is obtained from a `SparkContext` (a `SparkContext` is a connection to Spark’s cluster). Likewise, much of SnappyData’s API is offered through `SnappyContext`, which is an extension of `SQLContext`. Listing 1 is an example of using `SnappyContext`.
>
> Stream processing often involves maintaining counters or more complex multi-dimensional summaries. As a result, stream processors today are either used alongside a scale-out in-memory key-value store (e.g., Storm with Redisor Cassandra) or come with their own basic form of state management (e.g., Samza, Liquid [23]). These patterns are often implemented in the application code using simple get/put APIs. While these solutions scale well, we find that users modify their search patterns and trigger rules quite often. These modifications require expensive code changes and lead to brittle and hard-to-maintain applications.
>
> In contrast, SQL-based stream processors offer a higher level abstraction to work with streams, but primarily depend on roworiented stores (e.g., [5, 8, 27]) and are thus limited in supporting complex analytics. To support continuous queries with scans, aggregations, top-K queries, and joins with historical and reference data, some of the same optimizations found in OLAP engines must be incorporated in the streaming engine [26]. Thus, SnappyData extends Spark Streaming to allow declaring and querying streams in SQL. More importantly, SnappyData provides OLAP-style optimizations to enable scalable stream analytics, including columnar formats, approximate query processing, and <u>==co-partitioning==</u> [9].

Spark 提供了丰富的 API 来查询和转换不同的数据格式（例如，JSON、Java 对象、CSV）。同样，为了保持一致的编程风格，SnappyData 将其数据修改的功能作为 SparkSQL 方言及 DataFrame API 的扩展来提供。这些扩展是向后兼容的，即不使用它们的应用程序遵守 Spark 的原始语义。

Spark 中的 DataFrame 是组织为有列名的分布式数据集合。可以从 `SQLContext` 获取 `DataFrame` ，本身是从 `SparkContext` 获得的（ `SparkContext` 是到 Spark 集群的连接）。同样，SnappyData 的大部分 API 都是通过 `SnappyContext` 提供，它是 `SQLContext` 的扩展。 清单 1 是一个使用 `SnappyContext` 的示例。

```scala
/*
  --                                                  --  
  -- Listing 1: Working with DataFrames in SnappyData --
  --                                                  --
*/

// Create a SnappyContext from a SparkContext
val spContext = new org.apache.spark.SparkContext(conf)
val snpContext = org.apache.spark.sql.SnappyContext (spContext)

// Create a column table using SQL
snpContext.sql("CREATE TABLE MyTable (id int, data string) using column")

// Append contents of a DataFrame into the table
someDataDF.write.insertInto("MyTable");

// Access the table as a DataFrame
val myDataFrame: DataFrame = snpContext.table("MyTable")
println(s"Number of rows in MyTable = ${myDataFrame.count()}")
```

流处理通常涉及维护计数器或更复杂的多维聚合。因此，今天的流处理器要么与横向扩展的内存键值存储一起使用（例如，Storm with Redisor Cassandra），要么自己实现了基本的状态管理（例如，Samza、Liquid [23]），通常使用简单的 `get`/`put` API 在应用程序代码中实现。虽然这些解决方案扩展性很好，但我们发现用户经常修改他们的搜索模式和触发规则。 这些修改需要昂贵的代码更改，并导致应用程序脆弱且难以维护。

相比之下，基于 SQL 的流处理器提供更高的抽象来处理流，但主要依赖于面向行的存储（例如 [5, 8, 27]），因此在支持复杂分析方面受到限制。为了通过扫描、聚合、top-K 查询以及与历史数据和参考数据的联接来支持连续查询，必须将在 OLAP 引擎中的一些相同优化整合到流引擎中 [26]。 因此，SnappyData 扩展了 Spark Streaming 以允许在 SQL 中声明和查询流。 更重要的是，SnappyData 提供了 OLAP 风格的优化，以实现可扩展的流分析，包括列格式、近似查询处理和<u>==共分区==</u> [9]。

## 5.    混合存储

### 5.1    行存和列存表

> Tables can be partitioned or replicated and are primarily managed in memory with one or more consistent replicas. The data can be managed in Java heap memory or off-heap. Partitioned tables are always partitioned horizontally across the cluster. For large clusters, we allow data servers to belong to one or more logical groups, called “**server groups**”. The storage format can be “row” (either partitioned or replicated tables) or “column” (only supported for partitioned tables) format. Row tables incur a higher in-memory footprint but are well suited to random updates and point lookups, especially with in-memory indexes. Column tables manage column data in contiguous blocks and are compressed using dictionary, run-length, or bit encoding [36]. Listing 2 highlights some of SnappyData’s syntactic extensions to the using and options clauses of the create table statement.
>
> We extend Spark’s column store to support mutability. Updating row tables is trivial. When records are written to column tables, they first arrive in a **delta row buffer** that is capable of high write rates and then age into a columnar form. The delta row buffer is merely a partitioned row table that uses the same partitioning strategy as its base column table. This buffer table is backed by a conflating queue that periodically empties itself as a new batch into the column table. Here, conflation means that consecutive updates to the same record result in only the final state getting transferred to the column store. For example, inserted/updated records followed by deletes are removed from the queue. The delta row buffer itself uses **copy-on-write semantics** to ensure that concurrent application updates do not cause inconsistency [10]. SnappyData extends Spark’s Catalyst optimizer to merge the delta row buffer during query execution.
>

表可以分区或复制，主要在内存中管理，有一个或多个一致的副本。可以在 Java 堆内或堆外管理数据。分区表始终在集群中水平分区。对于大型集群，我们允许数据服务器属于一个或多个逻辑组，称为**服务器组**。存储格式可以是**行存**（分区表或复制表）或**列存**（仅支持分区表）。行表会产生更高的内存占用，但非常适合随机更新和点查找，尤其是内存索引。列存管理连续块中的列数据，并使用字典、run-length或位编码进行压缩 [36]。清单 2 显示了 SnappyData 对 `create table` 语句的 `using` 和 `options` 子句的一些语法扩展。

```SQL
/*
  --                                                  --  
  --     Listing 2: Create Table DDL in SnappyData    --
  --                                                  --
*/
CREATE [Temporary] TABLE [IF NOT EXISTS] table_name (
 <column definition>
 )
 USING [ROW | COLUMN]
 -- Should it be row or column oriented?
 OPTIONS (
 PARTITION_BY ’PRIMARY KEY | column(s) ’,
 -- Partitioning on primary key or one or more columns
 -- Will be a replicated table by default
 COLOCATE_WITH ’parent_table’,
 -- Colocate related records in the same partition ?
 REDUNDANCY ’1’ ,
 -- How many memory copies?
 PERSISTENT [Optional disk store name]
 -- Should this persist to disk too?
 OFFHEAP "true | false",
 -- Store in off􀀀heap memory?
 EVICTION_BY "MEMSIZE 200 | HEAPPERCENT"
 -- Heap eviction based on size or occupancy ratio ?
 ... )
```

我们扩展了 Spark 的列存以支持修改。更新行表很简单，当记录写入列存时，它们首先到达一个**增量行存缓冲区**，该缓冲区支持高写入率，**一段时间后==老化==为列存**。**增量行存缓冲区**只是一个分区行表，使用与基准列存相同的分区策略。该缓冲表由一个合并队列支持，该队列定期清空，将数据作为新批次插入列存中。在这里，合并意味着对同一记录的连续更新只会导致最终状态转移到列存。例如，先在队列中插入或更新，然后删除记录，等于从队列中删除该记录。增量行存缓冲区本身使用**写时复制语义**来确保应用程序并发更新不会导致不一致 [10]。 SnappyData 扩展了 Spark 的 Catalyst 优化器，以在查询执行期间合并增量行缓冲区。



### 5.2    Probabilistic Store

Achieving interactive response time is challenging when running complex analytics on streams, e.g., joining a stream with a large table [30]. Even OLAP queries on stored datasets can take tens of seconds to complete if they require a distributed shuffling of records, or if hundreds of concurrent queries run in the cluster [13]. In such cases, SnappyData’s storage engine is capable of using probabilistic structures to dramatically reduce the volume of input data and provide approximate but extremely fast answers. SnappyData’s probabilistic structures include uniform samples, stratified samples, and sketches [22]. The novelty in SnappyData’s approach compared to previous AQP engines [40] is in the way that it creates and maintains these structures efficiently and in a distributed manner. Given these structures, SnappyData uses off-the-shelf error estimation techniques [11, 41]. Thus, we only discuss SnappyData’s sample selection and maintenance strategies.

**Sample selection** — Unlike uniform samples, choosing which stratified samples to build is a non-trivial problem. The key question is which sets of columns to build a stratified sample on. Prior work has used skewness, popularity, and storage cost as the criteria for choosing column-sets [12, 13]. SnappyData extends these criteria as follows: for any declared or foreign-key join, the join key is included in a stratified sample in at least one of the participating relations (tables or streams). However, SnappyData never includes a table’s primary key in its stratified sample(s). Furthermore, we offer our open-source tool, called WorkloadMiner, which automatically analyzes past query logs and reports a rich set of statistics [3]. These statistics guide SnappyData’s users through the sample selection process. WorkloadMiner is integrated into CliffGuard. CliffGuard guarantees a robust physical design (e.g., set of samples), which remains optimal even if future queries deviate from past ones [28].

Once a set of samples is chosen, the challenge is how to update them, which is a key differentiator between SnappyData and previous AQP systems that use stratified samples [12, 21, 39].

**Sample maintenance** — Previous AQP engines that use offline sampling update and maintain their samples periodically using a single scan of the entire data [29]. This strategy is not suitable for SnappyData with streams and mutable tables for two reasons. First, maintaining per-stratum statistics across different nodes in the cluster is a complex process. Second, updating a sample in a streaming fashion requires maintaining a reservoir [16, 35], which means the sample must either fit in memory or be evicted to disk. Keeping samples entirely in memory is impractical for infinite streams unless we perpetually decrease the sampling rate. Likewise, diskbased reservoirs are inefficient as they require retrieving and removing individual tuples from disk as new tuples are sampled.

To solve these problems, SnappyData always includes timestamp as an additional column in every stratified sample. Uniform samples are treated as a special case with only one stratified column, i.e., timestamp. As new tuples arrive in a stream, a new batch (in row format) is created for maintaining a sample of each observed value of the stratified columns. Whenever a batch size exceeds a certain threshold (1M tuples by default), it is evicted and archived to disk (in a columnar format) and a new batch is started for that stratum.

Treating each micro-batch as an independent stratified sample has several benefits. First, this allows SnappyData to adaptively adjust the sampling rate for each micro-batch without the need for inter-node communications in the cluster. Second, once a microbatch is completed, its tuples never need to be removed or replaced, and therefore they can be safely stored in a compressed columnar format and even archived to disk. Only the latest micro-batch needs to be in-memory and in row-format. Finally, each micro-batch can be routed to a single node, reducing the need for network shuffles.

### 5.3    State Sharing

> **==SnappyData hosts GemFire’s tables in the executor nodes as either partitioned or replicated tables==**. When partitioned, the individual buckets are presented as Spark RDD partitions and their access is therefore parallelized. This is similar to the way that any external data source is accessed in Spark, except that the common operators are optimized in SnappyData. For example, by keeping each partition in columnar format, SnappyData avoids additional copying and serialization and speeds up scan and aggregation operators. SnappyData can also <u>==colocate tables==</u> by <u>exposing an appropriate partitioner</u> to Spark (see Listing 2).
>
> Native Spark applications can register any DataFrame as a temporary table. In addition to being visible to the Spark application, such a table is also registered in SnappyData’s catalog—a shared service that makes tables visible across Spark and GemFire. This allows remote clients connecting through ODBC/JDBC to run SQL queries on Spark’s temporary tables as well as tables in GemFire.
>
> In streaming scenarios, the data can be sourced into any table from parent stream RDDs (DStream), which themselves could source events from an external queue, such as Kafka. To minimize shuffling, SnappyData tables can preserve the partitioning scheme used by their parent RDDs. For example, a Kafka queue listening on Telco CDRs (call detail records) can be partitioned on subscriberID so that Spark’s DStream and the SnappyData table ingesting these records will be partitioned on the same key.
>
> from parent stream RDDs (DStream), which themselves could source events from an external queue, such as Kafka. To minimize shuffling, SnappyData tables can preserve the partitioning scheme used by their parent RDDs. For example, a Kafka queue listening on Telco CDRs (call detail records) can be partitioned on subscriberID so that Spark’s DStream and the SnappyData table ingesting these records will be partitioned on the same key.

**==SnappyData 将 GemFire 的表作为分区表或复制表托管在 executor 节点==**。分区后，各个存储桶将显示为 Spark RDD 分区，因此是并行访问它们。类似于在 Spark 中访问外部数据源，只是常见的运算符在 SnappyData 中进行了优化。 例如，通过将每个分区保持为列格式，SnappyData 避免了额外的复制和序列化，并加快了扫描和聚合操作的速度。 SnappyData 还可以通过<u>向 Spark 公开适当的分区器</u>来<u>==并置表==</u>（参见清单 2）。

### 5.4  感知局部性的分区设计

> A major challenge in horizontally partitioned distributed databases is to restrict the number of nodes involved in order to minimize (i) shuffling during query execution and (ii) distributed locks [25, 38]. In addition to network costs, shuffling can also cause CPU bottlenecks by incurring excessive copying (between kernel and user space) and serialization costs [32]. To reduce the need for shuffling and distributed locks, our data model promotes two fundamental ideas:
>
> 1. **Co-partitioning with shared keys** — A common technique in data placement is to take the application’s access patterns into account. We pursue a similar strategy in SnappyData: since joins require a shared key, we co-partition related tables on the join key. SnappyData’s query engine can then optimize its query execution by localizing joins and pruning unnecessary partitions.
> 2. **Locality through replication** — Star schemas are quite prevalent, wherein a few ever-growing fact tables are related to several dimension tables. Since dimension tables are relatively small and change less often, schema designers can ask SnappyData to replicate these tables. SnappyData particularly uses these replicated tables to optimize joins.
>

水平分区分布式数据库的一个主要挑战是限制所涉及的节点数量，以最大限度地减少 (i) 查询执行期间的 shuffle 和 (ii) 分布式锁 [25, 38]。 除了网络成本之外，shuffle 还会导致过度复制（在内核和用户空间之间）和序列化成本 [32]，从而导致 CPU 瓶颈。 为了减少对 shuffle 和分布式锁的需求，我们的数据模型提出了两个基本思想：

**使用共享 Key 共同分区** —— 数据放置的一种常用技术是考虑应用程序的访问模式。SnappyData 采用了类似的策略：由于连接需要共享 Key，我们在联接 key 上对相关表进行共同分区。然后，SnappyData 的查询引擎可以通过本地化连接和修剪不必要的分区来优化其查询执行。

**通过复制实现局部性**——星型模式非常普遍，一些不断增长的事实表与多个维度表相关。由于维度表相对较小且更改较少，因此架构设计者可以要求  SnappyData 复制这些表。 SnappyData 使用这些复制表来特别优化联接。

## 6.    HYBRID CLUSTER MANAGER

> Spark applications run as independent processes in the cluster, coordinated by the application’s main program, called the driver program. Spark applications connect to cluster managers (YARN or Mesos) to acquire executor nodes. While Spark’s approach is appropriate for long-running tasks, as **an operational database**, SnappyData’s cluster manager must meet additional requirements, such as high concurrency, high availability, and consistency.

Spark 应用程序作为集群中的独立进程运行，由应用程序的主程序（称为 **Driver**）协调。 Spark 应用程序连接到集群管理器（YARN 或 Mesos）以获取 executor 节点。 虽然 Spark 的方法适用于长时运行的任务，但作为[操作型数据库](https://zhuanlan.zhihu.com/p/344508825)，SnappyData 的集群管理器必须满足其他要求，例如高并发、高可用性和一致性。

### 6.1    High Availability

To ensure high availability (HA), SnappyData needs to detect faults and be able to recover from them instantly.

**Failure detection** — Spark uses heartbeat communications with a central master process to determine the fate of the workers. Since Spark does not use a consensus-based mechanism for failure detection, it risks shutting down the entire cluster due to master failures. However, as an always-on operational database, SnappyData needs to detect failures faster and more reliably. For faster detection, SnappyData relies on UDP neighbor ping and TCP ack timeout during normal data communications. To establish a new, consistent view of the cluster membership, SnappyData relies on GemFire’s weighted quorum-based detection algorithm [1]. Once GemFire establishes that a member has indeed failed, it ensures that a consistent view of the cluster is applied to all members, including the Spark master, driver, and data nodes.

**Failure recovery** — Recovery in Spark is based on logging the transformations used to build an RDD (i.e., its lineage) rather than the actual data. If a partition of an RDD is lost, Spark has sufficient information to recompute just that partition [37]. Spark can also  checkpoint RDDs to stable storage to shorten the lineage, thereby shortening the recovery time. The decision of when to checkpoint, however, is left to the user. GemFire, on the other hand, relies on replication for instantaneous recovery, but at the cost of lower throughput. SnappyData merges these recovery mechanisms as follows:

1. Fine-grained updates issued by transactions avoid the use of Spark’s lineage altogether, and instead use GemFire’s eager replication for fast recovery.
2. Batched and streaming micro-batch operations are still recovered by RDD’s lineage, but instead of HDFS, SnappyData writes their checkpoints to GemFire’s in-memory storage, which itself relies on a fast P2P (peer-to-peer) replication for recovery. Also, SnappyData’s intimate knowledge of the load on the storage layer, the data size, and the cost of recomputing a lost partition, allows for automating the choice of checkpoint intervals based on an application’s tolerance for recovery time.

### 6.2    Hybrid Scheduler and Provisioning

Thousands of concurrent clients can simultaneously connect to a SnappyData cluster. To support this degree of concurrency, SnappyData categorizes incoming requests as low and high latency operations. By default, SnappyData treats a job as a low-latency operation unless it accesses a columnar table. However, applications can also explicitly label their latency sensitivity. SnappyData allows low-latency operations to bypass Spark’s scheduler and directly operate on the data. High-latency operations are passed through Spark’s fair scheduler. For low-latency operations, SnappyData attempts to re-use their executors to maximize their data locality (in-process). For high-latency jobs, SnappyData dynamically expands their compute resources while retaining the nodes caching their data.

### 6.3    Consistency Model

SnappyData relies on GemFire for its consistency model. GemFire supports “read committed” and “repeatable read” transaction isolation levels using a variant of the Paxos algorithm [24]. Transactions detect write-write conflicts and assume that writers rarely conflict. When write locks cannot be obtained, transactions abort without blocking [1].

SnappyData extends Spark’s SparkContext and SQLContext to add mutability semantics. SnappyData gives each SQL connection its own SQLContext in Spark to allow applications to start, commit, and abort transactions.

While any RDD obtained by a Spark program observes a consistent view of the database, multiple programs can observe different views when transactions interleave. An MVCC mechanism (based on GemFire’s internal row versions) can be used to deliver a single snapshot view to the entire application.

In streaming applications, upon faults, Spark recovers lost RDDs from their lineage. This means that some subset of the data will be replayed. To cope with such cases, SnappyData ensures the exactly-once semantics at the storage layer so that multiple write attempts are idempotent, hence relieving developers of having to ensure this in their own applications. SnappyData achieves this goal by placing the entire flow as a single transactional unit of work, whereby the source (e.g., a Kafka queue) is acknowledged only when the micro-batch is entirely consumed and the application state is successfully updated. This ensures automatic rollback of incomplete transactions.

## 7.    EXPERIMENTS

## 8.    CONCLUSION

We proposed a unified platform for real time operational analytics, SnappyData, to support OLTP, OLAP, and stream analytics in a single integrated solution. Our approach is a deep integration of a computational engine for high throughput analytics (Spark) with a scale-out in-memory transactional store (GemFire). SnappyData extends SparkSQL and Spark Streaming APIs with mutability semantics, and offers various optimizations to enable colocated processing of streams and stored datasets. We also made the case for integrating approximate query processing into this platform for enabling real-time operational analytics over large (stored or streaming) data. Hence, we believe that our platform significantly lowers the TCO for mixed workloads compared to disparate products that are managed, deployed, and monitored separately.
