# Apache Calcite A Foundational Framework for Optimized Query Processing Over Heterogeneous Data Sources
## 摘要

[Apache Calcite](https://calcite.apache.org/)是一个基础软件框架，提供了查询处理、优化和查询语言，支持多个主流开源数据处理系统，比如 Apache Hive，Apache Storm，Apache Flink，Druid和MapD。Calcite的架构由如下组件构成：

- 模块化、可扩展的优化器，内置了上百个优化规则；
- 查询处理器，可以处理各种查询语言；
- 适配器架构设计，用于扩展和支持异构数据源和存储（关系模型、半结构化、流和地理空间）。

这个灵活、可内嵌和可扩展的架构，使得Calcite在大数据框架中被应用是一个很好的选择。这是一个很活跃的项目，会持续地引入新的数据类型，查询语言、查询处理和优化的方法。

## 1. 引言

遵循具有重要意义的关系数据库系统，传统关系数据库引擎主导了数据处理领域。然而，早在2005年，Stonebraker和Çetintemel预测[49]，我们将看到一系列特定的引擎，如列式存储、流处理引擎，文本检索引擎等。他们争论着只有特定的引擎才能提供高效的性能，结束“one size fits all”的模式。他们的愿景今天似乎比以往任何时候都更有意义。事实上，许多专门的开源系统已经流行起来，比如Storm[50]和Flink[16]（流处理），Elasticsearch[15] (文本检索)，Apache Spark [47]，Druid [14]等等。

由于各个组织根据他们的需要在定制化数据处理系统上的投资，出现了两个重要的问题：

- 这些特定系统的开发者们已经遇到一些相关的问题，比如查询优化[4,25]，或者查询语言的支持，比如SQL和相关扩展（流式查询[26]），以及受LINQ启发的语言集成查询[33]。没有一个统一的框架，许多工程师独自开发相似的优化逻辑和语言支持，是在浪费精力。
- 程序员们使用这些特定的系统，不得不把它们集成在一起。一个组织也许依赖Elasticsearch、Spark和Druid。我们需要构建一个系统，能够支持在跨异构数据源[55]上进行优化查询的能力。

Apache Calcite的开发就是被用来解决上述问题的。它是一个完整的查询处理系统，支持查询处理、优化和语言，是任何数据库管理系统所需要的，除了数据的存储和管理放置到特定的引擎中。Calcite很快就被Hive，Drill[13]，Storm和许多其他数据处理引擎所采用。比如，Hive[24]是一个主流的基于Hadoop的数仓项目。因为，Hive从批处理看框架转为了交互式SQL查询平台，很显然该项目在它的核心基础之上需要一个强大的优化器。因此，Hive采用Calcite作为它的优化器，它们的集成也一直在发展。许多其他项目或产品，也遵循着这种方式，包括Flink、MapD[12]等等。

因此，Calcite通过暴露公共接口给多个系统，能够进行跨平台的优化。为了提高效率，优化器需要进行全局性地推理。例如，在多个不同系统上，进行物化视图的选择。

构建一个通用的框架并非没有挑战。尤其，该框架需要有足够的可扩展性和灵活性，来满足不同类型系统的集成要求。

我们相信以下特性可以促进Calcite在开源社区和工业界的广泛使用：

- **开源友好**：在过去10年的主要数据处理平台已经是开源的或大部分是基于开源的。Calcite是一个开源框架，由Apache基金会[5]支持，提供一种协作开发项目的方式。而且，该软件由Java编写，更加容易和多个新的数据处理系统交互[12,13,16,24,28,44]，它们本身也是用Java写的（或者是基于JVM的Scala），尤其是Hadoop生态系统中的那些系统。
- **多数据模型**：Calcite提供查询优化和查询语言的支持，使用流式和传统数据处理模式。Calcite将流看作时间顺序的记录集合或事件，它们没有像传统数据处理系统那样，被持久化在磁盘上。
- **灵活的查询优化器**：优化器的每个组件都是可插拔和可扩展的，从规则到代价模型。而且，Calcite支持多种计划引擎。因此，优化过程可以被拆解为多个阶段，通过不同优化引擎来处理，这取决于哪个优化引擎更适合这个阶段。
- **跨系统支持**：Calcite框架能够运行和优化多个查询处理系统和后端数据库。
- **可靠性**：Calcite是靠的，因为多年的广泛使用，带来了平台的大量的测试。Calcite也包含了一些扩展的测试套件，来验证系统的所有组件，包括查询优化器规则和后端数据源的集成。
- SQL支持和扩展：许多系统并不提供它们自己的查询语言，但是更倾向依赖已有的东西，比如SQL。为了这些，Caclite提供了对ANSI标准SQL的支持，以及各种SQL方言和扩展。比如，在流式数据或嵌套数据上的表达式查询。而且，Calcite还包含了符合JDBC标准的驱动。

剩余章节的组织如下。第二章讨论相关工作，第三章介绍Calcite架构和主要组件，第四章描述关系代数在Calcite的Core中，第五章阐述Calcite的适配器，定义怎样读取外部数据源的一个抽象。然后，第六章节，描述Calcite的优化器和主要特性。第七章描述处理不同查询处理模式的扩展。第八章，给出了一个已经使用Calcite的数据处理系统概览。第九章讨论该框架的未来扩展，第十章总结。

## 2. 相关工作

虽然，Calcite是当前Hadoop生态系统中被大数据分析广泛采用的优化器，它背后的思想其实并不新奇。例如，优化器的思想是源于**Volcano**[20]和**Cascades**[19]框架，结合其他广泛使用的优化器技术，比如**物化视图重写**[10,18,22]。还有其他系统尝试为Calcite填补类似的功能。

**Orca**[45]是一个模块化查询优化器，使用在数据管理产品中，如GreenPlum和HAWQ。Orca通过实现一个用于在两者之间交换信息的框架（称为数据交换语言），将优化器与查询执行引擎分离。Orca还提供了用于验证生成的查询计划的正确性和性能的工具。相比于Orca，Calcite可以用于独立的查询执行引擎，联合多个存储和后端处理，包括可插拔计划和优化器。

**Spark SQL**[3]扩展了Apache Spark来支持SQL查询执行器，也可以在Calcite的多个数据源上执行查询。然而，虽然在Spark中的**Catalyst优化器**也尝试最小化查询执行的成本，但是它缺乏Calcite中使用的动态规划，有陷入局部最小化的风险。

**Algebricks**[6]是一个查询编译器架构，为大数据查询处理提供了数据模型无关的代数层和编译器框架。高等级语言被编译为Algebricks的逻辑代数。Algebricks会生成一个优化的作业，用于Hyracks的后端并行处理。Calcite与Algebricks共享模块化方法，还支持基于成本的优化。在当前版本的Calcite中，查询优化器架构，采用的是基于Volcano[20]的动态规划，以及扩展的Orca[45]中多阶段优化。虽然，在原理上Algebricks能够支持多个后端处理（比如，Tez，Spark），但是多年来Calcite为不同的后端提供了良好的测试支持。

**Garlic**[7]是一个异构数据管理系统，可以将来自多个系统的数据用统一的对象模型表示。然而，Garlic不支持来自不同系统的查询优化，依赖每个系统优化自己的查询。

**FORWARD**[17]是一个联合查询处理器，实现了SQL的超集，即SQL++[38]。SQL++有半结构化数据模型，将JSON和关系数据模型集成进来。而Calcite在查询计划期间，半结构化数据模型是通过关系数据模型表示的。SQL++将联合查询拆解为多个子查询，然后根据相应的查询计划，在底层数据库中执行。最后，FORWARD引擎进行数据的合并。

另一个，联合的数据存储和处理系统是**Big-DAWG**。它抽象了一个广泛的数据模型，包括关系型、时序、流式。在Big-DAWG中的一个抽象单元，叫island of information（信息孤岛）。每一个island of information有一个查询语言、数据模型，能够连接到一个或多个存储系统。在单个island of information的边界中，支持跨存储系统的查询。相反，Calcite采用了一个统一的关系抽象模型，来支持跨多个具有不同数据模型的后端查询。

**Myria**是一个通用的大数据分析引擎，对Python语言[21]高度支持。用于为其他后端引擎生成查询计划，比如Spark、PostgreSQL。

## 3. 架构

Calcite包含很多构成典型数据库管理系统的部分。然而，它跳过了一些关键组件，如数据存储、处理数据算法和存储元数据的仓库。这些舍弃是经过深思熟虑的，在具有多个数据存储位置和多个数据处理引擎的应用之间，Calcite作为一个中间媒介是最好的选择。同时，它也是构建定制的数据处理系统的坚实基础。

图1给出了Calcite架构的主要组件，Calcite的优化器使用关系算子树来作为内部表示。这个优化器引擎，主要由三个组件构成：rules、metadata providers以及planner engines。在第六章我们将深入讨论这些组件的细节。途中的虚线表示和其他框架的外部集成，和 Calcite 集成有**很多种方式**。

<p align="center">
 <img src="http://loopjump.com/wp-content/uploads/2019/11/image-20191029173659790-1024x871.png"/>
图1 Calcite 的架构和组件之间的交互
</p>

**首先**，Calcite 包含一个**查询解析器**和**验证器**，能够将 SQL查询翻译为关系算子树。因为 Calcite 不包含**存储层**，但提供了一个机制，可通过**适配器**（第五章讲述）来定义外部存储引擎里表和视图的结构，所以它被用于这些引擎之上。

其次，虽然 Calcite 为需要这种数据库语言支持的系统提供了优化的 SQL 支持，但它也为<u>已经有自己语言解析和解释</u>的系统提供了优化支持：

- 一些支持 SQL 查询的系统，没有或有限的查询优化。例如，Hive 和 Spark 早期就提供SQL支持，但不包含优化器。针对这样的场景，一旦查询已经被优化，Calcite 能够再次将关系算子树转为 SQL。这样的特性，可以使得 Calcite 可以独立运行在任何有 SQL 但没有优化器的数据管理系统之上。

- Calcite 的架构不仅仅专为优化SQL查询。通常，数据处理系统针对它们自己的查询语言使用自己的解析。Calcite也能够有助于优化这些查询。事实上，Calcite允许算子树通过直接实例化来构建，使得构建变得更加容易。有一种是可以使用内置的 relational expressions builder 接口。例如，假设我们想使用 expression builder 来表达如下 Pig[41] 的脚本。

  ```
  emp = LOAD 'empolyee_data' AS (deptno, sal);
  emp_by_dept = GROUP emp BY (deptno);
  emp_agg = FOREACH emp_by_dept GENERATE GROUP as deptno, COUNT(emp.sal) AS c, SUM(emp.sal) as S;
  dump emp_agg;
  ```

  等价表示如下所示：

  ```java
  final RelNode node = builder
      .scan("employee_data")
      .aggregate(builder.groupKey("deptno"),
                 builder.count(false, "c"),
                 builder.sum(false, "s", builder.field("sal")))
      .build();
  ```

  这个接口给出了在构建关系表达式时的主要构建过程。在优化阶段完成之后，应用程序会得到优化后的关系表达式，能够再映射到系统查询处理单元中。

## 4. 查询代数

**Operators**。关系代数[11]是 Calcite 的核心。除了表达常见的数据操作的算子之外，例如 `filter`，`project`，`join` 等，Calcite 还包含一些额外的操作，来满足不同的需求，例如简洁地表达复杂的操作和高效地识别优化的时机。例如，针对 OLAP，决策制定和流式应用，使用 window 定义来表达复杂分析函数，如数量在一个时间周期或数据行数上的移动平均数，是很常见的。因此，Calcite 引入了*window* 算子来封装window定义，即上下边界、分区等，以及在每个窗口内执行聚合函数。

**Traits**。Calcite 没有使用不同的实体来表示逻辑和物理算子，而是通过使用 *traits* 关联一个算子，来描述它的物理属性。这些 traits 有助于优化器评估不同可选算子的成本。改变 trait 的值，并不是改变正在评估的逻辑表达式，即给定的算子输出的行还是一样的。

在优化期间，Calcite会尝试在关系表达式上增强某个特定的 traits，例如特定字段的排序顺序。关系算子会实现一个 `converter` 接口来表明如何将表达式的 traits 从一个值转为另一个值。

Calcite 包含了一些常见的 traits，这些 traits描述了关系表达式生产数据的物理属性，例如，*ordering*、*grouping* 和 *partitioning*。和 SCOPE优化器[57]类似，Calcite优化器能够分析属性和利用它们寻找计划，来避免不必要的操作。例如，如果 sort 算子的输入已有正确排序，即底层系统这些数据有同样的排序，就可以移除 sort 操作。

除了这些属性，Calcite 的重要特性之一就是 **Calling convention** 的 trait。本质上，这个 trait 表明了该表达式将在相应的数据处理系统中执行。包含 **Calling convention** 的 trait，使得 Calcite 达到透明优化查询的目标，这些查询也许会横跨不同的引擎，即 **Calling convention** 将会被视为任何其他物理属性。

例如，考虑将 MySQL 中的 Products 表连接到 Splunk 中的 Orders 表（参见图 2）。 最初，订单的扫描在 splunk 约定中进行，产品的扫描在 jdbc-mysql 约定中进行。 这些表必须在其各自的引擎内进行扫描。 连接符合**==逻辑约定==**，这意味着尚未选择任何实现。 此外，图 2 中的 SQL 查询包含一个过滤器（where 子句），它由特定于适配器的规则推送到 splunk（参见第 5 节）。 一种可能的实现是使用 Apache Spark 作为外部引擎：join 转换为 spark 约定，其输入是从 jdbc-mysql 和 splunk 到 spark 约定的转换器。 但是有一个更有效的实现：利用 Splunk 可以通过 ODBC 对 MySQL 执行查找的事实，规划器规则通过 splunk-to-spark 转换器推送连接，现在连接采用 splunk 约定，在 Splunk 引擎内部运行。

<p align="center">
 <img src="http://loopjump.com/wp-content/uploads/2019/11/image-20191030112430474-1024x462.png" />
图2 查询优化过程
</p>


## 5. 适配器

适配器是一个**结构模式**，定义了 Calcite 如何和多种数据源交互，实现统一访问。图 3 描述了它的组件。本质上，一个适配器由一个 **model**、一个 **schema** 和一个 **schema factory** 构成。**model** 描述被访问数据源的物理属性。**schema** 是在 **model** 中可以找到的数据定义（格式和布局）。数据本身物理上是通过表访问。Calcite 接口与适配器中定义的表连接，以便在执行查询时读取数据。适配器也许会定义一系列规则，并添加到 planner 中。例如，包含一些规则<u>将各种**逻辑关系表达式**转为**适配器调用约定**的相应**关系表达式**</u>。**Schema factory** 组件从 **model** 获取元数据信息来创建 **schema**。



<p align="center">
 <img src="https://changbo.tech/blog/10fa9651/adapter_design.png" />
图3 适配器设计
</p>
如第 4 节所述，Calcite 使用称为 **calling convention** 的 **physical trait** 来识别对应于特定数据库后端的关系运算符。<u>这些物理运算符在每个适配器中实现了底层表的访问路径</u>。当解析查询并转换为关系代数表达式时，将为每个表创建一个运算符，表示扫描该表上的数据，它是适配器必须实现的最小接口。如果适配器实现了**表扫描运算符**，Calcite 优化器就能够使用**客户端运算符**，比如 sorting，filtering 和 joins，在这些表上执行任意的 SQL 查询。

这个**表扫描运算符**包含适配器向其后端数据库发出扫描所需的必要信息。为了扩展适配器提供的功能，Calcite 定义了一个**可枚举**的 **calling convention**。带有可枚举 **calling convention** 的关系运算符只是通过**迭代器接口**对元组进行操作。这种 **calling convention** 允许 Calcite 实现每个适配器后端可能不支持的运算符。例如，`EnumerableJoin` 运算符实现 `Join` 操作，从其子节点收集数据，并在需要的属性上进行 `Join` 操作。

对于只涉及表中一小部分数据的查询，让 Calcite 读取所有元组很低效。幸运的是，可以使用现有的基于规则的优化器，实现特定于适配器的优化规则。例如，假设查询涉及对表进行过滤和排序，可以在后端执行过滤的适配器可以实现匹配 `LogicalFilter` 的规则，并将其转换为适配器的 **calling convention**。该规则将 `LogicalFilter` 转换为另一个 `Filter` 的实例。新的 `Filter` 节点具有较低的成本，从而允许 Calcite 可以跨适配器来优化查询。

使用适配器是一种强大的抽象，不仅支持对特定后端进行查询优化，而且支持跨多个后端进行查询优化。通过将所有可能的逻辑下推到每个后端，然后对结果数据执行连接和聚合，Calcite 能够回答涉及多个后端表的查询。实现适配器可以像提供**表扫描运算符**一样简单，也可以涉及许多高级优化的设计。**关系代数中表示的任何表达式都可以通过优化器规则下推到适配器**。

> **==调用约定==**本质是表示可以在底层数据源执行的运算符。
>
> 这里本质是做各种下推？

## 6. 查询处理和优化

查询优化器是Calcite框架中的核心组件。Calcite通过不断重复地在关系表达式上应用planner rules来优化查询。一个代价模型主导这个处理过程，planner引擎尝试生成一个可替代的表达式，它的语义和原始的保持一样，并且代价更低。

**在优化器中的每个组件都是可以扩展的，用户可以添加关系算子，规则，代价模型和统计信息。**

**Planner Rule**。Calcite包含了一系列的planner rules来转换expression trees。具体来说，一个规则匹配了tree中的一个模式，然后执行一个保留expression语义的转换。Calcite包含了数百个优化规则。然而，依赖Calcite的数据处理系统，包含了它们自己的优化规则，允许有特定的重写，也是很常见的一种方式。

例如，Calcite提供了一个Apache Cassandra[29]的适配器，一个宽表存储通过部分列进行分区，然后在每个分区中，基于其他列进行行排序。正如第五章讨论的，一个适配器尽可能高效地将查询处理下推之到每个后端是非常有益的。下推sort到Cassandra的规则需要满足两个条件：

- 表现前已经过滤到单个分区级别（行排序仅仅在一个分区中）；
- 要求的排序和Cassandra中的分区排序有相同的前缀。

要求`LogicalFilter`被重写为`CassanddraFilter`，保证分区过滤被下推之数据库中。规则作用很简单（将`LogicalSort`转为`CassandraSort`），但是规则匹配的灵活性使后端能够在复杂的场景中下推算子。

例如，一个复杂用途的规则，看如下查询：

```SQL
SELECT products.name, COUNT(*)
FROM sales JOIN products USING (productId)
WHERE sales.discount IS NOT NULL
GROUP BY products.name
ORDER BY COUNT(*) DESC;
```
<p align="center">
 <img src="http://loopjump.com/wp-content/uploads/2019/11/image-20191031115353130.png" />
图4 FilterIntoJoinRule 应用
</p>


上述查询相应的关系代数表达式如图4所示。因为，Where仅仅作用在sales表上，我们可以在Join之前移动filter。这个优化能够极大减少查询执行的时间，因为我们不需要执行谓词没有匹配的行的Join操作。甚至，如果sales和products表都在同一个底层存储中，在Join前移动filter使得适配器将filter下推至底层。Calcite通过`FilterInoJoinRule`实现了这个优化，将filter节点和作为父节点的Join节点进行匹配，检测filter是否可以被join执行。这种优化方式，体现了Calcite优化方式的灵活性。

**Metadata providers**。元数据是Calcite的优化器很重要的一部分，主要有两个作用：一是引导planner往减少整个查询计划成本的方向为目标，二是在应用规则提供一些信息。

元数据提供者主要负责给优化器提供信息，特别在calcite的元数据providers的默认实现中包含了一些方法，可以返回在操作树中执行一个子表达式的总体成本，表达式结果的行数、数据大小，以及可以运行的最大并发度。继而，它还可以提供一个查询计划的结构，比如在一个tree node下的filter condition。

Calcite的providers接口可以允许数据处理系统将它们的元数据挂载到框架中。这些系统也许会选择实现providers，包括重写已有的函数或提供它们自己新的元数据函数，在优化阶段使用到。然而，对于它们当中大部分来说，提供输入数据的统计信息就已经足够了。比如，一个表的数据行数和大小，一个给定列的值是否是唯一的，以及Calcite还会使用默认实现做剩下的工作。

由于metdata providers是可插拔的，所以它们可以在运行期间通过使用Janio[27]（一个java轻量级编译器）来进行编译和实例化。它们的实现包含一个元数据结果缓存，可以达到显著的性能提升。比如，当我们需要计算不同类型的元数据时，例如基数、平均行大小和给定联接的选择性，所有这些计算都依赖于输入的基数。

**Planner engines**。一个planner engine的主要目标是触发提供给引擎的规则，直到达到给定的目标。此时，Calcite提供了两种不同的引擎。新的引擎在框架中是可插拔的。

第一个是基于代价的planner engine，基于减少表达式执行代价的目标，来触发输入的规则。该引擎使用动态规划算法，类似Volcano[20]，通过触发给定引擎的规则，来创建和跟踪多个可替换的计划。首先，每个表达式都在planner处注册，以及基于表达式属性和它的输入形成一个digest。当一个规则在表达式e1中触发后，就会生成一个新的表达式e2，planner就会将e2加入一个等价表达式集合Sa中，e1也属于该集合。同时，planner会生成一个新表达式的digest，和之前注册在planner中的表达式digest进行比较。如果在Sb中找到一个和表达式e3有类似digest，表示planner找到重复，将合并Sa和Sb成一个新的等价集合。这个处理过程持续到planner达到一个可配置的fix point。尤其是，它能够非常详尽地探索搜索空间直到所有规则已经应用在所有表达式上。或者，使用启发式规则，即当在最后一次计划迭代时超过给定阈值*δ*也不能提升执行代价时，来停止搜索。由metadata providers提供的代价函数可以让优化器决定选择哪一个计划。**默认的代价函数实现，整合了对给定表达式在CPU、IO和内存资源使用上的评估**。

第二个引擎是一个详尽的planner，尽可能详尽地触发rules直到生成一个不再被任何规则更改的表达式。这个planner在快速执行规则不用考虑每个表达式代价时是非常有用的。

用户选择使用已有的planner引擎，取决于他们具体的需要。当他们的系统需求改变时，可以从一个切换到另一个是很简单的。另外，用户可以选择生成多阶段优化逻辑，在优化过程的连续阶段应用不同的规则集合。重要的是，两种planner允许Calcite用户通过指导搜索不同的查询计划来减少整个优化时间。

**Materialized Views**。在数仓中一个用来加速查询处理的强大技术，就是相关摘要数据预计算或者物化视图。多个Calcite 适配器和依赖 Calcite 的项目有它们自己的物化视图的概念。例如，Cassandra 允许用户基于已有的表定义物化视图，由系统自动维护。

这些引擎将它们的物化视图暴露给 Calcite，优化器就有机会通过使用视图来替换原表，来将接收的查询重写。尤其，**Calcite提供了两种不同的基于物化视图的重写算法**。

第一个方法是基于视图替换（*view substitution*）[10,18]。这个目的是通过等价表达式（使用物化视图）来替换关系代数树中的一部分，这个算法流程是：(i) 物化视图上的 scan 算子和定义物化视图的 plan 被注册到优化器中，以及 (ii) 并触发转换规则以统一 plan 中的表达式。视图不需要与被替换的查询中的表达式完全匹配，因为 Calcite 的重写算法可以产生部分重写，包含了用于计算所需表达式的额外操作，如带有剩余谓词条件的 filters。

第二个方法是基于 lattices[22]。一旦一个数据源被声明形成一个 lattice，Calcite 会将每个物化信息表示成一个 **tile**，从而优化器可以使用它们来匹配进入的查询。一个方面，这个重写算法在用 star schema 组织的数据源上进行表达式匹配更加高效，通常用于 OLAP 应用。另一方面，它比视图替换更具限制性，因为它对底层模式施加了限制。

## 7. 扩展 Calcite

之前章节我们已经提到，Calcite不仅仅面向SQL处理进行定制。**实际上，Calcite提供了对SQL的扩展，来表达在其他数据抽象上的查询，比如半结构化、流式和地理空间的数据**。它的内部算子适配这些查询。除了对SQL的扩展，Calcite也包含了一种语言集成查询语言。我们将通过本章节来描述这些扩展，并提供一些示例。

### 7.1 半结构化数据

Calcite支持许多复杂字段数据类型，使得关系型和半结构化数据混合存储在表中。尤其，当列是ARRAY、MAP和MULITSET类型时。而且，这些复杂类型是可以嵌套的，例如MAP类型的values可以是ARRAY。ARRAY和MAP列中的数据，可以通过`[]`操作符提取。存储在这些复杂类型中的特殊类型值不需要预先定义。

例如，Calcite包含一个MongoDB适配[36]，一个文档存储，这些文档由类似json文档那个的数据组成。为了将MongoDB数据抛给Calcite，每个文档都创建一个单列（名为_MAP）的表。许多场景下，希望文档具有一个共同的结构。一个表示邮政编码的文档集合，也许每个都包含字段city name, latitude和longitude。将这些数据表示成一个关系表很有用。在Calcite中，可以抽取想要的值和转为正确的类型后，创建一个视图。

```
SELECT CAST(_MAP['city'] AS varchar(20)) AS city,
CAST(_MAP['loc'][0] AS float) as longitude,
CAST(_MAP['loc'][1] AS float) as latitude
FROM mongo_raw.zips;
```

以这种方式建立在半结构化数据上的视图，就更容易地同时操作不同半结构化数据源和关系型数据。

### 7.2 流

Calcite基于标准SQL进行了特定流式扩展，提供了一流的流式查询[26]，叫做*STREAM*扩展，windowing扩展，通过在join或其他操作中使用window表达式，来显式地使用流。这些扩展受到持续查询语言[2]的启发，尝试和标准SQL进行有效地集成。主要的扩展就是，通过*STREAM*声明，告诉系统用户对新入的记录感兴趣，而不是已有的记录。

```
SELECT STREAM rowtime, productId, units
FROM Orders
WHERE units > 25;
```

查询流的关键词STREAM去掉后，查询就变为了普通的关系查询，表示系统应该处理已有的记录，即从流中已经接收的记录，而不是新入的记录。

由于流固有的无边界特性，windowing用于解除阻塞运算符，比如Aggregate和Joins。Calcite的流扩展使用SQL分析函数来表达**滑动和级联窗口聚合**，如下示例所示：

```sql
SELECT STREAM 
  rowtime, 
  productId, 
  units,
  SUM(units) OVER (
      ORDER BY rowtime 
      PARTITION BY productId 
      RANGE INTERVAL '1' HOUR PRECEDING
  ) unitsLastHour
FROM Orders;
```

翻滚（Tumbling）、跳跃（Hopping）和会话（Session）窗口，通过TUMBLE，HOPPING，SESSION函数开启，相关实用函数比如TUMBLE_END和HOP_END。它们可以分别使用在GROUP BY的clauses和projections。

```
SELECT STREAM
  TUMBLE_END(rowtime, INTERVAL '1' HOUR) as rowtime,
  productId,
  COUNT(*) AS c,
  SUM(units) AS units
FROM Orders
GROUP BY TUMBLE(rowtime, INTERVAL '1' HOUR), productId;
```

涉及窗口聚合的流式查询要求在GROUP BY子句中或在ORDER BY子句中存在单调或准单调表达式，以防滑动和级联窗口查询。

涉及更加复杂的流和流JOIN的流式查询，可以通过在JOIN字句中使用隐式窗口表达式来表示。

```
SELECt STERAM 
  o.rowtime, 
  o.productId, 
  o.orderId,
  s.rowtime AS shipTime
FROM Orders AS o
JOIN Shipments AS s 
ON o.orderId = s.orderId 
AND s.rowtime BETWEEN o.rowtime AND o.rowtime + INTERVAL '1' HOUR;
```

在这个隐式窗口的例子中，Calcite的query planner会验证这个表达式是单调的。

### 7.3 地理空间查询

地理空间支持在Calcite中刚起步，但是正在使用关系代数来实现。核心就是增加一个GEOMETRY的数据类型，来封装不同的几何对象，比如点(point)、曲线(curve)和多边形(polygon)。Calcite将完全兼容OpenGIS Simple Feature Access[39]规范，该规范为访问地理空间数据的SQL接口定义了一个标准。2.下面给出一个列子，查询包含Amsterdam的国家：

```
SELECT name FROM(
  SELECT name, 
    ST_GeomFromTet('Polygon((4.82 52.543, 4.97 52.43, 4.97 52.33, 4.82 52.33, 4.82 52.33))') AS "Amsterdam",
    ST_GeomFromText(boundary) AS "Country"
  FROM country
)
WHERE ST_Contains("Country", "Amsterdam");
```

### 7.4 JAVA语言集成查询

Calcite可以用于查询多个数据源，不仅仅是关系型数据库，但它的目标也不仅仅是支持SQL语言。虽然，SQL仍然是数据库的主要语言，但是很多程序员喜欢使用语言集成语言，如LINQ[33]。不像SQL是内嵌在JAVA或C++代码中，语言集成查询语言允许程序员使用一种语言来写他们的代码。Calcite提供了针对JAVA的语言集成查询语言（简称LINQ4J），它严格遵循了微软的LINQ对.NET语言的约定。

## 8. 工业和学术界应用

Caclite得到了广泛的应用，尤其是在工业界中使用的开源项目。由于Calcite提供了特定集成的灵活性，这些项目选择在它们的core中内嵌Calcite（即作为library引入）或者实现的一个适配器来联邦查询处理。此外，我们看到研究界越来越有兴趣将Calcite作为开发数据管理项目的基石。下面，我们将介绍使用Calcite的不同项目。

### 8.1 内嵌Calcite

表1给出了使用Calcite的软件列表，包含以下几个维度：

- 暴露给用户的查询接口；
- 是否使用 Calcite 的 JDBC 驱动（Avatica）；
- 是否使用 Calcite 中的 SQL 解析和验证；
- 是否使用 Calcite 的查询代数来表示在数据上的操作；
- 是否依赖 Calcite 引擎来执行，即使用自己的原生引擎还是 Calcit 算子（enumerable）或者其他项目。

[![img](https://changbo.tech/blog/10fa9651/embed_calcite_systems.png)](https://changbo.tech/blog/10fa9651/embed_calcite_systems.png)

表1 内嵌Calcite的系统列表

Drill[13]是一个基于Dremel系统[34]的灵活数据处理引擎，内部使用无模式JSON数据模型。Drill使用它自己的SQL方言，包括半结构化数据查询表达的扩展，类似SQL++[38]。

Hive[24]第一次作为MapReduce编程模型之上的SQL接口而变得很流行。此后，它逐步转向成为一个交互式SQL查询引擎，采用Calcite作为它的基于规则和代价的优化器，不依赖Calcite的JDBC驱动、SQL解析和校验，采用自己的组件来实现。**查询先翻译为Calcite的算子，经过优化之后，再翻译为Hive的物理代数**。Hive算子能够在多个引擎上执行，主流的有Aapche Tez[43, 51]和Apache Spark[47, 56]。

Apache Solr[46]是一个主流的全文分布式检索平台，基于Apache Lucene库[31]构建。Solr给用户提供了多个查询接口，包扩类似Rest的HTTP/XML和JSON接口。而且，Solr集成Calcite来提供SQL兼容。

Apache Phoenix{40]和Apache Kylin[28]都运行在Apache HBase[23]之上，它是继Bigtable[9]之后的一个分布式KV存储。具体来说，Phoenix提供了一个SQL接口和编排层来查询HBase。**Kylin聚焦于OLAP式查询，通过构建cubes来声明物化视图并存储在HBase中，因此可以通过Calcite的优化器来重写输入的查询，使用cubes来处理查询**。**在Kylin中，查询计划的执行，是结合了Calcite原生算子和HBase的能力**。

近来，Calcite在流处理系统中也越来越流行。比如Apache Apex[1]，**Flink**[16]，Apache Samza[44]以及**Storm**[50]，这些项目选择和Calcite集成，使用它的组件来提供流SQL接口给用户。最后，其他商业系统也有采用Calcite的，比如MapD[32]，Lingual[30]和Qubole Quark[42]。

### 8.2 Calcite适配

除了将Calcite作为库来使用，其他系统也可以通过适配器方式集成Calcite，读取他们的数据源。表2给出了Calcite中的适配器列表。实现这些适配器最主要的组件就是*converter*，负责翻译关系代数表达式，推出给系统支持的查询语言。表中还给出了每个适配器翻译的语言。

JDBC适配器支持多个SQL方言，包括主流的RDBMS，比如PostgreSQL和MySQL。另外，Cassandra[8]适配器生成自己的类SQL语言，叫CQL。而Apache Pig[41]适配器生成的查询使用Pig Latin[37]来表达。Apache Spark[47]的适配器使用JAVA RDD API。最后，Druid[14], ElasticSearch[15]和Splunk[48]通过Rest HTTP API请求查询，通过JSON或XML来表达查询。

### 8.3 研究使用

在研究环境中，Calcite已经作为精确医学和临床分析场景的多存储替代方案。此处省略…

## 9. 未来工作

Calcite的未来工作聚焦于新特性的开发和适配器架构的扩展：

- 强化 Calcite 设计，支持作为一个独立引擎来使用，要求**支持DDL，物化视图、索引和约束**；
- **继续改进planner的设计和灵活性，包括使它更加模块化，允许用户通过Calcite为执行器提供planner程序（规则集合或组织到各个计划阶段）**；
- **将新的参数[53]纳入优化器设计**；
- 支持SQL命令、函数和工具的扩展，**包括OpenGIS的完全兼容**；
- 针对非关系数据源的新适配器，比如用于科学计算的阵列数据库；
- **改进性能分析和检测**。

### 9.1 性能测试与评估

虽然Calcite包含了一个性能测试模块，但是它没有评估查询执行。在评估基于Calcite构建的系统性能时将会有用的。例如，我们比较和Calcite类似的框架。不幸地是，做出公平的比较是比较困难的。例如，像Calcite，Algebricks优化了Hive的查询。Borkar等人[6]将Algebricks和Hyracks调度器跟Hive 0.12进行了比较（无Calcite）。Borkar等人的工作，要在Hive在重要工程和架构变化之前。在时间方面，一种公平的方式来比较Calcite和Algebricks似乎不太可行，因为要确保每个都使用相同的执行引擎。Hive应用主要依赖Apache Tez或Apache Spark作为执行引擎，而Algebricks则依赖于它自己的框架（包括hyracks）。

此外，为了评估基于Calcite的系统性能，我们需要考虑两个不同的使用场景。Calcite可以被用于作为单一系统的一部分或作为一个工具来加速一个系统的构建，甚至是作为一个公共层，整合多个不同系统的更加困难的任务。前者是跟数据处理系统的特点有关，因为Calcite功能多样和使用广泛，需要许多不同的基准。后者受已有异构基准可用性的限制。BigDAWG[55]被用于集成PostgreSQL和Vertica，在标准基准上，有人认为在处理查询时，集成系统是优于将整个表从一个系统拷贝到另一个系统的。基于实际经验，我们相信，更大的目标是集成多个系统，将优于每个系统部分的和。

## 10. 总结

新兴的数据管理实践和关联分析使用的数据，正在朝着越来越多样化和异构场景方向发展。与此同时，通过SQL访问的关系数据源，保留了企业处理数据的本质方式。在这个有点分叉的空间里，Calcite起到了一个独特的作用，来支持传统数据处理和其他包括半结构化、流和地理空间模型的数据源。而且，Calcite聚焦于灵活性、适应性和可扩展性的设计理念，已经成为Calcite在大量开源框架中使用最广泛的查询优化器的另一个因素。Calcite的动态和灵活的查询优化器，以及适配器架构使得嵌入到大量数据处理框架中成为可能，比如Hive，Drill，MapD和Flink。Calcite对异构数据处理的支持，以及关系函数扩展，在功能和性能上都在持续改进。

## 致谢

我们感谢Calcite社区，贡献者和用户，是他们构建、维护、使用、测试、写作和持续推动社区项目向前发展。本手稿部分由UT Battelle，LLC根据与美国能源部签订的合同（合同编号：DE-AC05-00OR22725）共同撰写。

## 参考文献

[1] Apex. Apace Apex. [https://apex.apache.org](https://apex.apache.org/). (Nov. 2017).

[2] Arvind Arasu, Shivnath Babu, and Jennifer Widom. 2003. *The CQL Continuous* *Query Language: Semantic Foundations and Query Execution*. Technical Report 2003-67. Stanford InfoLab.

[3] Michael Armbrust et al. 2015. Spark SQL: Relational Data Processing in Spark. In *Proceedings of the 2015 ACM SIGMOD International Conference on Management of Data (SIGMOD ’15)*. ACM, New York, NY, USA, 1383–1394.

[4] Michael Armbrust, Reynold S. Xin, Cheng Lian, Yin Huai, Davies Liu, Joseph K. Bradley, Xiangrui Meng, Tomer Kaftan, Michael J. Franklin, Ali Ghodsi, and Matei Zaharia. 2015. Spark SQL: Relational Data Processing in Spark. In *Proceedings of* *the 2015 ACM SIGMOD International Conference on Management of Data (SIGMOD* *’15)*. ACM, New York, NY, USA, 1383–1394.

[5] ASF. The Apache Software Foundation. (Nov. 2017). Retrieved November 20, 2017 from http://www.apache.org/

[6] Vinayak Borkar, Yingyi Bu, E. Preston Carman, Jr., Nicola Onose, Till Westmann, Pouria Pirzadeh, Michael J. Carey, and Vassilis J. Tsotras. 2015. Algebricks: A Data Model-agnostic Compiler Backend for Big Data Languages. In *Proceedings of the Sixth ACM Symposium on Cloud Computing (SoCC ’15)*. ACM, New York, NY, USA, 422–433.

[7] M. J. Carey et al. 1995. Towards heterogeneous multimedia information systems: the Garlic approach. In *IDE-DOM ’95*. 124–131.

[8] Cassandra. Apache Cassandra. (Nov. 2017). Retrieved November 20, 2017 from http://cassandra.apache.org/

[9] Fay Chang, Jeffrey Dean, Sanjay Ghemawat, Wilson C. Hsieh, Deborah A. Wallach, Michael Burrows, Tushar Chandra, Andrew Fikes, and Robert Gruber. 2006. Bigtable: A Distributed Storage System for Structured Data. In *7th Symposium on* *Operating Systems Design and Implementation (OSDI ’06), November 6-8, Seattle,* *WA, USA*. 205–218.

[10] Surajit Chaudhuri, Ravi Krishnamurthy, Spyros Potamianos, and Kyuseok Shim.1995. **Optimizing Queries with Materialized Views**. In *Proceedings of the Eleventh* *International Conference on Data Engineering (ICDE ’95)*. IEEE Computer Society, Washington, DC, USA, 190–200.

[11] E. F. Codd. 1970. A Relational Model of Data for Large Shared Data Banks. *Commun. ACM* 13, 6 (June 1970), 377–387.

[12] Alex Şuhan. **Fast and Flexible Query Analysis at MapD with Apache Calcite**. (feb 2017). Retrieved November 20, 2017 from https://www.mapd.com/blog/2017/02/08/fast-and-flexible-query-analysis-at-mapd-with-apache-calcite-2/

[13] Drill. Apache Drill. (Nov. 2017). Retrieved November 20, 2017 from http://drill.apache.org/

[14] Druid. Druid. (Nov. 2017). Retrieved November 20, 2017 from http://druid.io/

[15] Elastic. Elasticsearch. (Nov. 2017). Retrieved November 20, 2017 from [https://www.elastic.co](https://www.elastic.co/)

[16] Flink. **Apache Flink**. [https://flink.apache.org](https://flink.apache.org/). (Nov. 2017).

[17] Yupeng Fu, Kian Win Ong, Yannis Papakonstantinou, and Michalis Petropoulos. 2011. The SQL-based all-declarative FORWARD web application development framework. In *CIDR*.

[18] Jonathan Goldstein and Per-Åke Larson. 2001. **Optimizing Queries Using Materialized Views: A Practical, Scalable Solution.** *SIGMOD Rec.* 30, 2 (May 2001), 331–342.

[19] Goetz Graefe. 1995. The Cascades Framework for Query Optimization. *IEEE* *Data Eng. Bull.* (1995).

[20] Goetz Graefe and William J. McKenna. 1993. **The Volcano Optimizer Generator: Extensibility and Efficient Search**. In *Proceedings of the Ninth International* *Conference on Data Engineering*. IEEE Computer Society, Washington, DC, USA, 209–218.

[21] Daniel Halperin, Victor Teixeira de Almeida, Lee Lee Choo, Shumo Chu, Paraschos Koutris, Dominik Moritz, Jennifer Ortiz, Vaspol Ruamviboonsuk, Jingjing Wang, Andrew Whitaker, Shengliang Xu, Magdalena Balazinska, Bill Howe, and Dan Suciu. 2014. Demonstration of the Myria Big Data Management Service. In *Proceedings of the 2014 ACM SIGMOD International Conference on* *Management of Data (SIGMOD ’14)*. ACM, New York, NY, USA, 881–884.

[22] Venky Harinarayan, Anand Rajaraman, and Jeffrey D. Ullman. 1996. Implementing Data Cubes Efficiently. *SIGMOD Rec.* 25, 2 (June 1996), 205–216.

[23] HBase. Apache HBase. (Nov. 2017). Retrieved November 20, 2017 from http://hbase.apache.org/

[24] Hive. Apache Hive. (Nov. 2017). Retrieved November 20, 2017 from http://hive.apache.org/

[25] Yin Huai, Ashutosh Chauhan, Alan Gates, Gunther Hagleitner, Eric N. Hanson, Owen O’Malley, Jitendra Pandey, Yuan Yuan, Rubao Lee, and Xiaodong Zhang. 2014. Major Technical Advancements in Apache Hive. In *Proceedings of the 2014* *ACM SIGMOD International Conference on Management of Data (SIGMOD ’14)*. ACM, New York, NY, USA, 1235–1246.

[26] **Julian Hyde**. 2010. Data in Flight. *Commun. ACM* 53, 1 (Jan. 2010), 48–52.

[27] Janino. **Janino: A super-small, super-fast Java compiler**. (Nov. 2017). Retrieved November 20, 2017 from http://www.janino.net/

[28] Kylin. Apache Kylin. (Nov. 2017). Retrieved November 20, 2017 from http://kylin.apache.org/

[29] Avinash Lakshman and Prashant Malik. 2010. Cassandra: A Decentralized Structured Storage System. *SIGOPS Oper. Syst. Rev.* 44, 2 (April 2010), 35–40.

[30] Lingual. Lingual. (Nov. 2017). Retrieved November 20, 2017 from http://www.cascading.org/projects/lingual/

[31] Lucene. Apache Lucene. (Nov. 2017). Retrieved November 20, 2017 from https://lucene.apache.org/

[32] MapD. MapD. (Nov. 2017). Retrieved November 20, 2017 from [https://www.mapd.com](https://www.mapd.com/)

[33] Erik Meijer, Brian Beckman, and Gavin Bierman. 2006. LINQ: Reconciling Object, Relations and XML in the .NET Framework. In *Proceedings of the 2006 ACM* SIGMOD International Conference on Management of Data (SIGMOD ’06)*. ACM, New York, NY, USA, 706–706.

[34] Sergey Melnik, Andrey Gubarev, Jing Jing Long, Geoffrey Romer, Shiva Shivakumar, Matt Tolton, and Theo Vassilakis. 2010. **Dremel: Interactive Analysis of Web-Scale Datasets**. *PVLDB* 3, 1 (2010), 330–339. http://www.comp.nus.edu.sg/~vldb2010/proceedings/files/papers/R29.pdf

[35] Marcelo RN Mendes, Pedro Bizarro, and Paulo Marques. 2009. A performance study of event processing systems. In *Technology Conference on Performance* *Evaluation and Benchmarking*. Springer, 221–236.

[36] Mongo. MongoDB. (Nov. 2017). Retrieved November 28, 2017 from https://www.mongodb.com/

[37] Christopher Olston, Benjamin Reed, Utkarsh Srivastava, Ravi Kumar, and Andrew Tomkins. 2008. Pig Latin: a not-so-foreign language for data processing. In *SIGMOD*.

[38] Kian Win Ong, Yannis Papakonstantinou, and Romain Vernoux. 2014. The SQL++ query language: Configurable, unifying and semi-structured. *arXiv preprint* *arXiv:1405.3631* (2014)

[39] Open Geospatial Consortium. OpenGIS Implementation Specification for Geographic information - Simple feature access - Part 2: SQL option. http://portal.opengeospatial.org/files/?artifact_id=25355. (2010).

[40] Phoenix. Apache Phoenix. (Nov. 2017). Retrieved November 20, 2017 from http://phoenix.apache.org/

[41] Pig. Apache Pig. (Nov. 2017). Retrieved November 20, 2017 from http://pig.apache.org/

[42] Qubole Quark. Qubole Quark. (Nov. 2017). Retrieved November 20, 2017 from https://github.com/qubole/quark

[43] Bikas Saha, Hitesh Shah, Siddharth Seth, Gopal Vijayaraghavan, Arun C. Murthy, and Carlo Curino. 2015. Apache Tez: A Unifying Framework for Modeling and Building Data Processing Applications. In *Proceedings of the 2015 ACM SIGMOD* *International Conference on Management of Data, Melbourne, Victoria, Australia,* *May 31 - June 4, 2015*. 1357–1369. https://doi.org/10.1145/2723372.2742790

[44] Samza. Apache Samza. (Nov. 2017). Retrieved November 20, 2017 from http://samza.apache.org/

[45] Mohamed A. Soliman, Lyublena Antova, Venkatesh Raghavan, Amr El-Helw, Zhongxian Gu, Entong Shen, George C. Caragea, Carlos Garcia-Alvarado, Foyzur Rahman, Michalis Petropoulos, Florian Waas, Sivaramakrishnan Narayanan, Konstantinos Krikellas, and Rhonda Baldwin. 2014. **Orca: A Modular Query Optimizer Architecture for Big Data**. In *Proceedings of the 2014 ACM SIGMOD* *International Conference on Management of Data (SIGMOD ’14)*. ACM, New York, NY, USA, 337–348.

[46] Solr. Apache Solr. (Nov. 2017). Retrieved November 20, 2017 from http://lucene.apache.org/solr/

[47] Spark. **Apache Spark**. (Nov. 2017). Retrieved November 20, 2017 from http://spark.apache.org/

[48] Splunk. Splunk. (Nov. 2017). Retrieved November 20, 2017 from https://www.splunk.com/

[49] Michael Stonebraker and Ugur Çetintemel. 2005. “One size fits all”: an idea whose time has come and gone. In *21st International Conference on Data Engineering* *(ICDE’05)*. IEEE Computer Society, Washington, DC, USA, 2–11.

[50] Storm. Apache Storm. (Nov. 2017). Retrieved November 20, 2017 from http://storm.apache.org/

[51] Tez. Apache Tez. (Nov. 2017). Retrieved November 20, 2017 from http://tez.apache.org/

[52] Ashish Thusoo, Joydeep Sen Sarma, Namit Jain, Zheng Shao, Prasad Chakka, Suresh Anthony, Hao Liu, Pete Wyckoff, and Raghotham Murthy. 2009. Hive: a warehousing solution over a map-reduce framework. *VLDB* (2009), 1626–1629.

[53] Immanuel Trummer and Christoph Koch. 2017. Multi-objective parametric query optimization. *The VLDB Journal* 26, 1 (2017), 107–124.

[54] Ashwin Kumar Vajantri, Kunwar Deep Singh Toor, and Edmon Begoli. 2017. **An Apache Calcite-based Polystore Variation for Federated Querying of Heterogeneous Healthcare Sources**. In *2nd Workshop on Methods to Manage Heterogeneous* *Big Data and Polystore Databases*. IEEE Computer Society, Washington, DC, USA.

[55] Katherine Yu, Vijay Gadepally, and Michael Stonebraker. 2017. Database engine integration and performance analysis of the BigDAWG polystore system. In *2017* *IEEE High Performance Extreme Computing Conference (HPEC)*. IEEE Computer Society, Washington, DC, USA, 1–7.

[56] Matei Zaharia, Mosharaf Chowdhury, Michael J. Franklin, Scott Shenker, and Ion Stoica. 2010. Spark: Cluster Computing with Working Sets. In *HotCloud*.

[57] Jingren Zhou, Per-Åke Larson, and Ronnie Chaiken. 2010. **Incorporating partitioning and parallel plans into the SCOPE optimizer.** In *2010 IEEE 26th International* *Conference on Data Engineering (ICDE 2010)*. IEEE Computer Society, Washington, DC, USA, 1060–1071.