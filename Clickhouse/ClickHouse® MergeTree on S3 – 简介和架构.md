# [ClickHouse® MergeTree on S3 – 简介和架构](https://altinity.com/blog/clickhouse-mergetree-on-s3-intro-and-architecture)

随着 ClickHouse 的日益普及，单个数据库中的分析数据量也在迅速增长。应用程序从 PB 级数据开始逐渐增长的情况屡见不鲜。这引发了如何经济灵活地存储海量数据的问题。

幸运的是，ClickHouse MergeTree 表可以将数据存储在 S3 对象存储上，这不仅价格更便宜，而且不受块存储的大小限制。现在几乎所有公有云都提供兼容 S3 的存储服务。MergeTree 是处理大型表的主力引擎，而对 S3 的支持是其功能的重要扩展。我们在帮助客户有效使用 MergeTree 方面积累了丰富的经验。我们还在与许多其他社区成员一起积极改进 S3 功能。

本系列博文概述了如何管理基于 S3 的 MergeTree 表。第一篇文章介绍了 S3 存储架构以及如何创建使用 S3 的 MergeTree 表。第二篇文章总结了使用 MergeTree 进行对象存储的当前最佳实践。第三篇文章也是最后一篇文章介绍了如何保持 S3 存储的正常运行。具体来说，我们将展示如何清理孤立的 S3 文件，这些文件是由于 ClickHouse 表元数据与 S3 中存储的数据不同步而产生的。

以下示例使用 ClickHouse 官方构建版本 24.3.2.23，该版本运行在 AWS EKS 上，并由 Altinity Kubernetes Operator 为 ClickHouse 版本 0.23.5 管理。示例代码位于此处。您可以将这些实践应用于其他公有云以及在 Kubernetes 之外运行的 ClickHouse 集群。

## S3 支持的 MergeTree 存储概览
让我们从更宏观的角度开始。S3 支持的 MergeTree 表将 MergeTree 文件结构保留在本地存储中，但使用对象存储来存储实际的数据字节。我们将在三种不同情况下回顾其工作原理。

### 在单个 ClickHouse 服务器中使用 S3
MergeTree 表具有以下逻辑结构。在一个命名表中，我们包含多个部分，这些部分是根据分区键拆分的表部分。在每个部分中，我们包含文件，其中包含索引、列值以及有关该部分的描述信息（例如文件校验和）。文件包含实际数据，并存储在本地磁盘上。以下是层次结构的简单示意图。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-01-table-layout.png)

使用 S3 时，字节存储在 S3 文件中，而不是本地。下图简化了 S3 在单副本集群中的工作方式。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-02-single-server.png)

我们将本地文件称为“元数据”，因为它们提供了 MergeTree 数据所在的目录结构和文件名。实际的字节我们称为“数据”。将 MergeTree 数据存储在本地存储中的机制与将数据存储在 S3 中的机制基本相同。这是 S3 支持的 MergeTree 表的一个重要特性。我们将在后面的部分讨论它的优势。

### S3 上使用 ReplicatedMergeTree 表

在 ClickHouse 的生产部署中，部署副本是很常见的。在这种情况下，我们会有多台服务器，每台服务器都有自己的数据副本存储在 S3 中。如下图所示。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-03-replicas.png)

让我们简要了解一下复制过程。当您将数据块插入 MergeTree 表时，ClickHouse 会在本地存储中构建一个或多个包含文件结构（又称元数据）的 MergeTree 部分，以及表信息的实际字节（又称数据）。它还会将该部分记录在 [Zoo]Keeper 中。其他表副本可以查看 Keeper，了解需要获取哪些新部分。它们会联系拥有该部分的副本，下载该部分，并在本地存储该部分的副本。

在 S3 中存储 MergeTree 数据时，该过程的工作方式相同，只是我们需要从 S3 下载数据字节，而不是从本地存储读取。下图展示了部分传输的过程。为了清晰起见，省略了 Keeper。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-04-part-replication.png)

如图所示，复制过程与本地存储的 MergeTree 表几乎完全相同。关键在于，即使每个副本表可能像本例一样写入同一个 S3 bucket，它们在 S3 中都有自己的文件副本。字节位于 S3 中这一事实并不影响获取分块的过程。

### 零拷贝复制

一些读者（以及许多 ClickHouse 用户）经常指出，每个 ClickHouse 副本都将其各自的 MergeTree 文件副本存储在 S3 中是一种浪费。毕竟，它们都指向相同的数据。将每个文件的单个副本存储在 S3 上并让所有副本都指向该文件，岂不是更高效？

确实存在这样的功能，它被称为零拷贝复制。它由 MergeTree 设置控制，该设置会关闭 S3 文件的复制，而是将每个 ClickHouse 服务器指向相同的文件。零拷贝复制目前处于实验阶段。除非您精通 ClickHouse 并了解使用风险，否则 Altinity 不建议您使用它。不过，它已经存在，因此值得了解它的工作原理。零拷贝复制允许多个 ClickHouse 服务器共享 S3 中的相同文件。它的具体实现如下。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-05-zero-copy.png)

它还有一个好处——它使复制速度更快。如果没有零拷贝复制，ClickHouse 必须从 S3 复制文件才能与另一个副本共享，然后再将数据写回新的 S3 文件。零拷贝复制可以避免这种往返开销。

那么，为什么我们不推荐零拷贝复制呢？除了实验性之外，事实证明，多个服务器使用相同的远程文件会带来很大的复杂性。ClickHouse 必须在服务器之间进行协调，以保持所有服务器上 S3 文件的准确引用计数。这包括由 ALTER TABLE FREEZE 等操作生成的特殊情况，这只是众多情况中的一种。目前仍然存在一些 bug，并且还会发现更多。除了有更多方式丢失文件跟踪之外，零拷贝复制还会给 [Zoo]Keeper 带来额外的负载。

除了 bug 之外，还有另一个风险：未来版本可能不再支持零拷贝复制。还有其他设计方法，例如增强 s3_plain 磁盘，例如使其可写。通过在 S3 中整合元数据和数据，或许能更好地解决问题。

据我们所知，成功使用零拷贝复制的团队都有自己的 ClickHouse 贡献者，他们可以评估风险并解决问题。如果您想了解更多信息，请与我们联系。

## 文件名、硬链接和 S3 数据

我们上面提到，MergeTree 以尽可能模拟本地存储的方式访问 S3 存储有很多优势。如果您了解 ClickHouse 内部如何管理 MergeTree 存储，那么这种设计就很有意义了。

ClickHouse 使用 Linux 文件系统硬链接，允许多个文件名引用存储在 inode 中的底层数据。例如，ClickHouse 可以通过创建一个新的文件名，并为其自身创建指向底层表的硬链接，从而即时安全地重命名表。ClickHouse 对冻结表、分离或附加部分以及更改列等操作也使用相同的技巧。借助硬链接，ClickHouse 可以几乎即时地执行许多表重构操作，而无需触及数据。

以下是硬链接的实际示例。假设有两个文件名分别指向某个数据分区（part）中的一个文件及其冻结版本。后者（冻结版本）会在我们执行 `ALTER TABLE FREEZE` 命令时生成，该命令用于创建表数据的快照以用于备份。这两个文件名通过硬链接指向存储在同一 inode 中的相同二进制数据。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-06-local-storage-bytes.png)

上述链接代表同一文件的两个视图：一个位于活动数据库中，另一个位于运行备份时冻结的影子视图中。

**S3 磁盘实现扩展了 MergeTree 本地存储实现，如下图所示。ClickHouse 不是将数据存储在本地存储中，而是存储对 S3 中某个位置的引用**。

![](https://altinity.com/wp-content/uploads/2024/05/MergeTree-S3-07-remote-storage-bytes.png)

采用这种方法，即使表数据位于 S3 中，诸如表重命名之类的操作也“正常”进行。这适用于包括复制在内的所有操作。

缺点是 ClickHouse 依赖存储在本地文件系统上的元数据来识别 S3 文件。如果元数据丢失或与 S3 内容不同步，可能会导致所谓的“孤立”S3 文件。我们将在本系列的[第三篇博文中](https://altinity.com/blog/clickhouse-mergetree-on-s3-keeping-storage-healthy-and-future-work)讨论“孤立”S3 文件。

## 配置基于 S3 存储的 MergeTree 表

## 总结及后续内容

在这篇关于 S3 对象存储上的 MergeTree 表的第一篇文章中，我们展示了 MergeTree 如何管理 S3 文件、如何在 S3 中设置表以及如何跟踪文件的位置。我们还简要讨论了零拷贝复制，这是 ClickHouse 的一项实验性功能，只有当您非常确定自己在做什么时才应该使用。

顺便说一句，这并不是关于 S3 工作原理的唯一文档。您还可以查看以下内容了解更多信息。

- [基于 S3 的 ClickHouse 混合存储的底层工作原理](https://double.cloud/blog/posts/2022/11/how-s3-based-clickhouse-hybrid-storage-works-under-the-hood/) – 由 DoubleCloud 开发主管 Anton Ivashkin 撰写的 S3 MergeTree 内部原理的精彩总结。

- [ClickHouse MergeTree 表文档](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-s3) – 描述了 ClickHouse SQL 语法、存储策略以及许多其他主题。

您还可以阅读代码，如果您想了解实际发生的情况，这总是很有用的。S3 行为的大部分实现位于 [GitHub 上的 ClickHouse Storages 目录中](https://github.com/ClickHouse/ClickHouse/tree/master/src/Storages)。

在下一篇文章中，我们将提供有关设置 S3 存储和管理使用 S3 的 MergeTree 表的实用建议。