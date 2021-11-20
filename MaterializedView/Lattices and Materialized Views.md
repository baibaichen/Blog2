# Lattices

> A lattice is a framework for creating and populating materialized views, and for recognizing that a materialized view can be used to solve a particular query.

**Lattice**  是用于创建和填充**物化视图**以及用于判断**物化视图**是否可用于解决特定查询的框架。

- [Concept](https://calcite.apache.org/docs/lattice.html#concept)
- [Demonstration](https://calcite.apache.org/docs/lattice.html#demonstration)
- [Statistics](https://calcite.apache.org/docs/lattice.html#statistics)
- [Lattice suggester](https://calcite.apache.org/docs/lattice.html#lattice-suggester)
- [Further directions](https://calcite.apache.org/docs/lattice.html#further-directions)
- [References](https://calcite.apache.org/docs/lattice.html#references)

## Concept（概念）

> A lattice represents a star (or snowflake) schema, not <u>==a general schema==</u>. In particular, all relationships must be many-to-one, heading from a fact table at the center of the star.
>
> The name derives from the mathematics: a [lattice](https://en.wikipedia.org/wiki/Lattice_(order)) is a [partially ordered set](https://en.wikipedia.org/wiki/Partially_ordered_set) where any two elements have a unique greatest lower bound and least upper bound.
>
> [[HRU96](https://calcite.apache.org/docs/lattice.html#ref-hru96)] observed that the set of possible materializations of a data cube forms a lattice, and presented an algorithm to choose a good set of materializations. Calcite’s recommendation algorithm is derived from this.
>
> The lattice definition uses a SQL statement to represent the star. SQL is a useful short-hand to represent several tables joined together, and assigning aliases to the column names (it more convenient than inventing a new language to represent relationships, join conditions and cardinalities).
>
> Unlike regular SQL, order is important. If you put A before B in the FROM clause, and make a join between A and B, you are saying that there is a many-to-one foreign key relationship from A to B. (E.g. in the example lattice, the Sales fact table occurs before the Time dimension table, and before the Product dimension table. The Product dimension table occurs before the ProductClass outer dimension table, <u>==further down an arm of a snowflake==</u>.)
>
> A lattice implies constraints. In the A to B relationship, there is a foreign key on A (i.e. every value of A’s foreign key has a corresponding value in B’s key), and a unique key on B (i.e. no key value occurs more than once). These constraints are really important, because it allows the planner to remove joins to tables whose columns are not being used, and know that the query results will not change.
>
> Calcite does not check these constraints. If they are violated, Calcite will return wrong results.
>
> A lattice is a big, virtual join view. It is not materialized (it would be several times larger than the star schema, because of denormalization) and you probably wouldn’t want to query it (far too many columns). So what is it useful for? As we said above, (a) the lattice declares some very useful primary and foreign key constraints, (b) it helps the query planner map user queries onto filter-join-aggregate materialized views (the most useful kind of materialized view for DW queries), (c) gives Calcite a framework within which to gather stats about data volumes and user queries, (d) allows Calcite to automatically design and populate materialized views.
>
> Most star schema models force you to choose whether a column is a dimension or a measure. In a lattice, every column is a dimension column. (That is, it can become one of the columns in the GROUP BY clause to query the star schema at a particular dimensionality). Any column can also be used in a measure; you define measures by giving the column and an aggregate function.
>
><u>If “unit_sales” tends to be used much more often as a measure rather than a dimension, that’s fine. Calcite’s algorithm should notice that it is rarely aggregated, and not be inclined to create tiles that aggregate on it</u>. (By “should” I mean “could and one day will”. The algorithm does not currently take query history into account when designing tiles.)
> 
>But someone might want to know whether orders with fewer than 5 items were more or less profitable than orders with more than 100. All of a sudden, “unit_sales” has become a dimension. If there’s virtually zero cost to declaring a column a dimension column, I figured let’s make them all dimension columns.
> 
>
>The model allows for a particular table to be used more than once, with a different table alias. You could use this to model say OrderDate and ShipDate, with two uses to the Time dimension table.
> 
>Most SQL systems require that the column names in a view are unique. This is hard to achieve in a lattice, because you often include primary and foreign key columns in a join. So Calcite lets you refer to columns in two ways. If the column is unique, you can use its name, [“unit_sales”]. Whether or not it is unique in the lattice, it will be unique in its table, so you can use it qualified by its table alias. Examples:
> 
>- [“sales”, “unit_sales”]
> - [“ship_date”, “time_id”]
> - [“order_date”, “time_id”]
> 
>A “tile” is a materialized table in a lattice, with a particular dimensionality. The “tiles” attribute of the [lattice JSON element](https://calcite.apache.org/docs/model.html#lattice) defines an initial set of tiles to materialize.
> 

**Lattice**  代表星形（或雪花）模式，而不是<u>==一般模式==</u>。特别地，所有关系都必须是多对一的，从星形中心的事实表开始。

这个名字来源于数学：[lattice](https://en.wikipedia.org/wiki/Lattice_(order)) 是[偏序集](https://en.wikipedia.org/wiki/Partially_ordered_set)，其中任意两个元素具有唯一的**最大下界**和**最小上界**。

[[HRU96](https://calcite.apache.org/docs/lattice.html#ref-hru96)] 观察到数据立方体的可能物化集合形成 **lattice**，提出了一种算法来选择一个好的物化视图集合。 Calcite 的推荐算法就是由此衍生出来。

**Lattice**  定义使用 SQL 来表示星形。SQL 是一种好用的简写，可用于表示连接在一起的多个表，并为列名指定别名（这比发明一种新语言来表示关系、连接条件和基数更方便）。

与常规 SQL 不同，顺序很重要。 如果您在 `FROM` 子句中将 `A` 放在 `B` 之前，并在 A 和 B 之间建立连接，**则表示说从 A 到 B 存在多对一的外键关系**。（例如，在示例 **lattice** 中，`Sales` 事实表出现在 `Time` 维度表和 `Product` 维度表之前。`Product` 维度表出现在 `ProductClass` 外部维度表之前，更远的<u>==雪花臂==</u>）

**Lattice** 意味着约束。在 A 到 B 的关系中，A 上有一个外键（即 A 的外键的每个值在 B 的键中都有对应的值）和 B 上的唯一键（即没有键值出现超过一次）对应。这些约束非常重要，因为它允许 **planner**  删除（物化视图中）不用的 Join，并且知道查询结果不会改变。

**Calcite 不检查这些约束。 如果违反，Calcite 将返回错误的结果**。

**Lattice**  是一个<u>大的虚拟连接视图</u>。没有物化（由于并没有规范化，它会比星型模式大几倍）并且您可能不想查询它（太多列）。 那么它有什么用呢？ 正如我们上面所说，(a)  **lattice**  声明了一些非常有用的主键和外键约束，(b) 它帮助 **planner** 将用户查询映射到 `filter-join-aggregate` 的物化视图（数仓查询最有用的物化视图类型），(c) 为 Calcite 提供了一个框架，在该框架内收集有关数据量和用户查询的统计信息，(d) 允许 Calcite 自动设计和填充物化视图。

**大多数==星型模式模型==强制您选择列是维度还是度量**。在 **lattice** 中，每列都可以是维度列，即都可以成为 GROUP BY 子句中的列之一，以查询特定维度的**星型模型**。每列也可以用于度量；可以通过列上的聚合函数来定义度量。

<u>如果**单位销售额**往往更多地被用作度量而不是维度，那么 Calcite 的算法**应该**注意到它很少聚合，并且倾向于不在其上创建聚合的 **tile**</u>。我所说的“应该”是指“可以而且有一天会”。在设计 **tile** 时，算法目前不考虑查询历史。

但有人可能想知道，少于 5 件的订单是否比多于 100 件的订单更有利可图。突然，**单位销售额**变成了一个维度。如果将一列声明为维度列的成本几乎为零，则将它们全部设为维度列。

这种模型允许使用不同的表别名多次使用某张表。您可以使用它来建模 OrderDate 和 ShipDate，时间维度表有两种用途。

大多数 SQL 系统要求视图中的列名是唯一的。 这在 **lattice** 中很难实现，因为您经常在 `join` 中包含主键列和外键列。所以 Calcite 允许您以两种方式引用列。 如果该列是唯一的，则可以使用其名称 [“unit_sales”]。 无论它在 **lattice**  中是否唯一，它在其表中都是唯一的，因此您可以使用它的表别名来限定它。 例子：

- [“sales”, “unit_sales”]
- [“ship_date”, “time_id”]
- [“order_date”, “time_id”]

**Tile** 是 **lattice**   中的物化表，具有特定的维度。 [lattice JSON 元素](https://calcite.apache.org/docs/model.html#lattice) 的 **tiles** 属性定义了一组要物化的初始 tiles。

## Demonstration（演示）

>  Create a model that includes a lattice:

创建包含 lattice 的模型

```json
{
  "version": "1.0",
  "defaultSchema": "foodmart",
  "schemas": [ {
    "type": "jdbc",
    "name": "foodmart",
    "jdbcUser": "FOODMART",
    "jdbcPassword": "FOODMART",
    "jdbcUrl": "jdbc:hsqldb:res:foodmart",
    "jdbcSchema": "foodmart"
  },
  {
    "name": "adhoc",
    "lattices": [ {
      "name": "star",
      "sql": [
        "select 1 from \"foodmart\".\"sales_fact_1997\" as \"s\"",
        "join \"foodmart\".\"product\" as \"p\" using (\"product_id\")",
        "join \"foodmart\".\"time_by_day\" as \"t\" using (\"time_id\")",
        "join \"foodmart\".\"product_class\" as \"pc\" on \"p\".\"product_class_id\" = \"pc\".\"product_class_id\""
      ],
      "auto": true,
      "algorithm": true,
      "rowCountEstimate": 86837,
      "defaultMeasures": [ {
        "agg": "count"
      } ]
    } ]
  } ]
}
```

> This is a cut-down version of [hsqldb-foodmart-lattice-model.json](https://github.com/apache/calcite/blob/master/core/src/test/resources/hsqldb-foodmart-lattice-model.json) that does not include the “tiles” attribute, because we are going to generate tiles automatically. Let’s log into sqlline and connect to this schema:

这是 [hsqldb-foodmart-lattice-model.json](https://github.com/apache/calcite/blob/master/core/src/test/resources/hsqldb-foodmart-lattice-model.json) 的精简版，不包含 **tiles** 属性，因为我们将自动生成切片。我们登录 sqlline 并连接到这个 schema：

> 这里的 [schema 等价于数据库](https://www.zhihu.com/question/20355738)？

```
$ sqlline version 1.3.0
sqlline> !connect jdbc:calcite:model=core/src/test/resources/hsqldb-foodmart-lattice-model.json "sa" ""
```

> You’ll notice that it takes a few seconds to connect. Calcite is running the optimization algorithm, and creating and populating materialized views. Let’s run a query and check out its plan:

您会注意到连接需要几秒钟。 Calcite 正在运行优化算法，并创建和填充物化视图。 让我们运行一个查询并查看它的计划：

```
sqlline> select "the_year","the_month", count(*) as c
. . . .> from "sales_fact_1997"
. . . .> join "time_by_day" using ("time_id")
. . . .> group by "the_year","the_month";
+----------+-----------+------+
| the_year | the_month |    C |
+----------+-----------+------+
| 1997     | September | 6663 |
| 1997     | April     | 6590 |
| 1997     | January   | 7034 |
| 1997     | June      | 6912 |
| 1997     | August    | 7038 |
| 1997     | February  | 6844 |
| 1997     | March     | 7710 |
| 1997     | October   | 6479 |
| 1997     | May       | 6866 |
| 1997     | December  | 8717 |
| 1997     | July      | 7752 |
| 1997     | November  | 8232 |
+----------+-----------+------+
12 rows selected (0.147 seconds)

sqlline> explain plan for
. . . .> select "the_year","the_month", count(*) as c
. . . .> from "sales_fact_1997"
. . . .> join "time_by_day" using ("time_id")
. . . .> group by "the_year","the_month";
+--------------------------------------------------------------------------------+
| PLAN                                                                           |
+--------------------------------------------------------------------------------+
| EnumerableCalc(expr#0..2=[{inputs}], the_year=[$t1], the_month=[$t0], C=[$t2]) |
|   EnumerableAggregate(group=[{3, 4}], C=[$SUM0($7)])                           |
|     EnumerableTableScan(table=[[adhoc, m{16, 17, 27, 31, 32, 36, 37}]])        |
+--------------------------------------------------------------------------------+
```

> The query gives the right answer, but plan is somewhat surprising. It doesn’t read the `sales_fact_1997` or `time_by_day` tables, but instead reads from a table called `m{16, 17, 27, 31, 32, 36, 37}`. This is one of the tiles created at the start of the connection.
>
> It’s a real table, and you can even query it directly. It has only 120 rows, so is a more efficient way to answer the query:

查询给出了正确的答案，但计划有点令人惊讶。 它不读取 `sales_fact_1997` 或 `time_by_day` 表，而是从名为 `m{16, 17, 27, 31, 32, 36, 37}` 的表中读取。 这是在连接开始时创建的切片之一。

它是一个真实的表，您甚至可以直接查询它。 它只有 120 行，因此是一种更有效的方式来回答查询：

```
sqlline> !describe "adhoc"."m{16, 17, 27, 31, 32, 36, 37}"
+-------------+-------------------------------+--------------------+-----------+-----------------+
| TABLE_SCHEM | TABLE_NAME                    | COLUMN_NAME        | DATA_TYPE | TYPE_NAME       |
+-------------+-------------------------------+--------------------+-----------+-----------------+
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | recyclable_package | 16        | BOOLEAN         |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | low_fat            | 16        | BOOLEAN         |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | product_family     | 12        | VARCHAR(30)     |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | the_month          | 12        | VARCHAR(30)     |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | the_year           | 5         | SMALLINT        |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | quarter            | 12        | VARCHAR(30)     |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | fiscal_period      | 12        | VARCHAR(30)     |
| adhoc       | m{16, 17, 27, 31, 32, 36, 37} | m0                 | -5        | BIGINT NOT NULL |
+-------------+-------------------------------+--------------------+-----------+-----------------+

sqlline> select count(*) as c
. . . .> from "adhoc"."m{16, 17, 27, 31, 32, 36, 37}";
+-----+
|   C |
+-----+
| 120 |
+-----+
1 row selected (0.12 seconds)
```

> Let’s list the tables, and you will see several more tiles. There are also tables of the `foodmart` schema, and the system tables `TABLES` and `COLUMNS`, and the lattice itself, which appears as a table called `star`.

让我们列出所有表，你会看到更多的切片。 还有 `foodmart` 数据库里的表，系统表 `TABLES` 和 `COLUMNS`，以及 lattice 自身，显示为名为 `star` 的表。

```
sqlline> !tables
+-------------+-------------------------------+--------------+
| TABLE_SCHEM | TABLE_NAME                    | TABLE_TYPE   |
+-------------+-------------------------------+--------------+
| adhoc       | m{16, 17, 18, 32, 37}         | TABLE        |
| adhoc       | m{16, 17, 19, 27, 32, 36, 37} | TABLE        |
| adhoc       | m{4, 7, 16, 27, 32, 37}       | TABLE        |
| adhoc       | m{4, 7, 17, 27, 32, 37}       | TABLE        |
| adhoc       | m{7, 16, 17, 19, 32, 37}      | TABLE        |
| adhoc       | m{7, 16, 17, 27, 30, 32, 37}  | TABLE        |
| adhoc       | star                          | STAR         |
| foodmart    | customer                      | TABLE        |
| foodmart    | product                       | TABLE        |
| foodmart    | product_class                 | TABLE        |
| foodmart    | promotion                     | TABLE        |
| foodmart    | region                        | TABLE        |
| foodmart    | sales_fact_1997               | TABLE        |
| foodmart    | store                         | TABLE        |
| foodmart    | time_by_day                   | TABLE        |
| metadata    | COLUMNS                       | SYSTEM_TABLE |
| metadata    | TABLES                        | SYSTEM_TABLE |
+-------------+-------------------------------+--------------+
```

## Statistics

> The algorithm that chooses which tiles of a lattice to materialize depends on a lot of statistics. It needs to know `select count(distinct a, b, c) from star` for each combination of columns (`a, b, c`) it is considering materializing. As a result the algorithm takes a long time on schemas with many rows and columns.
>
> We are working on a [data profiler](https://issues.apache.org/jira/browse/CALCITE-1616) to address this.

选择要具体化那些切片的算法取决于大量统计数据。对于正在考虑物化的列（`a, b, c`）的每个组合，需要知道 `select count(distinct a, b, c) from star`。 因此，该算法在大量行和列的数据库上需要很长的时间。

我们正在开发一个[数据分析器](https://issues.apache.org/jira/browse/CALCITE-1616)来解决这个问题。

## Lattice suggester

If you have defined a lattice, Calcite will self-tune within that lattice. But what if you have not defined a lattice?

Enter the Lattice Suggester, which builds lattices based on incoming queries. Create a model with a schema that has `"autoLattice": true`:

```
{
  "version": "1.0",
  "defaultSchema": "foodmart",
  "schemas": [ {
    "type": "jdbc",
    "name": "foodmart",
    "jdbcUser": "FOODMART",
    "jdbcPassword": "FOODMART",
    "jdbcUrl": "jdbc:hsqldb:res:foodmart",
    "jdbcSchema": "foodmart"
  }, {
    "name": "adhoc",
    "autoLattice": true
  } ]
}
```

This is a cut-down version of [hsqldb-foodmart-lattice-model.json](https://github.com/apache/calcite/blob/master/core/src/test/resources/hsqldb-foodmart-lattice-model.json)

As you run queries, Calcite will start to build lattices based on those queries. Each lattice is based on a particular fact table. As it sees more queries on that fact table, it will evolve the lattice, joining more dimension tables to the star, and adding measures.

Each lattice will then optimize itself based on both the data and the queries. The goal is to create summary tables (tiles) that are reasonably small but are based on more frequently used attributes and measures.

This feature is still experimental, but has the potential to make databases more “self-tuning” than before.

## Further directions

Here are some ideas that have not yet been implemented:

- The algorithm that builds tiles takes into account a log of past queries.
- Materialized view manager sees incoming queries and builds tiles for them.
- Materialized view manager drops tiles that are not actively used.
- Lattice suggester adds lattices based on incoming queries, transfers tiles from existing lattices to new lattices, and drops lattices that are no longer being used.
- Tiles that cover a horizontal slice of a table; and a rewrite algorithm that can answer a query by stitching together several tiles and going to the raw data to fill in the holes.
- API to invalidate tiles, or horizontal slices of tiles, when the underlying data is changed.

## References

- [HRU96] V. Harinarayan, A. Rajaraman and J. Ullman. [Implementing data cubes efficiently](https://web.eecs.umich.edu/~jag/eecs584/papers/implementing_data_cube.pdf). In *Proc. ACM SIGMOD Conf.*, Montreal, 1996.

# Materialized Views

There are several different ways to exploit materialized views in Calcite.

- [Materialized views maintained by Calcite](https://calcite.apache.org/docs/materialized_views.html#materialized-views-maintained-by-calcite)
- Expose materialized views to Calcite
  - View-based query rewriting
    - [Substitution via rules transformation](https://calcite.apache.org/docs/materialized_views.html#substitution-via-rules-transformation)
    - Rewriting using plan structural information
      - Rewriting coverage
        - [Join rewriting](https://calcite.apache.org/docs/materialized_views.html#join-rewriting)
        - [Aggregate rewriting](https://calcite.apache.org/docs/materialized_views.html#aggregate-rewriting)
        - [Aggregate rewriting (with aggregation rollup)](https://calcite.apache.org/docs/materialized_views.html#aggregate-rewriting-with-aggregation-rollup)
        - [Query partial rewriting](https://calcite.apache.org/docs/materialized_views.html#query-partial-rewriting)
        - [View partial rewriting](https://calcite.apache.org/docs/materialized_views.html#view-partial-rewriting)
        - [Union rewriting](https://calcite.apache.org/docs/materialized_views.html#union-rewriting)
        - [Union rewriting with aggregate](https://calcite.apache.org/docs/materialized_views.html#union-rewriting-with-aggregate)
      - [Limitations](https://calcite.apache.org/docs/materialized_views.html#limitations)
- [References](https://calcite.apache.org/docs/materialized_views.html#references)

## Materialized views maintained by Calcite

For details, see the [lattices documentation](https://calcite.apache.org/docs/lattice.html).

## Expose materialized views to Calcite

> Some Calcite adapters as well as projects that rely on Calcite have their own notion of materialized views.
>
> ==For example, Apache Cassandra allows the user to define materialized views based on existing tables which are automatically maintained.== The Cassandra adapter automatically exposes these materialized views to Calcite. Another example is Apache Hive. When a materialized view is created in Hive, the user can specify whether the view may be used in query optimization. If the user chooses to do so, the materialized view will be registered with Calcite.
>
> By registering materialized views in Calcite, the optimizer has the opportunity to automatically rewrite queries to use these views.

某些 Calcite 适配器以及依赖 Calcite 的项目都有**物化视图的概念**。

==例如，Apache Cassandra 允许用户根据自动维护的表定义物化视图==。Cassandra 适配器自动将这些物化视图暴露给 Calcite。另一个例子是Apache Hive。 在 Hive 中创建物化视图时，用户可以指定该视图是否可以用于查询优化。 如果用户选择这样做，物化视图将被注册到 Calcite。

通过在 Calcite 中注册物化视图，优化器有机会自动重写查询以使用这些视图。

### View-based query rewriting

> View-based query rewriting aims to take an input query which can be answered using a preexisting view and rewrite the query to make use of the view. 
>
> Currently Calcite has two implementations of view-based query rewriting.

基于视图的查询重写是当输入查询可以使用预先存在的视图进行回答时，重写改查询以利用该视图。

目前，Calcite 有两种基于视图的查询重写的实现。

#### Substitution via rules transformation

> The first approach is based on view substitution.
>
> `SubstitutionVisitor` and its extension `MaterializedViewSubstitutionVisitor` aim to substitute part of the relational algebra tree with an equivalent expression which makes use of a materialized view. The scan over the materialized view and the materialized view definition plan are registered with the planner. ==Afterwards, transformation rules that try to unify expressions in the plan are triggered==. Expressions do not need to be equivalent to be replaced: the visitor might add a residual predicate on top of the expression if needed.
>
> The following example is taken from the documentation of `SubstitutionVisitor`:
>
>  * Query: `SELECT a, c FROM t WHERE x = 5 AND b = 4`
>  * Target (materialized view definition): `SELECT a, b, c FROM t WHERE x = 5`
>  * Result: `SELECT a, c FROM mv WHERE b = 4`
>
> Note that `result` uses the materialized view table `mv` and a simplified condition `b = 4`.
>
> While this approach can accomplish a large number of rewritings, it has some limitations. Since the rule relies on transformation rules to create the equivalence between expressions in the query and the materialized view, it might need to enumerate exhaustively all possible equivalent rewritings for a given expression to find a materialized view substitution. However, this is not scalable in the presence of complex views, e.g., views with an arbitrary number of join operators.

第一种方法基于视图替换。

`SubstitutionVisitor` 及其扩展 `MaterializedViewSubstitutionVisitor` 旨在用使用物化视图的等效表达式替换部分关系代数树。物化视图的定义以及如何扫描物化视图被注册进优化器中。==之后，将触发尝试在优化器中统一表达式的转换规则==。表达式不需要等价才能被替换：如果需要，访问者可以在表达式的顶部添加一个剩余的谓词。

以下示例取自 `SubstitutionVisitor` 的文档：

  * 查询：`SELECT a, c FROM t WHERE x = 5 AND b = 4`
  * 目标（物化视图的定义）：`SELECT a, b, c FROM t WHERE x = 5`
  * 结果：`SELECT a, c FROM mv WHERE b = 4`

请注意，`result` 使用物化视图表 `mv` 和简化条件 `b = 4`。

虽然这种方法可以完成大量的重写，但它有一些局限性。由于优化器依靠转换规则来创建查询中表达式和物化视图之间的等价性，它可能需要穷举给定表达式所有可能的等价重写，以找到可替换的物化视图。如果视图定义很复杂，例如有大量 `join` 的视图，这个方法不可扩展。

#### Rewriting using plan structural information

> In turn, an alternative rule that attempts to match queries to views by extracting some structural information about the expression to replace has been proposed.
>
> `MaterializedViewRule` builds on the ideas presented in [GL01](http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.95.113) and introduces some additional extensions.The rule can rewrite expressions containing arbitrary **chains of Join, Filter, and Project operators**. Additionally, the rule can rewrite expressions rooted at an Aggregate operator, rolling aggregations up if necessary. In turn, it can also produce rewritings using Union operators if the query can be partially answered from a view.
>
> To produce a larger number of rewritings, the rule relies on the information exposed as constraints defined over the database tables, e.g., *foreign keys*, *primary keys*, *unique keys* or *not null*.
>

反过来，已经提出了另一种替代规则，该规则尝试通过提取有关要替换的表达式的一些结构信息来将查询与视图匹配。

`MaterializedViewRule` 建立在 [[GL01]](http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.95.113) 中提出的想法的基础上，并引入了一些额外的扩展。该规则可以重写包含任意 `Join`、`Filter` 和 `Project` **运算符链**的表达式。此外，该规则可以重写以 `Aggregate` 运算符为根的表达式，并在必要时向上滚动聚合。如果视图可以部分回答查询，那么可以使用 `Unoin` 生成重写。

为了产生大量的重写，该规则依赖于在数据库表上公开定义的约束信息，例如：**外键**、**主键**、**唯一键**或**非空**。

##### Rewriting coverage

> Let us illustrate with some examples the coverage of the view rewriting algorithm implemented in `MaterializedViewRule`. The examples are based on the following database schema.

下面用一些例子说明 `MaterializedViewRule` 中实现的视图重写算法所涵盖的范围。这些示例基于以下的数据库 Schema。

```sql
CREATE TABLE depts(
  deptno INT NOT NULL,
  deptname VARCHAR(20),
  PRIMARY KEY (deptno)
);
CREATE TABLE locations(
  locationid INT NOT NULL,
  state CHAR(2),
  PRIMARY KEY (locationid)
);
CREATE TABLE emps(
  empid INT NOT NULL,
  deptno INT NOT NULL,
  locationid INT NOT NULL,
  empname VARCHAR(20) NOT NULL,
  salary DECIMAL (18, 2),
  PRIMARY KEY (empid),
  FOREIGN KEY (deptno) REFERENCES depts(deptno),
  FOREIGN KEY (locationid) REFERENCES locations(locationid)
);
```

###### Join rewriting

> The rewriting can handle different join orders in the query and the view definition. In addition, the rule tries to detect when a compensation predicate could be used to produce a rewriting using a view.

重写可以处理查询和视图定义中的<u>**不同连接顺序**</u>。此外使用视图重写时，该规则尝试检测是否可以使用补偿谓词。

- Query:

```sql
SELECT empid
FROM depts
JOIN (
  SELECT empid, deptno
  FROM emps
  WHERE empid = 1) AS subq
ON depts.deptno = subq.deptno
```

- Materialized view definition:

```sql
SELECT empid
FROM emps
JOIN depts USING (deptno)
```

- Rewriting:

```sql
SELECT empid
FROM mv
WHERE empid = 1
```

###### Aggregate rewriting

- Query:

```sql
SELECT deptno
FROM emps
WHERE deptno > 10
GROUP BY deptno
```

- Materialized view definition:

```
SELECT empid, deptno
FROM emps
WHERE deptno > 5
GROUP BY empid, deptno
```

- Rewriting:

```
SELECT deptno
FROM mv
WHERE deptno > 10
GROUP BY deptno
```

###### Aggregate rewriting (with aggregation rollup)

- Query:

```
SELECT deptno, COUNT(*) AS c, SUM(salary) AS s
FROM emps
GROUP BY deptno
```

- Materialized view definition:

```
SELECT empid, deptno, COUNT(*) AS c, SUM(salary) AS s
FROM emps
GROUP BY empid, deptno
```

- Rewriting:

```
SELECT deptno, SUM(c), SUM(s)
FROM mv
GROUP BY deptno
```

###### Query partial rewriting

Through the declared constraints, the rule can detect joins that only append columns without altering the tuples multiplicity and produce correct rewritings.

- Query:

```
SELECT deptno, COUNT(*)
FROM emps
GROUP BY deptno
```

- Materialized view definition:

```
SELECT empid, depts.deptno, COUNT(*) AS c, SUM(salary) AS s
FROM emps
JOIN depts USING (deptno)
GROUP BY empid, depts.deptno
```

- Rewriting:

```
SELECT deptno, SUM(c)
FROM mv
GROUP BY deptno
```

###### View partial rewriting

- Query:

```
SELECT deptname, state, SUM(salary) AS s
FROM emps
JOIN depts ON emps.deptno = depts.deptno
JOIN locations ON emps.locationid = locations.locationid
GROUP BY deptname, state
```

- Materialized view definition:

```
SELECT empid, deptno, state, SUM(salary) AS s
FROM emps
JOIN locations ON emps.locationid = locations.locationid
GROUP BY empid, deptno, state
```

- Rewriting:

```
SELECT deptname, state, SUM(s)
FROM mv
JOIN depts ON mv.deptno = depts.deptno
GROUP BY deptname, state
```

###### Union rewriting

- Query:

```
SELECT empid, deptname
FROM emps
JOIN depts ON emps.deptno = depts.deptno
WHERE salary > 10000
```

- Materialized view definition:

```
SELECT empid, deptname
FROM emps
JOIN depts ON emps.deptno = depts.deptno
WHERE salary > 12000
```

- Rewriting:

```
SELECT empid, deptname
FROM mv
UNION ALL
SELECT empid, deptname
FROM emps
JOIN depts ON emps.deptno = depts.deptno
WHERE salary > 10000 AND salary <= 12000
```

###### Union rewriting with aggregate

- Query:

```
SELECT empid, deptname, SUM(salary) AS s
FROM emps
JOIN depts ON emps.deptno = depts.deptno
WHERE salary > 10000
GROUP BY empid, deptname
```

- Materialized view definition:

```
SELECT empid, deptname, SUM(salary) AS s
FROM emps
JOIN depts ON emps.deptno = depts.deptno
WHERE salary > 12000
GROUP BY empid, deptname
```

- Rewriting:

```
SELECT empid, deptname, SUM(s)
FROM (
  SELECT empid, deptname, s
  FROM mv
  UNION ALL
  SELECT empid, deptname, SUM(salary) AS s
  FROM emps
  JOIN depts ON emps.deptno = depts.deptno
  WHERE salary > 10000 AND salary <= 12000
  GROUP BY empid, deptname) AS subq
GROUP BY empid, deptname
```

##### Limitations

> This rule still presents some limitations. In particular, the rewriting rule attempts to match all views against each query. We plan to implement more refined filtering techniques such as those described in [[GL01](https://calcite.apache.org/docs/materialized_views.html#ref-gl01)].

该规则仍然存在一些限制。特别是，重写规则尝试将每个查询与所有视图进行匹配。我们计划实施更精细的过滤技术，例如 [[GL01](https://calcite.apache.org/docs/materialized_views.html#ref-gl01)] 中描述的那些。

## References

- [GL01] Jonathan Goldstein and Per-åke Larson. [Optimizing queries using materialized views: A practical, scalable solution](https://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.95.113). In *Proc. ACM SIGMOD Conf.*, 2001.

# JSON/YAML models

Calcite models can be represented as JSON/YAML files. This page describes the structure of those files.

Models can also be built programmatically using the `Schema` SPI.

## Elements

### Root

#### JSON

```
{
  version: '1.0',
  defaultSchema: 'mongo',
  schemas: [ Schema... ]
}
```

#### YAML

```
version: 1.0
defaultSchema: mongo
schemas:
- [Schema...]
```

`version` (required string) must have value `1.0`.

`defaultSchema` (optional string). If specified, it is the name (case-sensitive) of a schema defined in this model, and will become the default schema for connections to Calcite that use this model.

`schemas` (optional list of [Schema](http://calcite.apache.org/docs/model.html#schema) elements).

### Schema

Occurs within `root.schemas`.

#### JSON

```json
{
  name: 'foodmart',
  path: ['lib'],
  cache: true,
  materializations: [ Materialization... ]
}
```

#### YAML

```yaml
name: foodmart
path:
  lib
cache: true
materializations:
- [ Materialization... ]
```

`name` (required string) is the name of the schema.

`type` (optional string, default `map`) indicates sub-type. Values are:

- `map` for [Map Schema](http://calcite.apache.org/docs/model.html#map-schema)
- `custom` for [Custom Schema](http://calcite.apache.org/docs/model.html#custom-schema)
- `jdbc` for [JDBC Schema](http://calcite.apache.org/docs/model.html#jdbc-schema)

`path` (optional list) is the SQL path that is used to resolve functions used in this schema. If specified it must be a list, and each element of the list must be either a string or a list of strings. For example,

#### JSON

```json
  path: [ ['usr', 'lib'], 'lib' ]
```

#### YAML

```yaml
path:
- [usr, lib]
- lib
```

declares a path with two elements: the schema ‘/usr/lib’ and the schema ‘/lib’. Most schemas are at the top level, and for these you can use a string.

`materializations` (optional list of [Materialization](http://calcite.apache.org/docs/model.html#materialization)) defines the tables in this schema that are materializations of queries.

`cache` (optional boolean, default true) tells Calcite whether to cache metadata (tables, functions and sub-schemas) generated by this schema.

- If `false`, Calcite will go back to the schema each time it needs metadata, for example, each time it needs a list of tables in order to validate a query against the schema.
- If `true`, Calcite will cache the metadata the first time it reads it. This can lead to better performance, especially if name-matching is case-insensitive.

However, it also leads to the problem of cache staleness. A particular schema implementation can override the `Schema.contentsHaveChangedSince` method to tell Calcite when it should consider its cache to be out of date.

Tables, functions, types, and sub-schemas explicitly created in a schema are not affected by this caching mechanism. They always appear in the schema immediately, and are never flushed.

### Map Schema

Like base class [Schema](http://calcite.apache.org/docs/model.html#schema), occurs within `root.schemas`.

#### JSON

```json
{
  name: 'foodmart',
  type: 'map',
  tables: [ Table... ],
  functions: [ Function... ],
  types: [ Type... ]
}
```

#### YAML

```yaml
name: foodmart
type: map
tables:
- [ Table... ]
functions:
- [ Function... ]
types:
- [ Type... ]
```

`name`, `type`, `path`, `cache`, `materializations` inherited from [Schema](http://calcite.apache.org/docs/model.html#schema).

`tables` (optional list of [Table](http://calcite.apache.org/docs/model.html#table) elements) defines the tables in this schema.

`functions` (optional list of [Function](http://calcite.apache.org/docs/model.html#function) elements) defines the functions in this schema.

`types` defines the types in this schema.

### Custom Schema

Like base class [Schema](http://calcite.apache.org/docs/model.html#schema), occurs within `root.schemas`.

#### JSON

```
{
  name: 'mongo',
  type: 'custom',
  factory: 'org.apache.calcite.adapter.mongodb.MongoSchemaFactory',
  operand: {
    host: 'localhost',
    database: 'test'
  }
}
```

#### YAML

```
name: mongo
type: custom
factory: org.apache.calcite.adapter.mongodb.MongoSchemaFactory
operand:
  host: localhost
  database: test
```

`name`, `type`, `path`, `cache`, `materializations` inherited from [Schema](http://calcite.apache.org/docs/model.html#schema).

`factory` (required string) is the name of the factory class for this schema. Must implement interface [org.apache.calcite.schema.SchemaFactory](http://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/SchemaFactory.html) and have a public default constructor.

`operand` (optional map) contains attributes to be passed to the factory.

### JDBC Schema

Like base class [Schema](http://calcite.apache.org/docs/model.html#schema), occurs within `root.schemas`.

#### JSON

```json
{
  name: 'foodmart',
  type: 'jdbc',
  jdbcDriver: TODO,
  jdbcUrl: TODO,
  jdbcUser: TODO,
  jdbcPassword: TODO,
  jdbcCatalog: TODO,
  jdbcSchema: TODO
}
```

#### YAML

```yaml
name: foodmart
type: jdbc
jdbcDriver: TODO
jdbcUrl: TODO
jdbcUser: TODO
jdbcPassword: TODO
jdbcCatalog: TODO
jdbcSchema: TODO
```

`name`, `type`, `path`, `cache`, `materializations` inherited from [Schema](http://calcite.apache.org/docs/model.html#schema).

`jdbcDriver` (optional string) is the name of the JDBC driver class. If not specified, uses whichever class the JDBC DriverManager chooses.

`jdbcUrl` (optional string) is the JDBC connect string, for example “jdbc:mysql://localhost/foodmart”.

`jdbcUser` (optional string) is the JDBC user name.

`jdbcPassword` (optional string) is the JDBC password.

`jdbcCatalog` (optional string) is the name of the initial catalog in the JDBC data source.

`jdbcSchema` (optional string) is the name of the initial schema in the JDBC data source.

### Materialization

Occurs within `root.schemas.materializations`.

#### JSON

```
{
  view: 'V',
  table: 'T',
  sql: 'select deptno, count(*) as c, sum(sal) as s from emp group by deptno'
}
```

#### YAML

```
view: V
table: T
sql: select deptno, count(*) as c, sum(sal) as s from emp group by deptno
```

> `view` (optional string) is the name of the view; null means that the table already exists and is populated with the correct data.
>
> `table` (required string) is the name of the table that materializes the data in the query. If `view` is not null, the table might not exist, and if it does not, Calcite will create and populate an in-memory table.
>
> `sql` (optional string, or list of strings that will be concatenated as a multi-line string) is the SQL definition of the materialization.

`view`（可选字符串）是视图的名称； null 表示该表已经存在并且填充了正确的数据。

`table`（必需字符串）是在查询中具体化数据的表的名称。 如果`view` 不为空，则该表可能不存在，如果不存在，Calcite 将创建并填充一个内存表。

`sql`（可选字符串，或将连接为多行字符串的字符串列表）是物化的 SQL 定义。

### Table

Occurs within `root.schemas.tables`.

#### JSON

```
{
  name: 'sales_fact',
  columns: [ Column... ]
}
```

#### YAML

```
name: sales_fact
columns:
  [ Column... ]
```

`name` (required string) is the name of this table. Must be unique within the schema.

`type` (optional string, default `custom`) indicates sub-type. Values are:

- `custom` for [Custom Table](http://calcite.apache.org/docs/model.html#custom-table)
- `view` for [View](http://calcite.apache.org/docs/model.html#view)

`columns` (list of [Column](http://calcite.apache.org/docs/model.html#column) elements, required for some kinds of table, optional for others such as View)

### View

Like base class [Table](http://calcite.apache.org/docs/model.html#table), occurs within `root.schemas.tables`.

#### JSON

```
{
  name: 'female_emps',
  type: 'view',
  sql: "select * from emps where gender = 'F'",
  modifiable: true
}
```

#### YAML

```
name: female_emps
type: view
sql: select * from emps where gender = 'F'
modifiable: true
```

`name`, `type`, `columns` inherited from [Table](http://calcite.apache.org/docs/model.html#table).

`sql` (required string, or list of strings that will be concatenated as a multi-line string) is the SQL definition of the view.

`path` (optional list) is the SQL path to resolve the query. If not specified, defaults to the current schema.

`modifiable` (optional boolean) is whether the view is modifiable. If null or not specified, Calcite deduces whether the view is modifiable.

A view is modifiable if contains only SELECT, FROM, WHERE (no JOIN, aggregation or sub-queries) and every column:

- is specified once in the SELECT clause; or
- occurs in the WHERE clause with a `column = literal` predicate; or
- is nullable.

The second clause allows Calcite to automatically provide the correct value for hidden columns. It is useful in multi-tenant environments, where the `tenantId` column is hidden, mandatory (NOT NULL), and has a constant value for a particular view.

Errors regarding modifiable views:

- If a view is marked `modifiable: true` and is not modifiable, Calcite throws an error while reading the schema.
- If you submit an INSERT, UPDATE or UPSERT command to a non-modifiable view, Calcite throws an error when validating the statement.
- If a DML statement creates a row that would not appear in the view (for example, a row in `female_emps`, above, with `gender = 'M'`), Calcite throws an error when executing the statement.

### Custom Table

Like base class [Table](http://calcite.apache.org/docs/model.html#table), occurs within `root.schemas.tables`.

#### JSON

```
{
  name: 'female_emps',
  type: 'custom',
  factory: 'TODO',
  operand: {
    todo: 'TODO'
  }
}
```

#### YAML

```
name: female_emps
type: custom
factory: TODO
operand:
  todo: TODO
```

`name`, `type`, `columns` inherited from [Table](http://calcite.apache.org/docs/model.html#table).

`factory` (required string) is the name of the factory class for this table. Must implement interface [org.apache.calcite.schema.TableFactory](http://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/TableFactory.html) and have a public default constructor.

`operand` (optional map) contains attributes to be passed to the factory.

### Stream

Information about whether a table allows streaming.

Occurs within `root.schemas.tables.stream`.

#### JSON

```
{
  stream: true,
  history: false
}
```

#### YAML

```
stream: true
history: false
```

`stream` (optional; default true) is whether the table allows streaming.

`history` (optional; default false) is whether the history of the stream is available.

### Column

Occurs within `root.schemas.tables.columns`.

#### JSON

```
{
  name: 'empno'
}
```

#### YAML

```
name: empno
```

`name` (required string) is the name of this column.

### Function

Occurs within `root.schemas.functions`.

#### JSON

```
{
  name: 'MY_PLUS',
  className: 'com.example.functions.MyPlusFunction',
  methodName: 'apply',
  path: []
}
```

#### YAML

```
name: MY_PLUS
className: com.example.functions.MyPlusFunction
methodName: apply
path: {}
```

`name` (required string) is the name of this function.

`className` (required string) is the name of the class that implements this function.

`methodName` (optional string) is the name of the method that implements this function.

If `methodName` is specified, the method must exist (case-sensitive) and Calcite will create a scalar function. The method may be static or non-static, but if non-static, the class must have a public constructor with no parameters.

If `methodName` is “*”, Calcite creates a function for every method in the class.

If `methodName` is not specified, Calcite looks for a method called “eval”, and if found, creates a table macro or scalar function. It also looks for methods “init”, “add”, “merge”, “result”, and if found, creates an aggregate function.

`path` (optional list of string) is the path for resolving this function.

### Type

Occurs within `root.schemas.types`.

#### JSON

```
{
  name: 'mytype1',
  type: 'BIGINT',
  attributes: [
    {
      name: 'f1',
      type: 'BIGINT'
    }
  ]
}
```

#### YAML

```
name: mytype1
type: BIGINT
attributes:
- name: f1
  type: BIGINT
```

`name` (required string) is the name of this type.

`type` (optional) is the SQL type.

`attributes` (optional) is the attribute list of this type. If `attributes` and `type` both exist at the same level, `type` takes precedence.

### Lattice

Occurs within `root.schemas.lattices`.

#### JSON

```json
{
  name: 'star',
  sql: [
    'select 1 from "foodmart"."sales_fact_1997" as "s"',
    'join "foodmart"."product" as "p" using ("product_id")',
    'join "foodmart"."time_by_day" as "t" using ("time_id")',
    'join "foodmart"."product_class" as "pc" on "p"."product_class_id" = "pc"."product_class_id"'
  ],
  auto: false,
  algorithm: true,
  algorithmMaxMillis: 10000,
  rowCountEstimate: 86837,
  defaultMeasures: [ {
    agg: 'count'
  } ],
  tiles: [ {
    dimensions: [ 'the_year', ['t', 'quarter'] ],
    measures: [ {
      agg: 'sum',
      args: 'unit_sales'
    }, {
      agg: 'sum',
      args: 'store_sales'
    }, {
      agg: 'count'
    } ]
  } ]
}
```

#### YAML

```json
name: star
sql: >
  select 1 from "foodmart"."sales_fact_1997" as "s"',
  join "foodmart"."product" as "p" using ("product_id")',
  join "foodmart"."time_by_day" as "t" using ("time_id")',
  join "foodmart"."product_class" as "pc" on "p"."product_class_id" = "pc"."product_class_id"
auto: false
algorithm: true
algorithmMaxMillis: 10000
rowCountEstimate: 86837
defaultMeasures:
- agg: count
tiles:
- dimensions: [ 'the_year', ['t', 'quarter'] ]
  measures:
  - agg: sum
    args: unit_sales
  - agg: sum
    args: store_sales
  - agg: 'count'
```

> `name` (required string) is the name of this lattice.
>
> `sql` (required string, or list of strings that will be concatenated as a multi-line string) is the SQL statement that defines the fact table, dimension tables, and join paths for this lattice.
>
> `auto` (optional boolean, default true) is whether to materialize tiles on need as queries are executed.
>
> `algorithm` (optional boolean, default false) is whether to use an optimization algorithm to suggest and populate an initial set of tiles.
>
> `algorithmMaxMillis` (optional long, default -1, meaning no limit) is the maximum number of milliseconds for which to run the algorithm. After this point, takes the best result the algorithm has come up with so far.
>
> `rowCountEstimate` (optional double, default 1000.0) estimated number of rows in the lattice
>
> `tiles` (optional list of [Tile](http://calcite.apache.org/docs/model.html#tile) elements) is a list of materialized aggregates to create up front.
>
> `defaultMeasures` (optional list of [Measure](http://calcite.apache.org/docs/model.html#measure) elements) is a list of measures that a tile should have by default. Any tile defined in `tiles` can still define its own measures, including measures not on this list. If not specified, the default list of measures is just ‘count(*)’:

`name`（必需的字符串）是 **lattice** 的名字。

`sql`（必需的字符串，或为字符串列表，可连接为多行字符串）为此 **lattice** 定义<u>事实表</u>、<u>维度表</u>和<u>关联关系</u>的 SQL 语句。

`auto`（可选布尔值，默认为 true）是在执行查询时是否根据需要**物化切片**。

`algorithm`（可选布尔值，默认为 false）是是否使用优化算法来建议和填充<u>初始的物化视图集</u>。

`algorithmMaxMillis`（可选 long，默认 -1，表示无限制）是运行算法的最大毫秒数。超过改时间之后，采用算法迄今为止提出的最佳结果。

`rowCountEstimate`（可选double，默认1000.0）估计 **lattice** 中的行数

`tiles`（[Tile](http://calcite.apache.org/docs/model.html#tile) 元素的可选列表）是一个预先创建的物化聚合列表。

`defaultMeasures`（[Measure](http://calcite.apache.org/docs/model.html#measure) 元素的可选列表）是切片默认应具有的度量列表。`tiles` 中定义的任何 tile 仍然可以定义自己的度量，包括不在此列表中的度量。如果没有指定，默认的度量列表就是‘count(*)’：

#### JSON

```
[ { name: 'count' } ]
```

#### YAML

```
name: count
```

`statisticProvider` (optional name of a class that implements [org.apache.calcite.materialize.LatticeStatisticProvider](http://calcite.apache.org/javadocAggregate/org/apache/calcite/materialize/LatticeStatisticProvider.html)) provides estimates of the number of distinct values in each column.

You can use a class name, or a class plus a static field. Example:

```
  "statisticProvider": "org.apache.calcite.materialize.Lattices#CACHING_SQL_STATISTIC_PROVIDER"
```

If not set, Calcite will generate and execute a SQL query to find the real value, and cache the results.

See also: [Lattices](http://calcite.apache.org/docs/lattice.html).

### Tile

Occurs within `root.schemas.lattices.tiles`.

```
{
  dimensions: [ 'the_year', ['t', 'quarter'] ],
  measures: [ {
    agg: 'sum',
    args: 'unit_sales'
  }, {
    agg: 'sum',
    args: 'store_sales'
  }, {
    agg: 'count'
  } ]
}
```

#### YAML

```
dimensions: [ 'the_year', ['t', 'quarter'] ]
measures:
- agg: sum
  args: unit_sales
- agg: sum
  args: store_sales
- agg: count
```

`dimensions` (list of strings or string lists, required, but may be empty) defines the dimensionality of this tile. Each dimension is a column from the lattice, like a `GROUP BY` clause. Each element can be either a string (the unique label of the column within the lattice) or a string list (a pair consisting of a table alias and a column name).

`measures` (optional list of [Measure](http://calcite.apache.org/docs/model.html#measure) elements) is a list of aggregate functions applied to arguments. If not specified, uses the lattice’s default measure list.

### Measure

Occurs within `root.schemas.lattices.defaultMeasures` and `root.schemas.lattices.tiles.measures`.

#### JSON

```
{
  agg: 'sum',
  args: [ 'unit_sales' ]
}
```

#### YAML

```
agg: sum
args: unit_sales
```

`agg` is the name of an aggregate function (usually ‘count’, ‘sum’, ‘min’, ‘max’).

`args` (optional) is a column label (string), or list of zero or more column labels

Valid values are:

- Not specified: no arguments
- null: no arguments
- Empty list: no arguments
- String: single argument, the name of a lattice column
- List: multiple arguments, each a column label

Unlike lattice dimensions, measures can not be specified in qualified format, {@code [“table”, “column”]}. When you define a lattice, make sure that each column you intend to use as a measure has a unique label within the lattice (using “{@code AS label}” if necessary), and use that label when you want to pass the column as a measure argument.

# 其他

重写逻辑基于 Goldstein 和 Larson 的**使用物化视图优化查询：一个实用的、可扩展的解决方案**。

在查询端，规则匹配 `Project` 节点链或 `Aggregate` 和 `Join` 节点。这些节点的子计划必须由以下一个或多个算子组成：`TableScan`、`Project`、`Filter` 和 `Join`。

对于每个加入MV，我们需要检查以下内容：

1. 以<u>视图中的 Join 运算符为根的计划</u>生成以<u>查询中的 Join 运算符为根的计划</u>所需的所有行。
2. <u>补偿谓词</u>所需的所有列（即需要在视图上强制执行的谓词）在视图输出中可用。
3. 所有**输出表达式**都可以从视图的输出中计算出来。
4. 所有输出行都以正确的重复因子出现。我们可能依赖现有的**唯一键 - 外键**关系来提取该信息。

反过来，对于每个聚合 MV，我们需要检查以下内容：

1. 以<u>视图中的聚合运算符为根的计划</u>生成以<u>查询中的聚合运算符为根的计划</u>所需的所有行。
2. 补偿谓词所需的所有列，即需要在视图上强制执行的谓词，在视图输出中可用。
3. **查询中的分组列是视图中分组列的子集**。
4. **视图输出**中提供了执行进一步分组所需的所有列。
5. **视图输出**中提供了计算输出表达式所需的所有列。

与原始论文相比，该规则包含多个扩展。其中之一是可以使用 `Union` 重写执行计划，比如物化视图只包含了部分查询结果。

工作步骤：

1. Explore query plan to recognize whether preconditions to  try to generate a rewriting are met（探索查询计划以识别是否满足尝试生成重写的先决条件）
2. Initialize all query related auxiliary data structures that will be used throughout query rewriting process Generate query table references（初始化将在整个查询重写过程中使用的所有查询相关的辅助数据结构生成查询表引用）
3. We iterate through all applicable materializations trying to rewrite the given query（我们遍历所有适用的物化尝试重写给定的查询）
   1. View checks before proceeding
   2. Initialize all query related auxiliary data structures that will be used throughout query rewriting process Extract view predicates
4. We map every table in the query to a table with the same qualified name (all query tables are contained in the view, thus this is equivalent to mapping every table in the query to a view table).
   1. Compute compensation predicates, i.e., predicates that need to be enforced over the view to retain query semantics. The resulting  predicates are expressed using {@link RexTableInputRef} over the query. First, to establish relationship, we swap column references of the view predicates to point to query tables and compute equivalence classes.
   2. 

## 定义

# 其他2



## 元数据信息

Calcite 在查询优化阶段依赖于 `RelMetadataQuery` 和 `RelMetadataProvider` 来查询获取统计信息 

> (如何收集？后面会继续研究哈- -), 

`DefaultRelMetadataProvider` 定义了一组各类 `RelMd*` 的 Meta 信息，meta 信息使用者 `RelMetadataQuery` 来查询特定类型的信息， 这个 **query** 实现是通过代码，<u>生成对 `RelMd*` 的调用</u>来实现

### `Metada` 关于关系表达式的元数据。

对于特定类型的元数据，子类定义了一种查询该元数据的方法。然后，`RelMetadataProvider` 可以为 `RelNode` 的特定子类提供这些类型的元数据。

用户代码（通常在规划器规则或 `RelNode.computeSelfCost(org.apache.calcite.plan.RelOptPlanner, RelMetadataQuery)` 的实现中）通过调用 `RelNode.metadata` 获取元数据实例。`Metadata` 实例已经知道它描述的是哪个特定的 `RelNode`，因此这些方法不会传入 `RelNode`。 事实上，相当多的元数据方法没有额外的参数。 例如，您可以按如下方式获取行数：


```java
RelNode rel;
double rowCount = rel.metadata(RowCount.class).rowCount();
```

 
