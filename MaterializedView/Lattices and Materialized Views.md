# Lattices

> A lattice is a framework for creating and populating materialized views, and for recognizing that a materialized view can be used to solve a particular query.

**Lattice**  是用于创建和填充**物化视图**以及用于判断**物化视图**是否可用于解决特定查询的框架。

- [Concept](https://calcite.apache.org/docs/lattice.html#concept)
- [Demonstration](https://calcite.apache.org/docs/lattice.html#demonstration)
- [Statistics](https://calcite.apache.org/docs/lattice.html#statistics)
- [Lattice suggester](https://calcite.apache.org/docs/lattice.html#lattice-suggester)
- [Further directions](https://calcite.apache.org/docs/lattice.html#further-directions)
- [References](https://calcite.apache.org/docs/lattice.html#references)

## Concept

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
>
> If “unit_sales” tends to be used much more often as a measure rather than a dimension, that’s fine. Calcite’s algorithm should notice that it is rarely aggregated, and not be inclined to create tiles that aggregate on it. (By “should” I mean “could and one day will”. The algorithm does not currently take query history into account when designing tiles.)
>
> But someone might want to know whether orders with fewer than 5 items were more or less profitable than orders with more than 100. All of a sudden, “unit_sales” has become a dimension. If there’s virtually zero cost to declaring a column a dimension column, I figured let’s make them all dimension columns.
>
>
> The model allows for a particular table to be used more than once, with a different table alias. You could use this to model say OrderDate and ShipDate, with two uses to the Time dimension table.
>
> Most SQL systems require that the column names in a view are unique. This is hard to achieve in a lattice, because you often include primary and foreign key columns in a join. So Calcite lets you refer to columns in two ways. If the column is unique, you can use its name, [“unit_sales”]. Whether or not it is unique in the lattice, it will be unique in its table, so you can use it qualified by its table alias. Examples:
>
> - [“sales”, “unit_sales”]
> - [“ship_date”, “time_id”]
> - [“order_date”, “time_id”]
>
> A “tile” is a materialized table in a lattice, with a particular dimensionality. The “tiles” attribute of the [lattice JSON element](https://calcite.apache.org/docs/model.html#lattice) defines an initial set of tiles to materialize.
>

**Lattice**  代表星形（或雪花）模式，而不是<u>==一般模式==</u>。特别地，所有关系都必须是多对一的，从星形中心的事实表开始。

这个名字来源于数学：[lattice](https://en.wikipedia.org/wiki/Lattice_(order)) 是[偏序集](https://en.wikipedia.org/wiki/Partially_ordered_set)，其中任意两个元素具有唯一的**最大下界**和**最小上界**。

[[HRU96](https://calcite.apache.org/docs/lattice.html#ref-hru96)] 观察到数据立方体的可能物化集合形成 **lattice**，提出了一种算法来选择一个好的物化视图集合。 Calcite 的推荐算法就是由此衍生出来的。

**Lattice**  定义使用 SQL 来表示星形。SQL 是一种好用的简写，可用于表示连接在一起的多个表，并为列名指定别名（这比发明一种新语言来表示关系、连接条件和基数更方便）。

与常规 SQL 不同，顺序很重要。 如果您在 `FROM` 子句中将 `A` 放在 `B` 之前，并在 A 和 B 之间建立连接，**则表示说从 A 到 B 存在多对一的外键关系**。（例如，在示例 **lattice** 中，`Sales` 事实表出现在 `Time` 维度表和 `Product` 维度表之前。`Product` 维度表出现在 `ProductClass` 外部维度表之前，更远的<u>==雪花臂==</u>）

**Lattice** 意味着约束。在 A 到 B 的关系中，A 上有一个外键（即 A 的外键的每个值在 B 的键中都有对应的值）和 B 上的唯一键（即没有键值出现超过一次）对应。这些约束非常重要，因为它允许 **planner**  删除（物化视图中）不用的 Join，并且知道查询结果不会改变。

**Calcite 不检查这些约束。 如果违反，Calcite 将返回错误的结果**。

**Lattice**  是一个<u>大的虚拟连接视图</u>。没有物化（由于并没有规范化，它会比星型模式大几倍）并且您可能不想查询它（太多列）。 那么它有什么用呢？ 正如我们上面所说，(a)  **lattice**  声明了一些非常有用的主键和外键约束，(b) 它帮助 **planner** 将用户查询映射到 `filter-join-aggregate` 的物化视图（DW 查询最有用的物化视图类型） )，(c) 为 Calcite 提供了一个框架，在该框架内收集有关数据量和用户查询的统计信息，(d) 允许 Calcite 自动设计和填充物化视图。

**大多数星型模式模型强制您选择列是维度还是度量**。 在 **lattice**   中，每一列都是一个维度列。 （也就是说，它可以成为 GROUP BY 子句中的列之一，以在特定维度查询星型模式）。 任何列也可以用于度量； 您可以通过提供列和聚合函数来定义度量。

如果**单位销售额**往往更多地被用作度量而不是维度，那么 Calcite 的算法**应该**注意到它很少聚合，并且倾向于不在其上创建聚合的 **tile**。（我所说的“应该”是指“可以而且有一天会”。在设计 **tile** 时，算法目前不考虑查询历史。）

但有人可能想知道，少于 5 件的订单是否比多于 100 件的订单更有利可图。 突然，**单位销售额**变成了一个维度。如果将一列声明为维度列的成本几乎为零，则将它们全部设为维度列。

这种模型允许使用不同的表别名多次使用某张表。您可以使用它来建模 OrderDate 和 ShipDate，时间维度表有两种用途。

大多数 SQL 系统要求视图中的列名是唯一的。 这在 **lattice** 中很难实现，因为您经常在 `join` 中包含主键列和外键列。所以 Calcite 允许您以两种方式引用列。 如果该列是唯一的，则可以使用其名称 [“unit_sales”]。 无论它在 **lattice**  中是否唯一，它在其表中都是唯一的，因此您可以使用它的表别名来限定它。 例子：

- [“sales”, “unit_sales”]
- [“ship_date”, “time_id”]
- [“order_date”, “time_id”]

**Tile** 是 **lattice**   中的物化表，具有特定的维度。 [lattice JSON 元素](https://calcite.apache.org/docs/model.html#lattice) 的 **tiles** 属性定义了一组要物化的初始 tiles。

## Demonstration

Create a model that includes a lattice:

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

This is a cut-down version of [hsqldb-foodmart-lattice-model.json](https://github.com/apache/calcite/blob/master/core/src/test/resources/hsqldb-foodmart-lattice-model.json) that does not include the “tiles” attribute, because we are going to generate tiles automatically. Let’s log into sqlline and connect to this schema:

```
$ sqlline version 1.3.0
sqlline> !connect jdbc:calcite:model=core/src/test/resources/hsqldb-foodmart-lattice-model.json "sa" ""
```

You’ll notice that it takes a few seconds to connect. Calcite is running the optimization algorithm, and creating and populating materialized views. Let’s run a query and check out its plan:

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

The query gives the right answer, but plan is somewhat surprising. It doesn’t read the `sales_fact_1997` or `time_by_day` tables, but instead reads from a table called `m{16, 17, 27, 31, 32, 36, 37}`. This is one of the tiles created at the start of the connection.

It’s a real table, and you can even query it directly. It has only 120 rows, so is a more efficient way to answer the query:

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

Let’s list the tables, and you will see several more tiles. There are also tables of the `foodmart` schema, and the system tables `TABLES` and `COLUMNS`, and the lattice itself, which appears as a table called `star`.

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

The algorithm that chooses which tiles of a lattice to materialize depends on a lot of statistics. It needs to know `select count(distinct a, b, c) from star` for each combination of columns (`a, b, c`) it is considering materializing. As a result the algorithm takes a long time on schemas with many rows and columns.

We are working on a [data profiler](https://issues.apache.org/jira/browse/CALCITE-1616) to address this.

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

