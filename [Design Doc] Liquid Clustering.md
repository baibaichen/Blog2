# [Design Doc] Liquid Clustering
## 动机
本设计文档提出了**Liquid Clustering**，这是一种为Delta设计的新型、灵活且可增量扩展的聚类机制。用户不再需要像`OPTIMIZE ZORDER BY`那样指定聚类列；相反，聚类列在表创建时指定，并持久化存储在表的元数据中。Liquid Clustering 还允许用户根据工作负载的变化调整聚类列。在更改聚类列后，现有数据不会重新聚类，只有新摄入的数据会按照新的聚类列进行聚类。

**分区/聚类**是管理数据集以减少不必要数据处理的常见技术。Hive 风格的分区和 ZORDER 聚类是 Delta 中现有的解决方案，但它们都有局限性。

**Hive风格的分区**

Hive风格的分区将数据聚类，使得每个文件仅包含一组唯一的分区列值组合。尽管 Hive 风格的分区在正确调优时表现良好，但它存在以下局限性：

- 由于分区值是文件的物理边界，对高基数列进行Hive风格的分区会产生大量无法合并的小文件，从而导致扫描性能下降。
- 在Spark/Delta中，一旦表被分区，其分区策略就无法更改，因此无法适应新的使用场景，例如查询模式的变化等。

**ZORDER聚类**

ZORDER是Delta中使用的一种多维聚类技术。`OPTIMIZE ZORDER BY`命令通过应用ZORDER聚类来提升在查询谓词中使用ZORDER BY列的查询性能。然而，它存在以下局限性：

- `OPTIMIZE ZORDER BY`是一种重写表中所有数据的操作，会导致较高的写放大（write amplification）。此外，当执行失败时，不会保存任何部分结果。
- ZORDER BY列不会被持久化存储，用户需要记住之前使用的ZORDER BY列，这常常会导致用户错误。

**术语**

- **Liquid Clustering**：一种利用Hilbert曲线和ZCube来支持增量聚类的技术。
- **写放大（Write Amplification）**：指多次重写相同的数据行。

##　需求

**功能性需求**

必须实现（MUST）：

- 用户界面（User Surface

  - 用户在创建Liquid表时，可以按任意顺序定义聚类列。

  - 用户可以通过`ALTER TABLE CLUSTER BY`更改或移除现有Liquid表的聚类列。

  - 默认情况下，用户最多可以指定4个聚类列。

  - 如果启用了列映射（column mapping），用户可以重命名现有Liquid表的聚类列。

  - 用户可以通过`OPTIMIZE`命令手动触发Liquid Clustering。

  - 聚类列通过`DESCRIBE DETAIL`命令向用户展示。

  - 用户可以使用`CREATE TABLE LIKE`创建Liquid表。


- 聚类功能（Clustering）**

  - Liquid Clustering必须能够增量地对新摄入的数据进行聚类。
  - Liquid Clustering必须基于当前的聚类列进行聚类。
  - Liquid Clustering应生成合适的文件大小，并应尊重为`OPTIMIZE`设置的目标文件大小。
  - 在更改聚类列后，Liquid Clustering应仅对新摄入的数据应用新的聚类列，而不应对更改前的现有数据进行重新聚类。


- 其他

  - 必须防止不支持Liquid Clustering的旧版Delta写入程序或外部写入程序对启用Liquid Clustering的表执行`OPTIMIZE ZORDER BY`。


## 用户界面（User Surface）
Liquid Clustering引入了以下新的SQL语法：  

### SQL语法
| 语法                                                         | 描述                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| `CREATE TABLE <table> USING delta CLUSTER BY (<col1>, <col2>, …)` | 创建一个Delta表，并使用`CLUSTER BY`指定的列作为Liquid Clustering的聚类列。 |
| `ALTER TABLE <table> CLUSTER BY (<col1>, <col2>, …)`         | 修改Liquid Clustering的聚类列。修改后新摄入的数据以及尚未聚类的数据将使用新的聚类列进行聚类。 |
| `ALTER TABLE <table> CLUSTER BY NONE`                        | 移除Liquid Clustering的聚类列。未来的数据摄入将不再进行聚类。 |
| `OPTIMIZE <table>`                                           | 触发Liquid Clustering。与现有的`OPTIMIZE`语义（仅压缩文件）不同，对于Liquid表，如果没有设置聚类列，则触发文件压缩；否则触发聚类操作。 |
| `OPTIMIZE ZORDER BY`                                         | 不允许对启用聚类的表执行此操作。                             |

---

### DeltaTable API
Liquid Clustering引入了以下新的DeltaTable API：  

| API名称                                           | 描述                                                         |
| ------------------------------------------------- | ------------------------------------------------------------ |
| `clusterBy(colNames: String*): DeltaTableBuilder` | 创建一个Delta表，并使用`CLUSTER BY`指定的列作为Liquid Clustering的聚类列。 |

**注**：我们将在OSS Spark中支持`clusterBy()`后，进一步完善`DataFrameWriter` API（目前正在开发中）。

## 提案概述

### 基于 Hilbert 曲线的更优聚类

目前，Delta支持通过`OPTIMIZE ZORDER BY`命令利用Z-Order曲线（[设计文档](https://docs.google.com/document/d/1TYFxAUvhtYqQ6IHAZXjliVuitA5D1u793PMnzsH_3vs/edit)）进行数据聚类。我们建议使用 **Hilbert曲线**（一种连续的分形空间填充曲线）作为Liquid的多维聚类技术，这将显著提升数据跳过（data skipping）能力，优于ZORDER。

与ZORDER类似，Hilbert曲线通过将多维数据映射到一维空间中来拟合曲线。这种映射方式能够很好地保持数据的局部性（locality），即在一维空间中接近的点在多维空间中也应该接近。我们可以利用这一特性来实现高效的数据跳过。以下是一个简单的两列表的示例，包含64条不同的记录。每个虚线矩形代表一个文件，每个文件包含4条记录。

- [ ] Fig 1 & Fig 2

在这个示例中，**我们首先通过对值分布进行范围分区（range partitioning），将两列A和B转换为[0, 7]的数值范围**。Hilbert曲线为我们提供了一个很好的特性：曲线上相邻的点之间的距离总是1。为了利用这一点，我们通过曲线上的点对数据进行分区，然后将附近的点打包成大小合适的文件。这意味着每个文件包含曲线上彼此接近的点，因此它们在每个聚类维度上的最小/最大范围也会很接近。

**为什么Z曲线比Hilbert曲线差？**

还记得Hilbert曲线的优良特性吗（见图1）？Z曲线并不具备这种特性。Z曲线上相邻的点之间的距离并不总是1，而且曲线上存在较大的跳跃。==这些跳跃会导致曲线子范围的边界框大小非线性（甚至可能巨大）地增加==。例如，让我们看一下同样长度为6的橙色线段。对于Z曲线，图3中显示的边界框覆盖了整个空间！而对于Hilbert曲线，相同长度的范围只能覆盖一半的空间（如图4所示），因为它只能覆盖两个相邻的象限。这意味着对于Z-Order，某些文件的min/max范围可能等于整个范围，数据跳过无法跳过这些文件。

> 通过使用Hilbert曲线，Liquid Clustering能够更有效地组织数据，减少文件之间的重叠范围，从而显著提升数据跳过能力，优化查询性能。

------

**图例说明**

- **图1**：Hilbert曲线的局部性特性，相邻点距离为1。
- **图3**：Z曲线的边界框覆盖整个空间，导致数据跳过效率低下。
- **图4**：Hilbert曲线的边界框仅覆盖部分空间，数据跳过更高效。

###　基于ZCube的增量聚类

目前，`OPTIMIZE ZORDER BY`需要重写所有数据，即使自上次运行以来没有添加新文件。这使得在大型表上运行该操作非常昂贵。此外，当操作失败时，所有进度都会丢失，下一次运行需要从头开始。

我们建议为Liquid引入增量聚类功能，允许用户在不重写所有数据的情况下运行`OPTIMIZE`。`OPTIMIZE`还将以批处理的方式完成，每批处理将生成一个单独的`OPTIMIZE`提交，这样即使出现问题，也不会丢失所有进度。

增量聚类的核心概念是**ZCube**。ZCube是由同一个`OPTIMIZE`任务生成的一组文件。由于我们只希望重写新的或未优化的文件，因此我们通过在`AddFile`中使用`ZCUBE_ID`标签来区分已经优化的文件（属于某些ZCube）和未优化的文件。每个新的ZCube将使用UUID生成一个唯一的`ZCUBE_ID`。

有几种策略可以选择要集群的文件，更多详细信息可以在这里[找到](https://docs.google.com/document/d/1FWR3odjOw4v4-hjFy_hVaNdxHVs4WuK1asfB6M6XEMw/edit#bookmark=kix.301alpimymwh)。为了提供灵活性并控制哪些文件参与聚类，我们将引入两个配置参数：

1. **MIN_CUBE_SIZE**：
   - 定义ZCube的最小大小，当ZCube达到该大小时，新的数据将不再与其合并。
   - 默认值为 **100 GB**。
2. **TARGET_CUBE_SIZE**：
   - 定义我们创建的ZCube的目标大小。这不是一个严格的最大值；系统会继续向ZCube添加文件，直到它们的总大小超过该值。
   - 该值必须大于或等于`MIN_CUBE_SIZE`。
   - 默认值为 **150 GB**。