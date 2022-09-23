# Impala高性能探秘之HDFS数据访问

Impala 是一个高性能的OLAP引擎，Impala 本身只是一个OLAP-SQL 引擎，它访问的数据存储在第三方引擎中，第三方引擎包括 HDFS、HBase、kudu。对于 HDFS 上的数据，Impala 支持多种文件格式，目前可以访问 Parquet、TEXT、avro、sequence file 等。对于 HDFS 文件格式，Impala 不支持更新操作，这主要限制于 HDFS 对于更新操作的支持比较弱。本文主要介绍 Impala 是如何访问 HDFS 数据的，Impala 访问 HDFS 包括如下几种类型：

1. 数据访问（查询）

2. 数据写入（插入）；

3. 数据操作（重命名、移动文件等）。

底层存储引擎的处理性能直接决定着 SQL 查询的速度快慢，目前 Impala+Parquet 格式文件存储的查询性能做到很好，肯定是有其独特的实现原理的。本文将详细介绍 Impala 是如何在查询执行过程中从 HDFS 获取数据，也就是 Impala 中 `HdfsScanNode` 的实现细节。

## 数据分区

Impala 执行查询的时首先在 FE 端进行查询解析，生成**物理执行计划**，进而分隔成多个 **Fragment**（子查询），然后交由 `Coordinator` 处理任务分发，`Coordinator` 在做任务分发的时候需要考虑到数据的本地性，它需要依赖于每一个文件所在的存储位置（在哪个 DataNode 上），这也就是为什么通常将 Impalad 节点部署在 DataNode 同一批机器上的原因，**为了揭开 Impala 访问 HDFS 的面纱需要先从 Impala 如何分配扫描任务说起**。

众所周知，无论是 MapReduce 任务还是 Spark 任务，它们执行的之前都需要在客户端将输入文件进行分割，然后每一个 Task 处理一段数据分片，从而达到并行处理的目的。Impala 的实现也是类似的原理，在生成物理执行计划的时候，Impala 根据数据所在的位置将 **Fragment** 分配到多个Backend Impalad 节点上执行，那么这里存在两个核心的问题：

1. Impala 如何获取每一个文件的位置？
2. 如何根据数据位置分配子任务？

在之前介绍的 Impala 的总体架构可以看到，Catalogd 节点负责整个系统的元数据，元数据是以表为单位的，这些元数据具有一个层级的关系，如下图所示

| ![img](http://www.uml.org.cn/bigdata/images/2020071512.png) |
| :---------------------------------------------------------: |
|                     Impala 表元数据结构                     |

每一个表包含如下元数据（只选取本文需要用到的）：

1. Schema 信息：该表中包含哪些列，每一列的类型是什么等
2. **表属性信息**：拥有者、数据库名、分区列、表的根路径、表存储格式。
3. **表统计信息**：主要包括表中总的记录数、所有文件总大小。
4. 分区信息：每一个分区的详细信息。

**每一个分区包含如下信息**：

1. 分区名：由所有的分区列和每一列对应的值唯一确定的
2. 分区文件格式：每一个分区可以使用不同的文件格式存储，解析时根据该格式而非表中的文件存储格式，如果创建分区时不指定则为表的存储格式。
3. 分区的所有文件信息：保存了该分区下每一个文件的详细信息，这也导致了重新写入数据之后需要REFRESH表。

**每一个文件包含如下的信息**：

1. 该文件的基本信息：通过 `FileStatus` 对象保存，包括文件名、文件大小、最后修改时间等。

2. 文件的压缩格式：根据文件名的后缀决定。
3. 文件中每一个 BLOCK 的信息：因为 HDFS 存储文件是按照 BLOCK 进行划分的，因此 Impala 也同样存储每一个块的信息。

**每一个 BLOCK 包含如下的信息**：

1. 这个 BLOCK 处于文件的偏移量、BLOCK 长度。

2. 这个 BLOCK 所在的 **Datanode** 节点：每一个 BLOCK 默认会被存储多个副本，分布在不同的 Datanode上。

3. 这个 BLOCK 所在的 Datanode 的 Disk 信息：这个BLOCK 存储在对应的 Datanode 的哪一块磁盘上，如果查询不到则返回-1表示未知。

## 任务分发

从上面的元数据描述可以解答我们的第一个问题，每一个表所拥有的全部文件信息都在表加载的时候由Impala缓存并且通过statestored同步到每一个impalad节点缓存，在impalad生成HdfsScanNode节点时会首先根据该表的过滤条件过滤掉不必要的分区（分区剪枝），然后遍历每一个需要处理分区文件，获取每一个需要处理的BLOCK的基本信息和位置信息，返回给Coordinator作为分配HdfsScanNode的输入。这里还有一个问题：每一个分配的range是多大呢？这个依赖于查询的配置项MAX_SCAN_RANGE_LENGTH，这个配置项表示每一个扫描的单元的最大长度，根据该配置项得到每一个range的大小为：

1.MAX_SCAN_RANGE_LENGTH ： 如果配置了该配置项并且该配置项小于BLOCK大小。

2.BLOCK大小 ： 如果配置了MAX_SCAN_RANGE_LENGTH但是该配置值大于HDFS的BLOCK大小。

3.BLOCK大小 ： 如果没有配置MAX_SCAN_RANGE_LENGTH

4.整个文件大小 ： 如果文件的大小小于一个HDFS的BLOCK大小。

到这一步得到了每一个HdfsScanNode扫描的range列表，每一个range包含所属的文件、该range的起始偏移量和长度，以及该range所属的BLOCK所在的DataNode地址、在DataNode的Disk id以及该BLOCK是否已被HDFS缓存等信息。

完成了SQL解析，Coordinator会根据分配的子任务（本文只关心HdfsScanNode）和数据分布进行任务的分发，分发的逻辑由Coordinator的Scheduler:: ComputeScanRangeAssignment函数完成，由于每一个range包含了存储位置，Impala会首先根据每一个BLOCK是否已被缓存，或者是否存储在某一个impalad本地节点上，前者表示可以直接从缓存（内存）中读取数据，后者意味着可以通过shortcut的方式读取HDFS数据，这里需要提到一个读取距离的概念，Impala中将距离从近到远分为如下几种：

1.CACHE_LOCAL : 该range已缓存，并且缓存的DataNode是一个impalad节点

2.CACHE_RACK : 该range已缓存，并且缓存在相同机架的DataNode上，目前没有使用。

3.DISK_LOCAL : 该range可以从本地读取，意味着该BLOCK所在的DataNode和处理该BLOCK的impala在同一个机器上。

4.DISK_RACK : 该range可以从同一个机架的磁盘读取，目前没有使用。

5.REMOTE : 该range不能通过本地读取，只能通过HDFS远程读取的方式获取。

客户端查询的时候可以设置REPLICA_PREFERENCE配置项，该配置项表示本次查询更倾向于使用哪种距离的副本，默认为0表示CACHE_LOCAL，其他的配置有3和5，分别表示DISK_LOCAL和REMOTE。另外可以配置DISABLE_CACHED_READS设置是否可以从缓存中读取，除此之外，可以在SQL的hints中设置默认读取的距离。最后，可以在SQL的hints中设置是否随机选择副本，有了这两个配置接下来就可以根据range的位置计算每一个range应该被哪个impalad处理。

处理range的分配首先需要计算出该range的最短距离，分为两种情况：

1.如果最短的距离是REMOTE，表示该range所在的DataNode没有部署impalad节点，这种range从所有impalad中选择一个目前已分配的range字节数最少的impalad。

2.CACHE_LOCAL和DISK_LOCAL的区别在于前者可以随机选择，此时可以从所有满足条件的副本（该副本的距离等于最短距离）随机选择一个impalad分配，否则分配到已分配的字节数最少的impalad。

讲到这里，也就回答了上面的第二个问题，Impala根据每一个range所在的位置分配到impalad上，尽可能的做到range的分配更均衡并且尽可能的从本地甚至缓存中读取。接下来需要看一下HdfsScanNode是如何运行的。

## `HdfsScanNode` 的实现

前面我们提到过，HdfsScanNode的作用是从保存在HDFS上的特定格式的文件读取数据，然后对其进行解析转换成一条条记录，将它们传递给父执行节点处理，因此下面介绍的过程主要是在已知扫描哪些数据的情况下返回所有需要获取的记录。在这之前，可以先看一下BE模块的ScanNode的类结构：

| ![img](http://www.uml.org.cn/bigdata/images/2020071513.png) |
| :---------------------------------------------------------: |
|                    Impala 执行节点类层次                    |

集合上图和Impala执行逻辑，SQL生成的物理执行计划中每一个节点都是ExecNode的子类，该类提供了6个接口：

1. `Init`：该函数在创建ExecNode节点的时候被调用，参数分别是该执行节点的详细描述信息和整个Fragment的上下文。HdfsScanNode初始化的时候会解析runtime filter信息和查询中指定的该表的filter条件。另外还初始化一些该节点的统计指标。
2. `Prepare`：该函数在Fragment执行Prepare函数的时候递归的调用该子树所有节点的Prepare函数，HdfsScanNode的Prepare函数初始化该表的描述信息以及需要读取并交给父节点的记录包含哪些列，初始化每一个range扫描的信息（创建Hdfs handler等）。
3. `Codegen`：该函数实现每一个节点的codegen，Impala利用LLVM实现codegen的功能，减少虚函数的调用，一定程度上提升了查询性能，HdfsScanNode在Codegen中生成每一种文件格式的codegen。
4. `Open`：该函数在执行之前被调用，完成执行之前的初始化工作，在HdfsScanNode的Open函数中初始化最大的scanner线程数，并且注册ThreadTokenAvailableCb函数用于启动新的scanner线程。
5. `GetNext`：该函数每次输出一个row_batch，并且传入eos变量用于设置该节点是否执行完成，HdfsScanNode会被父节点循环的调用，每次返回一个row_batch。
6. `Close`：该函数在完成时被调用，处理一些资源释放和统计的操作。

对于每一个 `ExecNode`，真正执行逻辑一般是在 `Open` 和 `GetNext` 函数中，在 `HdfsScanNode` 节点中也是如此，刚才提到 `Open` 函数中会注册一个回调函数，该函数被调用时会判断当前是否需要启动新的Scanner 线程，那么是 Scanner 线程又是什么呢？这里就需要介绍一下 impalad 执行数据扫描的模型，impalad 执行过程中会将数据读取和数据扫描分开，数据读取是指从远程 HDFS 或者本地磁盘读取数据，数据扫描是指基于读取的原始数据对其进行转换，转换之后的就是一条条记录数据。它们的线程模型和关系如下图所示：

| ![img](http://www.uml.org.cn/bigdata/images/2020071514.png) |
| :---------------------------------------------------------: |
|                   Impala数据处理线程模型                    |

我们从下往上看这个处理模型，最底层的线程池是HDFS数据I/O线程池，这个线程池在impalad初始化的时候启动和初始化，impalad将这些线程分为本地磁盘线程和远程访问数据线程，本地磁盘线程需要为每一个磁盘启动一组线程，它根据系统配置num_threads_per_disk项决定，默认情况下对于每一个机械磁盘启动1个线程，这样可以避免大量的随机读取（避免大量的磁盘寻道）；对于FLASH磁盘（SSD），默认情况对于每一块磁盘启动8个线程。远程数据访问线程数由系统配置num_remote_hdfs_io_threads决定，默认情况下启动8个线程，每一个线程拥有一个阻塞队列，Scanner线程通过传递共享变量ScanRange对象，该对象包含读取数据的输入：文件、range的偏移量，range的长度，磁盘ID等，在读取的过程中会向该对象中填充读取的一个个内存块，内存块的大小决定了每次从HDFS中读取的数据的大小，默认是8MB（系统配置项read_size配置），并且在ScanRange对象中记录本地读取数据和远程读取数据大小，便于生成该查询的统计信息。

将数据读取和数据解析分离是为了保证本地磁盘读写的顺序性以及远程数据读取不占用过量的CPU，而Scanner线程的执行需要依赖于Disk线程，Scanner线程的启动是由回调函数ThreadTokenAvailableCb触发的，我们下面在做介绍，当调用getNext方法获取一个个row_batch时，HdfsScanNode会判断是否是第一次调用，如果是第一次调用会触发所有需要扫描的range的请求下发到Disk I/O线程池，扫描操作需要根据文件类型扫描不同的区域，例如对于parquet总是需要扫描文件的footer信息。这里需要提到一个插曲，如果该表需要使用runtime filter需要在扫描文件之前等待runtime filter到达（超时时间默认是1s）。

我们可以假设，在第一个getNext调用之后，所有的数据都已经被读取了，虽然可能有的range的数据读取被block了（可能未被调度或者内存已经使用到了上线），但是这些对于scanner线程是透明的，scanner线程只需要从readercontext对象中获取已读取的数据（获取数据的操作可能阻塞）进行解析的处理。到这里，数据已经被I/O线程读取了，那么什么时候会启动Scanner线程呢？

## 数据解析和处理

前面提到Scanner线程的启动是ThreadTokenAvailableCb函数触发的，当每次向Disk线程池中请求RangeScan请求时会触发该函数，该函数需要根据当前Fragment和系统中资源使用的情况决定启动多少Scanner线程，当每一个Scanner线程执行完成之后会重新触发该回调函数启动新的Scanner线程。每一个Scanner线程分配一个ScanRange对象，该对象中保存了一个分区的全部数据。最后调用ProcessSplit函数，该函数处理这个分区的数据解析。

| ![img](http://www.uml.org.cn/bigdata/images/2020071515.png) |
| :---------------------------------------------------------: |
|                   HDFS文件数据处理类层次                    |


上图描述了不同HDFS文件类型的Scanner类结构，不同的文件类型使用不同的Scanner进行扫描和解析，这里我们以比较简单的TEXT格式为例来说明该流程，TEXT格式的表需要在建表的时候指定行分隔符、列分隔符等元数据，分区数据的解析依赖于这些分隔符配置。为了提升解析性能，Impala使用了Codegen计数和SSE4指令，但是由于分区的划分是按照BLOCK来的，而每一个BLOCK绝大部分情况下其实和结束都处于一条记录的中间，而且每次读取数据的缓存是8MB大小，每一块缓存中的数据还是可能处于记录的中间，这些情况都需要特殊处理。Impala处理每一个分区的时候首先扫描到该分区的第一条记录，当处理完成该分区，如果分区的结尾是一条不完整的记录则继续往下扫描到该记录结束位置。而正常情况下，Scanner只需要根据行分隔符解析出每一行，对于每一行根据需要解析的列将其保存，而直接跳过不需要解析的列，但是对于TEXT这种行式存储的文件格式需要首先读取全部的数据，然后遍历全部的数据，而对于Parquet之类的列式存储，虽然也需要读取每一个分区的数据，但是由于每一列的数据存储在一起，扫描的时候只需要扫描需要的列。这才是列式存储可以减少数据的扫描，而不是较少数据的读取。当然Parquet文件一般使用数据压缩算法使得数据量远小于TEXT格式。

无论是哪种文件格式，通过解析器解析出一条条记录，每一条记录中只包含该表需要读取的列的内容，组装成一条记录之后会通过该表的filter条件和runtime filter判断该条记录是否需要被淘汰。可以看出，ScanNode执行了Project和谓词下推的功能。所有没被淘汰的记录按照row_batch的结构组装在一起，每一个row_batch默认情况下是1024行，查询客户端可以使用BATCH_SIZE配置项设置。但是过大的row_batch大小需要占用更大的内存，可能降低ExecNode之间的并发度，因为ExecNode需要等到子节点完成一个row_batch的组装才进行本节点的计算。由于Scan操作是由Scanner线程中完成的，每次Scanner组装完成之后将其放到一个BlockingQueue中，等待父节点从该Queue中获取进行自身的处理逻辑，当然可能存在父节点和子节点执行频率不一致的情况，导致BlockingQueue队列被放满，此时Scanner线程将被阻塞，并且也不会创建新的Scanner线程。

## 数据压缩

最后我们简单的聊一下文件压缩，通常在聊到 OLAP 优化方式的时候都会提到数据压缩，相同的数据压缩之后可以有很大程度的数据体积的降低，但是通过学习 impala 的数据读取流程，impala 通过文件名的后缀判断文件使用了哪种压缩算法，对于使用了压缩的文件，虽然读取的数据量减少了许多，但是需要消耗大量的CPU 资源进行解压缩，解压缩之后的数据其实和非压缩的数据是一样的，因此对于解析操作处理的数据量两者并没有任何差异。因此使用数据压缩只不过是一个 I/O 资源换取 CPU 资源的常用手段，当一个集群中 I/O 负载比较高可以考虑使用数据压缩降低I/O消耗，而相反CPU负载比较高的系统则通常不需要进行数据压缩。

## 总结

好了，在结束之前我们总结一下Impala读取HDFS数据的逻辑，首先Impala会将数据扫描和数据读取线程分离，Impalad在启动的时候初始化所有磁盘和远程HDFS访问的线程，这些线程负责所有数据分区的读取。Impala对于每一个SQL查询根据表的元数据信息对每一个表扫描的数据进行分区（经过分区剪枝之后），并记录每一个分区的位置信息。BE根据每一个分区的位置信息对子任务进行分配，尽可能保证数据的本地读取和任务分配的均衡性。每一个子任务交给不同的Backend模块执行，首先会为子任务创建执行树，HdfsScanNode节点负责数据的读取和扫描，通常是执行树的孩子节点，执行时首先将该HdfsScanNode需要扫描的分区请求Disk I/O线程池执行数据读取，然后创建Scanner线程处理数据扫描和解析，解析时根据不同的文件类型创建出不同的Scanner对象，该对象处理数据的解析，组装成一个个的row_batch对象交给父节点执行。直到所有的分区都已经被读取并完成扫描和解析。

总结下来，Impala处理HdfsScanNode的性能还是有其独到之处的，这也促使了Impala中一般数据读取和扫描不会成为查询的瓶颈，反而聚合和JOIN操作有时会拖慢查询速度，从本文的分析中可以看到Impala处理HDFS数据源时有如下几点优化：

1. 数据位置作为表元数据存储，任务分配时充分考虑到数据本地行和任务分配的均衡性。
2. 数据读取线程和数据处理线程分离，两者可以并行处理。
3. 通过HDFS的shortcut机制实现本地数据读取，提升本地读的性能
4. 在Scan节点上执行project和filter处理，减少上层节点的内存拷贝和网络传输
5. 使用codegen技术降低运行中的虚函数调用损耗和生成特定的代码，使用SSE指令提升数据处理性能。
6. 使用batch机制批量处理数据，减少函数调用次数。

本文详细介绍了Impala如何实现HdfsScanNode执行节点，该节点是所有查询SQL获取数据的源头，因此是十分重要的，当然Impala支持的HDFS格式还是比较有限的，对于ORC格式不能够支持，而对于JSON格式的扫描我们完成各内部的开发版本，有待于进一步性能优化，本文中提到了数据扫描过程中会根据过滤条件和runtime filter进行数据的过滤，这种谓词下推也是各种大数据引擎性能优化的一大要点，而runtime filter可谓是impala的独家秘笈。

# [Impala高性能探秘之Runtime Filter](https://www.qedev.com/bigdata/145345.html)

# Impala 3.4 SQL查询之 ScanRange 流程归纳

## 三

我们在本系列的前两篇文章中，简单介绍了 SQL 查询的整个流程以及重写的相关知识。在接下来的这几篇中，会跟大家一起详细学习 `ScanRange` 的知识。由于涉及的内容非常多，因此会分成几篇来讲解，主要会涉及到`HDFS_SCAN_NODE`、IO thread 等知识。由于现在相关的文档比较少，这些文章都是笔者根据代码和实际调试结果整理出来的，如有错误，欢迎指正。默认情况下，本文涉及到的测试表都是 HDFS 上的 parquet 表，并且是以天为分区。

###  ScanRange

ScanRange是Impala中一个非常基础的概念，对于HDFS_SCAN_NODE来说，一个ScanRange表示的就是一个HDFS文件上的一部分，一般用file_name、offset和len来表示，更多关于ScanRange的详细介绍，可以参考文章：[Impala源码阅读——SimpleScheduler](https://blog.csdn.net/huang_quanlong/article/details/53980132)。本文我们主要讲一下ScanRange的构造，以及在HDFS_SCAN_NODE过程中的一些处理，同时会涉及到IO thread模型相关的一些知识，感兴趣的同学，可以看看我的前两篇文章：[Impala HDFS_SCAN_NODE之IO threads模型](https://blog.csdn.net/skyyws/article/details/115350188)和[Impala HDFS_SCAN_NODE之AverageHdfsReadThreadConcurrency](https://blog.csdn.net/skyyws/article/details/115521262)。 当SQL提交到Impalad节点之后，会通过JNI调用，由FE模块进行执行计划的解析，最终会针对每个表，构建一个HDFS_SCAN_NODE，其中就会包含ScanRange的信息，相关的函数调用栈如下所示：

```java
ExecuteInternal(impala-server.cc):956
-InitExecRequest(client-request-state.cc):1440
--GetExecRequest(frontend.cc):230
---createExecRequest(JniFrontend.java):154
----createExecRequest(Frontend.java):1464
-----getTExecRequest(Frontend.java):1494
------doCreateExecRequest(Frontend.java):1600
-------getPlannedExecRequest(Frontend.java):1734
--------createExecRequest(Frontend.java):1413
---------createPlans(Planner.java):264
----------createPlanFragments(Planner.java):118
-----------createSingleNodePlan(SingleNodePlanner.java):150
------------createQueryPlan(SingleNodePlanner.java):268
-------------createSelectPlan(SingleNodePlanner.java):669
--------------createTableRefsPlan(SingleNodePlanner.java):845
---------------createTableRefNode(SingleNodePlanner.java):1686
----------------createScanNode(SingleNodePlanner.java)
```

在 FE 端构造 `HdfsScanNode` 对象的时候，所有的 `ScanRange` 信息都存储在 `scanRangeSpecs_` 对象中：

```java
//HdfsScanNode.java
// Scan-range specs. Populated in init().
protected TScanRangeSpec scanRangeSpecs_
```

这里我们使用一个测试SQL，然后通过[远程调试](https://cloud.tencent.com/product/rd?from=10680)，查看这个变量的信息，如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/c3a0075ad16e2cbf31be19977ac0b0f8.png?imageView2/2/w/1620)

可以看到，这个 `scanRangeSpecs_` 对象中，就有 232 个 `TScanRangeLocationList` 对象。当 FE 端所有的处理都完成之后，最终会返回一个 `TExecRequest` 对象，我们同样通过远程调试，查看这个对象的信息，如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/ecb5c10bb17d745ed324731fe0f11a27.png?imageView2/2/w/1620)

 通过上面的截图可以看到，该测试 SQL 包含了两个 `TScanRangeSpec`，分别对应两个 `HDFS_SCAN_NODE`，一个包含了 232 个 `TScanRangeLocationList`，另外一个包含了 **4816** 个，而每个 `TScanRangeLocationList` 就包含了一个 `TScanRange` 对象，这个 `TScanRange` 对象就是 `ScanRange` 在 FE 端的一个体现。对于`HDFS_SCAN_NODE` 来说，TScanRange 包含了 1 个 `THdfsFileSplit`，其中就包含了 `path`、`offset`、`len `等信息。当 `TExecRequest` 被传回到BE端之后，同样需要进行一系列的转换操作，相关的函数调用如下所示：

```c
ExecuteInternal(impala-server.cc):977
-InitExecRequest(client-request-state.cc):1440
-Exec(client-request-state.cc):197
--ExecAsyncQueryOrDmlRequest(client-request-state.cc):508
---FinishExecQueryOrDmlRequest(client-request-state.cc):518
----SubmitForAdmission(admission-controller.cc):863         
-----FindGroupToAdmitOrReject(admission-controller.cc):1271
------ComputeGroupSchedules(admission-controller.cc):1248
-------Schedule(scheduler.cc):769
--------ComputeScanRangeAssignment(scheduler.cc):174
---------schedule->GetFragmentExecParams(fragment.idx)->scan_range_assignment
--------ComputeScanRangeAssignment(scheduler.cc):192
---------ComputeScanRangeAssignment(scheduler.cc):600/695
----------RecordScanRangeAssignment(scheduler.cc):1090~1100
-------Schedule(scheduler.cc):770
--------ComputeFragmentExecParams(scheduler.cc)
-------Schedule(scheduler.cc):771
--------ComputeBackendExecParams(scheduler.cc)
---FinishExecQueryOrDmlRequest(client-request-state.cc):539
----Exec(coordinator.cc):167
-----InitBackendStates(coordinator.cc)
----Exec(coordinator.cc):181
-----StartBackendExec(coordinator.cc):487
------ExecAsync(coordinator-backend-state.cc):246
-------SetRpcParams(coordinator-backend-state.cc):125-163
```

上面这个函数调用栈比较长，而且涉及到的过程也比较复杂，这里我们就不一一展开解释。我们需要知道的是：`TExecRequest`中包含的这些 `ScanRange` 会被分配到各个executor上，**每个executor对应的相关信息都被封装为一个BackendState 对象**，每个 `BackendState` 对象都包含一个 `BackendExecParams` 成员，这里就封装了 `ScanRange` 的相关信息，最终通过 `BackendState::ExecAsync` 函数在每个 executor 上执行真正的scan操作。我们将上述整个过程中涉及到的一些主要对象归纳为一张图，如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/02583132af40641157a7e4142b3808d3.png?imageView2/2/w/1620)

 其中绿色部分表示的是 typedef，比如 `PerNodeScanRanges` 对应的就是 `map<TPlanNodeId, std::vector>`，黄色的部分表示的是当前这个calss/struct包含的一些关键成员，蓝色部分表示的是thrift变量以及包含关系。**图中实线表示的是包含关系，箭头所指的是被包含的对象**。**虚线表示的是构建关系**，例如我们通过TExecRequest中的plan_exec_info构造了fragment_exec_params遍变量。 最终，我们通过BackendState::SetRpcParams方法，将BackendState对象的相关信息封装成为TExecPlanFragmentInfo，然后发送到对应的executor进行实际的扫描。需要注意的是，每个BackendState的构造是在coordinator上进行的，而实际的scan操作是在各个executor上进行的。

### BackendState

我们上面提到，每个executor需要的信息都会被封装成一个BackendState对象，每一个BackendState对象中，包含ScanRange信息的成员变量就是backend_exec_params_。这个变量是一个BackendExecParams的类型，可以通过上面的关系图追踪到相关的信息。为了方便理解，我们在源码中增加如下所示的DEBUG代码，可以看到整个查询的BackendState分布情况：

```javascript
//在Coordinator::StartBackendExec()中进行增加
  stringstream ss;
  for (BackendState* backend_state: backend_states_) {
    ss << "Netease::BackendState: " << backend_state->impalad_address().hostname << ":"
        << backend_state->impalad_address().port << endl;
    for(const FInstanceExecParams* params : backend_state->exec_params()->instance_params) {
        sss << "Netease::FInstanceExecParams: " << PrintId(params->instance_id) << " "
            << params->host.hostname << ":" << params->host.port << endl;
        PerNodeScanRanges::const_iterator iter = params->per_node_scan_ranges.begin();
        while (iter != params->per_node_scan_ranges.end()) {
          vector<TScanRangeParams> scVector = iter->second;
          sss << "Netease::PlanId: " << iter->first << ", ScanRange Size: "
              << scVector.size() << endl;
          iter++;
        }
    }
  }
  LOG(INFO) << ss.str();
```

复制

其中某个BackendState的结果如下所示，可以看到该BackendState有5个fragment，其中两个包含了HDFS_SCAN，分别有345和16和ScanRange：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/468c85459c59d18f9f5d19734433995b.png?imageView2/2/w/1620)

 我们直接使用某个instance id：c5478443d44931cc:767dad4400000003，在profile页面上进行搜到，可以看到该instance下的HDFS_SCAN_NODE对应的counter也是345：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/ee0eebfd69426e8ddc6ae16d1a5150e9.png?imageView2/2/w/1620)

### ScanRangesComplete

在Impala的profile中，有一个 `ScanRangesComplete` 计数器，我们将某个表的所有HDFS_SCAN_NODE中对应的ScanRangesComplete加在一起，就等于上面提到的TScanRangeLocationList对象数量，即232和4816。每个HDFS_SCAN_NODE的ScanRangesComplete，表示分发到这个executor上的ScanRange数量，我们对上面的测试SQL进行统计，如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/0fa4f9a56194b807397a2616bafbc172.jpeg?imageView2/2/w/1620)

 从上图可以看到，一共有13个executor，分别有两个表的HDFS_SCAN_NODE。因此，我们可以将这个counter，理解为这个executor上操作的ScanRange数量，后续我们还会在提到。

### PerDiskState

在[Impala HDFS_SCAN_NODE之IO threads模型](https://blog.csdn.net/skyyws/article/details/115350188)这篇文章中提到，IO thread会先获取一个 `RequestContext` 对象，每个对象都包含一个 `PerDiskState` 的集合：

```c++
  /// Per disk states to synchronize multiple disk threads accessing the same request
  /// context. One state per IoMgr disk queue.
  std::vector<PerDiskState> disk_states_;
```

根据这个RequestContext对象的类型，获取指定的PerDiskState对象，比如remote hdfs、S3等，每个PerDiskState都包含了多个不同的ScanRange成员变量：

```c++
class RequestContext::PerDiskState {
  DiskQueue* disk_queue_ = nullptr;
  bool done_ = true;
  AtomicInt32 is_on_queue_{0};
  int num_remaining_ranges_ = 0;
  InternalQueue<ScanRange> unstarted_scan_ranges_;
  InternalQueue<RequestRange> in_flight_ranges_;
  ScanRange* next_scan_range_to_start_ = nullptr;
  AtomicInt32 num_threads_in_op_{0};
  InternalQueue<WriteRange> unstarted_write_ranges_;
} 
```

这些成员变量都与Impala的IO thread处理流程紧密相关，下面我们就看下这些成员变量以及相关处理流程。 disk_queue_表示该PerDiskState所属的disk queue；done_表示这个RequestContext上的这个disk queue的扫描是否完成了；is_on_queue_表示当前这个RequestContext对象是否在队列上；num_threads_in_op_表示当前正在操作这个RequestContext对象的线程数。 当io thread从request_contexts_队列的头部获取一个RequestContext对象之后，就会进行对应的设置：

```javascript
// request-context.cc
  void IncrementDiskThreadAfterDequeue() {
    /// Incrementing 'num_threads_in_op_' first so that there is no window when other
    /// threads see 'is_on_queue_ == num_threads_in_op_ == 0' and think there are no
    /// references left to this context.
    num_threads_in_op_.Add(1);
    is_on_queue_.Store(0);
  }
```

将num_threads_in_op_+1，然后is_on_queue_设置为0，表示该RequestContext对象已经不在队列中。当我们获取了对应的ScanRange之后，就会将is_on_queue_设置为1，并将RequestContext对象放到队尾，此时其他的io thread就可以有机会再次获取这个RequestContext对象进行处理：

```javascript
// request-context.cc
void RequestContext::PerDiskState::ScheduleContext(const unique_lock<mutex>& context_lock,
    RequestContext* context, int disk_id) {
  DCHECK(context_lock.mutex() == &context->lock_ && context_lock.owns_lock());
  if (is_on_queue_.Load() == 0 && !done_) {
    is_on_queue_.Store(1);
    disk_queue_->EnqueueContext(context);
  }
}
```

当我们处理完对应的 `ScanRange` 之后，才会将 `num_threads_in_op_` 减 1，表示这个 IO thread 的本次处理已经完成。接着就会循环处理队列中的下一个 `RequestContext` 对象。 这里我们简单介绍了 `PerDiskState` 的几个成员变量，还有剩下的几个，例如`unstarted_scan_ranges_`、`in_flight_ranges_` 等，相对比较复杂，由于篇幅原因，我们将在后续的文章中继续进行探究。

## 四

在上篇文章中，我们主要介绍了 ScanRange 的构造，以及在FE和BE端的一些处理流程。同时，我们还介绍了IO thead处理模型中一个比较重要的对象RequestContext::PerDiskState，以及部分成员变量的含义，在本篇文章中，我们将介绍其中一个比较重要的成员：unstarted_scan_ranges_。

### BE端的 `ScanRange`

上篇文章中我们提到，FE端的 `ScanRange` 信息，主要通过 `TScanRange` 传到 BE 端，然后构造为 `TPlanFragmentInstanceCtx` 中的 `TScanRangeParams`，传到各个 executor 进行实际的扫描操作，那么当各个 executor 接收到请求之后，就会根据这些信息，构造相应的 `ScanRange` 类。ScanRang e是继承 RequestRange 这个类的，另外 WriteRange 也继承于 RequestRange 。从名字就可以看出，WriteRange 主要是针对写入的情况，这里我们不展开介绍，主要看下 `ScanRange` 对象。首先，RequestRange 主要包含了 file、offset、len 这些基本信息。而`ScanRange` 则增加了一些额外的信息，如下所示：

```c++
class ScanRange : public RequestRange {
    struct SubRange {
    int64_t offset;
    int64_t length;
  };
  
  DiskIoMgr* io_mgr_ = nullptr;
  RequestContext* reader_ = nullptr;
  bool read_in_flight_ = false;
  int64_t bytes_read_ = 0;
  std::vector<SubRange> sub_ranges_;
  ......
}
```

关于这些成员变量的含义，我们这里先不一一介绍了，后面在相应的场景下再展开说明。 当我们将`TPlanFragmentInstanceCtx` 的信息传到对应的 executor 的时候，对应的 executor 节点就会构造相应的 `HdfsScanNode`，然后在 `HdfsScanNodeBase::Prepare` 函数中，会循环遍历每个 `TScanRangeParams`，然后初始化下面的这个 `map 成员：

```c++
// hdfs-scan-node-base.h
/// This is a pair for partition ID and filename
typedef pair<int64_t, std::string> PartitionFileKey;

/// partition_id, File path => file descriptor (which includes the file's splits)
typedef std::unordered_map<PartitionFileKey, HdfsFileDesc*, pair_hash> FileDescMap;
FileDescMap file_descs_;

struct HdfsFileDesc {
  hdfsFS fs;
  std::string filename;
  int64_t file_length;
  int64_t mtime
  THdfsCompression::type file_compression;
  bool is_erasure_coded;
  std::vector<io::ScanRange*> splits;
};
```

`file_descs_` 是一个map，用分区 id 和文件名来作为 map 的 key，value 是一个 `HdfsFileDesc` 对象。当循环遍历 `TScanRangeParams` 对象的时候，Impala 会用其中包含的 `THdfsFileSplit` 对象的信息，来构造一个 `HdfsFileDesc` 对象，填充其中的 fs、filename 等信息，关键代码如下：

```c++
  for (const TScanRangeParams& params: *scan_range_params_) {
    const THdfsFileSplit& split = params.scan_range.hdfs_file_split;
    partition_ids_.insert(split.partition_id);
    HdfsPartitionDescriptor* partition_desc =
        hdfs_table_->GetPartition(split.partition_id);

    filesystem::path file_path(partition_desc->location());
    file_path.append(split.relative_path, filesystem::path::codecvt());
    const string& native_file_path = file_path.native();

    auto file_desc_map_key = make_pair(partition_desc->id(), native_file_path);
    HdfsFileDesc* file_desc = NULL;
    FileDescMap::iterator file_desc_it = file_descs_.find(file_desc_map_key);
    if (file_desc_it == file_descs_.end()) {
      // Add new file_desc to file_descs_ and per_type_files_
      file_descs_[file_desc_map_key] = file_desc;
      // 省略其余代码
      file_desc = runtime_state_->obj_pool()->Add(new HdfsFileDesc(native_file_path));
      per_type_files_[partition_desc->file_format()].push_back(file_desc);
    } else {
      // File already processed
      file_desc = file_desc_it->second;
    }

    file_desc->splits.push_back(
        AllocateScanRange(file_desc->fs, file_desc->filename.c_str(), split.length,
            split.offset, split.partition_id, params.volume_id, expected_local,
            file_desc->is_erasure_coded, file_desc->mtime, BufferOpts(cache_options)));
  }
```

我们删除了部分代码，只保留了关键的部分。可以看到，当` file_descs_`中，不存在指定 key时，我们构造新的 key 和 value，加入到 map 中。这里关注下对于 splits 这个 vector 的处理。对于分区的某个指定文件，在 map 中会有一条记录，如果这个文件对应多个 `TScanRangeParams`，那么这个 map 的 value 对应的 splits 则会有多个成员，但是这条 key-value 记录只有一条。我们前面说过了，一个 `ScanRange` 在 `HDFS_SCAN_NODE` 代表一个 block，所以如果文件跨越了多个block，那么就会分成多个 ScanRange，此时 map 的 value，`HdfsFileDesc` 对象的 splits 就会存在多个成员；反之，如果文件只存在于1个 block 中，那么` HdfsFileDesc` 的 `splits` 对象，则只会有 1 个成员。 除了` file_descs_`之外，还有一个成员也需要关注下：`per_type_files_` ，这个成员变量的定义如下所示：

```c++
// hdfs-scan-node-base.h
  /// File format => file descriptors.
  typedef std::map<THdfsFileFormat::type, std::vector<HdfsFileDesc*>>
    FileFormatsMap;
  FileFormatsMap per_type_files_;
```

可以看到，这个 `per_type_files_` 保存的就是文件格式和 `HdfsFileDesc`的集合，在上述处理 `file_descs_`的代码中，我们也可以看到对 `per_type_files_`的处理，根据当前这个文件所属分区的格式，加入到 map value 的 vector 中。

### `unstarted_scan_ranges`

上面我们介绍完了BE端的 `ScanRange` 对象，接下来我们来看一下 `PerDiskState` 中的`unstarted_scan_ranges_` 成员，以及它是如何更新的。首先，我们还是先看下这个成员变量的定义：

```c++
  /// Queue of ranges that have not started being read.  This list is exclusive
  /// with in_flight_ranges.
  InternalQueue<ScanRange> unstarted_scan_ranges_;
```

从注释我们可以看到，`unstarted_scan_ranges_` 表示是还没有开始进行scan操作的 `ScanRange`，这个解释比较空泛，我们接着看下 `unstarted_scan_ranges` 这个成员更新的相关函数调用（当前是针对 Parquet 格式的表进行梳理）：

```
ExecFInstance(query-state.cc):697
-Exec(fragment-instance-state.cc):98
--ExecInternal(fragment-instance-state.cc):383
---GetNext(hdfs-scan-node.cc):91
----IssueInitialScanRanges(hdfs-scan-node-base.cc):636
-----IssueInitialRanges(hdfs-parquet-scanner.cc):82
------IssueFooterRanges(hdfs-scanner.cc):837
-------AddDiskIoRanges(hdfs-scan-node.cc):212
--------AddScanRanges(request-context.cc):404
---------AddRangeToDisk(request-context.cc):357
----------unstarted_scan_ranges()->Enqueue
---------AddRangeToDisk(request-context.cc):362
----------num_unstarted_scan_ranges_.Add(1)
---------AddRangeToDisk(request-context.cc):366
----------next_scan_range_to_start()=null ScheduleContext(request-context.cc)
---------AddRangeToDisk(request-context.cc):379
----------num_remaining_ranges_++
```

在 `HdfsScanNodeBase::IssueInitialScanRange` s函数中，我们通过 `per_type_files_` 成员，获取所有PARQUET 格式的 `HdfsFileDesc`集合，然后在 `HdfsScanner::IssueFooterRanges` 函数中，循环构造初始的`ScanRange`（不同的文件格式，这里的处理流程有所不同），由于当前是 PARQUET 文件，所以会构造每个文件footer 的 `ScanRange`，这里我们摘取一些主要的步骤看下（忽略其他的一些特殊情况）：

```c++
    //这里FOOTER_SIZE是一个常量，为1024*100
    int64_t footer_size = min(FOOTER_SIZE, files[i]->file_length);
    int64_t footer_start = files[i]->file_length - footer_size;

    ScanRange* footer_split = FindFooterSplit(files[i]);

    for (int j = 0; j < files[i]->splits.size(); ++j) {
      ScanRange* split = files[i]->splits[j];

      if (!scan_node->IsZeroSlotTableScan() || footer_split == split) {
        ScanRangeMetadata* split_metadata =
            static_cast<ScanRangeMetadata*>(split->meta_data());
        ScanRange* footer_range;
        if (footer_split != nullptr) {
          footer_range = scan_node->AllocateScanRange(files[i]->fs,
              files[i]->filename.c_str(), footer_size, footer_start,
              split_metadata->partition_id, footer_split->disk_id(),
              footer_split->expected_local(), files[i]->is_erasure_coded, files[i]->mtime,
              BufferOpts(footer_split->cache_options()), split);
        }
        footer_ranges.push_back(footer_range);
    }
  // The threads that process the footer will also do the scan.
  if (footer_ranges.size() > 0) {
    RETURN_IF_ERROR(scan_node->AddDiskIoRanges(footer_ranges, EnqueueLocation::TAIL));
  }
  return Status::OK();
}
```

我们删除了其他的一些代码和注释，关注下主要的处理步骤，首先获取footer_size和footer_start，然后利用FindFooterSplit函数获取该file的footer split，判断逻辑就是从splits成员中找到：split.len+split.offset=file.len，可以理解为文件的最后一个split成员对象。然后遍历splits集合，当找到与footer_split对应的split时，我们就用这个footer_split和file的相关信息来构造一个ScanRange，作为footer ScanRange。这里需要注意的是一个file对应多个split（即多个block）的情况，此时在遍历某个file对应的split集合的时候，当满足如下的条件时候，我们就会用对应的split来构造foot ScanRange，如下所示：

```c++
// HdfsScanner::IssueFooterRanges()
// If there are no materialized slots (such as count(*) over the table), we can
// get the result with the file metadata alone and don't need to read any row
// groups. We only want a single node to process the file footer in this case,
// which is the node with the footer split.  If it's not a count(*), we create a
// footer range for the split always.
if (!scan_node->IsZeroSlotTableScan() || footer_split == split) {
}
```

也就是说，当满足条件时，我们对于一个file的多个split，我们会分别构造一个footer ScanRange，而不是1个。但是这些footer ScanRange的len、offset、file信息都是一样的，唯一不同的就是meta_data_，该成员类型是void*，但是实际会被赋值为ScanRangeMetadata。meta_data_中的original_split会保存原始的split对应的ScanRange信息，也就是原始的len、offset。 当处理完成所有的文件之后，我们最终通过RequestContext::AddRangeToDisk函数，将这些footer的ScanRange加入到unstarted_scan_ranges_对象中，同时，每入队一个ScanRange对象，我们会将num_unstarted_scan_ranges_这个成员加1。也就是说，这个unstarted_scan_ranges_最终存放的是所有file文件的footer ScanRange。 上面我们介绍了unstarted_scan_ranges_这个队列的入队流程，接着我们看下出队的操作。在前面的文章中，我们提到了，IO thread会从RequestContext队列的头部取出一个RequestContext对象，然后通过该RequestContext对象获取一个ScanRange进行处理，相关处理函数如下：

```c++ 
RequestRange* RequestContext::GetNextRequestRange(int disk_id) {
  PerDiskState* request_disk_state = &disk_states_[disk_id];
  unique_lock<mutex> request_lock(lock_);

  if (request_disk_state->next_scan_range_to_start() == nullptr &&
      !request_disk_state->unstarted_scan_ranges()->empty()) {
    ScanRange* new_range = request_disk_state->unstarted_scan_ranges()->Dequeue();
    num_unstarted_scan_ranges_.Add(-1);
    ready_to_start_ranges_.Enqueue(new_range);
    request_disk_state->set_next_scan_range_to_start(new_range);
  }

  if (request_disk_state->in_flight_ranges()->empty()) {
    request_disk_state->DecrementDiskThread(request_lock, this);
    return nullptr;
  }

  RequestRange* range = request_disk_state->in_flight_ranges()->Dequeue();

  request_disk_state->ScheduleContext(request_lock, this, disk_id);
  return range;
}
```

同样我们删除了一些代码，方便阅读。首选获取对应的 `PerDiskState` 对象，然后将`unstarted_scan_ranges_` 队列的头部对象出队，并将 `num_unstarted_scan_ranges_` 加 1，同时入队到 `ready_to_start_ranges_`中，这两个变量都是 `RequestContext` 的成员，这里我们先不展开说明。接着将出队的 `ScanRange` 对象设置到` next_scan_range_to_start_` 成员，关于这个成员的用处，我们也在后面展开说明。 紧接着，会判断 `in_flight_ranges_` 队列是否为空，是则直接返回 null，表示这次 IO thead 没取到`ScanRange`；否则，从 `in_flight_ranges_`弹出头部的 `ScanRange` 对象，返回进行处理。

### `unstarted_scan_ranges` 的后续处理

前面我们提到了 IO thread 并不会直接获取 `unstarted_scan_ranges_` 队列上的 `ScanRange` 进行处理。先将 `unstarted_scan_ranges_` 的头部出队，然后入队到 `ready_to_start_ranges_` 队列中，同时设置到 `next_scan_range_to_start_` 成员。然后再从 `in_flight_ranges_` 队列中取出头部对象，进行后续的处理。由于这里涉及到的成员变量很多，我们将 `RequestContext`和`PerDiskState`的成员进行了归纳，如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/ef60e3811418ac034e714df06d01169e.png?imageView2/2/w/1620)

 这里我们简单说明一下，`RequestContex` 对象会包含多个 `PerDiskState`对象，每一个 `PerDiskState` 对象表示一种 disk queue，例如 Remote HDFS、S3 等，所以 `RequestContex` 对象的这些成员，统计的是所有`PerDiskState` 的相应成员的**累加和**，比如 `num_unstarted_scan_ranges_` 这个成员，统计的就是该 `RequestContext` 对象上的所有 `PerDiskState` 的 `unstarted_scan_ranges_`  的总和。这点需要注意。 下面我们来看下 `ready_to_start_ranges_` 和 `next_scan_range_to_start_` 的相关处理，函数调用如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/9dadb364239ee37fc125785818d781e5.png?imageView2/2/w/1620)

由于这里涉及到了不同的调用路径，因此我们使用了上述图片的方式。可以看到，主要分为两条路径：左边路径的主要处理逻辑就是在 `HdfsScanNode` 的 `Open` 函数中，将回调函数 `ThreadTokenAvailableCb` 绑定到线程池；右边路径则会通过回调函数 `ThreadTokenAvailableCb` 启动专门的 Scanner 线程来处理 `unstarted_scan_ranges`。 最终在 `GetNextUnstartedRange` 函数中，会对 `next_scan_range_to_start_` 和 `ready_to_start_ranges_` 进行处理，关键代码如下所示：

```c++
// RequestContext::GetNextUnstartedRange()
*range = ready_to_start_ranges_.Dequeue();
int disk_id = (*range)->disk_id();
disk_states_[disk_id].set_next_scan_range_to_start(nullptr);
```

可以看到在 `GetNextUnstartedRange` 函数中，先将 `ready_to_start_ranges_` 队列中的头部对象弹出，然后将该 `ScanRange` 对应的 `PerDiskState` 的 `next_scan_range_to_start_` 对象设置为空，然后再继续后续的处理，这里省略了后续处理代码。关于回调函数和 Scanner 线程，后面我们讲到 `in_flight_ranges_` 的时候，会再详细说明，这里简单了解下这个处理过程即可。

### 小结

到这里，关于 `unstarted_scan_ranges_` 的相关处理流程我们就介绍的差不多了。回顾一下，我们在本文中，首先介绍了 B E端的 `ScanRange`，相较于 Thrift 的 `TScanRange` 结构体，ScanRange 对象主要是在每个 executor 上进行实际扫描操作时，需要用到的类。除此之外，我们还介绍了一个关键的对象：`unstarted_scan_ranges_`，这是一个 `ScanRange` 的队列，我们通过代码，一步一步了解了这个队列的更新情况，包括入队和出队，这个对象对于整个 IO thread 模型是比较重要。现在读者看下来这两篇文章可能觉得比较琐碎，后面笔者会将各个成员串起来，整体看下 Impala 的这个 IO thread 的处理。

## 五

在上篇文章中，我们介绍了 PerDiskState 的 `unstarted_scan_ranges_` 这个队列的更新逻辑，主要就是成员的入队和出队。总结下来就是：HdfsScanNode 会获取每个文件的 footer ScanRange，然后入队；IO thread会通过 RequestContext 获取对应的 PerDiskState，然后出队，并设置到`next_scan_range_to_start_` 成员，同时入队到 RequestContext 的 `ready_to_start_ranges_` 队列。IO thead 并不会直接从 `unstarted_scan_ranges_` 获取对象，进行扫描操作，而是会从另外一个队列 `in_flight_ranges_` 中获取对象，返回并进行后续的操作。在本文中，我们同样会结合代码，一起学习下如何更新 `in_flight_ranges_` 队列。

### 给 `ScanRange` 分配 buffer

> 已重构，见 [IMPALA-7556](https://issues.apache.org/jira/browse/IMPALA-7556)

**首先**，我们来看下 ScanRang e的buffer分配问题。在将ScanRange放到 `in_flight_ranges_` 队列之前，需要先给 `ScanRange` 分配 buffer，只有当分配了 buffer 之后，IO thread 才能进行实际的扫描操作。Buffer 分配的主要处理就是在 AllocateBuffersForRange 函数中。我们先来看下主要的处理逻辑：

```c++
// DiskIoMgr::AllocateBuffersForRange()
  vector<unique_ptr<BufferDescriptor>> buffers;
  for (int64_t buffer_size : ChooseBufferSizes(range->bytes_to_read(), max_bytes)) {
    BufferPool::BufferHandle handle;
    status = bp->AllocateBuffer(bp_client, buffer_size, &handle);
    if (!status.ok()) goto error;
    buffers.emplace_back(new BufferDescriptor(range, bp_client, move(handle)));
  }
  
// DiskIoMgr::ChooseBufferSizes()
// 删除了部分代码，只保留了关键的部分
vector<int64_t> DiskIoMgr::ChooseBufferSizes(int64_t scan_range_len, int64_t max_bytes) {
  while (bytes_allocated < scan_range_len) {
    int64_t bytes_remaining = scan_range_len - bytes_allocated;
    int64_t next_buffer_size;
    if (bytes_remaining >= max_buffer_size_) {
      next_buffer_size = max_buffer_size_;
    } else {
      next_buffer_size =
          max(min_buffer_size_, BitUtil::RoundUpToPowerOfTwo(bytes_remaining));
    }
    if (next_buffer_size + bytes_allocated > max_bytes) {
      if (bytes_allocated > 0) break;
      next_buffer_size = BitUtil::RoundDownToPowerOfTwo(max_bytes);
    }
    buffer_sizes.push_back(next_buffer_size);
    bytes_allocated += next_buffer_size;
  }
  return buffer_sizes;
}
```

这里主要涉及到两个参数：`bytes_to_read_`，表示这个 `ScanRange` 需要读的字节数；`max_bytes`，是一个阈值，我们这里先不展开它的获取方式，后面再介绍。接着，在`ChooseBufferSizes` 函数中，会根据这个两个参数，来循环构造 buffer，所有的 buffer 都放到一个 vector 中。这里的 `max_buffer_size_` 对应的就是 `read_size` 参数，默认是 8M；`min_buffer_size_` 对应的是 `min_buffer_size` 参数，默认是 **8K**。代码的主要逻辑就是：

1. 如果待分配字节数（初始就是 range 的 `bytes_to_read_` ）大于 `max_buffer_size_`，则直接分配一个 `max_buffer_size_` 大小的 buffer，加入到 vector 中；如果小于 `max_buffer_size_`，则取待分配字节数和 `min_buffer_size_` 较大的，保证分配的 buffer 不会小于 `min_buffer_size_`；
2. 如果分配的 buffer 总大小超过了 max_bytes 限制，则结束此次分配，也就是说，给 `ScanRange` 一次分配的 buffer 数量，不一定能够保证所有的 `bytes_to_read_`都足够读取，必须小于 max_bytes；

当获取了需要的 buffer 之后，我们根据这些 buffer，构造 BufferDescriptor，更新 ScanRange 的`unused_iomgr_buffer_bytes_` 和 `unused_iomgr_buffers_` 成员。然后 IO thread 就会获取 buffer，进行后续的扫描操作。

### IO thread 处理 `ScanRange` 流程

当 IO thread 获取到 ScanRange 的对象之后，就会进行实际的扫描操作。整个 ScanRange 的处理流程如下所示： 

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/a99b37d1bd46b0ca95d10fe1015af2e8.png?imageView2/2/w/1620)

 这里有几点需要注意：

1. 需要先获取 buffer，才能进行扫描操作，如果没有可用的 buffer，则直接返回，需要 Scanner 线程分配 buffer 之后，才能继续；
2. 如果本次操作完成之后，当前的 `ScanRange` 还没有读完，需要放回 `in_flight_range` 队列，等待再次处理；
3. 保存数据的 buffer，会更新到 ScanRange 的 `ready_buffers_`成员，后续 Scanner 线程会获取 `ready_buffers_` 中的 buffer，进行处理；

### Impala 处理 Parquet 格式文件

接着我们再来看下 Impala 对于 Parquet 格式的文件是如何处理的。这个对于后面 Impala 处理 `ScanRange` 的介绍有一定的帮助。首先简单看下 Parquet 的文件结构：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/36c220a260f72e01adfffc46b381a84b.png?imageView2/2/w/1620)

一个 Parquet 文件主要包括三个部分：header 和 footer 以及中间的数据区，数据区由多个 RowGroup 组成，每个RowGroup 包含一批数据；每个 RowGroup 又分为多个 ColumnChunk，每个 ColumnChunk 表示一个列的数据；ColumnChunk 又包含多个 DataPage，这是[数据存储](https://cloud.tencent.com/product/cdcs?from=10680)的最小单元。 为了读取 Parquet 文件的数据，针对上述文件结构，Impala也设计了相应的类进行处理，如下所示：

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/7ea7407368039f64e9974fdaabaca998.png?imageView2/2/w/1620)

结合上述的UML，我们将处理流程归纳为如下几点：

1. 对于每一个 split，executor 都会构造一个 HdfsParquetScanner（如果是其他的文件格式，则是其他的scanner对象）；
2. HdfsParquetScanner 会根据SQL中涉及列，来构造 ParquetColumnReader，或者是其子类BaseScalarColumnReader，每一个 reader 负责处理一个列的数据；
3. 一个 split，可能会包含多个 RowGroup，Impala 会根据 RowGroup 中的 ColumnChunk 信息，来初始化 BaseScalarColumnReader 中的 ParquetColumnChunkReade r对象，ParquetColumnChunkReader 主要负责从 data pages 中读取数据、解压、数据 buffer 的拷贝等；
4. 在初始化 ParquetColumnChunkReader 的时候，会一并初始化的它的一个成员ParquetPageReader，ParquetPageReader 就是最终实际去读 page headers 和 data pages。

需要注意的是，上面的这些操作，都是在 executor 上，由 Scanner 线程进行处理的，而真正的ScanRange 的扫描操作，是由 IO thread 进行的。

### `in_flight_ranges_` 的出队操作

介绍了一些前置基础知识，接下来我们看下 `in_flight_ranges_` 队列的更新操作。其实在[Impala 3.4 SQL查询之ScanRange详解（四）](https://blog.csdn.net/skyyws/article/details/115770717)一文中，已经有 `in_flight_ranges_` 的出现了，主要是在`RequestContext::GetNextRequestRange` 函数中，先对 `unstarted_scan_ranges_` 进行了出队操作，然后再判断 `in_flight_ranges_` 是否为空，不为空的话直接弹出队头成员，否则直接返回空，相关函数如下：

```c++
  if (request_disk_state->in_flight_ranges()->empty()) {
    // There are no inflight ranges, nothing to do.
    request_disk_state->DecrementDiskThread(request_lock, this);
    return nullptr;
  }
  DCHECK_GT(request_disk_state->num_remaining_ranges(), 0);
  RequestRange* range = request_disk_state->in_flight_ranges()->Dequeue();
  DCHECK(range != nullptr);
```

因此，我们可以知道，IO thread 实际每次是取 `in_flight_ranges_` 队列的队首成员返回进行处理的。出队操作比较简单，入队操作相对比较复杂。

### `in_flight_ranges_` 的入队操作

关于 `in_flight_ranges_` 的入队操作，涉及到的情况比较多，因此我们将相关的代码调用整理成了一张图，如下所示： 

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/960c02603b5da617c65d55b80470268d.png?imageView2/2/w/1620)

图中每个方框表示相应的函数或者函数调用栈，最下面的方框就是最终的 `in_flight_ranges_` 的入队。黄色方框表示的是，当满足该条件时，才会插入到 `in_flight_ranges_` 队列。下面我们就结合代码来看看不同场景下，`in_flight_ranges_` 的入队操作。

##### Footer ScanRange 的处理

在[Impala 3.4 SQL查询之ScanRange详解（四）](https://blog.csdn.net/skyyws/article/details/115770717)一文中，我们提到过：对于parquet格式的文件，会针对每个split（一个文件的一个block，会对应一个HdfsFileSplit），构造一个footer ScanRange，大小是100KB，并且保存着原始的split信息，主要是offset、len等。这些footer ScanRange会先被入队到unstarted_scan_ranges_队列中，然后在RequestContext::GetNextUnstartedRange()函数中出队，那么在这里就是通过图中的第二条路径：

```c++
StartNextScanRange(hdfs-scan-node-base.cc):679
-GetNextUnstartedRange(request-context.cc):467
```

上面处理会将footer ScanRange从unstarted_scan_ranges_队列弹出，然后由于该ScanRange的tag是NO_BUFFER，所以不会直接入队到in_flight_ranges_中，而是经由第三条路径中处理，通过scanner线程加入到in_flight_ranges_队列中。关于ScanRange::ExternalBufferTag::NO_BUFFER我们后面会再提到，这里先不展开。为了防止大家混淆，我们将第三条路径单独拎出来，如下所示：

```c++
ScannerThread(hdfs-scan-node.cc):403
-StartNextScanRange(hdfs-scan-node-base.cc):692
--AllocateBuffersForRange(disk-io-mgr.cc):399
---AddUnusedBuffers(scan-range.cc):147
----ScheduleScanRange(request-context.cc):797
-----state.in_flight_ranges()->Enqueue(range)
```

首先需要先对这些ScanRange分配buffer，然后再将这个ScanRange加入到in_flight_ranges_队列中。对照上面的ScanRange分配buffer的逻辑来看，scan_range_len参数对应初始的footer ScanRange大小，是100KB，而max_bytes参数的大小，来自于FE端的计算，表示处理一个ScanRange需要的最小内存，以HdfsScanNode为例，相关函数调用如下所示：

```c++
doCreateExecRequest(Frontend.java):1600
-getPlannedExecRequest(Frontend.java):1734
--createExecRequest(Frontend.java):1420
---computeResourceReqs(Planner.java):435
----computeResourceProfile(PlanFragment.java):263
-----computeRuntimeFilterResources(PlanFragment.java):327
------computeNodeResourceProfile(HdfsScanNode.java):1609
-------computeMinMemReservation(HdfsScanNode.java)
```

最终，在computeMinMemReservation函数中，会计算出一个值，通过TBackendResourceProfile结构体的min_reservation成员保存，并传到BE端。一般情况下，这个值是大于100KB的，因此，对于footer ScanRange，处理之后会分配1个buffer，大小是128KB（通过函数BitUtil::RoundUpToPowerOfTwo()向上取到2的整数次幂），最后将footer ScanRange加到in_flight_ranges_队列。之后IO thread就可以通过in_flight_ranges_队列取到这些footer ScanRange，根据上面的ScanRange处理流程进行处理。也就是说，对于每一个split，都会先构造一个footer ScanRange，该footer ScanRange处理完成之后，才能继续进行后面的数据扫描处理。

#### 数据 `ScanRange` 的处理

前面我们提到了对于每个 Split，Impala 都会构造一个 footer `ScanRange`。只有先解析出 footer 的信息，我们才能知道 Parquet 文件的元数据信息，进而构造数据的`ScanRange`，扫描真正的数据。我们将数据 ScanRange 的处理流程进行了梳理，如下所示： 

![img](https://ask.qcloudimg.com/http-save/yehe-8327180/6a892710d990e8c14cbc76d53a76cbaa.png?imageView2/2/w/1620)

 整个处理流程同样是通过 Scanner 线程进行处理的，主要分为如下几个部分：

1. 最左边红色的方框，就是 Scanner 线程读取footer ScanRange的buffer中的元数据信息。通过`ScanRange::GetNext` 函数，就可以获取 ready_buffers_ 中的 buffer 成员，进行后续的解析操作。需要注意的是，此时 footer ScanRange 是已经被 IO thead 处理完成，如果没有处理完成的话，Scanner 线程会一直等待。
2. 中间蓝色的方框，就是HdfsParquetScanner在获取到元数据之后，构造相应的 Column reader 成员，这里主要就是根据 SQL 中涉及到的 column 进行构造，详细构造过程不展开；
3. 左下角黄色的方框，就是计算每个 ScanRange 分配的最大字节数，也就是我们在上面提到的 max_bytes。最终，在给 ScanRange 分配 buffer 的时候，分配的总字节数不会超过这个 max_bytes。这个地方的计算与column reader包含的ScanRange的bytes_to_read_以及read_size和min_buffer_size参数有关系，核心实现逻辑在HdfsParquetScanner::DivideReservationBetweenColumnsHelper函数中，这块的计算也相对比较复杂，感兴趣的同学可以自行学习；
4. 最后是右边的绿色方框，就是根据这些column reader构造对应的data ScanRange，然后分配buffer，并添加到in_flight_ranges_队列。此时IO thread就可以获取这些data ScanRange进行实际的scan操作了。

整个data ScanRange的处理流程就in_flight_ranges_队列图的第四条路径，也就是最右边的那个绿色方框。需要注意的是，如果分配给ScanRange的buffer不能一次读完所有的字节数，那么当IO thread用完分配的buffer之后，scanner线程会重新分配buffer，等待后续IO thead再次处理。

#### IO thread  的处理

最左边的红色方框代表的路径表示：IO thread在处理完对应的ScanRange时，会更新相应的bytes_read、unused_iomgr_buffers_等成员。处理完成之后，会判断当前这个ScanRange是否处理完成，如果处理完成的话，则直接将num_remaining_ranges_成员减1，表示这个ScanRange已经处理完成。如果处理的结果是ReadOutcome::SUCCESS_NO_EOSR，则表示这个ScanRange还没有处理完成，会将这个ScanRange再次放回到in_flight_ranges_队列。这样其他的IO thread可以再次获取这个ScanRange进行处理。

#### 非ExternalBufferTag::NO_BUFFER

对于图中的第二条路径，主要是针对非remote HDFS的情况。在[Impala 3.4 SQL查询之ScanRange详解（四）](https://blog.csdn.net/skyyws/article/details/115770717)中介绍BE端的ScanRange的时候，我们提到会根据FE端的文件信息来构造ScanRange，此时会构造一个buffer tag，如下所示：

```javascript
// HdfsScanNodeBase::Prepare()
    int cache_options = BufferOpts::NO_CACHING;
    if (params.__isset.try_hdfs_cache && params.try_hdfs_cache) {
      cache_options |= BufferOpts::USE_HDFS_CACHE;
    }
    if ((!expected_local || FLAGS_always_use_data_cache) && !IsDataCacheDisabled()) {
      cache_options |= BufferOpts::USE_DATA_CACHE;
    }
```

对于 Remote HDFS，这里最终 `cache_options` 的值就是 4，即 `NO_CACHING | USE_DATA_CACHE` 。接着在 `RequestContext::GetNextUnstartedRange` 函数中，会使用该 tag 进行判断，如下所示：

``` c++
// RequestContext::GetNextUnstartedRange()
      ScanRange::ExternalBufferTag buffer_tag = (*range)->external_buffer_tag();
      if (buffer_tag == ScanRange::ExternalBufferTag::NO_BUFFER) {
        // We can't schedule this range until the client gives us buffers. The context
        // must be rescheduled regardless to ensure that 'next_scan_range_to_start' is
        // refilled.
        disk_states_[disk_id].ScheduleContext(lock, this, disk_id);
        (*range)->SetBlockedOnBuffer();
        *needs_buffers = true;
      } else {
        ScheduleScanRange(lock, *range);
      }
```

只有当  tag  不是 `NO_BUFFER` 的时候，才会将 ScanRange  加入 `in_flight_ranges_` 队列。也就是说，对于  Remote HDFS  的扫描操作，不是直接将 ScanRange 加入到 `in_flight_ranges_` 队列，而是在其他的地方进行处理。由于笔者手头的测试环境都是 Remote HDFS，因此目前暂不展开说明这种情况。

### 小结

到这里，关于 `in_flight_ranges_` 队列的更新，我们就基本介绍完毕了，当然这不是全部的情况，目前还有一些其他的情况我们没有展示在这篇文章当中。由于篇幅原因，本文也省略了很多细节的地方。总结一下，在这篇文章当中，我们首先介绍了 ScanRange 分配 buffer，也就是说对于每个 ScanRange，都需要先通过 Scanner 线程来分配 buffer，之后才能通过 IO thread 进行实际的扫描操作。接着，我们介绍了 IO thread 处理  `ScanRange` 流程和 Impala 处理 Parquet 格式文件。最后我们看到 `in_flight_ranges_` 队列是如何更新，最重要的部分就是 footer ScanRange 和数据 ScanRange 的处理，这个 Impala 的 IO 模型比较关键的地方。本文所有的代码都是基于3.4.0 分支，都是笔者个人结合调试结果，分析得出，如有错误，欢迎指正。


## 六

我们在前面几篇文章，从代码处理层面，详细分析了Impala的ScanRange相关知识，包括FE端的处理、parquet文件的处理、IO thread的处理等，涉及到的内容比较多。本文笔者将前几篇文章的内容做了一个汇总，整体看一下Impala的整个ScanRange的处理流程。需要注意的是，我们当前的分析都是基于parquet格式、remote HDFS的场景。我们将整个处理过程汇总到了一张流程图上，如下所示：

![](https://img.inotgo.com/imagesLocal/202202/25/202202250508068341_0.jpg)

### Coordinator处理

首先是左上方的紫色方框，表示的是Coordinator接收客户端发来的SQL请求，然后通过JNI传到FE端进行解析，最终生成分布式的执行信息，发到各个Executor上进行处理。这块的处理其实就是thrfit结构体在BE/FE之间的传输，我们在[Impala 3.4 SQL查询之ScanRange详解（三）](https://blog.csdn.net/skyyws/article/details/115751129)一文中，已经详细描述过了，这里不再赘述。

### Disk Queue与IO thread构造

Executor 有一个 `DiskIoMgr` 类专门用来管理本地磁盘或者远端文件系统上的 IO 相关的操作。`DiskIoMgr` 初始化的时候，会构造一个 `disk_queues_` 集合，集合中的每个成员都是代表一个本地 disk 对应的队列，或者是一种远端文件系统，例如 **Remote HDFS/S3** 等。**同时，每个队列都会绑定指定数量的线程来处理后续的数据扫描**，这些线程就是 IO thead。不同的队列，可以通过参数配置IO thread数量，以 Remote HDFS 为例，对应的参数就是`num_remote_hdfs_io_threads`，默认为 8。我们在 [Impala HDFS_SCAN_NODE之IO threads模型](https://blog.csdn.net/skyyws/article/details/115350188)文章中，有详细介绍过这部分的处理流程。对应流程图中的，就是右上角的第一个蓝色方框。

### RequestContext 处理

当查询计划信息发到executor之后，executor会根据相关信息构造RequestContext对象，然后放到request_contexts_队列当中。一个RequestContext对象，可以简单理解为对一个表的扫描请求的封装。这个executor上所有每个表的扫描请求，都在这个request_contexts_队列中等待处理。
每个RequestContext都会包含一个PerDiskState集合，我们可以根据当前这个RequestContext的disk queue类型，获取到指定的PerDiskState对象，这个PerDiskState就包含了每个disk queue的状态，比如unstarted_scan_ranges_、in_flight_ranges_等。
这些包含关系就对应了流程图中的黄色方框，关于RequestContext和PerDiskState的介绍，在 [mpala HDFS_SCAN_NODE 之 IO threads模型](https://blog.csdn.net/skyyws/article/details/115350188)和[Impala 3.4 SQL查询之ScanRange详解（三）](https://blog.csdn.net/skyyws/article/details/115751129)中都有详细说明。

### Footer ScanRange构造

Executor获取到coordinator发过来的执行计划信息之后，会构造footer ScanRange对象，然后加入到unstarted_scan_ranges队列中，然后准备启动scanner线程进行后续的处理。这个过程就对应流程图中左边的绿色方框。关于footer ScanRange的构造，我们在[Impala 3.4 SQL查询之ScanRange详解（四）](https://blog.csdn.net/skyyws/article/details/115770717)一文中，有详细介绍。

### IO thread 处理

IO线程启动之后，首先会先从request_contexts_队列中获取队首的RequestContext对象，然后获取对应的PerDiskState对象，接着从PerDiskState对象的unstarted_scan_ranges_队列中获取一个ScanRange成员，获取完成之后，IO thread会将该RequestContext对象又放回到request_contexts_队列的尾部。
接着，IO thread会将刚刚获取到的ScanRange对象加入到ready_to_start_ranges_队列中。然后，再从in_flight_ranges_队列的首部获取一个ScanRange对象，这个才是IO thread真正要处理的ScanRange。
从in_flight_ranges_队列获取到ScanRange之后，IO thread就会进行实际的scan操作，操作完成之后，会更新ScanRange的相关信息。然后再判断该ScanRange是否处理完成，如果没有处理完成，则加入到in_flight_ranges_队列尾部；如果已经处理完成，则直接返回。这表示IO thread完成了本次处理，结束之后，继续上述步骤，处理其他的ScanRange，直至结束。
上述的这些流程，我们在[Impala 3.4 SQL查询之ScanRange详解（四）](https://blog.csdn.net/skyyws/article/details/115770717)一文中，有详细的描述。

### Scanner线程处理

当Executor构造完footer ScanRange之后，就会启动scanner线程进行处理，主要就是流程图中的红色方框部分。Scanner线程首先会从ready_to_start_ranges_队列中获取头部的ScanRange进行判断，如果buffer_tag不是NO_BUFFER（以remote HDFS为例），那么会分配buffer，然后加入到in_flight_ranges_。
此时IO thread就可以获取in_flight_ranges_中的ScanRange（这里是footer ScanRange）进行处理。处理完成之后，scanner线程就会根据扫描的数据，解析parquet文件的元数据，进而构造data ScanRange。同样，分配buffer之后，会将这些data ScanRange加入到in_flight_ranges_队列。等待IO thread处理完这些data ScanRange，scanner线程再进行后续处理。关于scanner线程的处理，可以参考[Impala 3.4 SQL查询之ScanRange详解（五）](https://blog.csdn.net/skyyws/article/details/116237150)，有详细的介绍。

### 总结

以上就是整个ScanRange的基本处理流程，这其中比较重要的就是理解IO thread和scanner线程各自负责的功能，当然我们省略了一些实现细节。由于我们这里讨论的是parquet格式，因此我们[Impala 3.4 SQL查询之ScanRange详解（五）](https://blog.csdn.net/skyyws/article/details/116237150)一文中，也详细介绍了Impala对parquet文件的处理，这个在流程图中并没有体现。对于其他的文件格式的处理，我们目前也没有展开。后续有机会，再跟大家一起学习。

# Impala `HDFS_SCAN_NODE` 之 IO threads 模型

本文主要从代码出发，跟大家一起分享下 Impala `HDFS_SCAN_NODE` 中的 IO threads 模型。首先，在 Impala 中，有几个 io threads 相关的配置，通过对这几个参数进行配置，我们就可以增加处理 io 的线程数，相关的几个配置如下所示：

![](https://img-blog.csdnimg.cn/20210331144325103.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3NreXl3cw==,size_16,color_FFFFFF,t_70)

以我们最常见的 hdfs 存储引擎为例，如果 impalad 节点与 datanode 节点在一台机器上，对于 impala 来说，就是可以通过本地的 disk 直接读取数据；如果 impalad 节点与 datanode 在不同的机器上，那么就是远程读取。在我们内部的生产环境，大部分都是这样的情况：有一个公共的 HDFS 集群，业务所有的离线数据都存储在上面，我们需要单独部署一个 Impala 集群，对于 HDFS 集群上的某些数据进行 Ad-hoc 类的多维分析，此时 impala 就是通过远程来读取hdfs的数据，那么将 `num_remote_hdfs_io_threads` 配置项调整的大一些，就可以适当地加快 HDFS 扫描的速度。

在正式开启介绍之前，我们需要知道Impala的scan node模型分为两层：

1. IO threads，这层主要就是通过IO读取远端的hdfs数据，并且返回，通过配置num_remote_hdfs_io_threads参数，就可以调整读取的线程数，值得一提的是，一些谓词可以下推到远端的hdfs，减少扫描返回的数据量；

2. Scanner，当数据从远端的 HDFS 返回之后，会由专门的 scanner 线程进行处理，可能的操作包括：数据解码、cast 计算等。

本文我们主要讲的就是第一层 IO threads， 其他更多的介绍可以参考：Why Impala Scan Node is very slow 中 Tim Armstrong 的回答，这篇 CSDN的 博客也有介绍：[Impala高性能探秘之HDFS数据访问]()。

下面，我们就结合代码来简单看下这个参数是如何起作用的。在 Impala 的 BE 代码中，有一个类专门用来管理 IO 相关的操作，用于访问本地磁盘或者远端的文件系统，即 `DiskIoMgr`。该类有一个`disk_queues_` 成员，这是一个集合，每个成员都代表一个 disk 对应的队列，或者是一种远端文件系统，例如 HDFS/S3 等，如下所示：

```c++
// disk-io-mrg.h
/// Per disk queues. This is static and created once at Init() time.  One queue is
/// allocated for each local disk on the system and for each remote filesystem type.
/// It is indexed by disk id.
std::vector<DiskQueue*> disk_queues_;
```

首先会在构造函数中，对这个变量进行 `resize` 操作，如下所示：

```c++
// disk-io-mrg.cc
disk_queues_.resize(num_local_disks + REMOTE_NUM_DISKS);
```

这里的 `num_local_disks` 指的就是本地磁盘的个数，而 `REMOTE_NUM_DISKS` 就是一个 enum变量，用来控制远端访问的偏移：

```C++
// disk-io-mrg.h
/// "Disk" queue offsets for remote accesses.  Offset 0 corresponds to
/// disk ID (i.e. disk_queue_ index) of num_local_disks().
enum {
    REMOTE_DFS_DISK_OFFSET = 0,
    REMOTE_S3_DISK_OFFSET,
    REMOTE_ADLS_DISK_OFFSET,
    REMOTE_ABFS_DISK_OFFSET,
    REMOTE_OZONE_DISK_OFFSET,
    REMOTE_NUM_DISKS
};
```

所以，impala 将每一种远端的文件系统访问，也当成了一个磁盘，按照上述的 enum 顺序，放到 `disk_queues_` 中，作为一个成员变量。接着在 `Init` 中，会循环对这个 `disk_queues_` 变量进行初始化：

```c++
// disk-io-mrg.cc
for (int i = 0; i < disk_queues_.size(); ++i) {
    disk_queues_[i] = new DiskQueue(i);
    int num_threads_per_disk;
    string device_name;
    if (i == RemoteDfsDiskId()) {
        num_threads_per_disk = FLAGS_num_remote_hdfs_io_threads;
        device_name = "HDFS remote";
    }
}
```

在整个 `for` 循环中，会根据 `id` 来判断是需要对哪一个队列进行操作，这里以 HDFS 为例，id 就是本地磁盘的数量 + HDFS 在 enum 中的 offset：

```c++
  // disk-io-mrg.cc
  /// The disk ID (and therefore disk_queues_ index) used for DFS accesses.
  int RemoteDfsDiskId() const { return num_local_disks() + REMOTE_DFS_DISK_OFFSET; }
```

如果是要访问远端的 HDFS，那么对应的线程数量，即 `num_threads_per_disk`，就是我们通过配置文件指定的 `num_remote_hdfs_io_threads` 的值，默认是 8。表示会启动 8 个线程用于处理远端的 HDFS 访问操作。接着，impala 就会循环创建对应数量的线程：

```c++
// disk-io-mrg.cc
for (int j = 0; j < num_threads_per_disk; ++j) {
    stringstream ss;
    ss << "work-loop(Disk: " << device_name << ", Thread: " << j << ")";
    std::unique_ptr<Thread> t;
    RETURN_IF_ERROR(Thread::Create("disk-io-mgr", ss.str(), &DiskQueue::DiskThreadLoop,
                                   disk_queues_[i], this, &t));
    disk_thread_group_.AddThread(move(t));
}
```

在进行线程创建的时候，将函数 `DiskQueue::DiskThreadLoop` 绑定到了该线程上，该函数就是通过一个 while循环来不断的进行处理，相关的函数调用如下所示：

```
DiskThreadLoop(disk-io-mrg.cc)
-GetNextRequestRange(disk-io-mrg.cc)
--GetNextRequestRange(request-context.cc)
-DoRead(scan-range.cc)/Write(disk-io-mgr.cc)
```

`GetNextRequestRange` 函数就是用来获取当前这个`DiskQueue`（例如远端 HDFS 访问的 queue）的下一个`RequestRange`，来进行具体的 io 操作。`RequestRange` 代表一个文件中的连续字节序列，主要分为：`ScanRange` 和 `WriteRange`。每个 disk 线程一次只能处理一个 `RequestRange`。这里 impala 采用了一个两层的设计，在 `GetNextRequestRange` 中，首先会需要获取一个 `RequestContext` 对象，`RequestContext` 可以理解为一个查询的某个 instance 下的所有 IO 请求集合，可以简单理解为某个表的 `RequestRange` 集合都被封装在一个 `RequestContext` 对象中。获取 `RequestContext` 的代码如下所示：

```c++
*request_context = request_contexts_.front();
request_contexts_.pop_front();
DCHECK(*request_context != nullptr);
```

`request_contexts_` 是一个 `RequestContext` 类型的列表，每一个 `DiskQueue` 都包含了这样一个队列，表示该 `DiskQueue` 上的所有的待处理的 `RequestContext` 列表。这里我们可以简单的理解为每个表的扫描请求，都在这个队列中等待处理。首先会从队列的头部取出一个 `RequestContext`，然后将该对象弹出。该 `DiskQueue` 的其他线程就可以继续处理后续的 `RequestContext` 对象，这样就不会因为当前的 RequestContext 对象处理时间过长，而阻塞了其他的 `RequestContext` 对象处理。关于 `request_contexts_` 队列成员更新，不是本文介绍的重点，只要知道：当提交查询的时候，impalad 会自动进行解析，然后进行封装，最后添加到该队列中即可。在获取到 `RequestContext` 对象之后，我们就可以通过该 `RequestContext` 的 `GetNextRequestRange` 方法获取具体的 `RequestRange` 对象进行实际的扫描操作了。上面的描述可能不太容易理解，我们将上述的各个成员之间的包含关系以及操作流程进行了整理成了一张图，如下所示：

![](https://img-blog.csdnimg.cn/20210331144401259.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3NreXl3cw==,size_16,color_FFFFFF,t_70)

最终获取到了一个 RequestRange 之后，会进行判断，是 READ 还是 WRITE，进行相应地处理。这里我们以 READ 为例，相关函数调用如下所示：

```c++
DiskThreadLoop(disk-io-mrg.cc)
-GetNextRequestRange(disk-io-mrg.cc)
--GetNextRequestRange(request-context.cc)
-DoRead(scan-range.cc)
-ReadDone(request-context.cc)
```

从上面的相关代码，我们可以知道，如果我们将 `num_remote_hdfs_io_threads` 参数配置的更大一些，那么就会有更多的线程并发的通过 `DiskThreadLoop` 获取到 `RequestRange` 进行处理，从而可以在一定程度上提到扫描的速度，进而加快整个查询进程。在 Impala 的 profile 中，对于 HDFS 的 IO theads 的指标，即`AverageHdfsReadThreadConcurrency`，相关介绍如下所示：

![](https://img-blog.csdnimg.cn/2021033114441848.png)

可以简单理解为该 HDFS_SCAN_NODE 有多少个 IO 线程用于处于读写请求操作。所以说，如果线上查询的这个指标很小，那么就要考虑适当调整 num_remote_hdfs_io_threads 这个参数了。与这个指标很相似的是`AverageScannerThreadConcurrency`，这个表示 Scanner 线程的执行数量，与我前面提到的 scan node 两层模型中的 scanner 对应，这个之后再详细介绍。除此之外，还有其他的一些指标，例如 `ScannerIoWaitTime`，表示scanner 等到IO线程的数据就绪的时间，如果这个时间很长，那么说明 IO 线程存在瓶颈。还有很多指标，就不再一一展开描述。我们在线上排查慢查询的时候，这些指标都是非常有用的信息。上面提到了 profile 中的指标信息。另外，在 impala 服务启动之后，我们也可以通过 web页面上的 /thread z页面查看 **disk-io-mgr** 这个组下面的线程信息，就可以看到用于处理远端HDFS读取的线程：

![](https://img-blog.csdnimg.cn/20210331144429621.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3NreXl3cw==,size_16,color_FFFFFF,t_70)

上面的User/Kernel CPU和IO-wait的时间，都是直接从机器上读取的：

```c++
// os-util.h
/// Populates ThreadStats object for a given thread by reading from
/// /proc/<pid>/task/<tid>/stats. Returns OK unless the file cannot be read or is in an
/// unrecognised format, or if the kernel version is not modern enough.
Status GetThreadStats(int64_t tid, ThreadStats* stats);
```

对于每个 disk queue，impala 还绑定了对应的 metric 信息，如下所示：

![4](https://img-blog.csdnimg.cn/20210331144443304.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3NreXl3cw==,size_16,color_FFFFFF,t_70)

这些指标代表的就是读取延时和大小的统计直方图信息。到这里，关于HDFS_SCAN_NODE的IO threads就介绍的差不多了，我们通过代码分析，知道了Impala对于disk以及各种远端dfs的处理，这些都是属于IO threads部分，后续有时间再跟大家一起学习scanner模块的相关知识。本文涉及到的代码分析模块，都是笔者自己根据源码分析解读出来，如有错误，欢迎指正。
