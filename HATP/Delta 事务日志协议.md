# Delta 事务日志协议

# 概览

这份文件是 Delta 交易协议的一个规范，它为存储在分布式文件系统或对象存储中的大量数据集合带来了 [ACID](https://en.wikipedia.org/wiki/ACID) 的属性。在设计该协议时，我们考虑了以下的目标：

- **可串行化的ACID写操作** - 多个写入者可以同时修改 Delta 表格，同时维持 ACID 语义。
- **读取的快照隔离** - 读者可以阅读一个 Delta 表格的一致性快照，即使面临并发写操作也是如此。
- **可扩展到数十亿个分区或文件** - 针对 Delta 表的查询可以在单台机器上或并行进行规划。
- **自我描述性** - 所有针对 Delta 表的元数据都存储在数据旁边。这种设计消除了为了读取数据而维护一个单独的元数据仓库的需要，同时也允许使用标准文件系统工具复制或移动静态表格。
- **增量处理的支持** - 读者可以通过跟踪 Delta 日志来确定在给定时间周期内添加了哪些数据，从而实现有效的流处理。

Delta 的事务是通过多版本并发控制（MVCC）来实现的。作为一个表的改变，Delta 的 MVCC 算法会保留多份数据复制，而不是立即替换包含正在更新或删除的记录的文件。

表的读者确保他们在同一时间内只通过使用事务日志来选择性地处理哪些数据文件，从而只看到一份一致的表快照。

写入者分两个阶段修改表：**首先**，以乐观的方式<u>写出新的数据文件</u>或<u>现有数据文件的更新副本</u>。**然后**提交，通过向日志添加新条目来创建表的最新原子版本。在此日志条目中，记录了要逻辑添加和删除的数据文件，以及关于表的其他元数据的改变。

在表的最新版本中不再存在的数据文件可以在用户指定的保存期（默认为7天）之后，通过 `vacuum` 命令来进行延迟删除。

# Delta表规范

**表有一个原子版本的串行历史**，使用连续、且单调递增的整数命名。给定版本的表的状态称为快照，由以下属性定义：

- Delta日志协议由两个协议版本以及正确读取或写入表所需的相应表功能（如果适用）组成
  - **读者特性**只在读者版本为3时存在
  - **写作特性**只在写作版本为7时存在
- **表的元数据**（例如，模式，唯一标识符，分区列和其他配置属性）
- **表中存在的文件集**，以及这些文件的元数据
- **最近删除的文件的墓碑集**
- **已成功提交到表的应用程序特定的事务集**

## 文件类型

Delta 表存储在一个目录中，由以下不同类型的文件组成。

以下是在 `mytable` 目录中存储的，提交日志中有三个条目的 Delta 表的一个示例。

```
/mytable/_delta_log/00000000000000000000.json
/mytable/_delta_log/00000000000000000001.json
/mytable/_delta_log/00000000000000000003.json
/mytable/_delta_log/00000000000000000003.checkpoint.parquet
/mytable/_delta_log/_last_checkpoint
/mytable/_change_data/cdc-00000-924d9ac7-21a9-4121-b067-a0a6517aa8ed.c000.snappy.parquet
/mytable/part-00000-3935a07c-416b-4344-ad97-2a38342ee2fc.c000.snappy.parquet
/mytable/deletion_vector-0c6cbaaf-5e04-4c9d-8959-1088814f58ef.bin
```

### 数据文件

数据文件可以存储在表的根目录或任何非隐藏的子目录（即，其名称不以`_`开头的目录）中。默认情况下，参考实现将数据文件存储在根据该文件中数据的分区值命名的目录中（即`part1=value1/part2=value2/...`）。此目录格式只是遵循现有的约定，并不是协议所必需的。文件的实际分区值必须从事务日志中读取。

### 删除向量文件

删除向量（DV）文件存储在表的根目录，与数据文件一起存放。一个DV文件包含一个或多个序列化的DV，每个DV描述了与之相关的特定数据文件的**无效**（或“软删除”）行的集合。对于带有分区值的数据，DV文件**不**存放在与数据文件相同的目录层次结构中，因为每一个都可以包含来自多个分区的文件的 DV。DV 文件以[二进制格式]()存储DV。

### 变更数据文件

变更数据文件存储在表的根目录下名为`_change_data`的目录中，并代表他们所在的表版本的变化。对于带有分区值的数据，建议将变更数据文件存储在他们各自的分区内的`_change_data`目录中（即`_change_data/part1=value1/...`）。执行更改底层数据的操作，如`UPDATE`，`DELETE`和`MERGE`操作到Delta Lake表的时候，写者可以**选择性**地生成这些变更数据文件。如果一个操作只增加新数据或删除现有的数据，而不更新任何现有的行，写者可以只写入数据文件，并在`add`或`remove`动作中提交它们，而不需要将数据复制到变更数据文件中。当变更数据文件可用时，变更数据读取器应使用变更数据文件，而不是从底层数据文件中计算变更。

除了数据列，变更数据文件还包含额外的列，用于标识变更事件的类型：

Field Name | Data Type | Description
-|-|-
_change_type|`String`| `insert`, `update_preimage` , `update_postimage`, `delete` __(1)__

__(1)__ `preimage` 是更新之前的值，`postimage` 是更新之后的值。

### Delta 日志记录

Delta 文件以 JSON 格式存储在表的根目录下名为 `_delta_log` 的目录中，并与检查点一同构成了表所有的更改日志。

Delta 文件是表的原子性单元，使用下一个可用版本号进行命名，以零填充到 20 位数字。例如：

```plaintext
./_delta_log/00000000000000000000.json
```

Delta 文件使用换行符分隔的 JSON 格式，其中每个**操作**都存储为单行 JSON 文档。一个 Delta 文件 `n.json`，包含一组原子[**动作**](#Actions)，将其应用于表的前一个状态，`n-1.json`，以构造该表的第 `n` 个快照。一个动作会更改表状态的某一方面，例如添加或删除文件。

### 检查点

检查点也存储在`_delta_log`目录中，并且可以随时为表提交的任何版本创建检查点。出于性能原因，读取者应优先使用最新的完整检查点。对于时间旅行，使用的检查点不能比时间旅行版本新

检查点包含所有操作的完整重放，直至并包括检查点表版本，并删除了无效操作。使用[协调规则](#Action-Reconciliation)来确定哪些操作有效，哪些操作**无效**，**无效操作**被后续操作取消。检查点也包含[删除墓碑](#add-file-and-remove-file)，直到它们过期。检查点允许读取者节省读取日志到给定点以重建快照的成本，也允许[元数据清理](#metadata-cleanup)删除过期的 JSON Delta 日志条目。

读者不应该对检查点的存在或频率做出任何假设，但有一个例外：[元数据清理](#metadata-cleanup)必须为保留的最旧的表版本提供一个检查点，以覆盖所有已删除的 [Delta 日志条目]()。x`x``也就是说，鼓励写者频繁地进行检查点，以免读取者因读取大量的 delta 文件而支付过高的日志重播成本。

**检查点文件名基于检查点包含的表版本**。Delta 支持三种类型的检查点：

一）**UUID命名的检查点**：这些遵循 V2 规范，使用以下文件名：`n.checkpoint.u.{json/parquet}`，其中`u`是一个UUID，`n`是这个检查点代表的快照版本。这里的`n`必须用零填充到长度为20。UUID 命名的 V2 检查点可以是 json 或parquet 格式，并引用在 `_delta_log/_sidecars` 目录中的一个或多个检查点副本。一个检查点副本是一个具有唯一命名的 parquet 文件：`{unique}.parquet`，其中`unique`是一些唯一的字符串，如UUID。例如：

```plaintext
00000000000000000010.checkpoint.80a083e8-7026-4e79-81be-64bd76c43a11.json
_sidecars/3a0d65cd-4056-49b8-937b-95f9e3ee90e5.parquet
_sidecars/016ae953-37a9-438e-8683-9a9a4a79a395.parquet
_sidecars/7d17ac10-5cc3-401b-bd1a-9c82dd2ea032.parquet
```
二）表版本 `n` 的[经典检查点](#classic-checkpoint)由名为 `n.checkpoint.parquet` 的文件组成。这里的 `n` 必须用零填充到长度为20。这些可以遵循 [V1 规范](#v1-spec) 或 [V2 规范](#v2-spec)。例如：
```plaintext
00000000000000000010.checkpoint.parquet
```

三）版本`n`的[多部分检查点](#multi-part-checkpoint)包括 `p` 个文件（`p > 1`），其中 `p` 的第 `o` 个文件被命名 `n.checkpoint.o.p.parquet`。这里的 `n` 必须用零填充到长度为 20，而 `o` 和 `p` 必须用零填充到长度为10。这些始终是 [V1 检查点](#v1-spec)。 例如：

```plaintext
00000000000000000010.checkpoint.0000000001.0000000003.parquet
00000000000000000010.checkpoint.0000000002.0000000003.parquet
00000000000000000010.checkpoint.0000000003.0000000003.parquet
```

写者可以选择按照以下约束编写检查点：

- 编写者始终允许创建遵循 v1 规范的经典检查点。
- 如果启用 v2  检查点，写者不得创建多部分检查点。
- 如果启用了 v2 检查点表特性，编写者可以创建 v2 规范的检查点（无论是 classic 或 uuid-named）。

**多部分检查点过时了，编写者应避免创建它们。使用 uuid-named V2 规范检查点代替这些**。

同一表版本可能存在多个检查点，例如，如果两个客户端同时竞争创建检查点，但是格式不同。在这种情况下，客户端可以选择使用哪个检查点。

因为多部分检查点不能一次性创建（例如，易受到写入慢与/或失败的影响），读取者必须忽略缺失部分的多部分检查点。

给定版本的检查点只能在关联的 delta 文件已经成功写入后创建。

#### sidecar 文件

sidecar 文件包含文件操作。 这些文件采用 parquet 格式，并且必须具有唯一的名称。 然后将它们[链接](#Sidecar 文件信息)到检查点。请参阅 [V2 检查点规范](#v2-spec)，以获取更多详细信息。目前，sidecar 文件只能有[添加文件和删除文件](#Add-File-and-Remove-File) 条目。**添加和删除文件操作作为结构字段存储在 parquet 中的各个列中**。

这些文件位于 `_delta_log/_sidecars` 目录中。

### 日志整理文件

日志整理文件位于 `_delta_log` 目录中。从起始版本 `x` 到结束版本 `y` 的日志整理文件将有以下名称：`<x>.<y>.compacted.json`。这包含了提交范围`[x, y]`的聚合操作。与提交类似，日志整理文件中的每一行都代表一个操作。给定范围的提交文件是通过执行相应提交的[操作协调](#action-reconciliation)来创建的。实现可以选择读取日志整理文件 `<x>.<y>.compacted.json` 来加速快照构建，而不是读取范围 [x, y] 中的各个提交文件。示例：

假设我们有 `00000000000000000004.json` 为：

```json
{"commitInfo":{...}}
{"add":{"path":"f2",...}}
{"remove":{"path":"f1",...}}
```

`00000000000000000005.json` 为：

```json
{"commitInfo":{...}}
{"add":{"path":"f3",...}}
{"add":{"path":"f4",...}}
{"txn":{"appId":"3ae45b72-24e1-865a-a211-34987ae02f2a","version":4389}}
```

`00000000000000000006.json` 为：

```plaintext
{"commitInfo":{...}}
{"remove":{"path":"f3",...}}
{"txn":{"appId":"3ae45b72-24e1-865a-a211-34987ae02f2a","version":4390}}
```
那么 `00000000000000000004.00000000000000000006.compacted.json` 将会有以下内容：

```plaintext
{"add":{"path":"f2",...}}
{"add":{"path":"f4",...}}
{"remove":{"path":"f1",...}}
{"remove":{"path":"f3",...}}
{"txn":{"appId":"3ae45b72-24e1-865a-a211-34987ae02f2a","version":4390}}
```

写者：
  - 可以为任何给定的提交范围选择性地产生日志整理

读者：
  - 如果y有，可以选择使用日志整理文件
  - 在操作协调期间，可用日志整理文件会替换相应的提交

### 最新的检查点文件

Delta 事务日志通常会包含许多（例如，超过10,000个）文件。列出如此大的目录可能会非常耗时。最新的检查点文件可以通过提供一个指向日志结束部分的指针，帮助减少构建表格最新快照的成本。

读取者可以通过查看 `_delta_log/_last_checkpoint` 文件来定位最近的检查点，而不是遍历整个目录。由于在日志中的文件利用了零填充的编码方式，这个最新检查点的版本 ID 可以用在支持字典排序、翻页式目录列表的存储系统上，以列举出任何 delta 文件或比这个检查点更新的检查点，这些文件或检查点内含有表的更多最新版本信息。

## 操作（Actions）

操作会修改表的状态，它们既保存在 Delta 文件中，也保存在**检查点**中。本节列出了可用操作的空间以及它们的 **Schema**。

### 修改元数据

`metaData` 操作会改变表当前的元数据。 表的第一个版本必须包含一个 `metaData` 动作。后续的 `metaData` 动作会完全覆盖表的当前元数据。

在表的给定版本中，最多只能有一个元数据操作。每个元数据操作**必须**至少包含**必需**的字段。

`metaData` 动作的 Schema 如下：

| 字段名称         | 数据类型                               | 描述                                                        | 可选/必须 |
| :--------------- | :------------------------------------- | :---------------------------------------------------------- | :-------- |
| id               | `GUID`                                 | 此表的唯一标识符                                            | **必需**  |
| name             | `String`                               | 用户提供的此表的标识符                                      | 可选      |
| description      | `String`                               | 用户为此表提供的描述                                        | 可选      |
| format           | [Format Struct](#format-specification) | 表中存储的文件的编码规范                                    | **必需**  |
| schemaString     | [Schema Struct]()                      | 表的 Schema                                                 | **必需**  |
| partitionColumns | `Array[String]`                        | 包含应将数据按其进行分区的列的名称的数组                    | **必需**  |
| createdTime      | `Option[Long]`                         | 此元数据操作的<u>创建时间</u>，**自 Unix 纪元以来的毫秒数** | 可选      |
| configuration    | `Map[String, String]`                  | 元数据操作的配置选项                                        | **必需**  |

#### Format Specification

| 字段名称 | 数据类型              | 描述                  |
| :------- | :-------------------- | :-------------------- |
| provider | `String`              | 此表中文件的编码名    |
| options  | `Map[String, String]` | Format 的<u>配置选项</u> |

在参考实现中，**provider** 字段用于实例化 Spark SQL 的 [`FileFormat`](https://github.com/apache/spark/blob/master/sql/core/src/main/scala/org/apache/spark/sql/execution/datasources/FileFormat.scala)。截至Spark 2.4.3，对`parquet`、`csv`、`orc`、`json`和`text`的`FileFormat`支持已内置。

从 Delta Lake 0.3.0 开始，面向用户的 API 只允许创建 `format = 'parquet'` 且 `options = {}` 的表。出于对旧版系统的考虑，以及为了将来可能支持其他格式做的准备，我们保留了对读取其他格式的支持（详见 [#87](https://github.com/delta-io/delta/issues/87)）。

以下是一个 `metaData` 动作的示例：

```json
{
  "metaData":{
    "id":"af23c9d7-fff1-4a5a-a2c8-55c59bd782aa",
    "format":{"provider":"parquet","options":{}},
    "schemaString":"...",
    "partitionColumns":[],
    "configuration":{
      "appendOnly": "true"
    }
  }
}
```

### `Add` 和 `Remove` 文件

`add` 和 `remove` 操作分别用于通过添加或删除各自的**逻辑文件**来修改表中的数据。

表的每个**逻辑文件**都由数据文件的路径和一个可选的删除向量（DV）表示，该删除向量指示表中哪些数据文件的行已经不存在了。删除向量是可选的特性，请查看他们的 [Reader 的需求]()以了解详细信息。

当遇到对已存在于表中的逻辑文件的 `add` 操作时，应将来自最新版本的统计信息和其他信息替换任何之前版本的信息。文件集中逻辑文件记录的主键是数据文件的 `path` 和描述 DV  唯一 id 的元组。如果此逻辑文件没有 DV，则其主键为`(path, NULL)`。

`remove` 操作包含了时间戳，表示删除发生的时间。物理文件的物理删除可以在用户指定的到期时间阈值之后延迟进行。**这个延迟使得并发的读者能够继续对数据的过时快照进行操作**。`remove` 操作应作为<u>墓碑</u>（逻辑删除）保留在表的状态中，直到其过期。 当**当前时间**（根据执行清理的节点）超过 `remove` 操作时间戳添加的过期阈值时，<u>墓碑</u>就会过期。

在以下陈述中，`dvId` 可以指特定删除向量的唯一 id （`deletionVector.uniqueId`）或 `NULL`，==表示没有行被无效化==。由于不能保证给定 Delta 提交中的操作按顺序应用，因此对于 `path` 和 `dvId` 的任何一种组合，**有效版本**仅限于最多包含一个相同类型的文件操作（即 `add`/`remove`）。简单起见，要求在任何 `path` （无论 `dvId`）上最多只有一个同类型的文件操作。具体来说，对于任何提交...

- 在 `add` 操作和 `remove` 操作中出现相同的 `path` 是 **合法的**，但是两者的 `dvId` 不同。
- 添加和/或移除同一个 `path`，同时在 `cdc` 操作中出现是 **合法的**。
- 在每组 `add` 或 `remove` 操作中，同一 `path` 以不同的 `dvId` 出现两次是 **非法的**。

在 `add` 或 `remove` 上的 `dataChange` 标志可以设定为 `false`，以表示一个操作在与同一原子版本中的其他操作相结合时，只重新排列现有的数据或添加新的统计数据。例如，跟踪事务日志的流查询可以使用此标志来跳过那些不会影响最终结果的操作。

下面是 `add` 操作的 Schema：

| 字段名称                | 数据类型                                | 描述                                                         | 必填/选填 |
| :---------------------- | :-------------------------------------- | :----------------------------------------------------------- | :-------- |
| path                    | `String`                                | 从表的根到数据文件的相对路径，或应添加到表中的文件的绝对路径。路径是由[RFC 2396 URI通用语法](https://www.ietf.org/rfc/rfc2396.txt)规定的URI，需要解码以获取数据文件路径。 | **必填**  |
| partitionValues         | `Map[String, String]`                   | 此逻辑文件的分区列到值的映射。请参阅[分区值序列化]()         | **必填**  |
| size                    | `Long`                                  | 此数据文件的大小（以字节为单位）                             | **必填**  |
| modificationTime        | `Long`                                  | 创建此逻辑文件的时间，以==新纪元==以来的毫秒数表示           | **必填**  |
| dataChange              | `Boolean`                               | 当 `false` 时，逻辑文件必须已在表中存在，或者<u>添加文件中的记录必须</u>包含在同一版本的一个或多个 `remove` 操作中 | **必填**  |
| stats                   | [统计结构](#Per-file-Statistics)        | 包含此逻辑文件中的数据的统计信息（例如，某列的计数、最小/最大值） | 选填      |
| tags                    | `Map[String, String]`                   | 包含此逻辑文件的元数据的映射                                 | 选填      |
| deletionVector          | [删除向量描述符结构](#Deletion-Vectors) | 当没有与此数据文件关联的 DV 时，为 null（或在JSON中缺失），或者为包含与此逻辑文件相关的 DV 的必要信息的结构体。 | 选填      |
| baseRowId               | `Long`                                  | 默认生成文件中第一行的行 ID。文件中其他行的默认行 ID 可以通过将第一行的行 ID 加上该的物理索引来构建。请参阅[行 ID]()。 | 选填      |
| defaultRowCommitVersion | `Long`                                  | 第一个提交版本，即第一次将具有相同 `path` 的 `add` 操作提交到表中。 | 选填      |
| clusteringProvider      | `String`                                | 聚类实现的名称。请参阅[聚类表]()                             | 选填      |

以下是分区表 `add` 操作的示例：
```json
{
  "add": {
    "path": "date=2017-12-10/part-000...c000.gz.parquet",
    "partitionValues": {"date": "2017-12-10"},
    "size": 841454,
    "modificationTime": 1512909768000,
    "dataChange": true,
    "baseRowId": 4071,
    "defaultRowCommitVersion": 41,
    "stats": "{\"numRecords\":1,\"minValues\":{\"val..."
  }
}
```

以下是针对聚类表 `add` 操作的示例：
```json
{
  "add": {
    "path": "date=2017-12-10/part-000...c000.gz.parquet",
    "partitionValues": {},
    "size": 841454,
    "modificationTime": 1512909768000,
    "dataChange": true,
    "baseRowId": 4071,
    "defaultRowCommitVersion": 41,
    "clusteringProvider": "liquid",
    "stats": "{\"numRecords\":1,\"minValues\":{\"val..."
  }
}
```
下面是 `remove` 操作的 Schema：

字段名称 | 数据类型 | 说明 | 必填/选填
-|-|-|-
path| `String` | 从表的根到文件的相对路径，或者应从表中移除的文件的绝对路径。路径是由[RFC 2396 URI 通用语法](https://www.ietf.org/rfc/rfc2396.txt)规定的 URI，需要解码以获取数据文件路径。 | **必填** 
deletionTimestamp | `Option[Long]` | 删除发生的时间，以==新纪元==以来的毫秒数表示 | 选填
dataChange | `Boolean` | 当为 `false` 时，必须在同一版本的一个或多个 `add` 文件操作中包含被删除文件中的记录 | **必填** 
extendedFileMetadata | `Boolean` | 当为 `true` 时，字段 `partitionValues`、`size` 和 `tags` 存在 | 选填
partitionValues| `Map[String, String]` | 此文件的分区列到值的 `Map`。请参见[分区值序列化](#Partition-Value-Serialization) | 选填
size| `Long` | 以字节为单位的文件大小 | 选填
stats | [统计结构](#Per-file-Statistics) | 包含该逻辑文件中数据的统计信息（例如，列的计数、最小/最大值） | 选填
tags | `Map[String, String]` | 该文件**元数据的 `Map`** | 选填
deletionVector | [删除向量描述符结构](#Deletion-Vectors) | 当与此数据文件没有关联的 DV 时为null（在JSON中可能不存在），或者为包含与该逻辑文件的 DV 相关的必要信息的结构（如下所述）。 | 选填
baseRowId | `Long` | 文件中第一行的**默认行 ID**。文件中其他行的默认行 ID 可以通过将第一行的行 ID 加上该行的物理索引来构建。请参阅[行 ID]()。 |选填
defaultRowCommitVersion | `Long` | 第一个提交版本，即第一次将具有相同 `path` 的 `add` 操作提交到表中。 |选填

以下是 `remove` 操作的示例：

```json
{
  "remove": {
    "path": "part-00001-9…..snappy.parquet",
    "deletionTimestamp": 1515488792485,
    "baseRowId": 4071,
    "defaultRowCommitVersion": 41,
    "dataChange": true
  }
}
```

### `Add` `CDC` 文件
`cdc` 操作用于添加仅包含在事务中更改的数据的[文件](#change-data-files)。当==更改数据 Reader== 在特定 Delta 表版本中遇到 `cdc` 操作时，必须只使用 `cdc` 文件读取该版本中所做的更改。如果一个版本没有 `cdc` 操作，那么  `add` 和 `remove` 操作中的数据将分别视为插入行和删除行。

`cdc` 操作的 Schema如下：

字段名称 | 数据类型 | 描述
-|-|-
path| `String` | 相对于表根目录的变更数据文件的相对路径，或者应添加到表中的变更数据文件的绝对路径。路径是由[RFC 2396 URI通用语法](https://www.ietf.org/rfc/rfc2396.txt)指定的URI，需要解码才能获取文件路径。
partitionValues| `Map[String, String]` | 该文件分区列到值的 **Map**。参见[分区值序列化](#Partition-Value-Serialization) 
size| `Long` | 该文件的字节大小
dataChange |`Boolean` | 对于 `cdc` 操作，应始终设置为 `false`，因为它们**不会**更改表的底层数据 
tags | `Map[String, String]` | 该文件元数据的 **Map** 

以下是 `cdc` 操作的示例。

```json
{
  "cdc": {
    "path": "_change_data/cdc-00001-c…..snappy.parquet",
    "partitionValues": {},
    "size": 1213,
    "dataChange": false
  }
}
```

#### 对 `AddCDCFile` Writer 的要求

对于 [Writer 版本 4 到 6](#Writer-Version-Requirements)，所有 Writer 都必须尊重表元数据中的 `delta.enableChangeDataFeed` 配置标志。当 `delta.enableChangeDataFeed` 为 `true` 时，按[更改数据文件](#change-data-files)中规定，Writer 必须为更改数据的任何操作生成对应的 `AddCDCFile`。

对于版本 7 的 Writer，只有在表 `protocol` 的 `writerFeatures` 中存在 `changeDataFeed` 功能时，才需要遵守表的元数据中 `delta.enableChangeDataFeed` 配置标志。

#### 对 `AddCDCFile` Reader 的要求

如果可用，更改数据的 Reader 应使用给定表的版本中的 `cdc` 操作，而不是从 `add` 和 `remove` 操作引用的底层数据文件中计算==更改==。具体来说，应使用以下策略来读取版本中进行的==行级更改==：
1. 如果此版本中有 `cdc` 操作，则只读取这些操作以获得行级更改，并跳过此版本中其余的 `add` 和 `remove` 操作。
2. 否则，如果此版本中没有 `cdc` 操作，读取并处理 `add` 和 `remove` 操作中的所有行，分别作为插入行和删除行。
3. 更改数据的 Reader 应返回以下额外列：

    字段名称 | 数据类型 | 描述
    -|-|-
    _commit_version|`Long`| 包含更改的表版本。可以从**包含操作的 Delta 日志文件的名称中**获取。 
    _commit_timestamp|`Timestamp`| 创建提交时相关联的时间戳。可以从包含操作的 Delta 日志文件的文件修改时间中获取。

##### 非更改数据的 Reader 的注意事项

在启用了 **Change Data Feed** 的表中，`add` 和 `remove` 操作引用的数据 Parquet 文件被允许包含额外列 `_change_type`。此列不在表的 schema 中，并且始终会有一个 `null` 值。在访问这些文件时，Reader 应忽略此列，只处理表 schema 中定义的列。

### 事务标识符
增量处理系统（例如，流处理系统）使用**特定于应用程序的版本信息**来跟踪进度，需要记录已经完成了多少进度，以便在写入过程中出现失败和重试时，避免产生重复数据。**事务标识符**允许将此信息与修改表内容的其他操作一起自动记录在 delta 表的事务日志中。

事务标识符以 <`appId`, `version`> 对的形式存储，其中 `appId` 是修改表的进程的唯一标识符，`version` 指示该应用程序已取得多少进展。 此信息和修改表的的原子记录一起，使得外部系统能够以幂等方式写入 Delta 表。

例如，[Delta Sink for Apache Spark's Structured Streaming](https://github.com/delta-io/delta/blob/master/core/src/main/scala/org/apache/spark/sql/delta/sources/DeltaSink.scala) 在使用以下过程对表进行流式写入时，确保了 **exactly-once** 语义：
  1. 在预写日志中记录将要写入的数据，以及该批次的单调递增标识符。
  2. 通过目标表中 `appId = streamId` 检查事务的当前版本。如果该值大于或等于正在写入的批次，则此数据已经添加到表中，可以跳过，并开始处理下一个批次数据。
  4. 将数据乐观地写入表中。
  5. 尝试提交包含增加的写入数据和更新  <`appId`, `version`> 对的事务。

应用特定 `version` 的语义由外部系统决定。Delta 只保证表快照中给定 `appId` 的最新`version` 可用。例如，Delta 事务协议并不假设 `version` 的单调性，并且允许 `version` 降低，可能表示早期事务的"回滚"。

`txn` 操作的 schema 如下：

字段名称 | 数据类型 | 描述 | 可选/必需
-|-|-|-
appId | `String` | 执行事务的应用程序的唯一标识符 | **必填** 
version | `Long` | 此事务的应用特定数值标识符 | **必填** 
lastUpdated | `Option[Long]` | 创建此事务操作的时间，自Unix纪元以来的毫秒数 | 选填 

以下是一个`txn`操作的例子：
```json
{
  "txn": {
    "appId":"3ba13872-2d47-4e17-86a0-21afd2a22395",
    "version":364475
  }
}
```

### 协议演变
`protocol` 操作用于增加读取或写入给定表所需的 Delta 协议版本。**协议版本化**允许新的客户端排除**缺少正确解释事务日志所需功能**的旧版本 Reader 和（/或）Writer。每当对本规范进行非向前兼容的更改时，都会增加**协议版本**。如果客户端运行的协议版本无效，应抛出错误，指示用户升级到更高版本的 Delta 客户端库。

由于重大更改必须伴随着表中记录的协议版本的提高或表功能的添加，客户端可以假设，==绝不需要无法识别的操作、字段和/或元数据域==就可以正确解释事务日志。<u>客户端必须忽略这样无法识别的字段，并且在读取包含无法识别字段的表时，不应产生错误</u>。

版本 3 的 Reader 和版本 7 的 Writer 向协议操作中==添加了两个表功能列表==。Reader 和 Writer 对此类表的操作能力不仅依赖于他们支持的协议版本，而且还取决于他们是否支持 `readerFeatures` 和 `writerFeatures` 中列出的所有特性。有关更多信息，请参见[表特性](#table-features)部分。

`protocol` 操作的 schema 如下：

字段名称 | 数据类型 | 描述 | 可选/必需
-|-|-|-
minReaderVersion | `Int` | 客户端必须实现的 Delta 读取协议的最小版本，才能正确地**读取**此表 | 必需
minWriterVersion | `Int` | 客户端必须实现的 Delta 写入协议的最小版本，才能正确地**写入**此表 | 必需
readerFeatures | `Array[String]` | 客户端必须实现的一系列特性，才能正确读取此表（只在`minReaderVersion`设置为`3`时存在） | 可选
writerFeatures | `Array[String]` | 客户端必须实现的一系列特性，才能正确写入此表（只在`minWriterVersion`设置为`7`时存在） | 可选

这里有些 Delta 协议的例子：
```json
{
  "protocol":{
    "minReaderVersion":1,
    "minWriterVersion":2
  }
}
```

只对 Writer 使用**表特性**的表：
```json
{
  "protocol":{
    "readerVersion":2,
    "writerVersion":7,
    "writerFeatures":["columnMapping","identityColumns"]
  }
}
```
上述例子中的 Reader 版本 2 不支持列出读取特性，但支持列映射。这个例子等同于下一个，其中列映射被表示为 Reader 的**表特性**。

对 Reader 和 Writer 都使用**表特性**的表：
```json
{
  "protocol": {
    "readerVersion":3,
    "writerVersion":7,
    "readerFeatures":["columnMapping"],
    "writerFeatures":["columnMapping","identityColumns"]
  }
}
```

### Commit 出处信息
Delta 可以选择包含有关执行的高级别操作以及执行者的附加来源信息。

可以通过 `commitInfo` 操作自由存储任何有效的 JSON 格式数据。

下面是一个存储与 `INSERT` 操作相关的出处信息的例子：
```json
{
  "commitInfo":{
    "timestamp":1515491537026,
    "userId":"100121",
    "userName":"michael@databricks.com",
    "operation":"INSERT",
    "operationParameters":{"mode":"Append","partitionBy":"[]"},
    "notebook":{
      "notebookId":"4443029",
      "notebookPath":"Users/michael@databricks.com/actions"},
      "clusterId":"1027-202406-pooh991"
  }  
}
```

### 领域元数据
**领域元数据**操作包含指定元数据域配置的字符串。如果两个重叠的事务都包含了对同一个<u>元数据领域</u>的<u>领域元数据操作</u>，那么它们就会发生冲突。

元数据领域有两种类型：
1. **用户控制的元数据领域** 的名称以 `delta.` 前缀以外的任何内容开始。任何 Delta 客户端实现或用户应用都可以修改这些元数据领域，并可以允许用户随意修改它们。鼓励 Delta 客户端和用户应用使用旨在为避免与其它客户端或用户的元数据领域冲突的命名约定（例如`com.databricks.*`或`org.apache.*`）。
2. **系统控制的元数据领域** 的名称以 `delta.` 前缀开始。这个前缀被保留给由 Delta 规范定义的元数据领域，Delta 客户端实现不得允许用户修改系统控制域的元数据。Delta 客户端实现应该只更新它了解和理解的系统控制域的元数据。系统控制的元数据域由各种表特性使用，并且每个表特性可以对其使用的元数据域强加附加语义。

`domainMetadata` 操作的 scheme 如下：

字段名称 | 数据类型 | 描述
-|-|-
domain | `String` | 该域的标识符（系统或用户提供） 
configuration | `String` | **包含元数据域配置的字符串** 
removed | `Boolean` | 为 `true` 时，操作作为一个**墓碑**标志来逻辑删除一个元数据领域。Writer **应该保留配置的准确原像**。 

为了支持这个特性：
- 该表必须是版本 7 Writer。
- 一个名为 `domainMetadata` 的特性名必须存在于表的 `writerFeatures` 中。

#### 对领域元数据的 Reader 要求
- Reader 不需要支持==领域元数据==。
- 选择不支持领域元数据的 Reader 应该忽略不认识的元数据领域操作（参见[协议演变](#protocol-evolution)），快照不应包含任何元数据领域。
- 选择支持领域元数据的 Reader 必须将[操作协调](#action-reconciliation)应用于所有元数据域，快照必须包含它们 —— 即使 Reader 不了解它们。
- 对 Reader  施加任何要求的系统控制域都是[重大变化](#protocol-evolution)，并且必须是指定所需行为的 Reader-Writer 表特性的一部分。

#### 对领域元数据的 Writer 要求
- Writer 必须保留所有领域，即使他们不了解它们。
- Writer 不得允许用户修改或删除系统控制的领域。
- Writer 只能修改或删除他们理解的系统控制领域。
- 对 Writer 施加额外要求的系统控制领域是一个[重大变化](#protocol-evolution)，并且必须是 Writer 表特性的一部分，该特性指定预期的行为。

以下是一个 `domainMetadata` 操作的例子：
```json
{
  "domainMetadata": {
    "domain": "delta.deltaTableFeatureX",
    "configuration": "{\"key1\":\"value1\"}",
    "removed": false
  }
}
```
### Sidecar 文件信息
`sidecar` 操作引用一个 [sidecar 文件](#sidecar 文件)，它提供了一些检查点的文件操作。此操作仅在遵循 [V2 规范](#v2-spec)的检查点中允许。

`sidecar` 操作的 schema 如下：

字段名称 | 数据类型 | 描述 | 可选/必需
-|-|-|-
path | `String`              | 对 sidecar 文件的 URI-encoded 路径。因为 sidecar 文件必须始终位于表自己的  **\_delta\_log/\_sidecars** 目录中，所以我们鼓励实现只存储文件的名称（无需scheme 或父目录）。 | 必需
sizeInBytes | `Long`                | sidecar 文件的大小。 | 必需
modificationTime | `Long` | 此逻辑文件创建的时间，以==新纪元==以来的毫秒数表示。 | 必需
tags|`Map[String, String]`|包含检查点 sidecar 文件额外的元数据。| 可选

以下是一个`sidecar`操作的示例：
```json
{
  "sidecar":{
    "path": "016ae953-37a9-438e-8683-9a9a4a79a395.parquet",
    "sizeInBytes": 2304522,
    "modificationTime": 1512909768000,
    "tags": {}
  }
}
```

#### 检查点元数据
此操作仅在遵循[ V2 规范](#v2-spec)的检查点中允许。它描述了关于检查点的细节。它具有以下 schema：

字段名称 | 数据类型 | 描述 | 可选/必需
-|-|-|-
version|`Long`|检查点版本。| 必需
tags|`Map[String, String]`|包含 v2 规范检查点的额外的元数据。| 可选

例如：
```json
{
  "checkpointMetadata":{
    "version":1,
    "tags":{}
  }
}
```