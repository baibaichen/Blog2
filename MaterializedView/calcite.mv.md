# 历史

## 第一次支持[视图匹配](https://github.com/apache/calcite/commit/13136f9e4b7f4341d5cdce5b9ca8d498f353bb30) 

具体算法不知道

## 第一次实现视图 [`SubstitutionVisitor`](https://github.com/apache/calcite/commit/026ff5186edb1c1735b7caa8e2b569e22a1b998c) 算法

用一个**关系表达式树**替换**另一个关系表达式树的一部分**。

调用 `new SubstitutionVisitor(target, query).go(replacement))` 返回每次 `target` 被 `replacement` 替换的查询。以下示例展示如何使用 `SubstitutionVisitor` 识别物化视图。

```
query = SELECT a, c FROM t WHERE x = 5 AND b = 4
target = SELECT a, b, c FROM t WHERE x = 5
replacement = SELECT * FROM mv
result = SELECT a, c FROM mv WHERE b = 4
```

请注意，结果使用了物化视图表 mv 和简化条件 b = 4。使用**自下而上**的匹配算法。节点不需要完全相同。 每层都返回残差。输入必须只包含核心**关系运算符**：`TableAccessRel`, `FilterRel`, `ProjectRel`, `JoinRel`, `UnionRel`, `AggregateRel`.

## [支持视图 Filter](https://github.com/apache/calcite/commit/60e4da419027885e772abe209b2bfb04371c67ae)

识别包含过滤器的物化视图。为此，添加了将谓词（例如“x = 1 和 y = 2”）拆分为由底层谓词“y = 2”处理和未处理的部分的算法。

## [增加 `StarTable`](https://github.com/apache/calcite/commit/ef0acca555e6d78d08ea1aa5ecc6d7b42f689544)

这是**识别复杂物化**的第一步，**星型表**是通过多对一关系连接在一起的真实表组成的虚拟表。定义物化视图的查询和最终用户的查询按照星型表规范化。匹配(尚未完成)将是寻找 `sort`、`groupBy`、`Project` 的问题。

现在，我们已经添加了一个虚拟模式 mat 和一个虚拟星型表 star。稍后，模型将允许显式定义星型表。

## 第一次实现 `Lattice` 结构 - [CALCITE-344](https://issues.apache.org/jira/browse/CALCITE-344)

- [ ] x
- [ ] 

---
# 基本概念

## RelOptRule

在 Calcite 中所有**规则类**都是从基类 `RelOptRule` 派生。`RelOptRule` 定义了Calcite 规则的基本结构和方法。`RelOptRule` 中包含一个 `RelOptRuleOperand` 的列表，这个列表在规则匹配<u>要变换的关系表达式中</u>有重要作用。`RelOptRuleOperand` 的列表中的 Operand 都是有层次结构的，对应着要匹配的关系表达式结构。当规则匹配到了目标的关系表达式后 `onMatch` 方法会被调用，规则生成的新的关系表达式通过 `RelOptRuleCall` 的 `transform()` 方法让优化器知道关系表达式的变化结果。

![](https://pic2.zhimg.com/80/v2-3574129f1b39c42e9201252e34ac2d41_1440w.jpg)


## Calcite 的 Trait

在 Calcite 中没有使用不同的对象代表**逻辑和物理算子**，但是使用 `trait` 来表示一个算子的物理属性。

<img src="https://pic3.zhimg.com/80/v2-5b9f7c4b29b19333cb135c7cfc810d92_1440w.jpg" alt="img" style="zoom: 25%;" />

Calcite 中使用接口 `RelTrait` 表示一个**关系表达式节点的物理属性**，使用 `RelTraitDef` 来表示 `RelTrait` 的 class。`RelTrait `与 `RelTraitDef` 的关系就像 Java 中对象与 Class 的关系一样，每个对象都有 Class。对于**物理关系表达式算子**，会有一些物理属性，这些物理属性都会用 `RelTrait` 来表示。比如每个算子都有 Calling Convention 这一 `Reltrait`。比如上图中 `Sort` 算子还会有一个物理属性 `RelCollation`，因为 `Sort` 算子会对表的一些字段进行排序，`RelCollation` 这一物理属性就会记录这个 Sort 算子要排序的<u>字段索引</u>、<u>排序方向</u>，怎么排序 `null` 值等信息。

## Calcite 的 Calling Convention

Calling Convention 在 Calcite 中使用接口 `Convention` 表示，`Convention` 接口是 `RelTrait` 的子接口，**所以是一个算子的属性**。可以把 Calling Convention 理解为**==一个特定数据引擎协议==**，拥有相同 `Convention` 的算子可以认为都是一个统一数据引擎的算子，<u>可以相互连接起来</u>。比如 JDBC 的算子 `JDBCXXX ` 都有 `JdbcConvention`，Calcite 内建的 `Enumerable` 算子 `EnumerableXXX` 都有 `EnumerableConvention`。

![](https://pic3.zhimg.com/v2-5ae8eafe4ea0e9cb405c7f1c71ddbd6a_r.jpg)

上图中，Jdbc 算子可以通过 `JdbcConvention` 获得对应数据库的 `SqlDialect` 和 `JdbcSchema` 等数据，这样可生成对应数据库的 sql，**获得数据库的连接池与数据库交互实现算子的逻辑**。 如果数据要从一个 Calling Convention 的算子到另一个 Calling Convention 算子的时候，比如[这篇使用 Calcite 进行跨库 join 文章描述的场景](https://zhuanlan.zhihu.com/p/143935885)。需要 `Converter` 接口的子类作为两种算子之间的桥梁将两种算子连接起来。

![](https://pic2.zhimg.com/80/v2-7ce0b21af232a9c29af18b56b4a08741_1440w.jpg)

比如上面的执行计划，要将 `Enumerable` 的算子与 `Jdbc` 的算子连接起来，中间就要使用 `JdbcToEnumerableConverter` 作为桥梁。

## `Relset`

关于 RelSet，源码中介绍如下：

> `RelSet`是表达式的等价集，即具有相同语义的表达式集。我们通常对使用成本最低的表达式感兴趣。`RelSet`中的所有表达式都具有**相同的调用约定**。

它有以下特点：

1. 描述一组等价关系表达式，所有的 `RelNode` 会记录在 `rels` 中
2. **相同的调用约定**
3. 具有相同物理属性的关系表达式会记录在其成员变量 `List<RelSubset> subsets` 中.

RelSet 中比较重要成员变量如下：

```java
class RelSet {
   // 记录属于这个 RelSet 的所有 RelNode
  final List<RelNode> rels = new ArrayList<>();
  /**
   * Relational expressions that have a subset in this set as a child. This
   * is a multi-set. If multiple relational expressions in this set have the
   * same parent, there will be multiple entries.
   */
  final List<RelNode> parents = new ArrayList<>();
  
  //注: 具体相同物理属性的子集合（本质上 RelSubset 并不记录 RelNode，
  //    也是通过 RelSet 按物理属性过滤得到其 RelNode 子集合，见下面的 RelSubset 部分）
  final List<RelSubset> subsets = new ArrayList<>();

  /**
   * List of {@link AbstractConverter} objects which have not yet been
   * satisfied.
   */
  final List<AbstractConverter> abstractConverters = new ArrayList<>();

  /**
   * Set to the superseding set when this is found to be equivalent to another
   * set.
   * note：当发现与另一个 RelSet 有相同的语义时，设置为替代集合
   */
  RelSet equivalentSet;
  RelNode rel;

  /**
   * Variables that are set by relational expressions in this set and available for use 
   * by parent and child expressions.
   * 由本集合中的关系表达式设置，并可由父表达式和子表达式使用的变量。
   */
  final Set<CorrelationId> variablesPropagated;

  /**
   * Variables that are used by relational expressions in this set.
   * 此集合中的关系表达式使用的变量。
   */
  final Set<CorrelationId> variablesUsed;
  final int id;

  /**
   * Reentrancy flag.
   */
  boolean inMetadataQuery;
}
```

## `RelSubset`

关于 RelSubset，源码中介绍如下：

> 具有相同物理属性的等价**关系表达式**的子集。

它的特点如下：

1. 描述一组物理属性相同的等价关系表达式，即它们具有相同的物理属性
2. 每个 `RelSubset` 都会记录其所属的 RelSet；
3. `RelSubset` 继承自 `AbstractRelNode`，它也是一种 `RelNode`，物理属性记录在其成员变量 `traitSet` 中。

`RelSubset` 一些比较重要的成员变量如下：

```java
public class RelSubset extends AbstractRelNode {
  /**
   * cost of best known plan (it may have improved since)
   * note: 已知最佳 plan 的 cost
   */
  RelOptCost bestCost;

  /**
   * The set this subset belongs to.
   * RelSubset 所属的 RelSet，在 RelSubset 中并不记录具体的 RelNode，直接记录在 RelSet 的 rels 中
   */
  final RelSet set;

  /**
   * best known plan
   * note: 已知的最佳 plan
   */
  RelNode best;

  /**
   * Flag indicating whether this RelSubset's importance was artificially
   * boosted.
   * note: 标志这个 RelSubset 的 importance 是否是人为地提高了
   */
  boolean boosted;

  //~ Constructors -----------------------------------------------------------
  RelSubset(
      RelOptCluster cluster,
      RelSet set,
      RelTraitSet traits) {
    super(cluster, traits); // 继承自 AbstractRelNode，会记录其相应的 traits 信息
    this.set = set;
    this.boosted = false;
    assert traits.allSimple();
    computeBestCost(cluster.getPlanner()); //note: 计算 best
    recomputeDigest(); //note: 计算 digest
  }
}
```

每个 `RelSubset` 都将会记录其最佳计划（`best`）和最佳 计划的成本（`bestCost`）信息。

![](https://pic1.zhimg.com/80/v2-ba6cd69392ab326dc9fd43ae1884ae0c_1440w.jpg)

## VolcanoPlanner 处理流程

在应用 VolcanoPlanner 时，整体分为以下四步：

1. 初始化 `VolcanoPlanner`，并添加相应的 Rule（包括 `ConverterRule`）；
2. 对 `RelNode` 做等价转换，这里只是改变其**物理属性**（`Convention`）；
3. 通过 `VolcanoPlanner` 的 `setRoot()` 方法注册相应的 `RelNode`，并进行相应的初始化操作；
4. ==通过动态规划算法找到 cost 最小的 plan==；

下面来分享一下上面的详细流程。

### VolcanoPlanner#setRoot

![](https://matt33.com/images/calcite/14-volcano.png)

对于 `setRoot()` 方法来说，核心的处理流程是在 `registerImpl()` 方法中，在这个方法会进行相应的初始化操作（包括 `RelNode` 到 `RelSubset` 的转换、计算 `RelSubset` 的 importance 等），其他的方法在上面有相应的备注，这里我们看下 `registerImpl()` 具体做了哪些事情：

#### VolcanoPlanner#registerImpl

```java
private RelSubset registerImpl(RelNode rel, RelSet set)
```

注册一个新的表达式 `rel` 并将==**匹配的规则**==排队。如果 `set` 不为空，那么就使表达式成为等价集合（`RelSet`）的一部分。如果已经注册了相同的表达式，则不需要再注册这个表达式，也不对匹配的规则进行排队。

- **RelSet** 描述一组逻辑上相等的关系表达式
- **RelSubset** 描述一组物理上相等的关系表达式，即具有相同的物理属性

##### 参数

1. `rel` - 要注册的关系式表达式。必须是 `RelSubset` 或未注册的 `RelNode`
2. `Set` - `rel` 所属的集合，或为空
3. 返回: `equivalence-set`

##### 处理流程

`registerImpl()` 处理流程比较复杂，其方法实现，可以简单总结为以下几步：

1. 在经过最上面的一些验证之后，会通过 `rel.onRegister(this)` 这步操作，递归地调用 `VolcanoPlanner` 的 `ensureRegistered()` 方法对其 `inputs` `RelNode` 进行注册，最后还是调用 `registerImpl()` 方法先注册叶子节点，然后再父节点，最后到根节点；
2. 根据 RelNode 的 digest 信息（一般这个对于 RelNode 来说是全局唯一的），判断其是否已经存在 `mapDigestToRel` 缓存中，如果存在的话，那么判断会 RelNode 是否相同，如果相同的话，证明之前已经注册过，直接通过 `getSubset()` 返回其对应的 `RelSubset` 信息，否则就对其 `RelSubset` 做下合并；
3. 如果 `RelNode` 对应的 `RelSet` 为空，这里会新建一个 `RelSet`，并通过 `addRelToSet()` 将 `RelNode` 添加到 `RelSet` 中，并且更新 `VolcanoPlanner` 的 `mapRel2Subset` 缓存记录（`RelNode` 与 `RelSubset` 的对应关系），在 `addRelToSet()` 的最后还会更新 `RelSubset` 的 **best plan** 和 **best cost**（每当往一个 `RelSubset` 添加相应的 `RelNode` 时，都会判断这个 RelNode 是否代表了 best plan，如果是的话，就更新）；
4. 将这个 RelNode 的 inputs 设置为其对应 RelSubset 的 children 节点（实际的操作时，是在 RelSet 的 `parents` 中记录其父节点）；
5. 强制重新计算当前 RelNode 对应 RelSubset 的 importance；
6. 如果这个 RelSubset 是新建的，会再触发一次 `fireRules()` 方法（会先对 RelNode 触发一次），遍历找到所有可以 match 的 Rule，对每个 Rule 都会创建一个 VolcanoRuleMatch 对象（会记录 RelNode、RelOptRuleOperand 等信息，RelOptRuleOperand 中又会记录 Rule 的信息），并将这个 VolcanoRuleMatch 添加到对应的 RuleQueue 中（就是前面图中的那个 RuleQueue）。
