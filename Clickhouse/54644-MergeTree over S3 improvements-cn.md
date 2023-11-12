# MergeTree  上云

> 上 HDFS 会有什么问题？

## 背景

对 **MergeTree** 表的对象存储支持已于 2020 年添加到 ClickHouse 中，并从那时起不断发展。Double.Cloud 的文章[**基于 s3 的 ClickHouse 混合存储是如何工作的**](https://double.cloud/blog/posts/2022/11/how-s3-based-clickhouse-hybrid-storage-works-under-the-hood/) 描述了当前实现。我们将使用 S3 作为对象存储的同义词，但它也适用于 GCS 和 Azure blob 存储。

尽管近年来 S3 支持有了显着改善，但当前的实现仍然存在许多问题（另请参见 [[3](https://gist.github.com/filimonov/75360ce79c4a73e6adfab76a3a5705d1)] 和 [[4](https://docs.google.com/document/d/1sltWM2UJnAvtmYK_KMPvrKO9xB7PcHPfWsiOa7MbA14/edit#heading=h.czg4grkvo6gy)]）：

- 数据存储在两个地方：**本地元数据文件**和 **S3 对象**。
- 存储在 S3 中的数据不是独立的，即，如果没有本地元数据数据文件，则无法附加存储在 S3 中的表
- 每次修改都**需要在 2 个不同的非事务性介质之间进行同步**：本地磁盘上的本地元数据文件和存储在对象存储中的数据本身。这会导致一致性问题。
- 由于上述原因，[零拷贝复制](https://clickhouse.com/docs/en/operations/storing-data#zero-copy)也不可靠，并且存在[已知错误](https: //github.com/ClickHouse/ClickHouse/labels/comp-s3)。
- 备份并非易事，因为需要分别备份两个不同的源。

ClickHouse Inc. 使用 [SharedMergeTree 存储引擎](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates) 对此提出了自己的解决方案，但该解决方案不会 以开源形式发布。本文档的目的是提出一种解决方案，使对象存储对 MergeTree 的支持更好，并且可以由开源 ClickHouse 社区在 Apache 2.0 许可下实现。

## 要求

我们认为 S3 上的 MergeTree 应满足以下高级要求：

- 它应该将 MergeTree 表数据（完整或选定的 Part/分区）存储在对象存储中
- 它应该允许从多个**==副本节点==**读取 S3 MergeTree 表
- 它应该允许从多个**==副本节点==**写入 S3 MergeTree 表
- **它应该是独立的**，即所有数据和元数据都应该存储在一个存储桶中
- **它应该在现有 ClickHouse 功能的基础上逐步构建**。
- 解决方案应该与云提供商无关，并且也适用于 GCP 和 Azure（[s3proxy](https://github.com/gaul/s3proxy) 可以用作集成层）。

需要考虑的其他要求：

- <u>==能够在副本之间分发合并==</u>（另请参阅 **worker-replicas** 提案 [复制数据库的副本组 #53620](https://github.com/ClickHouse/ClickHouse/issues/53620)）
- 减少 S3 操作的数量，否则可能会增加不必要的成本。

## 提议

我们建议重点关注两个可以并行执行的工作：

1. 改进基于现有 S3 磁盘设计的零拷贝复制
2. 改进S3数据的存储模型

**我们不需要解决动态分片问题**，这也是 ClickHouse 的 `SharedMergeTree` 的一个功能。

### 1. 改进零拷贝复制

当前零拷贝复制的问题在于，它必须以传统方式管理本地元数据文件的复制，以及对象存储上数据的零拷贝复制。将这两者混合在一个解决方案中很容易出错。为了使零拷贝复制更加稳健，需要将 S3 元数据从本地存储移动到 Keeper。具体方法如下：

- 使元数据存储可配置，允许 S3 元数据存储在本地（为了向后兼容）或 Keeper 中
- 当存储在 Keeper 中时，所有 **Part** 相关的操作应在单个 Keeper 事务中完成，以确保 **Part** 元数据和 S3 同步
- **当 S3 元数据存储在 Keeper 中时，零拷贝复制变得更简单，因为不需要复制**
- 定期对 S3 存储桶进行元数据快照，以便在元数据在本地文件系统和 keeper 中丢失的情况下可以挂载/恢复表
- 允许从本地元数据迁移到 Keeper 元数据。例如。如果配置了 Keeper 元数据，并且 ClickHouse 在没有元数据的情况下启动 - 它可以从本地存储读取并填充 Keeper

由于这可能会增加 Keeper 中存储的数据量，因此还需要实现紧凑的元数据。这也将减少 S3 开销（参见 [5]）

我们可以保留本地存储元数据选项以实现兼容性和单节点操作。另外，由于 Keeper 可以用于嵌入式模式，因此它也可以用于单节点部署，但 ClickHouse 需要更复杂的配置。

### 2. 改进 S3 存储模型上的 MergeTree

当前基于 S3 的 MergeTree 实现由 **S3 磁盘**支持。我们无法在<u>==不打破兼容性的情况==</u>下更改它。从长远来看，还有另一个未记录的 `S3_plain` 磁盘更好。`S3_plain` 磁盘与 S3 磁盘的不同之处在于，它存储数据的结构与本地文件系统完全相同：文件路径与对象路径匹配，因此不需要本地元数据文件。**这具有以下含义**：

- 所有数据都集中在一处，因此易于管理
- `S3_plain` 磁盘可以透明地附加到任何 ClickHouse 实例，因为不需要额外的元数据
- 作为一个附带功能 - `S3_plain` **可以附加到只读节点中的任何 ClickHouse 以用于测试目的（例如版本升级）**
- 与文件系统相比，S3_plain 磁盘的数据修改必须受到限制。特别是一些突变和重命名是不容易完成的。有关兼容性矩阵，请参阅附录 A。
- 备份也更容易实施。例如，甚至可以使用 S3 存储桶版本控制。
- 它打开了通过 S3 数据运行 ClickHouse lambda 的大门

我们建议使用 `S3_plain` 磁盘代替S3，以解决 s3 本地元数据问题。目前 `S3_plain` 磁盘的实现非常有限，需要改进。需要进行以下更改：

**存储**：

- 扩展 ClickHouse 存储模型以与**不支持硬链接的存储**一起使用 - 这些存储可能不支持所有功能，但支持大部分功能。
- 允许在不使用硬链接的情况下执行 MOVE。相反，可以使用一些标志文件来标记完成。这将使 `S3_disk` 可用于冷分区，并且还允许从 S3 磁盘迁移现有数据。
- 实现完全重写 **Part** 的操作：`INSERT`、`MERGE`、`ALTER TABLE DELETE`
- 实现就地添加列/索引，无需硬链接/重命名即可完成
- 实现添加/删除 TTL、MATERIALIZE TTL
- 允许就地重命名列（无需重命名 part）- 可选
- 使用<u>==拷贝或服务器端拷贝==</u>实现 `ALTER TABLE UPDATE`。

**复制**：

- 将 `S3_plain` 与零拷贝复制集成。在这种情况下，Keeper 中的元数据在 ClickHouse 启动期间充当缓存。
- 或者，可以完全删除 S3 元数据。相反，与 Part 对应的 S3 前缀可以直接存储在 Keeper 中已存在的 Part节点中。它简化了复制协议并减少了 Keeper 中的数据量。
- 可以包含在这个[集群文件系统(CFS) 支持零复制#53629](https://github.com/ClickHouse/ClickHouse/pull/53629) – NFS 支持零复制。

该功能应该是通用的，并使用相应的 API 或 s3proxy 应用于其他对象存储类型 ([8])

## 参考

1. https://clickhouse.com/blog/concept-cloud-merge-tree-tables – 云上 MergeTree 表概念
2. [Simplify ReplicatedMergeTree (RFC) #13978](https://github.com/ClickHouse/ClickHouse/issues/13978) – 简化 `ReplicatedMergeTree` (RFC) (Yandex)
3. https://gist.github.com/filimonov/75360ce79c4a73e6adfab76a3a5705d1 – S3 discussion (Altinity)
4. https://docs.google.com/document/d/1sltWM2UJnAvtmYK_KMPvrKO9xB7PcHPfWsiOa7MbA14/edit – S3 Zero Copy replication RFC (Yandex Cloud)
5. [Unite all table metadata files in one #46813](https://github.com/ClickHouse/ClickHouse/issues/46813) – Compact Metadata
6. [Shared metadata storage #48620](https://github.com/ClickHouse/ClickHouse/issues/48620) – `SharedMetadataStorage` 社区需求
7. [Trivial Support For Resharding (RFC) #45766](https://github.com/ClickHouse/ClickHouse/issues/45766) – 对重新分片的简单支持(RFC), in progress by Azat.
8. https://github.com/gaul/s3proxy – s3 API proxy to over clouds, can be used for Azure and GCP
9. [The implementation of shared metadata storage with FoundationDB. #54567](https://github.com/ClickHouse/ClickHouse/pull/54567) – `SharedMetadataStorage` 社区 PR
10. [Replica groups for Replicated databases #53620](https://github.com/ClickHouse/ClickHouse/issues/53620) – 副本组提案


## 附录 A. S3 上不同 MergeTree 实现的功能兼容性

|                               | ** S3** | **S3_plain**                      |
| ----------------------------- | ------- | --------------------------------- |
| metadata                      | 独立    | 组合                              |
| can be restored from S3 only  | no      | yes                               |
| SELECT                        | yes     | yes                               |
| INSERT                        | yes     | yes                               |
| Merges                        | yes     | yes                               |
| ALTER TABLE DELETE            | yes     | yes                               |
| ALTER TABLE UPDATE            | yes     | **may require full data rewrite** |
| Moves                         | yes     | yes                               |
| Adding/removing column        | yes     | **yes, w/o mutation**             |
| Adding/removing index and TTL | yes     | **yes, w/o mutation**             |
| Rename table                  | yes     | yes, table is referenced by uuid  |
| Rename column                 | yes     | **no, may require add/remove**    |
| Lightweight delete            | yes     | **?**                             |

# 基于 s3 的 ClickHouse 混合存储是如何工作的

大家都知道 ClickHouse 处理大量数据的速度非常快。数据集可能达到数十/数百 TB 甚至数百 PB。当然，这些数据需要存储在<u>满足以下核心需求的地方</u>：**成本效益**、**高速**、**可访问性**、**安全性**和**可靠性**。S3 或对象存储是完美的匹配，但它唯一缺乏的关键点是速度。因此，我们构建了一种混合方法，可以融合 SSD 磁盘的速度和 S3 的经济性。

**DoubleCloud 团队在一年前开始开发S3混合存储功能，并于2022年4月18日成功合并到22.3版本中，并在22.8 版本中进行了进一步的修复和优化**。它被社区和 Clickhouse 团队广泛接受，主要是因为现在计算与存储解耦了。

我们发现，在适用混合存储的场景中，存储成本降低了 3-5 倍，这对于日志、指标、trace 或者是用户主要处理新鲜数据的其他场景来说，是一个真正的游戏规则改变者，保持旧的数据只会在在极少数情况下使用。

下面我将描述它幕后的工作原理以及它所基于的原则。

## 保守方法

经典方法是使用分片 ClickHouse 集群。假设数据为 100 TB，每个虚拟机上有 10 TB 的可用存储空间。那么完美的分区需要十个分片，每个分片有两个复制节点。此要求总计为 20 台机器。然而，只有在某些情况下，数据才会均匀分布，因此您可以安全地将该数字乘以 1.5。

另外，当存储没有可用空间时，ClickHouse 的工作效果不佳。对于完全冻结的只读数据，您仍然可以进行管理，但如果新数据定期流入，您必须至少多出 10% 的可用空间才能使其正常工作。

现在我们面临运行30+台机器的需求，这是相当重要的。在这种情况下，大多数虚拟机将仅使用磁盘空间，CPU 和 RAM 几乎闲置。

当然，在某些情况下，请求流量很大，其他资源也会分担负载，但根据我们对具有 10 个以上分片的集群的数据，它们往往会无限期空闲。

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-1.png)

## 另一种方法

ClickHouse可以使用S3兼容的存储。这种方法的优点如下：

- 几乎无限的容量，
- 与具有相同磁盘空间量的专用虚拟机相比，成本显着降低。

主要缺点是 S3 兼容存储是一种网络资源，因此访问数据的速度会增加操作时间。

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-2.png)

让我们看看它是如何工作的。`IDisk` 接口提供了基本文件操作的方法，例如创建、复制、重命名、删除等。ClickHouse 引擎与该接口配合使用。大多数时候，幕后的实现并不重要。具体存储方式有实现：

- 本地磁盘（`DiskLocal`），
- 内存存储（`DiskMemory`），
- 云存储（`DiskObjectStorage`）。

后者实现了在不同类型的存储中存储数据的逻辑，特别是在 S3 中。其他存储是 HDFS 和 MS Azure。它们在概念上很相似，但现在让我们关注 S3。

### 管理 S3 中的数据

当引擎想要在 S3 磁盘上**创建文件**时，它会在 S3 中创建一个具有随机名称的对象，向其写入数据流，并在本地磁盘上创建一个元数据文件，其中包含名称、大小和其他一些信息 。这样的本地元数据文件的大小为数十字节。

**然后，仅对本地元数据文件执行重命名和创建硬链接等操作，而 S3 上的对象保持不变**。

S3 不提供修改已创建 S3 对象的直接方法。例如，重命名操作是**创建新对象的负载密集型过程**。上述带有<u>小型本地元数据文件</u>的方案允许您绕过此限制。

```sql
# aws s3 ls s3://double-cloud-storage-chc8d6h0ehe98li0k4sn/cloud_storage/chc8d6h0ehe98li0k4sn/s1/
2022-11-21 12:32:58      8 bpmwovnptyvtbxrxpaixgnjhgsjfekwd
2022-11-21 12:32:58     80 enmwkqfptmghyxzxhiczjgpkhzsvexgi
2022-11-21 12:32:59     10 mjgumajoilbkcpnvlbbglgajrkvqbpea
2022-11-21 12:32:59      1 aoazgzkryvhceolzichwyprzsmjotkw
2022-11-21 12:32:59      4 xiyltehvfxbkqbnytyjwbsmyafgjscwg
2022-11-21 12:32:59    235 ickdlneqkzcrgpeokcubmkwtyyayukmg
2022-11-21 12:32:59     65 lyggepidqbgyxqwzsfoxltxpbfbehrqy
2022-11-21 12:32:59     60 ytfhoupmfahdakydbfumxxkqgloakanh
2022-11-21 12:32:59      8 tddzrmzildnwtmvescmbkhqzhoxwoqmq
# ls -l /var/lib/clickhouse/disks/object_storage/store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/2_0_0_0/
total 36
-rw-r----- 1 clickhouse clickhouse 120 Nov 21 12:32 checksums.txt
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 columns.txt
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 count.txt
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 data.bin
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 data.mrk3
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 default_compression_codec.txt
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 minmax_key.idx
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 partition.dat
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 primary.idx
# cat /var/lib/clickhouse/disks/object_storage/store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/2_0_0_0/data.mrk3
3                                       # [metadata file format version]
1    80                                 # [objects count] [total size]
80    enmwkqfptmghyxzxhiczjgpkhzsvexgi  # [object size] [object name]
0                                       # [reference count]
0                                       # [readonly flag]
```

一个单独的操作是将数据添加到文件中。如前所述，S3 不允许在创建后更改对象，因此我们创建另一个对象，并在其中添加新的数据部分。这个对象的名称被写入前面提到的元数据文件中，现在元数据开始引用多个对象。

请注意，ClickHouse 中的此类操作仅针对几乎没人使用的 [Log family 引擎](https://clickhouse.com/docs/en/engines/table-engines/log-family/) 执行。在流行的 [MergeTree 引擎](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/) 中，文件创建一次，就不会再次修改。

对于某些操作（例如**==增加新列==**），引擎会创建一个具有新结构的新 **Part**。然而，由于有些数据不会改变，我们使用该操作创建指向旧数据的**硬链接**，而不是复制它们。只有本地元数据文件被链接，我们在其中存储**链接计数器**，该计数器随着此操作而增加。

#### ClickHouse 对 S3 数据操作的限制

当您执行删除时，引擎会减少链接计数并删除本地元数据文件，如果这是指向已删除文件的最后一个硬链接，则可能会删除 S3 中的对象。在讨论复制时，我们将回头来说为什么**只是可能**。

**==ClickHouse 不会在文件中间使用数据替换等操作。因此，它没有实现==**。

我们再详细说明两点。

第一个是 S3 中的对象名称是随机的。这非常不方便，因为从对象本身并不清楚它是什么。我们随后会**谈谈操作日志**，它是一种在某种程度上，允许我们简化事情的机制，但也不完美。

第二点是，在元数据文件中存储硬链接的数量似乎没有必要，因为我们可以从文件系统中获取它。<u>==但如果通过 ClickHouse 手动操作本地文件，可能会破坏链接==</u>。在这种情况下，两个副本都有一个增加的计数器，当删除其中一个副本时，将不允许在 S3 中删除该对象。删除第二个也不会删除它，但最好将垃圾留在 S3 上，这总比丢失所需的数据要好。

当读取本地元数据文件时，它会了解 S3 中的一个或多个对象的名称，并且向 S3 会请求所需的数据部分。**S3 允许您按偏移量和大小下载对象的片段，这很有用**。

#### 缓存

在[最新的ClickHouse版本](https://clickhouse.com/docs/en/whats-new/changelog/)中，我们可以缓存从对象存储下载的数据。<u>==我们可以在写入时使用单独的选项将数据添加到缓存中。当不同的请求访问相同的数据时，它可以加快请求的执行速度==</u>。在一个请求中，不会重复读取相同的数据。此功能内置于引擎中。但是，缓存大小是有限的，因此最佳选择取决于您的情况。

#### 混合存储中的操作日志

> 时间旅行相关的操作？？？

有一个默认的 `send_metadata` 设置，默认情况下禁用。ClickHouse 保留一个操作计数器，该计数器随着文件创建、重命名和硬链接创建的每次操作而递增。

在创建时，以二进制形式将操作号添加到对象名称中，原始文件名写入**S3 元数据**（不要与本地元数据文件混淆，我们这里在术语上有一定的缺陷），并**S3 元数据**添加到对象中。

重命名和硬链接时，会在 S3 中创建一个特殊的小对象，该对象的名称中还包含操作号，该对象的 S3 元数据记录了**重命名**或**创建硬链接**的本地名称。

执行删除时，删除对象后操作计数器不会增加。它允许您恢复本地元数据 - S3 查询包含数据的对象的完整列表。它使您能够使用 S3 元数据恢复原始名称，然后将重命名和硬链接操作应用于现有文件。它是通过在磁盘启动之前创建一个特殊文件来触发的。

这种机制不允许执行所有操作，而只允许执行一些可用于备份的版本。


```sql
# aws s3 ls s3://double-cloud-storage-chc8d6h0ehe98li0k4sn/cloud_storage/chc8d6h0ehe98li0k4sn/s1/
             PRE operations/
2022-11-21 12:32:59      1 .SCHEMA_VERSION
2022-11-21 12:32:58      8 r0000000000000000000000000000000000000000000000000000000000000001-file-bpmwovnptyvtbxrxpaixgnjhgsjfekwd
2022-11-21 12:32:58     80 r0000000000000000000000000000000000000000000000000000000000000010-file-enmwkqfptmghyxzxhiczjgpkhzsvexgi
2022-11-21 12:32:59     10 r0000000000000000000000000000000000000000000000000000000000000011-file-mjgumajoilbkcpnvlbbglgajrkvqbpea
2022-11-21 12:32:59      1 r0000000000000000000000000000000000000000000000000000000000000100-file-aaoazgzkryvhceolzichwyprzsmjotkw
2022-11-21 12:32:59      4 r0000000000000000000000000000000000000000000000000000000000000101-file-xiyltehvfxbkqbnytyjwbsmyafgjscwg
2022-11-21 12:32:59    235 r0000000000000000000000000000000000000000000000000000000000000110-file-ickdlneqkzcrgpeokcubmkwtyyayukmg
2022-11-21 12:32:59     65 r0000000000000000000000000000000000000000000000000000000000000111-file-lyggepidqbgyxqwzsfoxltxpbfbehrqy
2022-11-21 12:32:59     60 r0000000000000000000000000000000000000000000000000000000000001000-file-ytfhoupmfahdakydbfumxxkqgloakanh
2022-11-21 12:32:59      8 r0000000000000000000000000000000000000000000000000000000000001001-file-tddzrmzildnwtmvescmbkhqzhoxwoqmq
```

```sql
# aws s3api head-object --bucket double-cloud-storage-chc8d6h0ehe98li0k4sn --key cloud_storage/chc8d6h0ehe98li0k4sn/s1/r0000000000000000000000000000000000000000000000000000000000000010-file-enmwkqfptmghyxzxhiczjgpkhzsvexgi
{
  "AcceptRanges": "bytes",
  "LastModified": "Mon, 21 Nov 2022 12:32:58 GMT",
  "ContentLength": 80,
  "ETag": "\"fbc2bf6ed653c03001977f21a1416ace\"",
  "ContentType": "binary/octet-stream",
  "Metadata": {
      "path": "store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/moving/2_0_0_0/data.mrk3"
  }
}
```

```sql
# aws s3 ls s3://double-cloud-storage-chc8d6h0ehe98li0k4sn/cloud_storage/chc8d6h0ehe98li0k4sn/s1/operations/
2022-11-21 12:33:02      1 r0000000000000000000000000000000000000000000000000000000000000001-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
2022-11-21 12:33:02      1 r0000000000000000000000000000000000000000000000000000000000000010-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
2022-11-21 12:32:59      1 r0000000000000000000000000000000000000000000000000000000000001010-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
```

```sql
# aws s3api head-object --bucket double-cloud-storage-chc8d6h0ehe98li0k4sn --key cloud_storage/chc8d6h0ehe98li0k4sn/s1/operations/r0000000000000000000000000000000000000000000000000000000000001010-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
{
  "AcceptRanges": "bytes",
  "LastModified": "Mon, 21 Nov 2022 12:32:59 GMT",
  "ContentLength": 1,
  "ETag": "\"cfcd208495d565ef66e7dff9f98764da\"",
  "ContentType": "binary/octet-stream",
  "Metadata": {
      "to_path": "store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/2_0_0_0/",
      "from_path": "store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/moving/2_0_0_0"
  }
}
```

#### 备份

> TODO

### 混合存储

更好的解决方案是混合存储。混合存储使用一对磁盘：本地磁盘和 S3。**新数据存储在本地磁盘上，合并为大的部分，然后这些不希望进一步合并的部分被发送到 S3**。这种情况下，本地数据的访问速度会更高，而且这种方式大多数情况下结合了本地磁盘的性能和云存储的容量。您可以配置这种数据移动：

- 按数据年龄（[TTL MOVE TO …](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/)），
- 按本地磁盘上的可用空间量 ([move_factor](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/))，
- 人工移动数据（[ALTER TABLE MOVE PARTITION](https://clickhouse.com/docs/en/sql-reference/statements/alter/partition/)）。

应选择按时间设置移动，以考虑数据流的均匀性，以便在数据仍在本地盘时发生主要的合并。另一件需要考虑的事情是读取数据的需要：从本地盘读取通常会快得多。因此，将冷数据传输到预计访问频率较低的 S3 是有意义的。最好不要单独依赖**本地磁盘可用空间**的配置来移动数据，因为可能会移动常用的热数据，从而降低性能。

但是，请注意除了总限制之外，没有特殊机制可以专门减少 S3 上的合并数量。因此，如果将新数据添加到已位于 S3 中的旧分区，则合并操作将涉及下载和上传。为了减少合并次数，可以使用 [`maxBytesToMergeAtMaxSpaceInPool`](https://double.cloud/docs/en/managed-clickhouse/settings-reference#maxbytestomergeatmaxspaceinpool) 设置，该设置限制最大块大小，但它适用于包含表数据的所有磁盘，包括本地磁盘。

此外，使用多个磁盘的机制并不局限于这种情况。例如，您可以拥有一个小型、快速的 SSD 磁盘和一个较大但速度较慢的 HDD，甚至可以组织一个多层级的方案，最后使用云存储。

### 复制

默认情况下，S3 使用与本地磁盘相同的复制机制：

1. 新数据写入任意节点，新部分的信息放入ZooKeeper/ClickHouse Keeper（为了方便，我们将两者简称为 Keeper）
2. 其他节点从 Keeper 处了解到这一点
3. 他们访问该数据所在的节点并从该节点下载数据（Fetch 操作）。

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-3.png)

**==对于 S3，序列如下==**：

1. 第一个节点从S3下载 **part**
2. 第二个节点从第一个节点下载 **part**
3. 第二个节点将 **part** 上传到S3。

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-4.png)

### 零拷贝复制

可以通过启用零拷贝复制机制（[allowRemoteFsZeroCopyReplication](https://double.cloud/docs/en/management-clickhouse/settings-reference) 设置）来避免这种情况。

通常，节点共享相同的 S3。当第二个节点向第一个节点请求数据时，第一个节点仅发送一小部分本地元数据。第二个节点检查它是否可以从该元数据中获取数据（事实上，它只请求一个对象的存在）； 如果存在，它会存储此元数据并将 S3 对象与第一个对象一起使用。如果**没有访问**（不同的 S3 存储桶或存储），则会采用保守方法进行数据的完整复制。

这种带有可访问性测试的机制使得移动到另一个对象存储成为可能，例如，使用 S3-A 的另外两个副本被添加到 S3-B，它们通过完全复制将数据复制到自己，并且每一对共享其 S3 中的对象。

对于零拷贝，每个副本在 Keeper 中额外标记它在 S3 中使用的部分，当从节点中删除最后一个硬链接时，它检查是否有其他人使用该数据，如果使用了，则不会触及S3中的对象。

这就是我们前面提到的**S3 上的对象可能会被删除**的情况。

#### 零拷贝限制和问题

零拷贝机制尚未达到生产质量； 有时会有错误。最新的一个已经在最近版本中修复了的例子是**修改期间**双重复制的情况。

当一个节点创建零件时，会发生以下情况：

1. 第二个节点复制它，
2. 在该 part 上运行修改，产生一个与原始数据硬链接的新 part，
3. 第二个节点复制新的 part。

同时，第二个节点对这些 part 之间的连接一无所知。

如果第一个节点之前删除了旧部分，则删除时的第二个节点将决定删除对象的最后一个本地链接。结果，它会从 Keeper 得到信息，没有其他人使用这部分的对象，因此，它会删除 S3 中的对象。

如上所述，这个错误已经被修复，并且我们长期以来一直在我们的解决方案中使用零拷贝。

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-5.png)

## 最后的想法

我们还看到该社区已经开始添加其他对象存储提供程序，例如由 Content Square 的朋友开发的 [Azure blob storage 开发](https://github.com/ClickHouse/ClickHouse/issues/29430)，这再次向我们展示了 我们正朝着正确的方向前进。

关于 DoubleCloud 上该功能的可用性的小说明。DoubleCloud 的所有集群默认都已经拥有基于 S3 的混合存储； 您不需要配置或设置任何额外的内容。[只需使用您首选的混合存储配置文件创建一个表](https://double.cloud/docs/en/management-clickhouse/step-by-step/use-hybrid-storage)，即可开始使用。

[联系我们的架构师](mailto:viktor@double.cloud)了解如何将此方法应用于您的项目，或者即使您正在寻求设置和使用该功能的帮助并希望与我们聊天。

ClickHouse® 是 ClickHouse, Inc. 的商标。[https://clickhouse.com](https://clickhouse.com/)

# 将 ClickHouse 与 S3 结合使用

## 为什么选择 S3

* 存储成本
* 可扩展性
* 耐用性

但

* 延迟
* 运营成本
* 性能
* 一致性（覆盖和删除是最终一致的）
* 更复杂（和本地磁盘相比）
* 无硬链接/重命名（在 ClickHouse 中大量使用）
* 各种实现（aws、gcs、azure、minio、ceph 等）

## ClickHouse 中 S3 支持的状态

ClickHouse 中 S3 支持的不同模式：

* s3 磁盘（支持所有操作，**元数据存放在本地磁盘**，<u>存储桶存储**具有随机名称**的对象</u>），需要额外的“状态”来读取 s3（来自本地磁盘的元数据）+ Zookeeper 中的正常副本状态
* **s3plain** 磁盘 - <u>**==存储桶存储文件的方式与存储在磁盘上的方式完全相同==**</u>，目前是**只能写入一次**（使用备份到 s3）
* s3 表引擎/表函数  - 可以从 s3 存储桶中读取各种格式的数据，支持 ==glob？？==
* s3 Cluster - 与上面相同，当读取大量文件时（使用全局选择器） - 将在不同节点之间分发不同的文件
   （单个文件无法扩展）
* 备份

最近的开发相当活跃，变化很多，很多新设置等等。**没有经过很好的测试**。

## 谁需要 S3？

**中小型用户真的需要 S3 吗**？

==使用 S3 的好处==主要用于备份或存档。块设备 (EBS) 通常更快/更便宜。

**大型用户真的需要 S3 吗**？
这可以带来显着的好处。但通常最好将活动数据集放在本地磁盘上。因此，如果他们使用 S3 作为主存储，他们可能仍然希望拥有一些本地缓存。<u>相反，可以使用分层存储（热数据位于本地磁盘上，冷数据位于 S3 ）。这样就不用担心缓存的问题，而且S3的成本也更低</u>。

**存算分离？**

选择：

1. s3 磁盘+零拷贝复制（+  `TTL MOVE` 的最终规则）
   - **零拷贝复制**仍然需要在 zookeeper 中创建/维护副本的状态。（不容易扩展/缩小，需要半手动配置/取消配置）。
   - **离线副本需要重新同步其状态**
   - 副本仍然需要一直执行复制队列（只有一些“捷径”来减少流量）
   - **需要始终使用固定分片模式，因此，如果数据是为 3 个分片写入的，则只能使用 3 个节点来处理该数据**。
   - 实验性的，新版本可能会更改，但适用于简单的情况，尚未准备好用于生产环境（？）
   - 元数据存储在本地文件系统上，需要手动备份
   - 所有数据都是实时在线的，并且可以通过单表界面访问。
   - `TTL move` 可用于制作多层系统
2. s3 磁盘+零拷贝复制+并行副本。与上面相同，**但不需要固定分片，因此您可以拥有单个分片**
   - 实验性的，新版本可能会更改
   - 每个副本都可以充当一个分片。
   - 某些查询（JOIN）可能会很棘手
   - 该功能有 3 轮迭代，前 2 个不是很成功，最后一个似乎工作良好（至少对于简单的情况）

3) **将数据卸载到类似 s3 的存储存档，以便以后访问**
   
    - 非实时
    - 要访问存档，您需要使用不同的查询/不同的表
    - 没有自动移动/TTL（因此需要，可能可以实现）
    - 可以使用标准格式（比如 Parquet 等）
    - 也可以实时工作
    
    选择存储格式：
    1) clickhouse 的磁盘格式，通过 **s3plain** 
       - 有标记/索引/元数据
       - Clickhouse 原生
       - 良好的压缩性
       - 范围读取
       - 专有格式（在 Clickhouse 之外不易阅读）
       如何做：`OPTIMIZE TABLE PARTITION ... ; BACKUP old partition to s3_plain disk; ATTACH TABLE`
    2) Parquet
       - 列格式
       - 标准且可以被其他工具使用
       - 良好的压缩性
       - 范围读取
       - 没有 Clickhouse 使用的额外元数据，如标记/索引
       - 不是 clickhouse 原生的，并且 clickhouse 目前无法使用它的所有功能（如索引）
       如何做：`insert into s3(...) select ... WHERE partition;`
    3) ORC：类似于Parquet
    4) JSONEachRow / TSV 等 - 基于行

4. ==无服务器/外部编排 - 使用无状态 clickhouse-local 执行器，由一些额外层或另一个 clickhouse-local 编排==

## 最好解决下列问题：

1. **启动新节点**（新的计算节点 - 当计算和存储分开时） - 非常昂贵（部署 schema  + 复制 + 在zookeeper 中注册等 ）。
2. 存储在本地磁盘上的元数据 - 不可靠（没有复制，难以备份），s3上的数据不是自描述的（没有元数据）
3. **ClickHouse inc.内部使用了一些部分闭源的解决方案。对于 p.1，他们可以反对接受同样的替代社区实现**。
4. s3 不是一个文件系统 - 大多数重命名和硬链接都是有问题的，这在 ClickHouse 中被大量使用
   1. 更改/突变/合并/移动等问题。
   2. 分布式硬链接/引用计数
5. 成本与性能 - s3 api 调用成本与 s3 性能
6. 最近有很多变化和改进，有一些新的/深奥的设置：需要大量的测试。
7. 非常嘈杂的日志
8. 备份
9. 更好（原子性）卸载不可变数据

最好做：

1. 大规模测试

2. 通过支持动态集群，**测试/改进 s3cluster（针对无服务器）**

3. s3 用于可变/热数据：测试/考虑改进（也许更密集地使用 keeper？Mike Kot 将致力于此）

4. s3 plain：扩展用法以使其可写 - 它应该支持简单插入，简单合并，简单移动（但没有**==修改==**/在表之间移动数据等）

   1. 避免文件夹重命名（使用文件标记代替）

      目前在许多情况下，写入时会发生重命名：**移动**：part -> tmp_clone（长时运行）和 tmp_clone -> part（目标磁盘）

      我们可以使用一些文件标记：正（part 已准备好）或负（part 未准备好）

   2. ~~抱怨尝试**使用硬链接**，测试基本场景来测试会抱怨什么~~。

5. 测试多层设置的不同方法，其中包括 s3plain

   1. 在普通（可变）MergeTree 表中有 s3plain

      1. 不可变/“冷”/“休息”分区 - 所有突变都会自动工作“IN PARTITION <可变分区集>”
      2. 设置标记？ 或者通过磁盘功能？ 因此，当至少一部分位于不可变磁盘上时，分区自动不可变
      3. 使用缓存层进行测试
      4. 使用普通 TTL 规则移动到不可变分区
      5. 合并到另一个磁盘

   2. 在单独的表中包含 s3plain 数据（或其他格式的数据，如 Parquet ）

      1. s3plain表+通常的MergeTree表+engine=Merge

         events_local 引擎=MergeTree

         events_cold 引擎=MergeTree 设置磁盘 = 磁盘(s3plain,...)

         events_full 引擎=合并

         如何原子移动？

      2. s3plain 表 + 引擎=S3(Parquet) + 引擎=合并

6. 改进 Parquet，以使用索引/分区/谓词下推/虚拟投影（如计数）

7. 测试 s3 的加密

8. 分析/优化 s3 api 调用（批处理、并行性、缓存、重试等）- 降低成本

# ClickHouse Cloud 通过 SharedMergeTree 和轻量级更新提高性能

## 介绍
ClickHouse 是用于实时应用和分析中，速度最快、资源效率最高的数据库。**MergeTree 表引擎**家族中的表是 ClickHouse 快速数据处理能力的核心组件。本文，我们描述该家族新成员——`SharedMergeTree` 表引擎背后的动机和机制。

该表引擎是 [ClickHouse Cloud](https://clickhouse.com/cloud) 中 `ReplicatedMergeTree` 表引擎更高效的直接替代品，它是为云原生数据处理而设计和优化的。我们深入了解这个新表引擎的内部结构，解释其优点，并通过基准测试展示其效率。我们还有一件事要告诉你。我们正在引入轻量级更新，它与 `SharedMergeTree` 具有协同效应。

## MergeTree表引擎是ClickHouse的核心

MergeTree 系列的表引擎是 ClickHouse 中的主要[表引擎](https://clickhouse.com/docs/en/engines/table-engines)。它们负责存储**插入查询**接收到的数据、在**后台合并该数据**、应用特定于引擎的数据转换等等。通过基于 `ReplicatedMergeTree` 表引擎的复制机制，MergeTree 系列中的大多数表都支持自动[数据复制](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication) 。

在传统的 [shared-nothing](https://en.wikipedia.org/wiki/Shared-nothing_architecture) ClickHouse [集群](https://clickhouse.com/company/events/scaling-clickhouse)中，通过 `ReplicatedMergeTree` 进行复制是用于数据可用性，[分片](https://clickhouse.com/docs/en/architecture/horizontal-scaling)用于集群扩展。[ClickHouse Cloud](https://clickhouse.com/cloud) 采用了一种新的方法来构建基于 ClickHouse 的云原生数据库服务，我们将在下面对此进行描述。

## ClickHouse Cloud登场

ClickHouse Cloud 于 2022 年 10 月[进入](https://clickhouse.com/blog/clickhouse-cloud-public-beta)公开测试版，具有完全不同的[架构](https://clickhouse.com/docs/en/cloud/reference/architecture)针对云进行了优化（我们[解释](https://clickhouse.com/blog/building-clickhouse-cloud-from-scratch-in-a-year)了如何用一年从头开始构建它）。通过将数据存储在几乎无限[共享](https://en.wikipedia.org/wiki/Shared-disk_architecture)的[对象存储](https://en.wikipedia.org/wiki/Object_storage)中，存储和计算是分离的：所有[水平](https://en.wikipedia.org/wiki/Scalability#Horizontal_or_scale_out)和[垂直](https://en.wikipedia.org/wiki/Scalability#Vertical_or_scale_up)扩展的 ClickHouse 服务器都可以访问相同的物理数据，并且实际上是单个无限[分片](https://clickhouse.com/docs/en/architecture/horizontal-scaling#shard)的多个副本：
![smt_01.png](https://clickhouse.com/uploads/smt_01_d28f858be6.png)

### 共享对象存储以实现数据可用性

由于 ClickHouse Cloud 将所有数据存储在共享对象存储中，因此无需在不同服务器上显式创建数据的物理副本。对象存储的实现，例如 Amazon AWS [简单存储服务](https://aws.amazon.com/s3/)、Google GCP [云存储](https://cloud.google.com/storage) 和 Microsoft Azure [Blob 存储](https://azure.microsoft.com/en-us/products/storage/blobs/) 确保<u>存储具有高可用性和容错能力</u>。

请注意，ClickHouse Cloud 服务具有多层 [read-through](https://en.wiktionary.org/wiki/read-through) 和 [write-through](https://en.wikipedia.org/wiki/Cache_(computing)#WRITE-THROUGH) 缓存（在本地 [NVM](https://en.wikipedia.org/wiki/Non-volatile_memory)e SSD 上），在对象存储之上，用于本机工作，尽管底层主数据存储的访问延迟较慢，但仍能快速获得分析查询结果。对象存储表现出**较慢的访问延迟**，但提供**高并发吞吐量**和**大聚合带宽**。ClickHouse Cloud 通过[利用](https://clickhouse.com/docs/knowledgebase/async_vs_optimize_read_in_order#asynchronous-data-reading)多个 I/O 线程来访问对象存储数据，并通过异步[预取](https:// /clickhouse.com/docs/en/whats-new/cloud#performance-and-reliability-3)数据。

### 自动集群扩展

**ClickHouse Cloud 不使用分片来扩展集群大小**，而是在共享和几乎无限的对象存储上，允许用户简单地增加运行的服务器的数量，或者向上扩展服务器。这增加了 `INSERT` 和 `SELECT` 查询数据处理的并行性。

请注意，ClickHouse 云服务器实际上是**单个无限分片**的多个副本，但它们与无共享集群中的副本服务器不同。这些服务器不包含相同数据的本地副本，而是可以访问共享对象存储中存储的相同数据。这将这些服务器分别变成动态计算单元或计算节点，其大小和数量可以轻松适应工作负载。手动或完全[自动](https://clickhouse.com/docs/en/cloud/reference/architecture#compute)。我们用下图解释

![smt_02.png](https://clickhouse.com/uploads/smt_02_a2d0b54be6.png)①通过放大和②缩小操作，我们可以改变一个节点的大小（CPU核心和RAM的数量) 。而根据③的横向扩展，我们可以增加参与并行数据处理的节点数量。无需对数据进行任何物理重新分片或重新平衡，我们就可以自由添加或删除节点。

对于这种集群扩展方法，ClickHouse Cloud 需要一个表引擎来支持更多数量的服务器访问相同的共享数据。

## 在 ClickHouse Cloud 中运行 ReplicatedMergeTree 的挑战

`ReplicatedMergeTree` 表引擎并不适合 ClickHouse Cloud 的预期架构，因为它的复制机制被设计为在少量副本服务器上创建数据的物理副本。而 ClickHouse Cloud 则需要一个支持共享对象存储之上大量服务器的引擎。

### 不需要显式数据复制

我们简单解释一下 `ReplicatedMergeTree` 表引擎的复制机制。该引擎使用 [ClickHouse Keeper](https://clickhouse.com/docs/en/guides/sre/keeper/clickhouse-keeper)（也称为**Keeper**）作为通过[复制日志](https://youtu.be/vBjCJtw_Ei0?t=1150)进行数据复制的协调系统。Keeper 充当复制特定元数据和表模式的中央存储，并充当分布式操作的[共识](https://en.wikipedia.org/wiki/Consensus_(computer_science))系统。Keeper 确保按照 Part 名称的顺序分配连续的块编号。到特定副本服务器[合并](https://clickhouse.com/blog/asynchronous-data-inserts-in-clickhouse#data-needs-to-be-batched-for-optimal-performance)和 [mutations](https:// /clickhouse.com/docs/en/sql-reference/statements/alter#mutations) 是通过 Keeper 提供的共识机制实现。

下图描绘了一个具有 3 个副本服务器的无共享 ClickHouse 集群，并展示了 `ReplicatedMergeTree` 表引擎的数据复制机制：

![smt_03.png](https://clickhouse.com/uploads/smt_03_21a5b48f65.png)

当 ① **server-1** 收到一个插入查询时，然后 ② **server-1** 在其本地磁盘上，使用插入查询的数据创建一个新的数据 [Part](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#mergetree-data-storage)。③ 通过复制日志，其他服务器（server-2、server-3）获知server-1 上存在新 Part。在 ④ 处，其他服务器独立地将部分从 server-1 下载（**获取**)到它们自己的本地文件系统。创建或接收 Part 后，三台服务器还会更新自己的元数据，描述其在 Keeper 中的 Part 集。

请注意，我们仅展示了如何复制新创建的 Part。Part 合并（和 mutations）以类似的方式复制。如果一台服务器决定合并一组 Part，那么其他服务器将自动在其本地 Part 副本上执行相同的合并操作（或者只是[下载](https://clickhouse.com/docs/en/operations/settings/merge-tree-settings#always_fetch_merged_part) 合并的 Part)。

如果本地存储完全丢失或添加新副本，`ReplicatedMergeTree` 会从现有副本克隆数据。ClickHouse Cloud 使用持久共享对象存储来实现数据可用性，并且不需要 `ReplicatedMergeTree` 的显式数据复制。

### 集群扩展不需要分片

无共享 ClickHouse [集群](https://clickhouse.com/company/events/scaling-clickhouse)的用户可以将复制与[分片](https://clickhouse.com/docs/en/architecture/horizontal-scaling)结合使用，以通过更多服务器处理更大的数据集。表数据以[分片](https://clickhouse.com/docs/en/architecture/horizontal-scaling#shard)的形式分布在多个服务器上（表数据的不同子集），每个分片通常有 2 或 3 个副本以确保存储和数据可用性。通过添加更多分片可以提高数据摄取和查询处理的并行性。请注意，ClickHouse 将拓扑更复杂的集群抽象到了[分布式表](https://clickhouse.com/docs/en/engines/table-engines/special/distributed)下，这样你就可以像本地一样进行分布式查询。

ClickHouse Cloud 不需要分片来实现集群扩展，因为所有数据都存储在几乎无限的共享对象存储中，并且可以通过添加访问共享数据的额外服务器来简单地提高数据处理的并行度。然而，`ReplicatedMergeTree` 的复制机制最初被设计为**在无共享集群架构中的本地文件系统之上工作**，并且具有少量的副本服务器。拥有大量的 `ReplicatedMergeTree` 副本是一种[反模式](https://en.wikipedia.org/wiki/Anti-pattern)，服务器会在复制日志上创建太多的[竞争](https://en.wikipedia.org/wiki/Resource_contention)，并且会增加服务器间通信的开销。

## 零拷贝复制并不能解决挑战

ClickHouse Cloud 提供服务器的自动垂直扩展 - 服务器的 CPU 核心和 RAM 数量会根据 CPU 和内存压力自动适应工作负载。开始时每个 ClickHouse 云服务都有固定数量的 3 台服务器，最终引入了水平扩展至任意数量的服务器。

为了使用 `ReplicatedMergeTree` 支持共享存储之上的这些高级扩展操作，ClickHouse Cloud 使用了一种称为[零拷贝复制](https://clickhouse.com/docs/en/operations/storing-data#zero-copy)的特殊修改，用于调整 `ReplicatedMergeTree` 表的复制机制以在共享对象存储之上工作。

这种改编使用了几乎相同的原始复制模型，只是对象存储中只存储了一份数据副本。因此称为零拷贝复制。服务器之间不复制数据。相反，我们只复制元数据：

![smt_04.png](https://clickhouse.com/uploads/smt_04_712af233a0.png)

当①server-1收到插入查询时，然后②服务器将插入的数据以 part 的形式写入对象存储，并且 ③ 将有关该 Part 的元数据（例如，该 Part 存储在对象存储中的位置）写入其本地磁盘。④ 通过复制日志，其他服务器获知 server-1 上存在新部分，尽管实际数据存储在对象存储中。⑤ 其他服务器独立地将元数据从 server-1 下载（“获取”）到自己的本地文件系统。为了确保在**<u>所有副本删除指向同一对象的元数据之前</u>**不会删除数据，使用了分布式引用计数机制：在创建或接收元数据后，所有三个服务器还会在 ClickHouse Keeper 中更新自己的 Part 信息元数据集。

为此，以及将合并和 mutations 等操作分配给特定服务器，零拷贝复制机制依赖于在 Keeper 中创建独占[锁](https://zookeeper.apache.org/doc/r3.1.2/recipes.html#sc_recipes_Locks)。这意味着这些操作可以互相阻塞，并且需要等待当前执行的操作完成。

零拷贝复制不足以解决共享对象存储之上的 `ReplicatedMergeTree` 的挑战：

- **元数据仍然与服务器耦合**：元数据存储与计算没有分离。零拷贝复制仍然需要每个服务器上有一个本地磁盘来存储有关 Part 的元数据。本地磁盘是额外的故障点，其可靠性取决于副本的数量，这与高可用性的计算开销有关。
- **零拷贝复制的持久性取决于3个组件的保证**：对象存储、Keeper 和本地存储。如此数量的组件增加了复杂性和开销，因为该堆栈是构建在现有组件之上的，而不是作为云原生解决方案进行重新设计。
- **这仍然是为少量服务器设计的**：使用最初<u>为具有少量副本服务器的无共享集群架构设计的相同复制模型</u>来更新元数据。大量服务器会在复制日志上产生过多争用，并在锁和服务器间通信上产生较高开销。此外，实现从一个副本到另一个副本的数据复制和克隆的代码非常复杂。由于元数据是独立更改的，因此不可能对所有副本进行原子提交。

## `SharedMergeTree` 用于云原生数据处理

我们决定（并且从一开始就[计划](https://github.com/ClickHouse/ClickHouse/issues/44767)）从头开始为 ClickHouse Cloud 实现一个名为 `SharedMergeTree` 的新表引擎 ——旨在工作于共享存储之上。`SharedMergeTree` 是云原生方式，让我们能够 (1) 使 MergeTree 代码更加简单和可维护，(2) 同时[支持](https://clickhouse.com/changes) 垂直和水平自动扩展服务器，以及 (3) 为我们的云用户提供进一步的功能改进，如更高的一致性保证、更好的持久性、时间点恢复、数据时间旅行等等。

这里，我们简单描述一下 [`SharedMergeTree`](https://clickhouse.com/docs/en/guides/developer/shared-merge-tree) 如何原生支持 ClickHouse Cloud 的集群自动扩展[模型](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#automatic-cluster-scaling)。提醒一下：每个 ClickHouse 云服务器只是**计算单元**，可以访问相同共享的数据，服务器的==大小==和数量可以自动更改。为了支持这种机制，`SharedMergeTree` **将数据和元数据的存储与服务器完全分离，并使用 `Keeper` 的接口来读取、写入和修改所有服务器的共享元数据**。**每个服务器都有一个包含元数据子集的本地缓存，并通过订阅机制自动获取有关数据更改的通知**。

此图概述了如何使用 SharedMergeTree 将新服务器添加到集群中：

![smt_05.png](https://clickhouse.com/uploads/smt_05_a45df09927.png)

当 server-3 添加到集群中时，这个新服务器 ① 订阅Keeper中的元数据变化，并将当前元数据的部分内容提取到本地缓存中。这不需要任何锁定机制； 新服务器基本上只是说：“我在这里。请让我了解所有数据更改的最新情况”。新添加的 server-3 几乎可以立即参与数据处理，因为它通过仅从 Keeper 获取必要的共享元数据集，来发现存在哪些数据以及在对象存储中的位置。

下图显示了所有服务器如何了解新插入的数据：

![smt_06.png](https://clickhouse.com/uploads/smt_06_dbf29bf0dc.png)

当①server-1收到插入查询时，则 ② 服务器将插入查询的数据以 **Part** 的形式写入对象存储。③ Server-1 还将有关该 Part 的信息存储在其本地缓存和 Keeper 中（例如，哪些文件属于该 Part 以及与文件对应的 blob 驻留在对象存储中的位置）。之后，④ ClickHouse 向查询发送者**确认插入**。其他服务器（server-2、server-3）会通过 Keeper 的订阅机制自动通知对象存储中存在的新数据，并将元数据更新获取到本地缓存中。

请注意，插入查询的数据在步骤 ④ 之后是持久的。即使 Server-1 或任何或所有其他服务器崩溃，该部分也会存储在高可用对象存储中，并且元数据存储在 Keeper 中（具有至少 3 个 Keeper 服务器的高可用设置）。

从集群中删除服务器也是一个简单而快速的操作。为了正常删除，服务器只需从 Keeper 注销自己，以便正确处理正在进行的**分布式查询**，而不会发出服务器丢失的警告消息。

> 疑问，`SharedMergeTree` 是否还使用**分布式表**？

## ClickHouse 云用户的好处
在 ClickHouse Cloud 中，`SharedMergeTree` 表引擎是 `ReplicatedMergeTree` 表引擎更高效的直接替代品。为 ClickHouse Cloud 用户带来以下强大的好处。

### 无缝的集群扩展
ClickHouse Cloud 将所有数据存储在几乎无限、持久且高度可用的共享对象存储中。`SharedMergeTree` 表引擎为所有表组件添加了共享元数据存储。它几乎可以无限地扩展在该存储之上运行的服务器。服务器实际上是无状态计算节点，我们几乎可以立即更改它们的大小和数量。

#### 示例

假设 ClickHouse Cloud 用户当前使用三个节点，如下图所示：

![smt_07.png](https://clickhouse.com/uploads/smt_07_9e7ecdd514.png)

（手动或自动）将计算量加倍很简单，将每个节点的大小加倍（垂直扩展），或者（例如，当达到每个节点的最大大小时）将节点数量从 3 个增加到 6 个（水平扩展）：

![smt_08.png](https://clickhouse.com/uploads/smt_08_a32f622149.png)

这[ Dobule 了](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#sharedmergetree-in-action)**插入**的吞吐量。对于 `SELECT` 查询，增加节点数量可以提高并发查询执行和[单个查询并发执行](https://clickhouse.com/blog/clickhouse-release-23-03#parallel-replicas-for-utilizing-the-full-power-of-your-replicas-nikita-mikhailov)的并行数据处理度。请注意，增加（或减少）ClickHouse Cloud 中的节点数量不需要任何物理重新分片或重新平衡实际数据。我们可以自由地添加或删除节点，其效果与无共享集群中的手动分片相同。

**更改无共享集群中的服务器数量需要更多的精力和时间。如果集群当前由三个分片组成，每个分片有两个副本**：

![smt_09.png](https://clickhouse.com/uploads/smt_09_52c758d36c.png)

则将分片数量加倍需要对当前存储的数据进行重新分片和重新平衡 :

![smt_10.png](https://clickhouse.com/uploads/smt_10_43b84bbb96.png)

### 自动增强插入查询的持久性
通过 `ReplicatedMergeTree`，您可以使用 [`insert_quorum`](https://clickhouse.com/docs/en/operations/settings/settings#settings-insert_quorum) 设置来确保数据持久性。您可以将**插入查询**配置为仅当插入的数据（零拷贝复制情况下的元数据）存储在特定数量的副本上时才返回发送者。对于 `SharedMergeTree`，不需要 `insert_quorum`。如上所示，当插入查询成功返回发送者时，查询的数据将存储在高可用的对象存储中，元数据集中存储在 Keeper 中（具有至少 3 个 Keeper 服务器的高可用设置）。


### 更轻量级的强一致性 Select 查询
如果您的用例需要一致性保证每个服务器提供相同的查询结果，那么您可以运行 [SYNC REPLICA](https://clickhouse.com/docs/en/sql-reference/statements/system#sync-replica) 系统语句，这是使用 `SharedMergeTree` 的更轻量级的操作。每个服务器只需要从 Keeper 获取当前版本的元数据，而不是在服务器之间同步数据（或具有零拷贝复制的元数据）。

### 提高后台合并和修改的吞吐量和可扩展性
使用 SharedMergeTree，服务器数量增加不会导致性能下降。只要 Keeper有足够的资源，后台的吞吐量就与服务器的数量成正比。对于通过显式触发实现的 [mutations](https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations) 也是如此（[默认情况下](https://clickhouse.com/docs/en/operations/settings/settings#mutations_sync)) 异步执行合并。

> 没有[原子性](https://clickhouse.com/docs/zh/sql-reference/statements/alter/overview)是要解决的：
>
> > 对于 `*MergeTree` 表，通过重写整个数据部分来执行突变。没有原子性——一旦突变的部件准备好，部件就会被替换，并且在突变期间开始执行的 `SELECT` 查询将看到来自已经突变的部件的数据，以及来自尚未突变的部件的数据。

这对 ClickHouse 中的其他新功能具有积极的影响，例如[**轻量级更新**](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#introducing-lightweight-updates-powered-by-sharedmergetree)，它可以从 `SharedMergeTree` 中获得性能提升。同样，特定于引擎的[数据转换](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)（[`AggregatingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/aggregatingmergetree)  的聚合、[`ReplacingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree) 的删除重复数据等）也受益于 `SharedMergeTree` 更好的**合并吞吐量**。这些转换在背台合并 Part 期间逐步应用。为了确保从可能未合并的 Part 中得到正确的查询结果，用户需要在查询时使用 [FINAL](https://clickhouse.com/docs/en/sql-reference/statements/select/from#final) 修饰符或**使用带有 GROUP BY 的聚合子句**来合并未合并的数据。在这两种情况下，这些查询的执行速度都受益于更好的合并吞吐量。因为这样查询在查询时要做的数据合并工作就少了。

## 新的 ClickHouse Cloud 默认表引擎

`SharedMergeTree` 表引擎现在通常作为 ClickHouse Cloud 的默认表引擎，用于新的开发层服务。如果您想使用 `SharedMergeTree` 表引擎创建新的生产层服务，请联系我们。

ClickHouse Cloud [支持](https://clickhouse.com/docs/en/whats-new/cloud-compatibility#database-and-table-engines)的 `MergeTree` 系列中的所有表引擎均自动基于 `SharedMergeTree`。例如，当您创建一个 [`ReplacingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree) 表时，ClickHouse Cloud 会自动在底层创建一个 `SharedReplacingMergeTree` 表 引擎：

```sql
CREATE TABLE T (id UInt64, v String)
ENGINE = ReplacingMergeTree
ORDER BY (id);

SELECT engine
FROM system.tables
WHERE name = 'T';

┌─engine───────────────────┐
│ SharedReplacingMergeTree │
└──────────────────────────┘
```
请注意，随着时间的推移，现有服务将从 `ReplicatedMergeTree` 迁移到 `SharedMergeTree` 引擎。如果您想讨论此问题，请联系 ClickHouse 支持团队。

另请注意，`SharedMergeTree` 的当前实现尚不支持 `ReplicatedMergeTree` 中存在的更高级功能，例如[异步插入的重复数据删除](https://clickhouse.com/blog/asynchronous-data-inserts- in-clickhouse#inserts-are-idempot) 和静态加密，但计划在未来版本中提供此支持。

## `SharedMergeTree` 的实际应用
> TODO:

## 简介介轻量级更新，由 `SharedMergeTree` 加速
`SharedMergeTree` 是一个强大的构建块，我们将其视为云原生服务的基础。它使我们能够在以前不可能或过于复杂而无法实现的情况下构建新功能并改进现有功能。许多功能都受益于在 `SharedMergeTree` 之上工作，并使 ClickHouse Cloud 性能更高、更耐用且易于使用。其中一个功能是**轻量级更新**——一种优化，允许在使用更少的资源的情况下立即提供 `ALTER UPDATE` 查询的结果。

### 传统分析数据库中的更新是很重的操作

ClickHouse 中 [ALTER TABLE … UPDATE](https://clickhouse.com/docs/en/sql-reference/statements/alter/update) 的查询被实现为 [mutations](https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations)。**mutations** 是一种重量级操作，可以同步或异步重写 **part**。

#### 同步修改

![smt_20.png](https://clickhouse.com/uploads/smt_20_fc56fe2e17.png)

在上面的示例场景中，ClickHouse ① 对首先为空表执行插入查询，② 将插入的数据写入存储上的新数据 Part，③ 确认插入。接下来，ClickHouse ④ 接收更新查询并通过 ⑤ 改变 Part-1 来执行该查询。该 Part 被加载到内存中，修改完成，修改后的数据被写入存储上的新 Part-2（Part-1被删除）。仅当该 Part 重写完成时， ⑥ 更新查询的确认才返回给更新查询的发送者。其他更新查询（也可以删除数据）以相同的方式执行。对于较大的 Part，这是一项非常繁重的操作。

#### 异步修改

[默认情况下](https://clickhouse.com/docs/en/operations/settings/settings#mutations_sync)，更新查询是异步执行的，以便将多个收到的更新融合到单个修改中，从而减轻重写 Part 对性能的影响 :

![smt_21.png](https://clickhouse.com/uploads/smt_21_f1b7f214ce.png)

当 ClickHouse ① 收到更新查询时，更新会被添加到[队列](https://clickhouse.com/docs/en/operations/system-tables/mutations)中并异步执行，而 ② 更新查询会立即获取对**更新**的**确认**。

请注意，在 ⑤ **==背台的修改被物化之前==**，对表的 SELECT 查询看不到更新。另请注意，ClickHouse 可以将排队的更新融合到单个 Part 的重写操作中。因此，最佳实践是批量更新，在单个查询发送 100 个更新。

### 轻量级更新
前面提到的更新查询的显式批处理不再是必要的，并且从用户的角度来看，单个更新查询的修改，即使是异步实现的，也将立即发生。

下图描绘了 ClickHouse 中新的轻量级即时更新[机制](https://clickhouse.com/docs/en/guides/developer/lightweght-update)：

![smt_22.png](https://clickhouse.com/uploads/smt_22_e303a94b55.png)

当 ClickHouse ① 收到更新查询时，更新会被添加到队列中并异步执行。② 此外，更新查询的更新表达式被放入主存中。更新表达式也存储在 Keeper 中并分发到其他服务器。当 ③ ClickHouse 在通过 Part 重写实现更新之前收到 SELECT 查询时，ClickHouse 将照常执行 SELECT 查询 - 使用[主索引](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)，用于减少需要从 Part 流式传输到内存的行集，然后将来自 ② 的更新表达式即时应用于流式传输的行。这就是为什么我们称这种机制为**动态修改**。当 ④ ClickHouse 收到另一个更新查询时， ⑤ 该查询的更新（在本例中为删除）表达式再次保留在主内存中，并且 ⑥ 将通过应用（② 和 ⑤）更新表达式来在后续流式流入的数据上执行 SELECT 查询。当所有排队的更新在下一个背台修改中物化后，动态更新表达式将从内存中删除。⑧ 新收到的更新和 ⑩ SELECT 查询的执行如上所述。

只需将 `apply_mutations_on_fly` 设置为 `1` 即可启用此新机制。

#### 优点

用户无需等修改完成。ClickHouse 立即提供更新的结果，同时使用更少的资源。此外，这使得 ClickHouse 用户更容易使用更新，他们可以发送更新而无需考虑如何批量更新。

#### 与 SharedMergeTree 的协同作用

从用户的角度来看，轻量级更新的修改将立即发生，但在更新物化之前，用户将体验到 SELECT 查询性能的轻微降低，因为更新是查询时在流式数据中执行的。 随着更新作为后台合并操作的一部分而物化，对查询延迟的影响就消失了。 `SharedMergeTree` 表引擎[提高了后台合并和修改的吞吐量和可扩展性](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#improved-throughput-and-scalability-of-background-merges-and-mutations)，因此，修改完成得更快，轻量级更新后的 SELECT 查询更快地恢复全速。

#### 下一步是？

我们上面描述的轻量级更新机制只是第一步。 我们已经在计划额外的实现阶段，以进一步提高轻量级更新的性能并消除当前的[限制](https://clickhouse.com/docs/en/guides/developer/lightweght-update)。

## 总结

在这篇博文中，我们探索了新的 ClickHouse Cloud `SharedMergeTree` 表引擎的机制。 我们解释了为什么有必要引入一个原生支持 ClickHouse 云架构的新表引擎，分开垂直和水平可扩展的计算节点和存储在几乎无限的共享对象存储中的数据。 `SharedMergeTree` 可以在存储之上无缝地、几乎无限地扩展计算层。 插入和后台合并的吞吐量可以轻松扩展，这有利于 ClickHouse 中的其他功能，如轻量级更新和特定于引擎的数据转换。 此外，`SharedMergeTree` 为插入提供了更强的持久性，为选择查询提供了更轻量级的强一致性。 最后，它为新的云原生功能和改进打开了大门。 我们通过基准测试展示了引擎的效率，并描述了 `SharedMergeTree` 增强的一项新功能，称为轻量级更新。