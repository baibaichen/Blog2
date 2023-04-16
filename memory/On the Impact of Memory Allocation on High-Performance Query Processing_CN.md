# 论内存分配对高性能查询处理的影响

1. Clickhouse [Using jemalloc instead of tcmalloc](https://github.com/ClickHouse/ClickHouse/pull/2773).
2. Doris [[enhancement\](memory) jemalloc performance optimization and compatibility with MemTracker](https://github.com/apache/doris/pull/12496)
3. Duckdb [OOM when reading Parquet file](https://github.com/duckdb/duckdb/issues/3969)

   1. [jemalloc "extension" for Linux](https://github.com/duckdb/duckdb/pull/4971)

**摘要**
有点令人惊讶的是，分析查询引擎的行为主要受所用**动态内存分配器**的影响。内存分配器在很大程度上影响着其他进程的**性能**、可扩展性、**内存效率**和**内存公平性**。本文首次对内存分配对高性能查询引擎的影响进行了全面的实验分析。我们测试了五个最先进的动态内存分配器，并讨论了它们在我们的 DBMS 中的优缺点。正确的分配器可以在 4 路英特尔至强服务器上将 TPC-DS (SF 100) 的性能提高 2.7 倍。

## 1. 引言

现代高性能查询引擎比传统数据库系统快几个数量级。因此，迄今为止对性能不重要的组件可能会成为性能瓶颈。其中一个组件是内存分配。大多数现代查询引擎都是高度并行的，并且严重依赖临时哈希表进行查询处理，这会导致大量不同大小的短期内存分配。因此，内存分配器需要具有可扩展性，并且能够同时处理无数个中小型分配以及几个大型内存分配。正如我们在本文中展示的那样，**内存分配已成为影响整体查询处理性能的一个重要因素**。

新的硬件趋势加剧了分配问题。随着多核和众核服务器架构的发展，多达 100 个通用核的服务器架构对内存分配策略提出了新的挑战。由于纯计算能力的增加，可以进行更多的主动查询。此外，多线程数据结构实现导致密集和同时访问模式。**由于大多数多节点机器依赖于非统一内存访问 (NUMA) 模型，因此从远程节点请求内存特别昂贵**。

因此，动态内存分配器应该实现以下目标：

- **可扩展性**：减少多线程分配的开销。
- **性能**：最小化 `malloc` 和 `free` 的开销。
- **内存公平性**：将释放的内存还给操作系统。
- **内存效率**：避免内存碎片。

本文首次对现代数据库系统中的内存分配问题进行了全面的研究。我们评估了各种满足上述要求的**动态内存分配器**。尽管内存分配位于查询处理的关键路径上，对于内存数据库系统中不同的动态内存分配器，还没有进行过实证研究（Appuswamy等人，[2017](http://www.vldb.org/pvldb/vol11/p121-appuswamy.pdf)）。

> ![](https://media.arxiv-vanity.com/render-output/6472788/x1.png)
> *Figure 1*. **Execution of a given query set on TPC-DS (SF 100) with different allocators**.

图 [1](https://www.arxiv-vanity.com/papers/1905.01135/#S1.F1) 显示了不同分配策略对比例因子为 100 的 TPC-DS 的影响。在 4 路英特尔至强服务器上，用我们的多线程数据库系统测量内存消耗和执行时间 。在此实验中，我们的 DBMS 使用所有可用内核顺序执行查询集。即使是这种相对简单的工作负载也已经导致显着的性能和内存使用差异。使用 `jemalloc` 的数据库与使用 glibc 2.23 标准 `malloc` 的数据库相比，可以将执行时间缩短到原来的$\frac{1}{2}$。另一方面，`jemalloc` 内存消耗最高，执行完查询后不会直接释放内存。虽然 `TCMalloc` 的常驻内存消耗看起来很高，但它已经将内存缓慢地返回给操作系统。因此，分配策略对于内存数据库系统的性能和内存消耗行为至关重要。

本文的其余部分结构如下：在第 [2](https://www.arxiv-vanity.com/papers/1905.01135/#S2) 节 中讨论了相关工作之后，我们将在 [3](https://www.arxiv-vanity.com/papers/1905.01135/#S3) 节中描述所使用的分配器及其最重要的设计细节。第 [4](https://www.arxiv-vanity.com/papers/1905.01135/#S4) 节重点介绍了我们的 DBMS 的重要属性，并根据其分配模式分析了执行的工作负载。我们的综合实验评估第 [5](https://www.arxiv-vanity.com/papers/1905.01135/#S5) 节。第 [6](https://www.arxiv-vanity.com/papers/1905.01135/#S6) 节总结了我们的发现。

## 2. 相关工作

尽管内存分配是主要的性能驱动因素，但还没人对**内存分配对内存数据库系统的影响**进行过实证研究。费雷拉等人 （Ferreira 等人，[2011](https://www.arxiv-vanity.com/papers/1905.01135/#bib.bib8)）分析了各种多线程工作负载下的动态内存分配器。但是，该研究最多只考虑了 4 个核。因此，很难预测当前众核系统的可扩展性。

内存中 DBMS 和分析查询处理引擎，例如，HyPer [[2011](http://www.cs.brown.edu/courses/cs227/papers/olap/hyper.pdf)]）、SAP HANA [[2017](https://dx.doi.org/10.1007/s13222-015-0185-2)]、 Quickstep [[2018](https://www. arxiv-vanity.com/papers/1905.01135/#bib.bib22)] 都是为了尽可能利用众核来加速查询处理。由于这些系统依赖于大量分配内存的运算符（例如，哈希连接、聚合等），因此需要对最新分配器的可扩展性进行修改的实验分析。内存中哈希连接和聚合可以通过许多不同的方式实现，这会严重影响分配模式（Balkesen 等人 [2013](http://people.inf.ethz.ch/jteubner/publications/parallel-joins/parallel-joins.pdf)；Blanas  等人 [2011](http://www.cs.wisc.edu/~jignesh/publ/hashjoin.pdf)；Zhang 等人 [2019](https: //www.arxiv-vanity.com/papers/1905.01135/#bib.bib25); Leis 等人 [2014](https://www.arxiv-vanity.com/papers/1905.01135/#bib.bib16) )。

一些在线事务处理（OLTP）系统试图通过以块的形式管理其分配的内存，来减少分配开销，以提高小型事务查询的性能（Tu et al., [2013](https://dl.acm.org/ft_gateway.cfm?id=2522713&type=pdf); Stoica and Ailamaki, [2013](http://www.inf.ufpr.br/carmem/oficinaBD/artigos2s2013/a7-stoica.pdf); Durner and Neumann, [2019](https://www.arxiv-vanity.com/papers/1905.01135/#bib.bib5)）。

但是，大多数数据库系统都处理事务查询和分析查询。因此，还需要考虑分析查询的各种内存分配模式。自定义**分块内存管理器**有助于减少小内存分配的内存调用，但较大的分块大小以牺牲了内存效率的代价，提高了性能。因此，我们的数据库系统使用<u>**事务本地块**</u>来加速小内存的分配。尽管有这些优化，分配仍然是一个性能问题。因此，分配器的选择对于最大化吞吐量至关重要。

随着非易失性存储器 (NVM) 的发展，引入了新的分配要求。**首先，碎片整理和安全释放未使用的内存是很重要的，因为所有更改都是持久的**。已经为这些新颖的持久内存系统。开发了新的动态内存分配器并进行了实验研究（Oukid 等人，[2017](https://dl.acm.org/ft_gateway.cfm?id=3137629&type=pdf)）。但是，由于内存限制较少，常规分配器在大多数工作负载中的性能优于这些 NVM 分配器。

## 3. 内存分配器

在本节中，我们将讨论用于实验研究的五种不同分配策略。我们根据内存分配和释放来解释这些算法的基本属性。经过测试的最先进的分配器可作为 Ubuntu 18.10 软件包使用。只有 glibc malloc 2.23 实现是以前的 Ubuntu 软件包的一部分。尽管如此，该版本仍在许多当前发行版中使用，例如稳定的 Debian 发行版。

**内存分配与操作系统 (OS) 密切相关**。物理内存和虚拟内存之间的映射由内核处理。分配器需要从操作系统请求虚拟内存。传统上，用户程序通过调用分配器的 malloc 方法来请求内存。分配器要么有未使用且合适的可用内存，要么需要从操作系统请求新内存。例如，Linux 内核有多个用于请求和释放内存的 API。`brk` 调用可以通过更改程序中断来增加和减少分配给数据段的内存量。`mmap` 将文件映射到内存并实现请求分页，以便仅在使用时分配物理页面。使用匿名映射，也可以在主内存中分配不受真实文件支持的虚拟内存。内存分配过程如下图所示。

![](https://media.arxiv-vanity.com/render-output/6472788/x2.png)

除了通过上述调用直接释放内存外，内存分配器还可以选择使用 `MADV_FREE` 释放内存（自 Linux Kernel 4.5 起）。`MADV_FREE` 表示允许内核重用该内存区域。但分配器仍然可以访问虚拟内存地址，接收先前的物理页面，要么内核提供新的归零页面。只有当内核重新分配物理页面时，新的页面才需要归零。因此，`MADV_FREE` 减少了需要归零的页面数量，因为旧页面可能会被同一进程重用。

### 3.1 MALLOC 2.23

The glibc malloc implementation is derived from ptmalloc2 which originated from dlmalloc (Library, [2018](https://sourceware.org/glibc/wiki/MallocInternals)). It uses chunks of various sizes that exist within a larger memory region known as the heap. malloc uses multiple heaps that grow within their address space.

For handling multi-threaded applications, malloc uses arenas that consist of multiple heaps. At program start the main arena is created and additional arenas are chained with previous arena pointers. The arena management is stored within the main heap of that arena. Additional arenas are created with mmap and are limited to eight times the number of CPU cores. For every allocation, an arena-wide mutex needs to be acquired. Within arenas free chunks are tracked with free-lists. Only if the top chunk (adjacent unmapped memory) is large enough, memory will be returned to the OS.

![](https://media.arxiv-vanity.com/render-output/6472788/x3.png)

malloc is aware of multiple threads but no further multi-threaded optimizations, such as thread locality or NUMA awareness, is integrated. It assumes that the kernel handles these issues.

### 3.2 MALLOC 2.28

A thread-local cache (tcache) was introduced with glibc v2.26 (Library, [2017](https://sourceware.org/ml/libc-alpha/2017-08/msg00010.html)). This cache requires no locks and is therefore a fast path to allocate and free memory. If there is a suitable chunk in the tcache for allocation, it is directly returned to the caller bypassing the rest of the malloc routine. The deletion of a chunk works similarly. If the tcache has a free slot, the chunk is stored within it instead of immediately freeing it.

### 3.3 JEMALLOC 5.1

![](https://media.arxiv-vanity.com/render-output/6472788/x4.png)

jemalloc 最初是为 FreeBSD 开发的可扩展和低碎片标准分配器。今天，jemalloc 用于各种应用程序，例如 Facebook、Cassandra 和 Android。它区分三种大小类别 - 小 (<16/<u>==textKB==</u>)、大 (<4MB) 和巨大。这些类别进一步分为不同的尺寸等级。它使用 **Arena** 作为完全独立的分配器。Arenas 由分配 1024 页 (4MB) 的倍数的块组成。jemalloc 为**大分配**实现低地址重用以减少碎片。低地址重用，基本上是扫描第一个足够大的空闲内存区域，与更昂贵的策略（如最佳匹配）具有相似的理论属性。jemalloc 尝试通过使用 `MADV_FREE` 释放页面而不是取消映射来减少页面归零。最重要的是，jemalloc 使用**时钟**（自 v4.1 起）**基于衰减**清除脏页，这导致最近使用过的脏页的高重用率。因此，如果不再请求，未使用的内存将被清除，以实现内存公平（Evans, [2015](https://dl.acm.org/citation.cfm?id=2742807), [2018](https://github.com/jemalloc/jemalloc/blob/dev/ChangeLog)）。

### 3.4 TBBMALLOC 2017 U7

Intel’s Threading Building Blocks (TBB) allocator is based on the scalable memory allocator McRT (Hudson et al., [2006](https://dx.doi.org/10.1145/1133956.1133967)). It differentiates between small, quite large, and huge objects. Huge objects (≥4MB) are directly allocated and freed from the OS. Small and large objects are organized in thread-local heaps with chunks stored in memory blocks.

Memory blocks are memory mapped regions that are multiples of the requested object size class and inserted into the global heap of free blocks. Freed memory blocks are stored within a global heap of abandoned blocks. If a thread-local heap needs additional memory blocks, it requests the memory from one of the global heaps. Memory regions are unmapped during coalescing of freed memory allocations if no block of the region is used anymore (Kukanov and Voss, [2007](https://dx.doi.org/10.1535/itj.1104.05); Intel, [2017](https://github.com/01org/tbb/tree/tbb_2017)).

### 3.5 TCMALLOC 2.5

TCMalloc 是 Google 的 gperftools 的一部分。每个线程都有一个本地缓存，用于满足小的分配（≤256KB）。大对象使用 8KB 页分配在中央堆中。

TCMalloc 为小对象使用**大小不同的可分配类**，并将每个<u>大小类的单链表</u>存储在**线程本地缓存**。中型分配 (≤1MB) 使用多个页面并由中央堆处理。如果没有可用空间，则将中型分配视为大型分配。对于较大的分配，空闲内存页的范围在红黑树中跟踪。新的分配只是在树中搜索**容量最适配的页面（最小）**。如果未找到页面，则从内核分配内存（Google，[2007](https://gperftools.github.io/gperftools/tcmalloc.html)）。

在 `MADV_FREE` 调用的帮助下释放未使用的内存。如果线程本地缓存超过最大大小，则垃圾收集**小分配**。自从启用积极的**取消提交**（decommit ）选项（从 2.3 版开始）以减少内存碎片后，立即释放页面（Google, [2017](https://github.com/gperftools/gperftools/tree/gperftools-2.5.93)）。

## 4. DBMS AND WORKLOAD ANALYSIS

决策支持系统依赖于分析查询 (OLAP)，例如通过连接不同的关系从庞大的数据集中收集信息。在内存查询引擎中，通常将 Join 物理安排为 Hash Join，从而导致大量较小的分配。在下文中，我们使用一个使用预聚合哈希表的数据库系统来执行多线程分组和 Join（Leis et al., [2014](https://www.arxiv-vanity.com/papers/1905.01135 /#bib.bib16))。我们的 DBMS 有一个**自定义事务本地分块分配器**，可以加速小于 32KB 的小分配。我们将小分配存储在中等大小的内存块中。由于只有小的分配存储在块中，因此这些小对象块的内存效率足迹是微不足道的。此外，元组具体化所需的内存以块的形式获取。这些块随着更多元组的具体化而增长。因此，我们已经在保持内存效率的同时显着降低了分配器的压力。

TPC-H 和 TPC-DS 基准测试旨在标准化常见的决策支持工作负载（Nambiar 和 Poess，[2006](https://www.arxiv-vanity.com/papers/1905.01135/#bib.bib20)）。由于 TPC-DS 包含比 TPC-H 更大的工作量和更复杂的查询，我们在下文中重点介绍 TPC-DS。因此，我们预计看到更加多样化和更具挑战性的分配模式。TPC-DS 描述了具有不同销售渠道（例如实体店和网络销售）的零售产品供应商。

下面，我们统计分析 TPC-DS 执行所有查询（没有使用 Roll Up 和窗口函数）的分配模式。请注意，具体的分配模式取决于所讨论的 Join 和分组运算符的实现选择。

| ![](https://media.arxiv-vanity.com/render-output/6472788/x5.png) | ![](https://media.arxiv-vanity.com/render-output/6472788/x6.png) |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
*Figure 2.* *Allocations in TPC-DS (SF 100, serial execution).* 

图 [2](https://www.arxiv-vanity.com/papers/1905.01135/#S4.F2) 显示了我们系统中比例因子为 100 的 TPC-DS 的分配分布。最常见的分配范围是 32KB 到 512KB。需要更大的内存区域来创建哈希表的桶数组。使用<u>前面提到的分块分配器</u>来物化元组，需要大量的中等大小的分配。

此外，我们衡量哪些运算符需要最多的内存分配。两个主要的使用者是分组和 join 操作符。在 TPC-DS (SF 100) 上顺序执行查询时，每个操作符的分配百分比如下表所示：

|              | Group By | Join  | Set  | Temp | Other |
| ------------ | -------- | ----- | ---- | ---- | ----- |
| **By Size**  | 61.2%    | 25.7% | 4.3% | 8.4% | 0.4%  |
| **By Count** | 77.9%    | 11.7% | 8.5% | 1.8% | 0.1%  |

为了模拟真实的工作负载，我们使用指数分布的工作负载来确定查询到达时间。

我们从指数分布中取样以计算两个事件之间的时间。一个独立的常数平均率λ定义了分布的等待时间。与均匀分布的分配模式相比，并发活动事务的数量是不同的。因此，创建了一个更加多样化和复杂的分配模式。事件发生的预期时间间隔值为1/λ，方差为1/λ^2^。TPC-DS执行的查询均匀分布在启动事件中。因此，我们能够在相同的实际工作负载上测试所有分配器。

==我们从指数分布中抽样来计算两个事件之间的时间。一个独立的恒定平均速率 λ 定义了分布的等待时间。与均匀分布的分配模式相比，并发活动事务的数量各不相同。因此，创建了更加多样化和复杂的分配模式。事件发生在 1/λ 的预期时间间隔值和 1/λ^2^ 的方差内。TPC-DS 执行的查询均匀分布在启动事件中。因此，我们能够在相同的真实世界工作负载上测试所有分配器==。

我们的内存查询引擎最多允许同时激活 10 个事务。如果查询的事务超过 10 个，DBMS 的调度程序延迟事务 ，直到活动事务计数减少。

## 5. EVALUATION

In this section, we evaluate the five allocators on three hardware architectures with different workloads. We show that the approaches have significant performance and scalability differences. Additionally, we compare the allocator implementations according to their memory consumption and release strategies which shows memory efficiency and memory fairness to other processes.

We test the allocators on a 4-socket Intel Xeon E7-4870 server (60 cores) with 1 TB of main memory, an AMD Threadripper 1950X (16 cores) with 64 GB main memory (32 GB connected to each die region), and a single-die Intel Core i9-7900X (10 cores) server with 128 GB main memory. All three systems support 2-way hyperthreading. These three different architectures are used to analyze the behavior in terms of the allocators’ ability to scale on complex multi-socket NUMA systems.

This section begins with a detailed analysis of a realistic workload on the 4-socket server. We continue our evaluation by scheduling a reduced and increased number of transactions to test the allocators’ performance in varying stress scenarios. An experimental analysis on the different architectures gives insights on the scalability of the five malloc implementations. An evaluation of the memory consumption and the memory fairness to other processes concludes this section.

### 5.1.MEMORY CONSUMPTION AND QUERY LATENCY

![](https://media.arxiv-vanity.com/render-output/6472788/x7.png)

*Figure 3.* *Memory consumption over time (4-socket Xeon, λ=1.25 q/s, SF 100).*

The first experiment measures an exponentially distributed workload to simulate a realistic query arrival pattern on the 4-socket Intel Xeon server. Figure [3](https://www.arxiv-vanity.com/papers/1905.01135/#S5.F3) shows the memory consumption over time for TCP-DS (SF 100) and a constant query arrival rate of λ=1.25 q/s. Although the same workload is executed, very different memory consumption patterns are measured. TBBmalloc and jemalloc release most of their memory after query execution. Both malloc implementations hold a minimum level of memory which increases over time. TCMalloc releases its memory accurately with MADV_FREE which is not visible by tracking the system provided resident memory of the database process. Due to huge performance degradations for tracking the lazy freeing of memory, we show the described release behavior of TCMalloc in Section [5.4](https://www.arxiv-vanity.com/papers/1905.01135/#S5.SS4) separately. However, the overall performance is reduced due to an increased number of kernel calls.

![](https://media.arxiv-vanity.com/render-output/6472788/x8.png)

For an in-depth performance analysis, the query and wait latencies of the individual queries are visualized in Figure [4](https://www.arxiv-vanity.com/papers/1905.01135/#S5.F4). Although the overall runtime is similar between different allocators, the individual query statistics show that only jemalloc has minor wait latencies. TBBmalloc and jemalloc are mostly bound by the actual execution of the query. On the contrary, both glibc malloc implementations and TCMalloc are dominated by the wait latencies. Thus, the later allocators cannot process the queries fast enough to prevent query congestion. Query congestion results from the bound number (10) of concurrently scheduled transactions that our scheduler allows to be executed simultaneously.

| Allocator   |     Local |     Remote |      Total | Page Fault |
| :---------- | --------: | ---------: | ---------: | ---------: |
| malloc 2.28 | 63B, 100% | 172B, 100% | 236B, 100% |  41M, 100% |
| jemalloc    |      120% |        97% |       103% |       400% |
| TBBmalloc   |      121% |        97% |       103% |       516% |
| TCMalloc    |      106% |       105% |       104% |       153% |
| malloc 2.23 |      103% |       100% |       101% |       139% |

Table 1. NUMA-local and NUMA-remote DRAM accesses and OS page faults (4-socket Xeon, λ=1.25 q/s, SF 100).

Because of these huge performance differences, we measure NUMA relevant properties to highlight advantages and disadvantages of the algorithms. Table [1](https://www.arxiv-vanity.com/papers/1905.01135/#S5.T1) shows page faults, local and remote DRAM accesses. All measurements are normalized to the current standard glibc malloc 2.28 implementation for an easier comparison. The two fastest allocators have more local DRAM accesses and significantly more page faults, but have a reduced number of remote accesses. Note that the system requires more remote DRAM accesses due to NUMA-interleaved memory allocations of the TPC-DS base relations. Thus, the highly increased number of local accesses change the overall number of accesses only slightly. Minor page faults are not crucially critical since both jemalloc and TBBmalloc release and acquire their pages frequently. Consequently, remote accesses for query processing are the major performance indicator. Because TCMalloc reuses MADV_FREE pages, the number of minor page faults remains small.

![img](https://media.arxiv-vanity.com/render-output/6472788/x9.png)
Figure 5. Query latency distributions for different query rates (4-socket Xeon, SF 100).

### 5.2.PERFORMANCE WITH VARYING STRESS LEVELS

In the previous workload, only two allocators were able to efficiently handle the incoming queries. This section evaluates the effects for a varying constant rate λ. We analyze two additional workloads that use the rates λ=0.63 and λ=2.5 queries per second. Thus, we respectively increase and decrease the average waiting time before a new query is scheduled by a factor of 2.

Figure [5](https://www.arxiv-vanity.com/papers/1905.01135/#S5.F5) shows the query latencies of the three workloads. The results for the reduced and increased waiting times confirm the previous observations. The allocators have the same respective latency order in all three experiments. jemalloc performs best again for all workloads, followed by TBBmalloc.

All query latencies are dominated by the wait latencies in the λ=2.5 workload due to frequent congestions. With an increased waiting time (λ=0.63) between queries, the glibc malloc 2.28 implementation is able to reduce the median latency to a similar level as TBBmalloc. However, the query latencies within the third quantile vary vastly. TCMalloc and malloc 2.23 are still not able to process the queries without introducing long waiting periods.

### 5.3.SCALABILITY

After analyzing the allocators’ perfromance on the 4-socket Intel Xeon architecture, this section focuses on the scalability of the five dynamic memory allocators. Therefore, we execute an exponentially distributed workload with TPC-DS (SF 10) on the NUMA-scale 60 core Intel Xeon server, the 16 core AMD Threadripper (two die regions), and the single-socket 10 core Intel Skylake X.

Figure [6](https://www.arxiv-vanity.com/papers/1905.01135/#S5.F6) shows the memory consumption during the workload execution. Since the AMD Threadripper has a very similar memory consumption pattern to the Intel Skylake X, we only show the 4-socket Intel Xeon and the single-socket Intel Skylake. Most notable are the differences of both glibc malloc implementations. These two allocators have a very long initialization phase on the 4-socket system, but are able to allocate their initial memory as fast as the other ones on the single-socket system. Due to more cores and the resulting different access pattern, the decay-based deallocation pattern of jemalloc differs slightly in the beginning. However, jemalloc’s decay-based purging reduces the memory consumption on both architectures considerably. TCMalloc cannot process all queries in the same time frame as the other allocators on the 4-socket system whereas it finishes at the same time on Skylake.


![img](https://media.arxiv-vanity.com/render-output/6472788/x10.png)Figure 6. Memory consumption over time (λ=6 q/s, SF 10).

![img](https://media.arxiv-vanity.com/render-output/6472788/x11.png)Figure 7. Query latencies (λ=6 q/s, SF 10).

Especially the query latencies differ vastly between the architectures. In Figure [7](https://www.arxiv-vanity.com/papers/1905.01135/#S5.F7), we show the latencies for the λ=6 q/s workload. The more cores are utilized, the larger are the latency differences between the allocators. On the single-socket Skylake X, all the allocators have very similar performance. Besides having more cores, AMD’s Threadripper uses two memory regions which requires a more advanced placement strategy to obtain fast accesses. In particular, TCMalloc and malloc 2.23 without a thread-local cache have a reduced performance. The latency variances are reduced on the Threadripper but the overall latencies are worse in comparison to the Skylake architecture.

Yet, the most interesting behavior is introduced by the multi-socket Intel Xeon. It has both the best and worst overall query performance. jemalloc and TBBmalloc execute the queries with the overall lowest latencies and smallest variance. On the other hand, TCMalloc is worse by more than 10x in comparison to any other allocator. Both glibc implementations have a similar median performance but incur high variance such that a reliable query time prediction is impossible.

The experiments show that both jemalloc and TBBmalloc are able to scale to large systems with many cores. TCMalloc, on the other hand, has significant performance loss on larger servers.

To validate our findings, we evaluate a subset of the queries on MonetDB 11.31.13 (Idreos et al., [2012](https://www.arxiv-vanity.com/papers/1905.01135/#bib.bib12)). We observe a performance boost by using jemalloc on MonetDB; however, the differences are smaller because our DBMS parallelizes better and thus utilizes more cores.

### 5.4.MEMORY FAIRNESS

|             | peak total | average total |           |          |
| :---------- | :--------: | :-----------: | :-------: | :------: |
| Allocator   | requested  |   measured1   | requested | measured |
| TCMalloc    |  55.7 GB   |    58.1 GB    |  17.8 GB  | 53.7 GB  |
| malloc 2.23 |  61.4 GB   |    61.0 GB    |  26.2 GB  | 41.3 GB  |
| malloc 2.28 |  61.5 GB   |    62.6 GB    |  20.2 GB  | 42.5 GB  |
| TBBmalloc   |  55.7 GB   |    55.7 GB    |  15.9 GB  | 27.9 GB  |
| jemalloc    |  58.6 GB   |    59.4 GB    |  11.1 GB  | 24.7 GB  |

Table 2. Memory usage (4-socket Xeon, λ=1.25 q/s, SF 100).

Many DBMS run alongside other processes on a single server. Therefore, it is necessary that the query engines are fair to other processes. In particular, the memory consumption and the memory release pattern are good indicators of the allocators’ memory fairness.

Our DBMS is able to track the allocated memory regions with almost no overhead. Hence, we can compare the measured process memory consumption with the requested one. The used memory differs between the allocators due to the performance and scalability properties although we execute the same set of queries. Table [2](https://www.arxiv-vanity.com/papers/1905.01135/#S5.T2) shows the peak and average memory consumption for the λ=1.25 q/s workload (SF 100) on the 4-socket Intel Xeon. The peak memory consumption is similar for all tested allocators. On the contrary, the average consumption is highly dependant on the used allocator. Both glibc malloc implementations demand a large amount of average memory. jemalloc requires less average memory than TBBmalloc. However, the DBMS requested average memory is also higher for the allocators with increased memory usage. Although the consumption of TCMalloc seems to be higher, it actually uses less memory than the other allocators. This results from the direct memory release with MADV_FREE. The tracking of MADV_FREE calls on the 4-socket Intel Xeon is very expensive and would introduce many anomalies for both performance and memory consumption. Therefore, we analyze the madvise behavior on the single-socket Skylake X that is only affected slightly by the MADV_FREE tracking. The memory consumption with the λ=6 q/s workload (SF 10) is shown in Figure [8](https://www.arxiv-vanity.com/papers/1905.01135/#S5.F8). The only two allocators that use MADV_FREE to release memory are jemalloc and TCMalloc. The measured average memory curve of TCMalloc follows the DBMS required curve almost perfectly. jemalloc has a 15% reduced consumption if the MADV_FREE pages are subtracted from the memory consumption.

![img](https://media.arxiv-vanity.com/render-output/6472788/x12.png)
Figure 8. Memory consumption over time with subtracted MADV_FREE pages (λ=6 q/s, SF 10).

## 6.CONCLUSIONS

In this work, we provided a thorough experimental analysis and discussion on the impact of dynamic memory allocators for high-performance query processing. We highlighted the strength and weaknesses of the different state-of-the-art allocators according to scalability, performance, memory efficiency, and fairness to other processes. For our allocation pattern, which is probably not unlike to that of most high-performance query engines, we can summarize our findings as follows:

|             | scalable | fast | mem. fair | mem. efficient |
| :---------- | :------: | :--: | :-------: | :------------: |
| TCMalloc    |    −−    |  ∼   |    ++     |       +        |
| malloc 2.23 |    −     |  ∼   |     +     |       ∼        |
| malloc 2.28 |    ∼     |  +   |     −     |       ∼        |
| TBBmalloc   |    +     |  ∼   |    ++     |       +        |
| jemalloc    |    ++    |  +   |     +     |       +        |

As a result of this work, we use jemalloc as the standard allocator for our DBMS.

This project has received funding from the European Research Council (ERC) under the European Union’s Horizon 2020 research and innovation programme (grant agreement No 725286). 

## REFERENCES

1. Raja Appuswamy et al. (2017) [Raja Appuswamy, Angelos Anadiotis, Danica Porobic, Mustafa Iman, and Anastasia Ailamaki. 2017. Analyzing the Impact of System Architecture on the Scalability of OLTP Engines for High-Contention Workloads. *PVLDB* 11, 2 (2017), 121–134.](http://www.vldb.org/pvldb/vol11/p121-appuswamy.pdf)
2. Balkesen et al. (2013) [Cagri Balkesen, Jens Teubner, Gustavo Alonso, and M. Tamer Özsu. 2013. Main-memory hash joins on multi-core CPUs: Tuning to the underlying hardware. In *ICDE*. 362–373.](http://people.inf.ethz.ch/jteubner/publications/parallel-joins/parallel-joins.pdf)
3. Blanas et al. (2011) [Spyros Blanas, Yinan Li, and Jignesh M. Patel. 2011. Design and evaluation of main memory hash join algorithms for multi-core CPUs. In *SIGMOD*. 37–48.](http://www.cs.wisc.edu/~jignesh/publ/hashjoin.pdf)
4. Durner and Neumann (2019) *Dominik Durner and Thomas Neumann. 2019.* No False Negatives: Accepting All Useful Schedules in a Fast Serializable Many-Core System. In *ICDE*.
5. Evans (2015) *Jason Evans. 2015.* Tick Tock, Malloc Needs a Clock [Talk]. https://dl.acm.org/citation.cfm?id=2742807. In *ACM Applicative*.
6. Evans (2018) *Jason Evans. 2018.* jemalloc ChangeLog. https://github.com/jemalloc/jemalloc/blob/dev/ChangeLog. (2018).
7. Ferreira et al. (2011) *Tais B Ferreira, Rivalino Matias, Autran Macedo, and Lucio B Araujo. 2011.* An experimental study on memory allocators in multicore and multithreaded applications. In *2011 12th International Conference on Parallel and Distributed Computing, Applications and Technologies*. IEEE, 92–98.
8. Google (2007) *Google. 2007.* TCMalloc Documentation. https://gperftools.github.io/gperftools/tcmalloc.html. (2007).
9. Google (2017) *Google. 2017.* gperftools Repository. https://github.com/gperftools/gperftools/tree/gperftools-2.5.93. (2017).
10. Hudson et al. (2006) [Richard L. Hudson, Bratin Saha, Ali-Reza Adl-Tabatabai, and Ben Hertzberg. 2006. McRT-Malloc: a scalable transactional memory allocator. In *ISMM*. 74–83.](https://dx.doi.org/10.1145/1133956.1133967)
11. Idreos et al. (2012) *Stratos Idreos, Fabian Groffen, Niels Nes, Stefan Manegold, K. Sjoerd Mullender, and Martin L. Kersten. 2012.* MonetDB: Two Decades of Research in Column-oriented Database Architectures. *IEEE Data Eng. Bull.* 35, 1 (2012), 40–45.
12. Intel (2017) *Intel. 2017.* Threading Building Blocks Repository. https://github.com/01org/tbb/tree/tbb_2017. (2017).
13. Kemper and Neumann (2011) [Alfons Kemper and Thomas Neumann. 2011. HyPer: A hybrid OLTP&OLAP main memory database system based on virtual memory snapshots. In *ICDE*. 195–206.](http://www.cs.brown.edu/courses/cs227/papers/olap/hyper.pdf)
14. Kukanov and Voss (2007) [Alexey Kukanov and Michael J Voss. 2007. The Foundations for Scalable Multi-core Software in Intel Threading Building Blocks. *Intel Technology Journal* 11, 4 (2007).](https://dx.doi.org/10.1535/itj.1104.05)
15. Leis et al. (2014) *Viktor Leis, Peter A. Boncz, Alfons Kemper, and Thomas Neumann. 2014.* Morsel-driven parallelism: a NUMA-aware query evaluation framework for the many-core age. In *SIGMOD*. 743–754.
16. Library (2017) *GNU C Library. 2017.* The GNU C Library version 2.26 is now available. https://sourceware.org/ml/libc-alpha/2017-08/msg00010.html. (2017).
17. Library (2018) *GNU C Library. 2018.* Malloc Internals: Overview of Malloc. https://sourceware.org/glibc/wiki/MallocInternals. (2018).
18. May et al. (2017) [Norman May, Alexander Böhm, and Wolfgang Lehner. 2017. SAP HANA - The Evolution of an In-Memory DBMS from Pure OLAP Processing Towards Mixed Workloads. In *BTW*. 545–563.](https://dx.doi.org/10.1007/s13222-015-0185-2)
19. Nambiar and Poess (2006) *Raghunath Othayoth Nambiar and Meikel Poess. 2006.* The Making of TPC-DS. In *VLDB*. 1049–1058.
20. Oukid et al. (2017) [Ismail Oukid, Daniel Booss, Adrien Lespinasse, Wolfgang Lehner, Thomas Willhalm, and Grégoire Gomes. 2017. Memory Management Techniques for Large-Scale Persistent-Main-Memory Systems. *PVLDB* 10, 11 (2017), 1166–1177.](https://dl.acm.org/ft_gateway.cfm?id=3137629&type=pdf)
21. Patel et al. (2018) *Jignesh M. Patel, Harshad Deshmukh, Jianqiao Zhu, Navneet Potti, Zuyu Zhang, Marc Spehlmann, Hakan Memisoglu, and Saket Saurabh. 2018.* Quickstep: A Data Platform Based on the Scaling-Up Approach. *PVLDB* 11, 6 (2018), 663–676.
22. Stoica and Ailamaki (2013) [Radu Stoica and Anastasia Ailamaki. 2013. Enabling efficient OS paging for main-memory OLTP databases. In *DaMoN*. 7.](http://www.inf.ufpr.br/carmem/oficinaBD/artigos2s2013/a7-stoica.pdf)
23. Tu et al. (2013) [Stephen Tu, Wenting Zheng, Eddie Kohler, Barbara Liskov, and Samuel Madden. 2013. Speedy transactions in multicore in-memory databases. In *SOSP*. 18–32.](https://dl.acm.org/ft_gateway.cfm?id=2522713&type=pdf)
24. Zhang et al. (2019) *Zuyu Zhang, Harshad Deshmukh, and Jignesh M. Patel. 2019.* Data Partitioning for In-Memory Systems: Myths, Challenges, and Opportunities. In *CIDR*.
