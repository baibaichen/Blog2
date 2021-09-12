#  SnappyData: A Unified Cluster for Streaming, Transactions, and Interactive Analytics

**ABSTRACT**  Many modern applications are a mixture of streaming, transactional and analytical workloads. However, traditional data platforms are each designed for supporting a specific type of workload. The lack of a single platform to support all these workloads has forced users to combine disparate products in custom ways. The common practice of stitching heterogeneous environments has caused enor- mous production woes by increasing complexity and the total cost of ownership.

To support this class of applications, we present SnappyData as the first unified engine capable of delivering analytics, transactions, and stream processing in a single integrated cluster. We build this hybrid engine by carefully marrying a big data computational en- gine (Apache Spark) with a scale-out transactional store (Apache GemFire). We study and address the challenges involved in build- ing such a hybrid distributed system with two conflicting compo- nents designed on drastically different philosophies: one being a lineage-based computational model designed for high-throughput analytics, the other a consensus- and replication-based model de- signed for low-latency operations

## 1.  INTRODUCTION

An increasing number of enterprise applications, particularly those in financial trading and IoT (Internet of Things), produce mixed workloads with all of the following: (1) continuous stream pro- cessing, (2) online transaction processing (OLTP), and (3) online analytical processing (OLAP). These applications need to simulta- neously consume high-velocity streams to trigger real-time alerts, ingest them into a write-optimized transactional store, and perform analytics to derive deep insight quickly. Despite a flurry of data management solutions designed for one or two of these tasks, there is no single solution that is apt for all three.

SQL-on-Hadoop solutions (e.g., Hive, Impala/Kudu and Spark- SQL) use OLAP-style optimizations and columnar formats to run OLAP queries over massive volumes of static data. While apt for batch-processing, these systems are not designed as real-time oper- ational databases, as they lack the ability to mutate data with trans- actional consistency, to use indexing for efficient point accesses, or to handle high-concurrency and bursty workloads. For example, Wildfire [17] is capable of analytics and stream ingestion but lacks ACID transactions.

Hybrid transaction/analytical processing (HTAP) systems, such as MemSQL, support both OLTP and OLAP queries by storing data in dual formats (row and columns), but need to be used alongside an external streaming engine (e.g., Storm [34], Kafka, Confluent) to support stream processing.

Finally, there are numerous academic [20, 31, 33] and commer- cial [2, 8, 14, 34] solutions for stream and event processing. Al- though some stream processors provide some form of state man- agement or transactions (e.g., Samza [2], Liquid [23], S-Store [27]), they only allow simple queries on streams. However, more complex analytics, such as joining a stream with a large history table, need the same optimizations used in an OLAP engine [18, 26, 33]. For example, streams in IoT are continuously ingested and correlated with large historical data. Trill [19] supports diverse analytics on streams and columnar data, but lacks transactions. DataFlow [15] focuses on logical abstractions rather than a unified query engine.

Consequently, the demand for mixed workloads has resulted in several composite data architectures, exemplified in the “lambda” architecture, which requires multiple solutions to be stitched to- gether — a difficult exercise that is time consuming and expensive. 

In capital markets, for example, a real-time market surveillance application has to ingest trade streams at very high rates and detect abusive trading patterns (e.g., insider trading). This requires corre- lating large volumes of data by joining a stream with (1) historical records, (2) other streams, and (3) financial reference data which can change throughout the trading day. A triggered alert could in turn result in additional analytical queries, which will need to run on both ingested and historical data. In this scenario, trades arrive on a message bus (e.g., Tibco, IBM MQ, Kafka) and are processed by a stream processor (e.g., Storm) or a homegrown application, while the state is written to a key-value store (e.g., Cassandra) or an in-memory data grid (e.g., GemFire). This data is also stored in HDFS and analyzed periodically using a SQL-on-Hadoop or a traditional OLAP engine.

These heterogeneous workflows, although far too common in practice, have several drawbacks (D1–D4):

**D1. Increased complexity and total cost of ownership:** The use of incompatible and autonomous systems significantly increases their total cost of ownership. Developers have to master disparate APIs, data models, and tuning options for multiple products. Once in production, operational management is also a nightmare. To di- agnose the root cause of a problem, highly-paid experts spend hours to correlate error logs across different products.

**D2. Lower performance:** Performing analytics necessitates data movement between multiple non-colocated clusters, resulting in several network hops and multiple copies of data. Data may also need to be transformed when faced with incompatible data models (e.g., turning Cassandra’s ColumnFamilies into Storm’s domain objects).

**D3. Wasted resources:** Duplication of data across different products wastes network bandwidth (due to increased data shuf- fling), CPU cycles, and memory.

**D4. Consistency challenges:** The lack of a single data gover- nance model makes it harder to reason about consistency seman- tics. For instance, a lineage-based recovery in Spark Streaming may replay data from the last checkpoint and ingest it into an ex- ternal transactional store. With no common knowledge of lineage and the lack of distributed transactions across these two systems, ensuring exactly-once semantics is often left as an exercise for the application [4].

**Our goal** — We aim to offer streaming, transaction processing, and interactive analytics in a single cluster, with better performance, fewer resources, and far less complexity than today’s solutions.

**Challenges** — Realizing this goal involves overcoming significant challenges. The first challenge is the drastically different data struc- tures and query processing paradigms that are optimal for each type of workload. For example, column stores are optimal for analytics, transactions need write-optimized row-stores, and infinite streams are best handled by sketches and windowed data structures. Like- wise, while analytics thrive with batch-processing, transactions rely on point lookups/updates, and streaming engines use delta/incre- mental query processing. Marrying these conflicting mechanisms in a single system is challenging, as is abstracting away this hetero- geneity from programmers.

Another challenge is the difference in expectations of high avail- ability (HA) across different workloads. Scheduling and resource provisioning are also harder in a mixed workload of streaming jobs, long-running analytics, and short-lived transactions. Finally, achiev- ing interactive analytics becomes non-trivial when deriving insight requires joining a stream against massive historical data [7].

**Our approach** — Our approach is a seamless integration of Apache Spark, as a computational engine, with Apache GemFire, as an in-memory transactional store. By exploiting the complementary functionalities of these two open-source frameworks, and carefully accounting for their drastically different design philosophies, Snap- pyData is the first unified, scale-out database cluster capable of supporting all three types of workloads. SnappyData also relies on a novel probabilistic scheme to ensure interactive analytics in the face of high-velocity streams and massive volumes of stored data.

**Contributions** — We make the following contributions.

1. We discuss the challenges of marrying two breeds of distributed systems with drastically different design philosophies: a lineage- based system designed for high-throughput analytics (Spark) and a consensus-driven replication-based system designed for low- latency operations (GemFire) §2.
2. We introduce the first unified engine to support streaming, trans- actions, and analytics in a single cluster. We overcome the chal- lenges above by offering a unified API §4, utilizing a hybrid stor- age engine, sharing state across applications to minimize serial- ization §5, providing high-availability through low-latency fail- ure detection and decoupling applications from data servers §6.1, bypassing the scheduler to interleave fine-grained and long-running jobs §6.2, and ensuring transactional consistency §6.3.
3. Using a mixed benchmark, we show that SnappyData delivers 1.5–2 × higher throughput and 7–142 × speedup compared to to- day’s state-of-the-art solutions §7.

## 2.    OVERVIEW

### 2.1    Approach Overview

To support mixed workloads, SnappyData carefully fuses Apache Spark, as a computational engine, with Apache GemFire, as a trans- actional store.

Through a common set of abstractions, Spark allows program- mers to tackle a confluence of different paradigms (e.g., stream- ing, machine learning, SQL analytics). Spark’s core abstraction, a Resilient Distributed Dataset (RDD), provides fault tolerance by efficiently storing the lineage of all transformations instead of the data. The data itself is partitioned across nodes and if any partition is lost, it can be reconstructed using its lineage. The benefit of this approach is two-fold: avoiding replication over the network, and higher throughput by operating on data as a batch. While this ap- proach provides efficiency and fault tolerance, it also requires that an RDD be immutable. In other words, Spark is simply designed as a computational framework, and therefore (i) does not have its own storage engine and (ii) does not support mutability semantics^1^.

> ^1^Although IndexedRDD [6] offers an updatable key-value store [6], it does not support colocation for high-rate ingestions or distributed transactions. It is also unsuitable for HA, as it relies on disk-based checkpoints for fault tolerance.

On the other hand, Apache GemFire [1] (a.k.a. Geode) is one of the most widely adopted in-memory data grids in the industry^2^, which manages records in a partitioned row-oriented store with synchronous replication. It ensures consistency by integrating a dynamic group membership service and a distributed transaction service. GemFire allows for indexing and both fine-grained and batched data updates. Updates can be reliably enqueued and asyn- chronously written back out to an external database. In-memory data can also be persisted to disk using append-only logging with offline compaction for fast disk writes [1].

> ^2^GemFire is used by major airlines, travel portals, insurance firms, and 9 out of 10 investment banks on Wall Street [1].

**Best of two worlds** — To combine the best of both worlds, Snappy- Data seamlessly integrates Spark and GemFire runtimes, adopting Spark as the programming model with extensions to support mu- tability and HA (high availability) through GemFire’s replication and fine grained updates. This marriage, however, poses several non-trivial challenges.

### 2.2    Challenges of Marrying Spark & GemFire

Each Spark application runs as an independent set of processes (i.e., executor JVMs) on the cluster.  While immutable data can be cached and reused in these JVMs within a single application, sharing data across applications requires an external storage tier (e.g., HDFS). In contrast, our goal in SnappyData is to achieve an “always-on” operational design whereby clients can connect at will, and share data across any number of concurrent connections. The first challenge is thus to alter the life-cycle of Spark executors so that their JVMs are *long-lived* and *de-coupled from individual applications*. This is difficult because, unlike Spark which spins up executors on-demand (using Mesos or YARN) with resources sufficient only for the current job, we need to employ a static re- source allocation policy whereby the same resources are reused concurrently across several applications. Moreover, unlike Spark which assumes that all jobs are CPU-intensive and batch (or micro- batch), in a hybrid workload we do not know if an operation is a long-running and CPU-intensive job or a low-latency data access.

The second challenge is that in Spark a single driver orchestrates all the work done on the executors. Given the need for high con- currency in our hybrid workloads, this driver introduces (i) a single point of contention, and (ii) a barrier for HA. If the driver fails, the executors are shutdown, and any cached state has to be re-hydrated. Due to its batch-oriented design, Spark uses a block-based mem- ory manager and requires no synchronization primitives over these blocks. In contrast, GemFire is designed for fine-grained, highly concurrent and mutating operations. As such, GemFire uses a va- riety of concurrent data structures, such as distributed hashmaps, treemap indexes, and distributed locks for pessimistic transactions. SnappyData thus needs to (i) extend Spark to allow arbitrary point lookups, updates, and inserts on these complex structures, and (ii) extend GemFire’s distributed locking service to support modifica- tions of these structures from within Spark.

Spark RDDs are immutable while GemFire tables are not. Thus, Spark applications accessing GemFire tables as RDDs may expe- rience non-deterministic behavior. A naïve approach of creating a copy when the RDD is lazily materialized is too expensive and defeats the purpose of managing local states in Spark executors.

Finally, Spark’s growing community has zero tolerance for in- compatible forks. This means that, to retain Spark users, Snap- pyData cannot change Spark’s semantics or execution model for existing APIs (i.e., all changes in SnappyData must be extensions).

## 3.    ARCHITECTURE

Figure 1 depicts SnappyData’s core components (the original components from Spark and GemFire are highlighted).

SnappyData’s hybrid storage layer is primarily in-memory, and can manage data in row, column, or probabilistic stores. Snap- pyData’s column format is derived from Spark’s RDD implemen- tation.  SnappyData’s row-oriented tables extend GemFire’s ta- ble and thus support indexing, and fast reads/writes on indexed keys §5.1. In addition to these “exact” stores, SnappyData can also summarize data in *probabilistic* data structures, such as strati- fied samples and other forms of synopses. SnappyData’s query en- gine has built-in support for approximate query processing (AQP), which can exploit these probabilistic structures. This allows appli- cations to trade accuracy for interactive-speed analytics on streams or massive datasets §5.2.

SnappyData supports two programming models—SQL (by ex- tending SparkSQLdialect) and Spark’s API. Thus, one can perceive SnappyData as a SQL database that uses Spark’s API as its lan- guage for stored procedures. Stream processing in SnappyData is primarily through Spark Streaming, but it is modified to run *in-situ* with SnappyData’s store §4.

SQL queries are federated between Spark’s Catalyst and Gem- Fire’s OLTP engine. An initial query plan determines if the query is a low latency operation (e.g., a key-based lookup) or a high latency one (scans/aggregations). SnappyData avoids scheduling overheads for OLTP operations by immediately routing them to ap- propriate data partitions §6.2.

To support replica consistency, fast point updates, and instanta- neous detection of failure conditions in the cluster, SnappyData relies on GemFire’s P2P (peer-to-peer) cluster membership ser- vice [1]. Transactions follow a 2-phase commit protocol using GemFire’s Paxos implementation to ensure consensus and view consistency across the cluster.

nappyData as a SQL database that uses Spark’s API as its lan- guage for stored procedures. Stream processing in SnappyData is primarily through Spark Streaming, but it is modified to run *in-situ* with SnappyData’s store §4.

SQL queries are federated between Spark’s Catalyst and Gem- Fire’s OLTP engine. An initial query plan determines if the query is a low latency operation (e.g., a key-based lookup) or a high latency one (scans/aggregations). SnappyData avoids scheduling overheads for OLTP operations by immediately routing them to ap- propriate data partitions §6.2.

To support replica consistency, fast point updates, and instanta- neous detection of failure conditions in the cluster, SnappyData relies on GemFire’s P2P (peer-to-peer) cluster membership ser- vice [1]. Transactions follow a 2-phase commit protocol using GemFire’s Paxos implementation to ensure consensus and view consistency across the cluster.

## 4.    A UNIFIED API

Spark offers a rich procedural API for querying and transform- ing disparate data formats (e.g., JSON, Java Objects, CSV). Like- wise, to retain a consistent programming style, SnappyData offers its mutability functionalities as extensions of SparkSQL’s dialect and its DataFrame API. These extensions are backward compati- ble, i.e., applications that do not use them observe Spark’s original semantics.

A DataFrame in Spark is a distributed collection of data orga- nized into named columns. A DataFrame can be accessed from a SQLContext, which itself is obtained from a SparkContext (a SparkContext is a connection to Spark’s cluster). Likewise, much of SnappyData’s API is offered through SnappyContext, which is an extension of SQLContext. Listing 1 is an example of using SnappyContext.

Stream processing often involves maintaining counters or more complex multi-dimensional summaries. As a result, stream pro- cessors today are either used alongside a scale-out in-memory key- value store (e.g., Storm with Redisor Cassandra) or come with their own basic form of state management (e.g., Samza, Liquid [23]). These patterns are often implemented in the application code us- ing simple get/put APIs. While these solutions scale well, we find that users modify their search patterns and trigger rules quite of- ten. These modifications require expensive code changes and lead to brittle and hard-to-maintain applications.

In contrast, SQL-based stream processors offer a higher level abstraction to work with streams, but primarily depend on row- oriented stores (e.g., [5, 8, 27]) and are thus limited in supporting complex analytics. To support continuous queries with scans, ag- gregations, top-K queries, and joins with historical and reference data, some of the same optimizations found in OLAP engines must be incorporated in the streaming engine [26]. Thus, SnappyData extends Spark Streaming to allow declaring and querying streams in SQL. More importantly, SnappyData provides OLAP-style op- timizations to enable scalable stream analytics, including columnar formats, approximate query processing, and co-partitioning [9].

## 5.    HYBRID STORAGE

### 5.1    Row and Column Tables

Tables can be partitioned or replicated and are primarily man- aged in memory with one or more consistent replicas. The data can be managed in Java heap memory or off-heap. Partitioned tables are always partitioned horizontally across the cluster. For large clus- ters, we allow data servers to belong to one or more logical groups, called “server groups”. The storage format can be “row” (either partitioned or replicated tables) or “column” (only supported for partitioned tables) format. Row tables incur a higher in-memory footprint but are well suited to random updates and point lookups, especially with in-memory indexes. Column tables manage col- umn data in contiguous blocks and are compressed using dictio- nary, run-length, or bit encoding [36]. Listing 2 highlights some of SnappyData’s syntactic extensions to the using and options clauses of the create table statement.

We extend Spark’s column store to support mutability. Updat- ing row tables is trivial. When records are written to column ta- bles, they first arrive in a *delta row buffer* that is capable of high write rates and then age into a columnar form. The delta row buffer is merely a partitioned row table that uses the same partitioning strategy as its base column table. This buffer table is backed by a conflating queue that periodically empties itself as a new batch into the column table. Here, conflation means that consecutive up- dates to the same record result in only the final state getting trans- ferred to the column store. For example, inserted/updated records followed by deletes are removed from the queue. The delta row buffer itself uses copy-on-write semantics to ensure that concurrent application updates do not cause inconsistency [10]. SnappyData extends Spark’s Catalyst optimizer to merge the delta row buffer during query execution.

### 5.2    Probabilistic Store

Achieving interactive response time is challenging when running complex analytics on streams, e.g., joining a stream with a large table [30]. Even OLAP queries on stored datasets can take tens of seconds to complete if they require a distributed shuffling of records, or if hundreds of concurrent queries run in the cluster [13]. In such cases, SnappyData’s storage engine is capable of using probabilistic structures to dramatically reduce the volume of input data and provide approximate but extremely fast answers. Snappy- Data’s probabilistic structures include uniform samples, stratified samples, and sketches [22]. The novelty in SnappyData’s approach compared to previous AQP engines [40] is in the way that it creates and maintains these structures efficiently and in a distributed man- ner. Given these structures, SnappyData uses off-the-shelf error es- timation techniques [11, 41]. Thus, we only discuss SnappyData’s sample selection and maintenance strategies.

**Sample selection** — Unlike uniform samples, choosing which strat- ified samples to build is a non-trivial problem. The key question is which sets of columns to build a stratified sample on. Prior work has used skewness, popularity, and storage cost as the criteria for choosing column-sets [12, 13]. SnappyData extends these crite- ria as follows: for any declared or foreign-key join, the join key is included in a stratified sample in at least one of the participat- ing relations (tables or streams). However, SnappyData never in- cludes a table’s primary key in its stratified sample(s). Furthermore, we offer our open-source tool, called WorkloadMiner, which auto- matically analyzes past query logs and reports a rich set of statis- tics [3]. These statistics guide SnappyData’s users through the sample selection process. WorkloadMiner is integrated into Clif- fGuard. CliffGuard guarantees a robust physical design (e.g., set of samples), which remains optimal even if future queries deviate from past ones [28].

Once a set of samples is chosen, the challenge is how to update them, which is a key differentiator between SnappyData and pre- vious AQP systems that use stratified samples [12, 21, 39].

**Sample maintenance** — Previous AQP engines that use offline sampling update and maintain their samples periodically using a single scan of the entire data [29]. This strategy is not suitable for SnappyData with streams and mutable tables for two reasons. First, maintaining per-stratum statistics across different nodes in the cluster is a complex process. Second, updating a sample in a streaming fashion requires maintaining a reservoir [16, 35], which means the sample must either fit in memory or be evicted to disk. Keeping samples entirely in memory is impractical for infinite streams unless we perpetually decrease the sampling rate. Likewise, disk- based reservoirs are inefficient as they require retrieving and re- moving individual tuples from disk as new tuples are sampled.

To solve these problems, SnappyData always includes times- tamp as an additional column in every stratified sample. Uniform samples are treated as a special case with only one stratified col- umn, i.e., timestamp. As new tuples arrive in a stream, a new batch (in row format) is created for maintaining a sample of each ob- served value of the stratified columns. Whenever a batch size ex- ceeds a certain threshold (1M tuples by default), it is evicted and archived to disk (in a columnar format) and a new batch is started for that stratum.

Treating each micro-batch as an independent stratified sample has several benefits. First, this allows SnappyData to adaptively adjust the sampling rate for each micro-batch without the need for inter-node communications in the cluster. Second, once a micro- batch is completed, its tuples never need to be removed or replaced, and therefore they can be safely stored in a compressed columnar format and even archived to disk. Only the latest micro-batch needs to be in-memory and in row-format. Finally, each micro-batch can be routed to a single node, reducing the need for network shuffles.

### 5.3    State Sharing

SnappyData hosts GemFire’s tables in the executor nodes as ei- ther partitioned or replicated tables. When partitioned, the individ- ual buckets are presented as Spark RDD partitions and their access is therefore parallelized. This is similar to the way that any external data source is accessed in Spark, except that the common opera- tors are optimized in SnappyData. For example, by keeping each partition in columnar format, SnappyData avoids additional copy- ing and serialization and speeds up scan and aggregation operators. SnappyData can also colocate tables by exposing an appropriate partitioner to Spark (see Listing 2).

Native Spark applications can register any DataFrame as a tem- porary table. In addition to being visible to the Spark application, such a table is also registered in SnappyData’s catalog—a shared service that makes tables visible across Spark and GemFire. This allows remote clients connecting through ODBC/JDBC to run SQL queries on Spark’s temporary tables as well as tables in GemFire.

In streaming scenarios, the data can be sourced into any table from parent stream RDDs (DStream), which themselves could source events from an external queue, such as Kafka. To minimize shuf- fling, SnappyData tables can preserve the partitioning scheme used by their parent RDDs. For example, a Kafka queue listening on Telco CDRs (call detail records) can be partitioned on subscriberID so that Spark’s DStream and the SnappyData table ingesting these records will be partitioned on the same key.

from parent stream RDDs (DStream), which themselves could source events from an external queue, such as Kafka. To minimize shuf- fling, SnappyData tables can preserve the partitioning scheme used by their parent RDDs. For example, a Kafka queue listening on Telco CDRs (call detail records) can be partitioned on subscriberID so that Spark’s DStream and the SnappyData table ingesting these records will be partitioned on the same key.

### 5.4    Locality-Aware Partition Design

A major challenge in horizontally partitioned distributed databases is to restrict the number of nodes involved in order to minimize (i) shuffling during query execution and (ii) distributed locks [25, 38]. In addition to network costs, shuffling can also cause CPU bot- tlenecks by incurring excessive copying (between kernel and user space) and serialization costs [32]. To reduce the need for shuffling and distributed locks, our data model promotes two fundamental ideas:

1. **Co-partitioning with shared keys** — A common technique in data placement is to take the application’s access patterns into account. We pursue a similar strategy in SnappyData: since joins require a shared key, we co-partition related tables on the join key. SnappyData’s query engine can then optimize its query execution by localizing joins and pruning unnecessary partitions.
2. **Locality through replication** — Star schemas are quite preva- lent, wherein a few ever-growing fact tables are related to several dimension tables. Since dimension tables are relatively small and change less often, schema designers can ask SnappyData to repli- cate these tables. SnappyData particularly uses these replicated tables to optimize joins.

## 6.    HYBRID CLUSTER MANAGER

Spark applications run as independent processes in the cluster, coordinated by the application’s main program, called the driver program. Spark applications connect to cluster managers (YARN or Mesos) to acquire executor nodes. While Spark’s approach is ap- propriate for long-running tasks, as an operational database, Snap- pyData’s cluster manager must meet additional requirements, such as high concurrency, high availability, and consistency.

### 6.1    High Availability

To ensure high availability (HA), SnappyData needs to detect faults and be able to recover from them instantly.

**Failure detection** — Spark uses heartbeat communications with a central master process to determine the fate of the workers. Since Spark does not use a consensus-based mechanism for failure detec- tion, it risks shutting down the entire cluster due to master failures. However, as an always-on operational database, SnappyData needs to detect failures faster and more reliably. For faster detection, SnappyData relies on UDP neighbor ping and TCP ack timeout during normal data communications. To establish a new, consistent view of the cluster membership, SnappyData relies on GemFire’s weighted quorum-based detection algorithm [1]. Once GemFire establishes that a member has indeed failed, it ensures that a con- sistent view of the cluster is applied to all members, including the Spark master, driver, and data nodes.

**Failure recovery** — Recovery in Spark is based on logging the transformations used to build an RDD (i.e., its lineage) rather than the actual data. If a partition of an RDD is lost, Spark has sufficient information to recompute just that partition [37]. Spark can also  checkpoint RDDs to stable storage to shorten the lineage, thereby shortening the recovery time. The decision of when to checkpoint, however, is left to the user. GemFire, on the other hand, relies on replication for instantaneous recovery, but at the cost of lower throughput. SnappyData merges these recovery mechanisms as follows:

 

\1.  Fine-grained updates issued by transactions avoid the use of Spark’s lineage altogether, and instead use GemFire’s eager replication for fast recovery.

\2.  Batched and streaming micro-batch operations are still recovered by RDD’s lineage, but instead of HDFS, SnappyData writes their checkpoints to GemFire’s in-memory storage, which itself relies on a fast P2P (peer-to-peer) replication for recovery. Also, Snap- pyData’s intimate knowledge of the load on the storage layer, the data size, and the cost of recomputing a lost partition, allows for automating the choice of checkpoint intervals based on an appli- cation’s tolerance for recovery time.

### 6.2    Hybrid Scheduler and Provisioning

Thousands of concurrent clients can simultaneously connect to a SnappyData cluster. To support this degree of concurrency, Snap- pyData categorizes incoming requests as low and high latency op- erations. By default, SnappyData treats a job as a low-latency operation unless it accesses a columnar table. However, applica- tions can also explicitly label their latency sensitivity. Snappy- Data allows low-latency operations to bypass Spark’s scheduler and directly operate on the data. High-latency operations are passed through Spark’s fair scheduler. For low-latency operations, Snap- pyData attempts to re-use their executors to maximize their data locality (in-process). For high-latency jobs, SnappyData dynam- ically expands their compute resources while retaining the nodes caching their data.

### 6.3    Consistency Model

SnappyData relies on GemFire for its consistency model. Gem- Fire supports “read committed” and “repeatable read” transaction isolation levels using a variant of the Paxos algorithm [24]. Trans- actions detect write-write conflicts and assume that writers rarely conflict. When write locks cannot be obtained, transactions abort without blocking [1].

SnappyData extends Spark’s SparkContext and SQLContext to add mutability semantics. SnappyData gives each SQL connec- tion its own SQLContext in Spark to allow applications to start, commit, and abort transactions.

While any RDD obtained by a Spark program observes a consis- tent view of the database, multiple programs can observe different views when transactions interleave. An MVCC mechanism (based on GemFire’s internal row versions) can be used to deliver a single snapshot view to the entire application.

In streaming applications, upon faults, Spark recovers lost RDDs from their lineage. This means that some subset of the data will be replayed. To cope with such cases, SnappyData ensures the exactly-once semantics at the storage layer so that multiple write attempts are idempotent, hence relieving developers of having to ensure this in their own applications. SnappyData achieves this goal by placing the entire flow as a single transactional unit of work, whereby the source (e.g., a Kafka queue) is acknowledged only when the micro-batch is entirely consumed and the applica- tion state is successfully updated. This ensures automatic rollback of incomplete transactions.

## 7.    EXPERIMENTS

## 8.    CONCLUSION

We proposed a unified platform for real time operational analyt- ics, SnappyData, to support OLTP, OLAP, and stream analytics in a single integrated solution. Our approach is a deep integration of a computational engine for high throughput analytics (Spark) with a scale-out in-memory transactional store (GemFire). SnappyData extends SparkSQL and Spark Streaming APIs with mutability se- mantics, and offers various optimizations to enable colocated pro- cessing of streams and stored datasets. We also made the case for integrating approximate query processing into this platform for en- abling real-time operational analytics over large (stored or stream- ing) data. Hence, we believe that our platform significantly lowers the TCO for mixed workloads compared to disparate products that are managed, deployed, and monitored separately.
