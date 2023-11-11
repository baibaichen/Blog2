# MergeTree  上云

> 上 HDFS 会有什么问题？

## 背景

对 **MergeTree** 表的对象存储支持已于 2020 年添加到 ClickHouse 中，并从那时起不断发展。Double.Cloud 的文章[**基于 s3 的 ClickHouse 混合存储是如何工作的**](https://double.cloud/blog/posts/2022/11/how-s3-based-clickhouse-hybrid-storage-works-under-the-hood/) 描述了当前实现。我们将使用 S3 作为对象存储的同义词，但它也适用于 GCS 和 Azure blob 存储。

尽管近年来 S3 支持有了显着改善，但当前的实现仍然存在许多问题（另请参见 [3] 和 [4]）：

- 数据存储在两个地方：**本地元数据文件**和 **S3 对象**。
- 存储在 S3 中的数据不是独立的，即，如果没有本地元数据数据文件，则无法附加存储在 S3 中的表
- 每次修改都**需要在 2 个不同的非事务性介质之间进行同步**：本地磁盘上的本地元数据文件和存储在对象存储中的数据本身。这会导致一致性问题。
- 由于上述原因，[零拷贝复制](https://clickhouse.com/docs/en/operations/storing-data#zero-copy)也不可靠，并且[已知存在错误](https: //github.com/ClickHouse/ClickHouse/labels/comp-s3)。
- 备份并非易事，因为需要分别备份两个不同的源。

ClickHouse Inc. 使用 [SharedMergeTree 存储引擎](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates) 对此提出了自己的解决方案，但该解决方案不会 以开源形式发布。本文档的目的是提出一种解决方案，使对象存储对 MergeTree 的支持更好，并且可以由开源 ClickHouse 社区在 Apache 2.0 许可下实现。

## 要求

我们认为 S3 上的 MergeTree 应满足以下高级要求：

- 它应该将 MergeTree 表数据（完整或选定的部分/分区）存储在对象存储中
- 它应该允许从多个**==副本节点==**读取 S3 MergeTree 表
- 它应该允许从多个**==副本节点==**写入 S3 MergeTree 表
- **它应该是独立的**，即所有数据和元数据都应该存储在一个存储桶中
- **它应该在现有 ClickHouse 功能的基础上逐步构建**。
- 解决方案应该与云提供商无关，并且也适用于 GCP 和 Azure（[s3proxy](https://github.com/gaul/s3proxy) 可以用作集成层）。

需要考虑的其他要求：

- <u>==能够在副本之间分发合并==</u>（另请参阅“worker-replicas”提案 [复制数据库的副本组 #53620](https://github.com/ClickHouse/ClickHouse/issues/53620)）
- 减少 S3 操作的数量，否则可能会增加不必要的成本。

## 提议

我们建议重点关注两个可以并行执行的不同工作：

1. 改进基于现有 S3 磁盘设计的零拷贝复制
2. 改进S3数据的存储模型

我们不需要解决动态分片问题，这也是 ClickHouse 的 `SharedMergeTree` 的一个功能。

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

零拷贝机制尚未达到生产质量； 有时会有错误。 最新的一个已经在最近版本中修复了的例子是**修改期间**双重复制的情况。

当一个节点创建零件时，会发生以下情况：

1. 第二个节点复制它，
2. 在该 part 上运行修改，产生一个与原始数据硬链接的新 part，
3. 第二个节点复制新的 part。

同时，第二个节点对这些 part 之间的连接一无所知。

如果第一个节点之前删除了旧部分，则删除时的第二个节点将决定删除对象的最后一个本地链接。 结果，它会从 Keeper 得到信息，没有其他人使用这部分的对象，因此，它会删除 S3 中的对象。

如上所述，这个错误已经被修复，并且我们长期以来一直在我们的解决方案中使用零拷贝。

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-5.png)

## 最后的想法

我们还看到该社区已经开始添加其他对象存储提供程序，例如由 Content Square 的朋友开发的 [Azure blob storage 开发](https://github.com/ClickHouse/ClickHouse/issues/29430)，这再次向我们展示了 我们正朝着正确的方向前进。

关于 DoubleCloud 上该功能的可用性的小说明。 DoubleCloud 的所有集群默认都已经拥有基于 S3 的混合存储； 您不需要配置或设置任何额外的内容。 [只需使用您首选的混合存储配置文件创建一个表](https://double.cloud/docs/en/management-clickhouse/step-by-step/use-hybrid-storage)，即可开始使用。

[联系我们的架构师](mailto:viktor@double.cloud) 了解如何将此方法应用于您的项目，或者即使您正在寻求设置和使用该功能的帮助并希望与我们聊天。

ClickHouse® 是 ClickHouse, Inc. 的商标。 [https://clickhouse.com](https://clickhouse.com/)