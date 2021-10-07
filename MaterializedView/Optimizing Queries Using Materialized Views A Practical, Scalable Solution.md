# Optimizing Queries Using Materialized Views: A Practical, Scalable Solution

[TOC]

## Abstract

> Materialized views can provide massive improvements in query processing time, especially for aggregation queries over large tables. To realize this potential, the query optimizer must know how and when to exploit materialized views. This paper presents a fast and scalable algorithm for determining whether part or all of a query can be computed from materialized views and describes how it can be incorporated in transformation-based optimizers. The current version handles views composed of selections, joins and a final group-by. Optimization remains fully cost based, that is, a single “best” rewrite is not selected by heuristic rules but multiple rewrites are generated and the optimizer chooses the best alternative in the normal way. Experimental results based on an implementation in Microsoft SQL Server show outstanding performance and scalability. Optimization time increases slowly with the number of views but remains low even up to a thousand

物化视图可以大大地缩短查询处理时间，尤其是对于大数据表上的聚合查询。为了实现这种潜力，查询优化器必须知道如何以及何时利用物化视图。本文提出了一快速且可扩展的算法，用于确定是否可以从物化视图完成部分或全部查询，并描述如何将其合并到基于**转换**的优化器中。当前版本处理由<u>选择</u>、<u>连接</u>和<u>最后的 `group by`</u> 组成的视图。还是基于成本优化，也就是说，启发式规则不会选择单个“最佳”重写，而是生成多个重写，优化器以正常方式选择最佳执行方案。基于在 Microsoft SQL Server 中实现的实验结果表明，该算法具有良好的性能和可扩展性。优化时间随着视图数量的增加而缓慢增加，即使有 1000 个视图，优化时间仍然维持在较低的水平。

## 1. 简介（Introduction）

> Using materialized views to speed up query processing is an old idea [10] but only in the last few years has the idea been adopted in commercial database systems. Recent TPC-R benchmark results and actual customer experiences show that query processing time can be improved by orders of magnitude through judicious use of materialized views. To realize the potential of materialized views, efficient solutions to three issues are required:
>
> - **View design**: determining what views to materialize, including how to store and index them.
> - **View maintenance**: efficiently updating materialized views when base tables are updated.
> - **View exploitation**: making efficient use of materialized views to speed up query processing.
>
> This paper deals with view exploitation in transformation-based optimizers. Conceptually, an optimizer generates all possible rewritings of a query expression, estimates their costs, and chooses the one with the lowest cost. A transformation-based optimizer generates rewritings by applying **local transformation rules** on subexpressions of the query. Applying a rule produces substitute expressions, equivalent to the original expression. View matching, that is, computing a subexpression from materialized views, is one such transformation rule. The view-matching rule invokes a viewmatching algorithm that determines whether the original expression can be computed from one or more of the existing materialized views and, if so, generates substitute expressions. The algorithm may be invoked many times during optimization, each time on a different subexpression. 
>
> The main contributions of this paper are (a) an efficient viewmatching algorithm for views composed of selections, joins and a final group-by (SPJG views) and (b) a novel index structure (on view definitions, not view data) that quickly narrows the search to a small set of candidate views on which view-matching is applied. The version of the algorithm described here is limited to SPJG views and produces single-view substitutes. However, these are not inherent limitations of our approach; the algorithm and the index structure can be extended to a broader class of views and substitutes. We briefly discuss possible extensions but the details are beyond the scope of this paper.
>
> Our view-matching algorithm is fast and scalable. Speed is crucial because the view-matching algorithm may be called many times during optimization of a complex query. We also wanted an algorithm able to handle thousands of views efficiently. Many database systems contain hundreds, even thousands, of tables. Such databases may have hundreds of materialized views. Tools similar to that described in [1] can also generate large numbers of views. A smart system might also cache and reuse results of previously computed queries. Cached results can be treated as temporary materialized views, easily resulting in thousands of materialized views. The algorithm was implemented in Microsoft SQL Server, which uses a transformation-based optimizer based on the Cascades framework [6]. Experiments show outstanding performanceand scalability. Optimization time increases linearly with the number of views but remains low even up to a thousand.
>
> Integrating view matching through the optimizer’s normal rule mechanism provides important benefits. Multiple rewrites may be generated; some exploiting materialized views, some not. All rewrites participate in the normal cost-based optimization, regardless of whether they make use of materialized views.  Secondary indexes, if any, on materialized views are automatically considered. The optimization time may even be reduced. If a cheap plan using materialized views is found early in the optimization process, it tightens cost bounds resulting in more aggressive pruning.
>
> The rest of the paper is organized as follows. Section 2 describes the class of materialized views supported and defines the problem to be solved. Section 3 describes our algorithm for deciding if a query expression can be computed from a view. Section 4 introduces our index structure. Section 5 presents experimental results based on our prototype implementation. Related work is discussed in section 6. Section 7 contains a summary and a brief discussion of possible extensions.
>

使用物化视图来加速查询处理是一个古老的想法 [10]，但直到最近几年，商业数据库系统才采用这种想法。 最近的 TPC-R 基准测试结果和实际客户体验表明，通过合理使用物化视图可以将查询处理时间缩短几个数量级。要实现物化视图的潜力，需要有效解决三个问题：

- **视图设计**：确定要物化的视图，包括如何存储和索引这些视图。
- **视图维护**：更新基表时，能高效地更新物化视图。
- **视图利用**：有效利用物化视图，加快查询处理。

本文讨论了如何在基于转换的优化器中利用视图。从概念上讲，优化器生成查询表达式所有可能的执行计划，估算它们的成本，并选择成本最低的那个。基于转换的优化器利用**本地转换规则**来重写查询的子表达式。规则会产生与原始表达式等价的替换表达式。视图匹配就是这样的一种转换规则，即利用**物化视图**计算<u>子表达式</u>。**视图匹配规则**调用==视图匹配算法==，该算法确定是否可以从一个或多个现有物化视图中计算出原始表达式，如果可以，则生成替代表达式。在优化期间，可以在不同的子表达式上多次调用该算法。

本文的主要贡献： (a)针对由<u>选择</u>、<u>连接</u>和<u>最后的 `group by`</u> 组成的（SPJG）视图，提出了一种高效的视图匹配算法；(b) 提出了一种新颖的索引结构（基于视图定义，而不是视图数据），可以快速地将搜索范围缩小到一小组候选视图，以简化视图匹配。这里描述的算法版本仅限于 SPJG 视图，且只替换为单个视图。然而，这并不是该方法的固有局限；该算法和索引结构可以扩展到更广泛的视图和替代。我们简要讨论了可能的扩展，但详细信息超出了本文的范围。

我们的视图匹配算法快速且可扩展。 速度至关重要，因为在优化复杂查询期间，可能会多次调用视图匹配算法。我们还想要一种能够有效处理数千个视图的算法。 许多数据库系统包含数百、甚至数千个表。这样的数据库可能有数百个物化视图。 类似于 [1] 中描述的工具也可以生成大量视图。智能系统还可以缓存和重用先前计算的查询结果。缓存的结果可以当作临时的物化视图，很容易产生数千个物化视图。Microsoft SQL Server 在 Cascades 框架的基础上使用基于转换的优化器[6]，我们基于此实现了该算法。实验表明，该系统具有优异的性能和可扩展性。优化时间随视图数量线性增加，即使有 1000 个视图，优化时间仍然维持在较低的水平。

通过优化器的正常规则机制集成视图匹配算法，有很重要的好处。可能会产生多次重写；有些利用物化视图，有些则不利用。无论是否使用物化视图，所有重写都要参与基于成本的优化。将自动考虑物化视图上的二级索引（如果有）。甚至可以缩短优化时间，如果在优化过程的早期，就发现了使用物化视图的廉价计划，则会收紧成本上限，从而导致更积极的修剪。

本文的其余部分安排如下。第 2 节描述了所支持的物化视图，并定义了要解决的问题。第 3 节描述了我们用于确定是否可以从视图计算查询表达式的算法。第 4 节介绍了我们的索引结构。第 5 节给出了基于原型实现的实验结果。相关工作在第 6 节中讨论。第 7 节包含总结和对可能扩展的简要讨论。

## 2. 问题定义（Defining the problem）

> SQL Server 2000 supports materialized views. They are called indexed views because a materialized view may be indexed in multiple ways. A view is materialized by creating a unique clustered index on an existing view. Uniqueness implies that the view output must contain a unique key. This is necessary to guarantee that views can be updated incrementally. Once the clustered index has been created, additional secondary indexes can be created. Not all views are indexable. An indexable view must be defined by a single-level SQL statement containing selections, (inner) joins, and an optional group-by. The FROM clause cannot contain derived tables, i.e. it must reference base tables, and subqueries are not allowed. The output of an aggregation view must include all grouping columns as output columns (because they define the key) and a count column. Aggregation functions are limited to sum and count. This is the class of views considered in this paper.
>
> **Example 1**: This example shows how to create an indexed view, with an additional secondary index, in SQL Server 2000. All examples in this paper use the TPC-H/R database.
>
> ```sql
> create view v1 with schemabinding as
>  select p_partkey, p_name, p_retailprice,
>    count_big(*) as cnt,
>    sum(l_extendedprice*l_quantity) as gross_revenue
>  from dbo.lineitem, dbo.part
>  where p_partkey < 1000 
>    and p_name like ‘%steel%’
>    and p_partkey = l_partkey
>  group by p_partkey, p_name, p_retailprice
> 
> create unique clustered index v1_cidx on v1(p_partkey)
> create index v1_sidx on v1( gross_revenue, p_name)
> ```
>
> The first statement creates the view v1. The phrase “with schemabinding” is required for indexed views. A count_big column is required in all aggregation views so deletions can be handled incrementally (when the count becomes zero, the group is empty and the row must be deleted). Output columns defined by arithmetic or other expressions must be assigned names (using the AS clause) so that they can be referred to. The second statement materializes the view and stores the result in a clustered index. Even though the statement specifies only the (unique) key of the view, the rows contain all output columns. The final statement creates a secondary index on the materialized view.
>
> As outlined in the introduction, a transformation-based optimizer generates rewrites by recursively applying transformation rules on relational expressions. View matching is a transformation rule that is invoked on select-project-join-group-by (SPJG) expressions. For each expression, we want to find every materialized view from which the expression can be computed. In this paper, we require that the expression can be computed from the view alone. The following is the view-matching problem considered in this paper.
>
> **View Matching with Single-View Substitutes**: Given a relational expression in SPJG form, find all materialized (SPJG) views from which the expression can be computed and, for each view found, construct a substitute expression equivalent to the given expression.
>
> No restrictions are imposed on the overall query. Even though we consider only single-view substitutes, different views may be used to evaluate different parts of a query. Whenever the optimizer finds a SPJG expression the view-matching rule is invoked. All substitutes produced by view matching participate in cost-based optimization in the normal way. Furthermore, any secondary indexes defined on a materialized view will be considered automatically in the same way as for base tables.
>
> The algorithm explained in this paper is limited to SPJG subexpressions and single-table substitutes. However, this is not an inherent limitation of our approach. The algorithm can be extended to a broader class of input and substitute expressions, for example, expressions containing unions, outer joins or aggregation with grouping sets.
>

SQL Server 2000 支持物化视图。它们之所以被称为索引视图，是因为物化视图可以以多种方式进行索引。通过在现有视图上创建唯一的聚集索引来物化视图。唯一性意味着视图输出必须包含唯一键。这是保证视图可以增量更新所必需的。创建聚集索引后，可以创建其他二级索引。并非所有视图都是可索引的。可索引视图必须由包含选择、`inner join` 和可选 `group-by` 的**单级 SQL 语句**定义。FROM 子句不能包含**<u>派生表</u>**，即它必须引用基表，并且不允许子查询。聚合视图的输出必须包括所有**<u>分组列</u>**作为输出列（因为它们定义了键）和一个计数列。聚合函数仅限于 `sum` 和 `count`。这就是本文所考虑的一类视图。

**例 1**：本例显示如何在 SQL Server 2000 中创建带有额外二级索引的索引视图。本文中的所有示例均使用 TPC-H/R 数据库。

```sql
create view v1 with schemabinding as
 select p_partkey, p_name, p_retailprice,
   count_big(*) as cnt,
   sum(l_extendedprice*l_quantity) as gross_revenue
 from dbo.lineitem, dbo.part
 where p_partkey < 1000 
   and p_name like ‘%steel%’
   and p_partkey = l_partkey
 group by p_partkey, p_name, p_retailprice

create unique clustered index v1_cidx on v1(p_partkey)
create index v1_sidx on v1( gross_revenue, p_name)
```
第一条语句创建视图 v1。索引视图需要短语 `with schemabinding`。所有的聚合视图都需要一个 `count_big` 列，以便可以增量的方式处理删除（当计数为零时，分组为空，必须删除该行）。由算术或其他表达式定义的输出列必须（使用 AS 子句）定义名称，以便可以引用它们。第二个语句物化视图并将结果存储在聚集索引中。即使该语句仅指定视图的（唯一）键，行也包含所有输出列。最后一条语句在物化视图上创建二级索引。□

如简介中所述，基于转换的优化器在关系表达式上递归地应用优化规则来生成等价的执行计划。视图匹配是在 `select`-`project`-`join`-`group-by` (SPJG) 表达式上调用的转换规则。对于每个表达式，我们希望找到可以从中计算表达式的每个物化视图。 在本文中，我们要求必须从视图中计算出整个关系表达式。以下是本文考虑的视图匹配问题。

**使用单视图替代的视图匹配**：给定一个 SPJG 形式的关系表达式，找到所有可以计算该表达式的物化视图，并为找到的每个视图构造一个与给定表达式等价的替代表达式。

对整个查询没有任何限制。即使我们只考虑单一视图替代，也可以使用不同的视图来计算查询的不同部分。**只要优化器找到 SPJG 表达式，就会调用视图匹配规则**。视图匹配产生的所有替代表达式都以正常方式参与基于成本的优化。此外，物化视图上定义的任何二级索引都将按照与基表相同的方式自动考虑。

本文介绍的算法仅限于 SPJG 子表达式和单表替换。然而，这不是我们方法的固有限制。该算法可以扩展到更广泛的输入和替换表达式类，例如，包含 `union`、`outer join` 或带有 `grouping set` 的表达式。

## 3. 从视图计算查询表达式（Computing a query expression from a view）

> In this section, we describe the tests applied to determine whether a query expression can be computed from a view and, if it can, how to construct the substitute expression. The first subsection deals with join-select-project (SPJ) views and queries assuming that the view and the query reference the same tables. <u>Views with extra tables</u> and <u>views with aggregation</u> are covered in separate subsections. There is no need to consider views with fewer tables than the query expression. Such views can only be used to compute a subexpression of the query expression. The view-matching rule will automatically be invoked on every subexpression.
>
> Our algorithm exploits four types of constraints: not-null constraints on columns, primary key constraints, uniqueness constraints (either explicitly declared or implied by creating a unique index), and foreign key constraints. We assume that the selection predicates of view and query expressions have been converted into conjunctive normal form (CNF). If not, we first convert them into CNF. We also assume that join elimination has been performed so query and view expressions contain no redundant tables. (The SQL Server optimizer does this automatically.)
>

在本节中描述如何确定可以从视图构造出**查询表达式**，以及如果可以，**如何构造等价的替换表达式**。第一小节讨论 **<u>join select project</u>（<u>SPJ</u>）**视图和查询，假设视图和查询引用相同的表。<u>有额外表的</u>视图和聚合视图在单独的小节中介绍。不需要考虑表的数量少于查询表达式的视图。这样的视图只能用于计算<u>查询表达式的子表达式</u>。 视图匹配规则将在每个<u>子表达式</u>上自动调用。

算法利用四种约束类型：**<u>非空列约束</u>**，**<u>主键约束</u>**，**<u>唯一性约束</u>**（通过创建唯一索引显式或隐含声明）以及**<u>外键约束</u>**。我们假设视图和查询表达式的选择谓词已转换为**<u>合取范式</u>（conjunctive normal form，<u>CNF</u>）**。如果没有，我们首先将它们转换为**CNF**。 我们还假定已执行<u>**联接消除**</u>，因此查询和视图表达式不包含冗余表（SQL Server优化器会自动执行此操作）。

> 注：
>
> 1. CNF
> 2. 关联消除：意味着SQL优化器消除了不必再关联中出现的表
>
> To prove that two expressions are equal, a frequently used technique is to transform both expressions to a standard form. One such standard form is called conjunctive normal form or CNF. An expression in CNF is a ‘product of sums’. The ‘sums’ are literals (simple propositions or negated propositions, e.g., $P$, or $\neg Q$) linked by $\vee$, which are then formed into a ‘product’ using $\wedge$.
>
> Consider the expression:  $(P \Leftrightarrow Q)$
>
> > 表示 P 等价于 Q
>
> Its conjunctive normal form is $(\neg P \vee Q) \wedge (P \vee \neg Q)$. 
>
> To get this result, (using Axiom (2.1.9)) we reduce all the operators to $\wedge$, $\vee$, and $\neg$, $( P \wedge Q) \vee (\neg P \wedge \neg Q)$.
>
> We then use the first distribution law, three times:
>
> $$(P∧Q)∨(¬P∧¬Q)$$ =
> $$(P∨¬P∧¬Q)∧(Q∨¬P∧¬Q)$$=
> $$(P∨¬P)∧(P∨¬Q)∧(Q∨¬P∧¬Q)$$=
> $$(P∨¬P)∧(P∨¬Q)∧(Q∨¬P)∧(Q∨¬Q)$$
>
> Finally, we eliminate the sums $$(P∨¬P)$$ and $$(Q∨¬Q)$$  which are always *True*, leaving $$(P∨¬Q)∧(Q∨¬P)$$.
>
> Normalisation is a purely mechanical process that a computer can do (although it is NP-hard). We can prove the theorem $$ (P⇔Q)=(P⇒Q)∧(P⇐Q)$$ by converting both sides to CNF. We have already dealt with the left-hand side above. Normalising its right-hand side is left as a simple exercise for the reader.
>

### 3.1 Join-select-project views and queries

> For a SPJ query expression to be computable from a view, the view must satisfy the following requirements.
>
> 1. **The view contains all rows needed by the query expression**. Because we are considering only single-view substitutes, this is an obvious requirement. However, this is not required if substitutes containing unions of views are considered. 
> 2. **All required rows can be selected from the view**. Even if all required rows exist in the view, we may not be able to extract them correctly. Selection is done by applying a predicate. If one of the columns required by the predicate is missing from the view output, the required rows cannot be selected. 
> 3. **All output expressions can be computed from the output of the view**. 
> 4. **All output rows occur with the correct duplication factor**. SQL is based on <u>bag semantics</u>, that is, a base table or the output of a SQL expression may contain duplicate rows. Hence, it is not sufficient that two expressions produce the same set of rows but any duplicate rows must also occur exactly the same number of times. 
>
> Equivalences among columns play an important role in our tests so we cover this topic first. We then discuss how we ensure that the requirements above are met, devoting a separate subsection to each requirement.

如果要从视图中返回SPJ查询表达式的结果，视图必须满足如下的条件：

1. **视图包含查询表达式所需的所有行**。 因为我们仅考虑<u>单个视图</u>的替代，所以这是显而易见的要求。但是，如果我们考虑用<u>视图的并集</u>替代，则不是必需的。
2. **可以从视图中选择所有必需的行**。 即使视图中存在所有必需的行，也可能无法正确提取它们。选择是通过谓词来完成的。如果视图中缺少谓词所需的某一列，则无法选择所需的行。
3. **可以从视图的输出算出所有输出表达式**。
4. **所有输出行都使用正确的复制因子**。SQL基于<u>Bag语义</u>，即（物化视图的）基础表或SQL表达式的输出可能包含重复的行。<u>因此，两个表达式产生相同的行集还不够，任何重复的行也必须出现完全相同的次数</u>。

列之间的等效性在我们的测试中起着重要作用，因此我们首先讨论该主题。然后，我们讨论如何确保满足上述要求，再用单独的小节讨论每项需求。

> 注：
>
> 1. [Bag 语义](http://ceur-ws.org/Vol-1087/keynote2slides.pdf)：表示有重复元素，与之对应的是Set语义，表示没有重复。也就是查询返回的结果不会去重，有重复数据，除非加上`distinct`。

#### 3.1.1 列等价分类（column equivalence classes）

> Let *W=P~1~∧ P~2~∧ … ∧P~n~* be the selection predicate (in CNF) of a `SPJ` expression. By collecting the appropriate conjuncts, we can rewrite the predicate as *W=PE∧ PNE* where *PE* contains column equality predicates of the form *(T~i~.C~p~ =T~j~.C~q~)* and *PNE* contains all remaining conjuncts. T~i~ and T~j~ are tables, not necessarily distinct, and C~p~ and C~q~ are column references.
>
> Suppose we evaluate the SPJ expression by computing the Cartesian product of the tables, then applying the column-equality predicates in *PE*, then applying the predicates in *PNE*, and finally computing the expressions in the output list. ==After the column equality predicates have been applied, some columns are interchangeable in both the **PNE** predicates and the output columns==. This ability to **reroute column references among equivalent columns** will be important later on.
>
> Knowledge about column equivalences can be captured compactly by <u>computing a set of equivalence classes</u> based on the column equality predicates in *PE*. **An equivalence class is a set of columns that are known to be equal**. Computing the equivalence classes is straightforward. Begin with each column of the tables referenced by the expression in a separate set. Then loop through the <u>column equality predicates</u> in any order. For each *(T~i~.C~p~ = T~j~.C~q~)*, find the set containing *T~i~.C~p~* and the set containing *T~j~.C~q~*. If they are in different sets merge the two sets, otherwise do nothing. The sets left at the end is the desired collection of equivalence classes, including trivial classes consisting of a single column.

设*W=P~1~∧P~2~∧…∧P~n~*为`SPJ`表达式的选择谓词（按CNF的形式）。通过适当地调整<u>==连接词==</u>，可重写谓词为*W=PE∧ PNE*，其中，其中 *PE* 包含所有形式为*(T~i~.C~p~=T~j~.C~q~)* 的<u>列相等</u>谓词，*PNE* 包含所有剩余的连接。T~i~ 和 T~j~ 是表，有可能相同，而C~p~和C~q~是列引用。

假设我们求解 SPJ 表达式是先计算表的笛卡尔积，再应用 *PE* 中的列相等谓词，然后再应用 *PNE* 中谓词，最后计算输出列表中的表达式。==应用<u>列相等谓词</u>后，某些列可以在**PNE** 谓词和输出列互换==。这种**在等价列之间<u>重新路由引用列</u>的功能**稍后将非常重要。

通过基于 *PE* 中列相等谓词<u>计算等价类的集合</u>，可简洁地获取**列等价性**的知识。**等价类是一组已知相等的列**。计算等价类很简单。在单独的集合中，从表达式引用的表的每一列开始，然后按任意顺序循环遍历<u>列相等谓词</u>。对于每个 *(T~i~.C~p~=T~j~.C~q~)*，找到包含 *T~i~.C~p~* 的集合和包含 *T~j~.C~q~* 的集合。如果它们位于不同的集合中，则将这两个集合合并，否则啥也不用做。最后留下的集合是所需的等价类集合，包括由单个列组成的没有价值的<u>等价类</u>。

#### 3.1.2 视图中是否存在所有必需的行？（Do all required rows exist in the view?）

> Assume that the query expression and the view expression reference the tables *T~1~, T~2~,…, T~m~*. Let *W~q~* denote the predicate in the `where-clause` of the query expression and *W~v~* the predicate of the view expression. Determining whether the view contains all rows required by the query expression is, in principle, easy. All we need to show is that the output of the expression *(select \* from T~1~,T~2~,…,T~m~ where W~q~)* produces a subset of the output of *(select \* from T~1~,T~2~,…,T~m~ where W~v~)* for all valid instances of tables *T~1~, T~2~,…,T~m~*. This is guaranteed to hold if *W~q~ ⇒W~v~*,where ‘⇒’ denotes **logical implication**. 
>
> Therefore we need an algorithm to decide whether *W~q~ ⇒ W~v~* holds. We rewrite the predicates as *W~q~ =P~q,1~∧P~q,2~∧…∧P~q,m~* and *W~v~ =P~v,1~∧P~v,2~∧…∧P~v,n~*. A simple conservative algorithm is to check that every conjunct *P~v,i~* in *W~v~*, matches a conjunct *P~q,i~* in *W~q~*. There are several ways to decide whether two conjuncts match. <u>For instance, the matching can be purely syntactic</u>. This can be implemented by converting each conjunct into a string, i.e., the SQL text version of the conjunct, and then matching the strings. The drawback with this approach is that even minor syntactic differences result in different strings. For example, the two predicates `(A > B)` and `(B < A)` would not match. To avoid this problem, we must interpret the predicates and exploit equivalences among expressions. Exploiting **commutativity** is a good example, applicable to many types of expressions: comparisons, addition, multiplication, and disjunction (OR). We can design matching functions at different levels of sophistication and complexity depending on how much knowledge about equivalences we build into the function. For example, a simple function might only understand that `(A+B) = (B+A)`, while a more sophisticated function might also recognize that `(A/2 + B/5) * 10 = A * 5 + B * 2`. 
>
> Our decision algorithm exploits knowledge about column equivalences and column ranges. We first divide the predicates *W~q~* and *W~v~* into three components and write the <u>**implication test**</u> as
>
> *(PE~q~∧ PR~q~∧PU~q~ ⇒ PE~v~∧ PR~v~∧PU~v~)*
>
> *PE~q~* consists of all <u>column equality predicates</u> from the query, *PR~q~* contains range predicates, and *PU~q~* is the <u>residual predicate</u> containing all remaining conjuncts of *W~q~*. *W~v~* is divided similarly. ==A column-equality predicate is any atomic predicate of the form *(T~i~.C~p~ = T~j~.C~r~)*, where *C~p~* and *C~r~* are column references.== A range predicate is any atomic predicate of the form *(T~i~.C~p~ op c)* where *c* is a constant and *op* is one of the operators “<”, “≤”, “=”, “≥”, “>”. The implication test can be split into three separate tests: 
>
> *(PE~q~∧ PR~q~∧PU~q~⇒ PE~v~) ∧* 
> *(PE~q~∧ PR~q~∧PU~q~⇒ PR~v~) ∧*
> *(PE~q~∧ PR~q~∧PU~q~⇒ PU~v~)*
>
>==An implication test can be strengthened by dropping <u>conjuncts</u> in the <u>antecedent</u>==. (Expressed in formal terms, the formula *(A⇒C) ⇒(AB⇒C)* holds for arbitrary predicates *A*, *B*, *C*. In words, if we can deduce that A by itself implies C then certainly A and B together imply C.) Our final tests are strengthened versions of the three tests. To determine whether all rows required by a query exist in the view, we apply the following three tests: 
> 
>*(PE~q~ ⇒PE~v~)*                   (Equijoin subsumption test)
> *(PE~q~∧ PR~q~ ⇒PR~v~)*          (Range subsumption test) 
> *(PE~q~ ∧PU~q~ ⇒PU~v~)*          (Residual subsumption test) 
> 
>
>The first test is called the equijoin subsumption test because, in practice, most column equality predicates come from equijoins. However, all column equality predicates are included in *PE*, even those referencing columns in the same table. Recall that the predicates in *PE~q~* are the column equality predicates used for computing the query equivalence classes. Since *PE~q~* is in the antecedent in the latter two implications, we can reroute a column reference to any column within its query equivalence class.
> 
>
>The tests are clearly stronger than minimally required and may cause some opportunities to be missed. For instance, by dropping *PR~q~* from the antecedent of the equijoin test we will miss cases when the query equates two columns to the same constant, say, *(A=2)∧(B=2)* and the view contains the weaker predicate *(A=B)*. A similar problem may arise in the residual subsumption test. For instance, if the query contains *(A=5)∧(B=3)* and the view contains the predicate *(A+B) = 5*, we would safely but incorrectly conclude that the view does not provide all required rows. It is a tradeoff between speed and completeness.
> 
>**Check constraints** can be readily incorporated into the tests. The key observation is that **check constraints on the tables of a query can be added to the <u>where-clause</u> without changing the query result**. Hence, check constraints can be taken into account by including them in the antecedent of the implication *W~q~ ⇒ W~v~*. Whether or not the check constraints will actually be exploited depends on the algorithm used for testing.

假设查询表达式和视图表达式引用表*T~1~，T~2~，…，T~m~*。让 *W~q~* 表示查询表达式 `where` 子句中的谓词，*W~v~* 表示视图表达式的谓词。理论上，确定视图是否包含查询表达式所需的所有行很容易。我们只需要证明，对表 *T~1~, T~2~,…,T~m~* 所有的有效实例，表达式 *(select \* from T~1~，T~2~，…，T~m~ where W~q~)* 的输出都会产生 *(select \* from T~1~,T~2~,…,T~m~ where W~v~)* 输出的子集。因此只要 *W~q~ ⇒ W~v~*，则证明成立，这里 ⇒ 表示**逻辑包含**。

> 这里的[logical implication](https://whatis.techtarget.com/definition/logical-implication) ，感觉就是[充分条件](https://baike.baidu.com/item/%E5%85%85%E5%88%86%E5%BF%85%E8%A6%81%E6%9D%A1%E4%BB%B6)。即，如果p能推出q，p是q的充分条件，同时q是p的必要条件，此时**p是q的子集**。

因此，我们需要一个算法来判断 *W~q~ ⇒ W~v~* 是否成立。我们重写谓词如下：*W~q~ =P~q,1~∧P~q,2~∧…∧P~q,m~*  和 *W~v~ =P~v,1~∧P~v,2~∧…∧P~v,n~*。一种简单的保守算法是检查 *W~v~* 中每个条件*P~v,i~* ，是否匹配*W~q~* 中的每个条件*P~q,i~* 。有几种方法可以确定两个条件是否匹配。<u>例如，匹配可以是纯语法的</u>。这可通过将每个条件转换为字符串来实现，即将条件转为SQL，然后匹配字符串。这种方法的缺点是，细微的语法差异会导致字符串不同。比如，`(A > B)`和 `(B < A)` 这两个谓词会匹配失败。为了避免这个问题，我们必须分析谓词，并利用表达式之间的等价性。利用**交换性**是一个很好的例子，适用于许多类型的表达式：比较、加法、乘法和<u>析取</u>（OR）。可设计不同精密度和复杂度的匹配函数，这取决于匹配函数有多少等价性的知识。比如，简单函数只能理解`（A+B）=（B+A）`，更复杂的函数可能识别`（A/2 + B/5）* 10 = A*5 + B*2`。

我们的决策算法利用了列等价性和列范围的知识。我们首先将谓词 *W~q~* 和 *W~v~* 分为三个部分，并将<u>**包含测试**</u>写为：

*(PE~q~∧ PR~q~∧PU~q~ ⇒ PE~v~∧ PR~v~∧PU~v~)*

*PE~q~* 包含查询中的所有<u>列相等谓词</u>，*PR~q~* 包含范围谓词，*PU~q~* 是<u>余下的谓词</u>，包含 *W~q~* 中所有剩余的条件。*W~v~* 也类似划分。==列相等谓词是 *(T~i~.C~p~ = T~j~.C~r~)* 这种形式的任何原子谓词，其中 *C~p~* 和 *C~r~* 是列引用==。范围谓词是 *(T~i~.C~p~ op c)* 这种形式的任何原子谓词，其中 *c* 是常量，*op* 是 “<”、 “≤”、 “=”、 “≥”、 “>” 这些操作符。包含测试可以分为三个独立的测试：

*(PE~q~∧ PR~q~∧PU~q~⇒ PE~v~) ∧* 
*(PE~q~∧ PR~q~∧PU~q~⇒ PR~v~) ∧*
*(PE~q~∧ PR~q~∧PU~q~⇒ PU~v~)*

在<u>先行词</u>中去掉<u>连接词</u>可以增强包含测试（以正式术语表示，公式 *(A⇒C) ⇒(AB⇒C)* 适用于任意谓词*A*，*B*，*C*。换句话说，如果我们可以推论出A本身暗含C，则肯定A和B一起暗含C ）。最终测试是三个测试的强化版本。为了确定视图中是否存在查询所需的所有行，我们应用以下三个测试：

> 注：这里的意思是A是C的子集，那么 A&&B 也是C的子集

*(PE~q~ ⇒PE~v~)*                   (等值关联包含测试)
*(PE~q~∧ PR~q~ ⇒PR~v~)*         (范围包含测试) 
*(PE~q~ ∧PU~q~ ⇒PU~v~)*         (Residual subsumption test) 

第一个测试称为**等值联接包含测试**，因为实际上，大多数列相等谓词都来自**等值联接包含测试**。所有列相等谓词都包含在PE中，即使那些引用同一表中列的谓词也是如此。回想一下*PE~q~*中的谓词是用于计算查询等价类的列相等谓词。由于*PE~q~*位于后两个包含测试的<u>前导项（先行词）</u>中，因此我们可以重新路由<u>列引用</u>到查询等价类中的任何列。

这些测试显然比最低要求强，因此可能会错过一些机会。例如，从等值关联测试的前导项中删除 *PR~q~*，当查询条件是两列分别等于相同的常量，比如 *(A=2)∧(B=2)* ，而视图的谓词 *(A=B)* 较弱时。余下的包含测试也会出现类似的问题。例如，如果查询包含 *(A=5)∧(B=3)*，而视图包含谓词 *(A+B) = 5*，我们将安全但错误地得出结论，即视图没有提供所有必需的行。这是速度和完整性之间的权衡。

> 注：这里视图的谓词怀疑是 *(A+B) = 8*

**检查约束**可以很容易地合并到测试中。这里观察到的关键点是，**可以将表上的检查约束添加到<u>where子句</u>中，而不会更改查询结果**。因此，可以通过将检查约束包含在 *W~q~ ⇒ W~v~* 的前导项中考虑它们。是否真正利用检查约束取决于测试算法。

##### 等值关联包含测试（Equijoin subsumption test）

> **The equijoin subsumption test** amounts to requiring that all columns equal in the view must also be equal in the query (but not vice versa). We implement this test by first computing column equivalence classes, as explained in the previous section, both for the query and the view, and then checking whether every nontrivial view equivalence class is a subset of some query equivalence class. Just checking that all column equality predicates in the view also exist in the query is a much weaker test because of transitivity. Suppose the view contains *(A=B and B=C)* and the query contains *(A=C and C=B)*. Even though the actual predicates don’t match, they are logically equivalent because they both imply that *A=B=C*. The effect of transitivity is correctly captured by using equivalence classes.
>
> If the view passes the equijoin subsumption test, we know that it does not contain any conflicting column equality constraints. We can also easily compute what, if any, compensating column equality constraints must be enforced on the view to produce the query result. Whenever some view equivalence classes *E~1~, E~2~ … E~n~* map to the same query equivalence class *E*, we create a column equality predicate between any column in E~i~ and any column in *E~i+1~* for *i=1, 2, …, n-1*.
>

**等值关联包含测试**等于要求视图中所有相等的列在查询中也必须相等（但反之则不是）。要完成此测试，首先按上一节所述的方式，为查询和视图做<u>**等价列分类**</u>，然后检查<u>视图每个有意义的列等价分类</u>是否是查询的某个列等价分类的子集。由于可传递性，只检查视图中所有<u>列相等谓词</u>是否存在于查询中是一个较弱的测试。比如视图包含 *(A=B and B=C)*，而查询包含 *(A=C and C=B)*。即使实际谓词不匹配，它们在逻辑上也是等效的，因为它们都意味着 *A=B=C*。使用等价列分类可以正确地获取传递性。

如果该视图通过了**等值连接包含测试**，我们就知道该视图不包含任何有冲突的列相等约束。我们还可以轻松计算<u>必须在视图上强制补偿哪些列相等约束（如果有的话）</u>以产生查询结果。每当某些视图列等价分类 *E~1~, E~2~ … E~n~* **都**映射到查询的列等价类 *E* 时，那么对于 *i = 1、2，…，n-1*，我们在 *E~i~* 的所有列和 *E~i+1~* 的所有列之间创建一个相等谓词。

##### 范围包含测试（Range subsumption test）

> When no *ORs* are involved, there is an easy algorithm for the range subsumption test. We associate with **<u>each equivalence class</u>** in the query a range that specifies a lower and upper bound on the columns in the equivalence class. Both bounds are initially left uninitialized. We then consider the range predicates one by one, find the equivalence class containing the column referenced, and set or adjust its range as needed. If the predicate is of type *(T~i~.C~p~ <=c)*, we set the upper bound to the minimum of its current value and *c*. If is of type *(T~i~.C~p~ >= c)*, we set the lower bound to the maximum of its current value and *c*. Predicates of the form *(T~i~.C~p~ <c)* are treated as *(T~i~.C~p~ <= c-∆)* where *c-∆* denotes the smallest value preceding *c* in the domain of column *T~i~.C~p~*. Predicates of the form *(T~i~.C~p~ >c)* are treated as *(T~i~.C~p~>= c+∆)*. Finally, predicates of the form *(T~i~.C~p~ =c)* are treated as *(T~i~.C~p~ >= c) ∧ (T~i~.C~p~ <= c)*. The same process is repeated for the view.
>
> The view cannot produce all required rows if it is more tightly constrained than the query. <u>To check this, we consider the view equivalence classes with ranges where at least one of the bounds has been set</u>. We find the matching equivalence class in the query, the query equivalence class that has at least one column in common with the ~~query~~ equivalence class, and check whether the range of the query equivalence class is contained in the range of the view equivalence class. (Uninitialized bounds are treated as +∞ or -∞.) If it is not, the range subsumption test fails and the view is rejected.
>
> During this process we can determine what **compensating** range predicates must be applied to the view to produce the query result. If a query range matches precisely the corresponding view range, no restriction is needed. If the lower bound doesn’t match exactly, we must restrict the view result by enforcing the predicate *(T.C >= lb)* where *T.C* is a column in the (query) <u>equivalence class</u> and *lb* is the lower bound of the query range. If the upper bounds differ, we need to enforce the predicate *(T.C <= ub)*.
>
> This range coverage algorithm can be extended to support disjunctions (OR) of range predicates. Due to space limitations, we will not discuss the extension here. Our prototype does not support disjunctions.
>

不涉及*OR*时，可以使用一种简单的算法进行范围包含测试。我们将查询中涉及到的<u>**列等价分类**</u>关联到一个<u>范围</u>，用于指定该等价分类中列的下界和上界。它们最初都未初始化。然后我们逐个考察**范围谓词**，找到包含引用列的等价分类，并根据需要设置或调整其范围。如果谓词类型为 *(T~i~.C~p~ <=c)*，则将上界设置为当前值和 *c* 的最小值。如果类型为 *(T~i~.C~p~ >= c)*，则将下界设为其当前值和 *c* 的最大值。*(T~i~.C~p~ <c)* 形式的谓词被视为 *(T~i~.C~p~ <= c-∆)*，其中 *c-∆* 表示表示 *T~i~.C~p~* 列中 *c* 之前的最小值，*(T~i~.C~p~ > c)* 形式的谓词被视为 *(T~i~.C~p~ >= c+∆)*，最后，*(T~i~.C~p~ =c)* 形式的谓词被视为 *(T~i~.C~p~ >= c) ∧ (T~i~.C~p~ <= c)*。对视图重复同样的过程。

如果视图比查询有更严格地约束，则该视图无法生成所有必需的行。要检查这点，我们用至少有一列设置了上下界的视图**<u>列等价分类</u>**，找到其匹配的查询<u>**列等价分类**</u>（查询的列等价分类与视图的列等价分类至少具有一列相同），验证查询等价类的范围是否包含在视图等价类的范围内（未初始化的边界为+∞或-∞）。如果没包含，范围包含测试失败，拒绝视图。

在此过程中，我们可以确定对视图的范围谓词如何**补偿**才能产生查询结果。如果查询范围与相应的视图范围精确匹配，则不需要任何限制。如果下界不完全匹配，则必须增加谓词 *(T.C >= lb)* 来限制视图结果，其中 *T.C* 是（查询的）<u>列等价分类</u>中的列，而 *lb* 是查询范围的下界 。如果上界不一样，则必须增加谓词 *(T.C <= ub)* 来限制视图结果。

这种范围覆盖算法可以扩展到支持范围谓词的析取（或）。由于篇幅有限，这里不讨论扩展。我们的原型不支持析取。

##### 剩余的包含测试（Residual subsumption test）

> **Conjuncts** that are neither column-equality predicates nor range predicates form the residual predicates of the query and the view. <u>The only reasoning applied to these predicates is column equivalence</u>. We test the implication by checking whether every conjunct in the view residual predicate matches a conjunct in the query residual predicate. Two column references match if they belong to the same (query) equivalence class. If the match fails, the view is rejected because the view contains a predicate not present in the query. Any residual predicate in the query that did not match anything in the view must be applied to the view.

既不是列相等谓词也不是范围谓词的 **Conjuncts** 构成了查询和视图的剩余谓词。<u>用于这些谓词的唯一推理是列等价</u>。我们检查视图剩余谓词中每个 **Conjunt** 是否与查询剩余谓词中的 **Conjunt** 相匹配来测试包含性。如果两个列引用属于同一（查询的）列等价分类，则它们匹配。如果匹配失败，则该视图将被拒绝，因为该视图包含查询中不存在的谓词。查询中无法与视图匹配的谓词都必须应用于视图。

> As discussed in the beginning of this section, whether two **conjuncts** are found to match depends on the matching algorithm. Our prototype implementation uses a shallow matching algorithm: except for column equivalences, the expressions must be identical. An expression is represented by a text string and a list of column references. The text string contains the textual version of the expression with column references omitted. The list contains every column reference in the expression, in the order they would occur in the textual version of the expression. To compare two expressions, we first compare the strings. If they are equal, we scan through the two lists comparing column references in the same positions in the two lists. If both column references are contained in the same (query) equivalence class, the column references match, otherwise not. If all column pairs match, the expressions match. We chose this shallow algorithm for speed, fully aware that it may cause some opportunities to be missed.
>
> In summary, here are the steps of our procedure for testing whether a view contains all the rows needed by the query.
>
> 1. Compute equivalence classes for the query and the view.
> 2. Check that every view equivalence class is a subset of a query equivalence class. If not, reject the view
> 3. Compute range intervals for the query and the view.
> 4. Check that every view range contains the corresponding query range. If not, reject the view.
> 5. Check that every conjunct in the residual predicate of the view matches a conjunct in the residual predicate of the query. If not, reject the view.
>

如本节开头所讨论的，两个 **Conjunct** 是否匹配，取决于匹配算法。我们的原型实现使用一个浅匹配算法：除了列等价性之外，表达式必须相同。表达式由文本字符串和一组列引用表示。文本字符串包含表达式的文本版本，省略了列引用。列引用组包含了表达式中所有的列，并按照它们在表达式的文本版本中出现的顺序排列。为了比较两个表达式，我们首先比较字符串。如果它们相等，我们扫描两个列表，比较两个列表中相同位置的列引用。如果两个列引用都包含在一个查询的列等价分类中，则列引用匹配，否则不匹配。如果每对列都匹配，则表达式匹配。我们选择这种浅层算法来提高速度，完全意识到它可能会错过一些机会。

下面概括了视图是否包含查询所需的所有行的过程步骤。

1. 计算查询和视图列的等价分类。
2. 检查每个视图的列等价分类是否是查询的列等价分类的子集。 如果不是，拒绝该视图
3. 计算查询和视图的范围区间。
4. 检查视图是否包含了相应的查询范围。 如果没有，拒绝该视图。
5. 检查视图剩余谓词中的每个**Conjunct**是否匹配查询剩余谓词中的某个 **Conjunct**。如果没有，拒绝视图。

##### 例2

> View:
>
> ```sql
> Create view V2 with schemabinding as
> Select l_orderkey, o_custkey, l_partkey,
>     l_shipdate, o_orderdate,
>     l_quantity*l_extendedprice as gross_revenue
> From dbo.lineitem, dbo.orders, dbo.part
> Where l_orderkey = o_orderkey
> And l_partkey = p_partkey
> And p_partkey >= 150
> And o_custkey >= 50 and o_custkey <= 500
> And p_name like ‘%abc%’
> ```
>
> Query:
>
> ```SQL
> Select l_orderkey, o_custkey, l_partkey,
> l_quantity*l_extendedprice
> From lineitem, orders, part
> Where l_orderkey = o_orderkey
> And l_partkey = p_partkey
> And l_partkey >= 150 and l_partkey <= 160
> And o_custkey = 123
> And o_orderdate = l_shipdate
> And p_name like ‘%abc%’
> And l_quantity*l_extendedprice > 100
> ```
>
> <u>Step 1</u>: Compute equivalence classes.
> |                            |                                                              |
> | -------------------------- | ------------------------------------------------------------ |
> | View equivalence classes:  | {l_orderkey, o_orderkey},{l_partkey, p_partkey}, {o_orderdate}, {l_shipdate} |
> | Query equivalence classes: | {l_orderkey, o_orderkey},{l_partkey, p_partkey}, {o_orderdate, l_shipdate} |
>
> Not all trivial equivalence classes are shown; {o_orderdate} and {l_shipdate} are included because they are needed later in the example.
>
> <u>Step 2</u>: Check view equivalence class containment.
>
> The two non-trivial view equivalence classes both have exact matches among the query equivalence classes. The (trivial) equivalence classes `{o_orderdate}` and `{l_shipdate}` map to the same query equivalence class, which means that the substitute expression must create the compensating predicate `(o_orderdate=l_shipdate)`.
>
> <u>Step 3</u>: Compute ranges.
>
> |               |                                                              |
> | ------------- | ------------------------------------------------------------ |
> | View ranges:  | {l_partkey, p_partkey} ∈ (150, +∞),<br/>{o_custkey} ∈ (50, 500) |
> | Query ranges: | {l_partkey, p_partkey} ∈ (150, 160),<br/>{o_custkey} ∈ (123, 123) |
>
> <u>Step 4</u>: Check query range containment.
>
> The range (150, 160) on {l_partkey, p_partkey} is contained in the corresponding view range. The upper bounds do not match so we have to enforce the predicate ({l_partkey, p_partkey} <= 160). The range (123, 123) on {o_custkey} is also contained in the corresponding view range. The bounds don’t mach so we must enforce the predicates (o_custkey >= 123) and (o_custkey <= 123), which can be simplified to (o_custkey = 123).
>
> <u>Step 5</u>: Check match of view residual predicates.
>
> |                            |                                                           |
> | -------------------------- | --------------------------------------------------------- |
> | View residual predicate:   | p_name like ‘%abc%’                                       |
> | Query residual predicate:: | p_name like ‘%abc%’,<br/>l_quantity*l_extendedprice > 100 |
>
> The view has only one residual predicate, p_name like ‘%abc%’, which also exists in the query. The extra residual predicate, l_quantity*l_extendedprice > 100 must be enforced.
>
> The view passes all the tests so we conclude that it contains all the required rows. The compensating predicates that must be applied to the view are (o_orderdate = l_shipdate), ({p_partkey, l_partkey} <= 160), (o_custkey = 123), and (l_quantity \* l_extendedprice > 100.00). The notation {p_partkey, l_partkey} in the second predicates means that we can choose either p_partkey or l_partkey.

视图：


```sql
Create view V2 with schemabinding as
Select l_orderkey, o_custkey, l_partkey,
       l_shipdate, o_orderdate,
       l_quantity*l_extendedprice as gross_revenue
From dbo.lineitem, dbo.orders, dbo.part
Where l_orderkey = o_orderkey
  And l_partkey = p_partkey
  And p_partkey >= 150
  And o_custkey >= 50 and o_custkey <= 500
  And p_name like ‘%abc%’
```

查询：

```SQL
Select l_orderkey, o_custkey, l_partkey,
l_quantity*l_extendedprice
From lineitem, orders, part
Where l_orderkey = o_orderkey
  And l_partkey = p_partkey
  And l_partkey >= 150 and l_partkey <= 160
  And o_custkey = 123
  And o_orderdate = l_shipdate
  And p_name like ‘%abc%’
  And l_quantity*l_extendedprice > 100
```

<u>第 1 步</u>：计算列等价分类

|                  |                                                              |
| ---------------- | ------------------------------------------------------------ |
| 视图列等价分类： | `{l_orderkey, o_orderkey}`<br/>`{l_partkey, p_partkey}`<br/>`{o_orderdate}`<br/>`{l_shipdate}` |
| 查询列等价分类： | `{l_orderkey, o_orderkey}`<br/>`{l_partkey, p_partkey}`<br/>`{o_orderdate, l_shipdate}` |

没有显示所有简单的**列等价分类**，这里显示 `{o_orderdate}` 和 `{l_shipdate}`，因为本示例的后面要用它们。

<u>第 2 步</u>：检查视图列等价分类是否为子集

视图两个简单的列等价分类在查询的列等价类中有精确匹配。简单的等价分类 `{o_orderdate}` 和 `{l_shipdate}` 映射到同一个查询的列等价分类中，这意味着替换表达式必须创建补偿谓词 `(o_orderdate=l_shipdate)`。

<u>第 3 步</u>：计算范围

|              |                                                              |
| ------------ | ------------------------------------------------------------ |
| 视图的范围： | {l_partkey, p_partkey} ∈ (150, +∞),<br/>{o_custkey} ∈ (50, 500) |
| 查询的范围： | {l_partkey, p_partkey} ∈ (150, 160),<br/>{o_custkey} ∈ (123, 123) |

<u>第 4 步</u>：检查查询的范围是否为视图范围的子集

`{l_partkey，p_partkey}` 上的范围 `[150，160]` 包含在相应的视图范围中。上界不匹配，因此我们必须增加谓词 `({l_partkey，p_partkey}<=160)`。`{o_custkey}` 上的范围 `[123，123]` 也包含在相应的视图范围中。范围不匹配，所以我们必须增加谓词 `(o_custkey>=123) and (o_custkey<=123)`，可简化为 `(o_custkey=123)`。

<u>第 5 步</u>：检查视图剩余谓词是否匹配

|                  |                                                           |
| ---------------- | --------------------------------------------------------- |
| 视图剩余的谓词： | p_name like ‘%abc%’                                       |
| 查询剩余的谓词： | p_name like ‘%abc%’,<br/>l_quantity*l_extendedprice > 100 |

这个视图只有一个剩余谓词，`p_name like ‘%abc%’`，该谓词也存在于查询中。必须增加查询额外的剩余谓词 `l_quantity * l_extendedprice> 100`。

视图通过了所有测试，所以我们得出结论，该视图包含所有必需的行。 视图必须增加的的谓词为：`(o_orderdate = l_shipdate)`、`({p_partkey, l_partkey} <= 160)`、`(o_custkey = 123)` 和 `(l_quantity * l_extendedprice > 100.00)`。第二个谓词中的符号{p_partkey，l_partkey}，表示我们可以选择 p_partkey 或 l_partkey。


#### 3.1.3 可以选择所需的行吗？（Can the required rows be selected?）

> We explained in the previous section how to determine the compensating predicates that must be enforced on the view to reduce it to the correct set of rows. They are of three different types.
>
> 1. Column equality predicates obtained while comparing view and query equivalence classes. In our example above, there was one predicate of this type: (o_orderdate = l_shipdate).
> 2. Range predicates obtained while checking query ranges against view ranges. There were two predicates of this type: , ({p_partkey, l_partkey} <= 160) and (o_custkey = 123).
> 3. Unmatched residual predicates from the query. There was one predicate of this type: (l_quantity*l_extendedprice > 100).
>
> **All compensating predicates must be computable from the view’s output**. We exploit equalities among columns by considering each column reference to refer to the equivalence class containing the column, instead of referencing the column itself. The query equivalence classes are used <u>in all but one case</u>, namely, the compensating column equality predicates (point one in the list above). These predicates were introduced precisely to enforce additional column equalities required by the query. Each such predicate merges two view equivalence classes and, collectively, they make the view equivalence classes equal to the query equivalence classes. Hence, a column reference can be redirected to any column within its view equivalence class but not within its query equivalence class.
>
> Compensating predicates of type 1 and type 2 above contain only simple column references. All we need to do is check whether at least one of the columns in the referenced equivalence class is an output column of the view and route the reference to that column. **Compensating predicates of type 3 may involve more complex expressions**. In that case, it may be possible to evaluate the expression even though some of the columns referenced cannot be mapped to an output column of the view. For example, if  `l_quantity * l_extendedprice`  is available as a view output column, we can still evaluate the predicate  `(l_quantity * l_extendedprice > 100)` without the columns `l_quantity` and `l_extendedprice`. However, our prototype implementation ignores this possibility and requires that all columns referenced in compensating predicates be mapped to (simple) output columns of the view.
>
> In summary, we determine whether all rows required by the query can be correctly selected from a view as follows.
>
> 1. Construct compensating column equality predicates while comparing view equivalence classes against query equivalence classes as described in the previous section. Try to map every column reference to an output column (using the view equivalence classes). If this is not possible, reject the view.
> 2. Construct compensating range predicates by comparing column ranges as described in the previous section. Try to map every column reference to an output column (using the query equivalence classes). If this is not possible, reject the view.
> 3. Find the residual predicates of the query that are missing in the view. Try to map every column reference to an output column (using the query equivalence classes). If this is not possible, reject the view.
>

在上一节中，我们解释了如何确定必须在视图上增加补偿谓词，以获得正确的行集。它们有三种不同的类型。

1. 比较视图和查询的列等价分类，获得列相等谓词。上面例子中，有一个这种类型的谓词：`(o_orderdate=l_shipdate)`。
2. 根据视图范围检查查询范围时获得的范围谓词。这里有两个此类谓词： `({p_partkey, l_partkey} <= 160)` 和 `(o_custkey = 123)`。
3. 查询中不匹配的剩余谓词。有一个这种类型的谓词： `(l_quantity*l_extendedprice > 100)`

**所有补偿谓词必须可以从视图的输出中计算得出**。我们通过<u>列引用</u>来**引用**包含列的等价分类，而不是引用列本身，从而利用了列之间的<u>等价性</u>。查询的列等价分类<u>用于除一种情况以外的所有情况</u>，即补偿列相等谓词（上面列表中的第一点）。引入这些谓词是为了增加查询所需的其他列相等性。每个这样的谓词合并两个视图的列等价分类，并共同使视图的列等价分类等于查询的列等价分类。因此，列引用可以重定向到其视图的列等价分类中的任何列，但不能重定向到其查询的列等价分类中的任何列。

上面类型1和类型2的补偿谓词只包含简单的列引用。我们需要做的就是，检查所引用的等价分类中，至少有一列是视图的输出列，并将引用路由到该列。**类型3的补偿谓词可能涉及更复杂的表达式**。在这种情况下，即使某些引用的列无法映射到视图的输出列，也可以评估表达式。例如，如果 `l_quantity * l_extendedprice` 已作为视图的输出列，那么我们仍然可以在没有 `l_quantity` 和 `l_extendedprice` 列的情况下评估谓词  `(l_quantity * l_extendedprice > 100)`。但是，我们的原型实现忽略了这种可能性，并要求补偿谓词中引用的所有列，都能映射到视图（简单）的输出列。

总之，我们确定是否可以从视图中正确选择查询所需的所有行，如下所示：

1. 如前一节所述，在比较视图的<u>列等价分类</u>和查询的<u>列等价分类</u>时，**补偿**<u>列等价谓词</u>。使用视图的列等价分类，尝试将每个列引用映射到输出列。如果不行，拒绝该视图。
2. 按前一节所述，通过比较列范围来**补偿**<u>范围谓词</u>。尝试将每个列引用映射到输出列（使用查询的列等价分类）。如果不行，拒绝该视图。
3. 在剩余谓词中，查找视图中缺少的、查询需要的谓词。尝试将每个列引用映射到输出列（使用查询的列等价分类）。如果不行，拒绝该视图。

#### 3.1.4 可以计算输出表达式吗？（Can output expressions be computed?）

> <u>Checking whether all output expressions of the query can be computed from the view is similar to checking whether the additional predicates can be computed correctly</u>. If the output expression is a constant, just copy the constant to the output. If the output expression is a simple column reference, check whether it can be mapped (using the query equivalence classes) to an output column of the view. <u>For other expressions, we first check whether the view output contains exactly the same expression (taking into account column equivalences)</u>. If so, the output expression is just replaced by a reference to **the matching view output column**. If not, we check whether the expression’s <u>source columns</u> can all be mapped to view output columns, i.e. whether the complete expression can be computed from (simple) output columns. If the view fails these tests, the view is rejected.
>
> This algorithm will miss some cases. For instance, we do not consider whether some part of an expression matches a view output expression. Neither do we consider the case when it can be deduced that a query column is constant because of constraints in the **where-clause**, possibly taking into account **check constraints** on the column.

<u>检查是否可以从视图中计算查询的所有输出表达式，类似于检查是否可以正确计算附加谓词</u>。如果输出表达式是常量，将常量复制到输出即可。如果输出表达式是简单的列引用，通过查询的列等价分类，检查是否可以将其映射到视图的输出列。<u>对于其他表达式，我们首先检查视图输出是否包含完全相同的表达式（要考虑列等价性）</u>。如果是这样，则将输出表达式替换为**匹配的视图输出列的**引用。如果不是，检查表达式的<u>列引用</u>是否都可以映射到视图输出列，即是否可以从（简单的）输出列计算出完整的表达式。如果视图未通过这些测试，则拒绝视图。

这个算法会漏掉一些情况。例如，我们不考虑表达式的某些部分是否与视图输出表达式匹配。我们也不考虑由于**where子句**中的约束，或是列上的[**检查约束**](https://docs.microsoft.com/zh-cn/sql/relational-databases/tables/unique-constraints-and-check-constraints?view=sql-server-ver15#Check)，而推断查询列为常量的情况。

#### 3.1.5 行是否以正确的重复因子出现？（Do rows occur with correct duplication factor?）

> When the query and the view reference exactly the same tables, this condition is trivially satisfied if the view passes the previous tests. The more interesting case occurs when the view references additional tables, which is covered in the next section.

当查询和视图引用完全相同的表时，如果视图通过了先前的测试，则可以轻松满足此条件。 当视图引用其他表时，会发生更有趣的情况，下一部分将对此进行介绍。

### 3.2 有额外表的视图（Views with extra tables）

> Suppose we have a SPJ query that references tables *T~1~, T~2~ ,…, T~n~* and a view that references one additional table, that is, tables *T~1~, T~2~ ,…, T~n~, S*. ==Under what circumstances can the query still be computed from the view?== Our approach is <u>based on recognizing cardinality-preserving joins</u> (sometimes called table extension joins). A join between tables *T* and *S* is cardinality preserving if every row in *T* joins with exactly one row in *S*. If so, we can view *S* as simply extending *T* with the columns from *S*. <u>An equijoin between all columns in a non-null foreign key in *T* and a unique key in *S* has this property</u>. A foreign key constraint guarantees that, for every row *t* of *T*, there exists at least one row *s* in *S* with matching column values for <u>all non-null foreign-key columns in *t*</u>. All columns in *t* containing a null are ignored when validating the foreign-key constraint. It can be shown that all requirements (<u>equijoin, all columns, non-null, foreign key, unique key</u>) are essential.
>
> Now consider the case when the view references multiple extra tables. Suppose the query references tables *T~1~, T~2~ ,…, T~n~* and the view references **m** extra tables, that is, it references tables *T~1~, T~2~,…, T~n~ , T~n+1~, T~n+2~ ,…, T~n+m~*. To determine whether tables *T~n+1~, T~n+2~ ,…, T~n+m~* are joined to tables  *T~1~, T~2~ ,…, T~n~* through a series of cardinality preserving joins we build a directed graph, called the foreign-key join graph. The nodes in the graph represent tables *T~1~, T~2~,…, T~n~ , T~n+1~, T~n+2~ ,…, T~n+m~*. <u>There is an edge from table *T~i~* to table *T~j~* if the view specifies, directly or transitively, a join between tables *T~i~* and *T~j~* and the join satisfies all the five requirements listed above (equijoin, all columns, non-null, foreign key, unique key)</u>. To capture transitive equijoin conditions correctly we must use the equivalence classes when adding edges to the graph. Suppose we are considering whether to add an edge from table *T~i~* to table *T~j~* and there is an acceptable foreign key constraint going from columns *F~1~, F~2~, …, F~n~* of table Ti to columns *C~1~, C~2~, …, C~n~* of *T~j~*. For each column *C~i~*, we locate the column’s equivalence class and check whether the corresponding foreign key column *F~i~* is part of the same equivalence class. If the join columns pass this test, we add the edge.
>
> Once the graph has been built, we try to eliminate nodes *T~n+1~, T~n+2~,…, T~n+m~* by a sequence of deletions. We repeatedly delete any node that has no outgoing edges and exactly one incoming edge. (Logically, this performs the join represented by the incoming edge.) When a node *T~i~* is deleted, its incoming edge is also deleted, which may make another node deletable. This process continues until no more nodes can be deleted or the nodes *T~n+1~, T~n+2~,…, T~n+m~* have been eliminated. If we succeed in eliminating nodes *T~n+1~, T~n+2~,…, T~n+m~*, the extra tables in the view can be eliminated through cardinality-preserving joins and the view passes this test. 
>
> <u>The view must still pass the tests detailed in the previous section (subsumption tests, required output columns available). However, these test all assume that the query and the view reference the same tables</u>. To make them the same, we conceptually add the extra tables *T~n+1~, T~n+2~,…, T~n+m~* to the query and join them to the existing tables *T~1~, T~2~ ,…, T~n~* through exactly the same foreign-key joins that were used to eliminate them from the view. Because the joins are all cardinality preserving, this will not change the result of the query in any way. ==In practice==, we merely simulate the addition of extra tables by updating query equivalence classes. We ==first== add a trivial equivalence class for each column in tables *T~n+1~,T~n+2~ ,…, T~n+m~*. (We have now added the tables to the from clause of the query.) ==Next==, we scan the join conditions of all foreign-key edges deleted during the elimination process above and apply them to query equivalence classes. This will cause some query equivalence classes to merge. (We have now added the join conditions to the where-clause.) ==At the end of== this process, the (conceptually) modified query references the same tables as the view and the query equivalence classes have been updated to reflect this change. After this modification, all tests described in the previous section can be applied unchanged.
>
> **Example 3**: This example illustrates views with extra tables.
>
> View:
> ```sql
> Create view v3 with schemabinding as
> Select c_custkey, c_name, l_orderkey,
>        l_partkey, l_quantity
> From dbo.lineitem, dbo.orders, dbo.customer
> Where l_orderkey = o_orderkey
>   And o_custkey = c_custkey
>   And o_orderkey >= 500
> ```
>
> Query:
> ```SQL
> Select l_orderkey, l_partkey, l_quantity
> From lineitem
> Where l_orderkey between 1000 and 1500
>   And l_shipdate = l_commitdate
> ```
>
> We obtain the following equivalence classes and ranges for the view and the query.
>
> |        |                                                              |
> | ------ | ------------------------------------------------------------ |
> | View:  | {l_orderkey, o_orderkey}, {o_custkey, c_custkey}<br/>{ l_orderkey, o_orderkey} ∈ (500, +∞) |
> | Query: | {l_shipdate, l_commitdate}<br/>{l_orderkey} ∈ (1000, 1500)   |
>
> The foreign-key join graph for the view consists of three nodes (lineitem, orders, customer) with an edge from lineitem to orders and an edge from orders to customer. The customer node can be deleted because it has no outgoing edges and one incoming edge. This also deletes the edge from orders to customer. Now orders has no outgoing edges and can be removed.
>
> We then conceptually add orders and customer to the query. The join predicate for the <u>lineitem-to-orders</u> edge is `l_orderkey = o_orderkey`, which generates the equivalence class *{l_orderkey, o_orderkey}*. The join predicate for the <u>orders-to-customer</u> edge is `o_custkey = c_custkey`, which generates the equivalence class *{o_custkey, c_custkey}*. The updated query equivalence classes and ranges for the query are
>
> ```bash
> Query: {l_shipdate, l_commitdate}, {l_orderkey, o_orderkey},
>        {o_custkey, c_custkey};
>        {l_orderkey, o_orderkey} ∈ (1000, 1500)
> ```
>
> We then apply the subsumption tests. The view passes the equijoin subsumption test because every view equivalence class is a subset of a query equivalence class. It also passes the range subsumption test because the view range *{ l_orderkey, o_orderkey}∈ (500, +∞)* contains the corresponding query range *{ l_orderkey, o_orderkey} ∈ (1000, 1500)*. The compensating predicates are `l_orderkey >= 1000 and l_orderkey <= 1500`, which can be enforced because *l_orderkey* is available in the view output. Finally, every output column of the ~~view~~(query) can be computed from the view output.
>
> The procedure above **ensures** that we can “prejoin”, directly or indirectly, each extra table in the view to some input table *T* of the query and the resulting, wider table will contain exactly the same rows as *T.* This is safe but somewhat restrictive because we only need to guarantee it for <u>the rows actually consumed by the query</u>, not all rows. Here is an example of such a case. Suppose we have a view consisting of tables *T* and *S* joined on T.F=S.C where *F* is declared as a foreign key referencing *C* and *C* is the primary key of *S*. Now consider a selection query on table *T* with the predicate *T.F > 50*. If *T.F* is not declared with “**not null**”, the view will be rejected by our procedure. The join of *T* and *S* does not preserve the cardinality of *T* because rows with a **null** in column *T.F* are not present in the view. However, for the subset of rows with a non-null *T.F* value, it does preserve cardinality, which is all that matters because of the null-rejecting predicate *T.F > 50* in the query. On other words, any row in *T* containing a null value in *T.F* will be discarded the query predicate in any case. The algorithm can be modified to handle this case (not yet implemented). All that is required is an additional check when considering whether to add an edge to the foreign-key join graph. A foreign key column allowing nulls is still acceptable if the query contains a null-rejecting predicate on the column (other than the equijoin predicate).

假设我们有一个SPJ查询引用表 *T~1~，T~2~，…，T~n~*，有一个视图额外多引用了一张表，即表 *T~1~，T~2~，…，T~n~，S*。==在什么情况下仍然可以从视图计算查询？==我们的方法<u>基于识别保留基数的 Join</u>（有时称为表扩展 Join）。如果 *T* 中的每一行恰好与 *S* 中的一行关联，则表 *T* 和 *S* 之间的 Join 保留基数。如果这样，我们可以简单地把 *S* 看作是用 *S* 中的列扩展 *T*。<u>*T* 中非空外键中的所有列与 *S* 中的唯一键之间的等值Join具有此属性</u>。外键约束保证，对于 *T* 中的每一行  *t*，*S* 中至少存在一行 *s*，<u>对于 *t* 中所有非空外键列</u>，都有匹配的列值。验证外键约束时，将忽略 *t* 中所有包含空值的列。可以证明，所有要求（<u>等值 Join，有外键，外键的所有列，非空，唯一键</u>）都是必需的。

现在考虑视图引用多个额外表的情况。假设查询引用表 *T~1~，T~2~，…，T~n~*，视图引用 **m** 个额外的表，即引用表 *T~1~，T~2~，…，T~n~，T~n+1~，T~n+2~，…，T~n+m~*。要确定表 *T~n+1~, T~n+2~ ,…, T~n+m~* 与表 *T~1~, T~2~ ,…, T~n~* 之间的Join是否是一系列保留基数Join，我们建立一个有向图，称为**外键关联图**。图中的节点表示表*T~1~, T~2~,…, T~n~ , T~n+1~, T~n+2~ ,…, T~n+m~*。<u>如果视图直接或通过传递指定表*T~i~* 和表 *T~j~* 之间的 Join 满足上面列出的5个要求（等值 Join，有外键，外键的所有列，非空，唯一键），那么从表 *T~i~* 到表 *T~j~* 有一条边</u>。为了正确地捕获可传递的等值 Join 的条件，在向图中添加边时必须使用<u>列的等价分类</u>。假设我们正在考虑是否在表 *T~i~* 和表 *T~j~* 之间添加一条边，且从表 *T~i~*  的列 *F~1~，F~2~，…，F~n~* 到 *T~j~* 的列 *C~1~，C~2~，…，C~n~* 之间有一个可接受的外键约束。对于每列 *C~i~*，我们找到该列的等价分类，并检查对应的外键列 *F~i~* 是否属于同一等价分类。如果 Join 的列通过此测试，则添加边。

一旦建立了图，我们试图通过一系列的删除来消除节点 *T~n+1~，T~n+2~，…，T~n+m~*。我们反复删除没有输出边且只有一个输入边的节点（逻辑上，这是在执行由输入边表示的Jion）。删除节点 *T~i~* 时，也会删除其输入边，这可能会使另一个节点可删除。此过程将一张持续，直到无法删除更多节点，或者节点 *T~n+1~，T~n+2~，…，T~n+m~* 已被删除为止。如果我们能成功地消除了节点*T~n+1~，T~n+2~，…，T~n+m~*，那么视图中多余的表就可以通过保留基数的Join来消除，视图则通过了这个测试。

<u>视图仍必须通过上一节中详细介绍的测试（包含测试，且存在所需要的输出列）。但是，这些测试均假设查询和视图引用相同的表</u>。为了使它们相同，我们在概念上将多余的表 *T~n+1~, T~n+2~,…, T~n+m~*  添加到查询中，并将它们与现有表 *T~1~, T~2~ ,…, T~n~* Join，Join的键是前述从视图中消除这些冗余表Join的外键。由于Join保留基数，因此不会更改查询结果。实际上，我们只是通过<u>更新查询的列等价分类</u>**来**<u>模拟额外表的添加</u>。==首先==，我们为表 *T~n+1~,T~n+2~ ,…, T~n+m~* 中的每一列添加一个简单的等价分类（**现在**已将表添加到查询的`from子句`中）。==接着==，我们扫描在上述消除过程中删除的所有外键边的连接条件，并将它们应用于查询等价类。这将导致一些查询的列等价分类合并（==现在==已经在`where子句`中添加了关联条件）。==在此过程结束时==，（从概念上而言）修改后的查询引用与视图相同的表，并且查询的列等价分类已更新以反映此更改。修改后，可以原样使用上一节描述的所有测试。

**例 3**: 这个例子演示带有额外表的视图

视图：
```sql
Create view v3 with schemabinding as
Select c_custkey, c_name, l_orderkey,
       l_partkey, l_quantity
From dbo.lineitem, dbo.orders, dbo.customer
Where l_orderkey = o_orderkey
  And o_custkey = c_custkey
  And o_orderkey >= 500
```

查询：
```SQL
Select l_orderkey, l_partkey, l_quantity
From lineitem
Where l_orderkey between 1000 and 1500
  And l_shipdate = l_commitdate
```

视图和查询的列等价分类和范围如下：

|        |                                                              |
| ------ | ------------------------------------------------------------ |
| 视图： | {l_orderkey, o_orderkey}, {o_custkey, c_custkey}<br/>{ l_orderkey, o_orderkey} ∈ (500, +∞) |
| 查询： | {l_shipdate, l_commitdate}<br/>{l_orderkey} ∈ (1000, 1500)   |

视图的外键关联图由三个节点（lineitem、orders、customer）组成，其中分别从 `lineitem` 到 `orders`、从 `orders` 到 `customer` 有一条边。因为 `customer`节点没有输出边且只有一个输入边，可以删除它，这也删除了从 `orders` 到 `customer` 的边。现在 `orders` 没有输出边了，也可以删除。

然后，我们从概念上将 `orders` 和 `customer` 添加到查询中。<u>lineitem-to-orders</u> 这条边的关联谓词是 `l_orderkey = o_orderkey`，它产生的等价分类是 *{l_orderkey, o_orderkey}*。<u>orders-to-customer</u> 这条边的关联谓词是 `o_custkey = c_custkey`，它产生的等价分类是 *{o_custkey, c_custkey}* 。更新的查询等价分类和查询的范围是：

```bash
Query: {l_shipdate, l_commitdate}, {l_orderkey, o_orderkey},
       {o_custkey, c_custkey};
       {l_orderkey, o_orderkey} ∈ (1000, 1500)
```

然后我们开始包容性测试。因为每个视图的列等价分类都是查询的列等价分类的子集，所以视图通过**等值关联包含测试**。因为视图范围 *{l_orderkey，o_orderkey}∈(500，+∞)* 包含相应的查询范围 *{l_orderkey，o_orderkey}∈(1000，1500)*，所以它也通过了**范围包含测试**。因为 *l_orderkey* 在视图输出中可用，所以可以增加补偿谓词 `l_orderkey>=1000 and l_orderkey<= 1500` 。最后，可以从视图输出中计算查询的每个输出列。

上面的过程**确保**，我们可以直接或间接地，将视图中的每个额外表“预连接”到查询的某些输入表 *T* 中，并且生成的宽表将包含与 *T* 完全相同的行。虽然安全，但有一定的限制性，因为我们只需要保证<u>查询实际使用的行</u>，而不是所有行。下面就是这样一个例子。假设我们有一个视图，该视图由表 *T* 和 *S* 通过 *T.F = S.C* 关联组成，其中 *F* 被声明为引用 *C* 的外键，而 *C* 是 *S* 的主键。现在考虑表 *T* 上谓词 *T.F>50* 的选择查询。如果 *T.F* 未声明为“**not null**”，我们的算法将拒绝该视图。*T* 和 *S* 的关联不保留 *T* 的基数，因为视图中不存在 *T.F* 列有 **null** 的行。但重要的是，对于 *T.F* 的非空子集，它确实保留了基数，因为查询中的谓词 *T.F> 50* 过滤了空值。换句话说，在任何情况下，都将丢弃 *T* 中 *T.F* 列包含空值的行。可以修改算法以处理这种情况（尚未实现）。所需的只是在考虑是否向**外键关联图**添加边时，增加一个额外检查。如果在列上，查询包含拒绝空的谓词（等值join谓词除外），则仍然可以接受空的外键列。

### 3.3 聚合查询和视图（Aggregation queries and views）

> In this section, we consider aggregation queries and views. SQL Server allows expressions, as opposed to just columns, in the group-by list both in queries and materialized views. In a materialized view, all group-by expressions must also be in the output list to ensure a unique key for each row. In addition, the output list must contain a count_big(*) column so deletions can be handled incrementally. The only other aggregation function currently allowed in materialized views is sum.
>
> We treat aggregation queries as consisting of a SPJ query followed by a group-by operation and similarly for views. An aggregation query can be computed from a view if the view satisfies the following requirements.
>
> 1. The SPJ part of the view produces all rows needed by the SPJ part of the query and with the right duplication factor.
> 2. All columns required by compensating predicates (if any) are available in the view output.
> 3. The view contains no aggregation or is less aggregated than the query, i.e, the groups formed by the query can be computed by further aggregation of groups output by the view.
> 4. All columns required to perform further grouping (if necessary) are available in the view output.
> 5. All columns required to compute output expressions are available in the view output.
>
>
> The first two requirements are the same as for SPJ queries. The third requirement is satisfied if the group-by list of the query is a subset of the group-by list of the view. That is, if the view is grouped on expressions A, B, C then the query can be grouped on any subset of A, B, C. This includes the empty set, which corresponds to an aggregation query without a group-by clause. We currently require that each group-by expression in the query match exactly some group-by expression in the view (taking into account column equivalences). This can be relaxed. As shown in[16], it is sufficient that the grouping expression of the view functionally determine the grouping expressions of the query.
>
> If the query group-by list is equal to the view group-by list, no further aggregation is needed so the fourth requirement is automatically satisfied. If it is a strict subset, then we must add a compensating group-by on top of the view. The grouping expressions are the same as for the query. Because they are a subset of the view grouping expressions and all grouping expressions of the view must be part of the view output, they are always available in the view output. Hence, the third requirement is automatically satisfied.
>
> Testing whether the fourth requirement is satisfied is virtually identical to what was discussed for SPJ queries. The only slight difference occurs when dealing with aggregation expressions. If the query specifies a `count(*)` and the view is an aggregation view, the `count(*)` must be replaced by a SUM over the view’s `count_big(*)` column. If the query output contains a `SUM(E)` where E is some scalar expression, we require that the view contain an output column that matches exactly (taking into account column equivalences). `AVG(E)` is converted to `SUM(E)/count_big(*)`.
>
> **Example 4**: This may sound too easy, perhaps causing some readers to wonder whether we handle situations illustrated by the following example view and query.
>
> View:
>
> ```sql
> Create view v4 with schemabinding as
> Select o_custkey, count_big(*) as cnt
>        sum(l_quantity*l_extendedprice)as revenue
> From dbo.lineitem, dbo.orders
> Where l_orderkey = o_orderkey
> Group by o_custkey
> ```
>
> Query:
>
> ```sql
> Select c_nationkey,
>        sum(l_quantity*l_extendedprice)
> From lineitem, orders, customer
> Where l_orderkey = o_orderkey
>   And o_custkey = c_custkey
> Group by c_nationkey
> ```
>
> It is easy to see that the query can be computed from the view by joining it with the customer table and then aggregating the result on c_nationkey. However, the view satisfies none of the conditions listed above so one might conclude that we will miss this opportunity. Not so – this is a case where integration with the optimizer helps. For queries of this type, the SQL Server optimizer also generates alternatives that include preaggregation. That is, it will generate the following form of the query expression.
>
> ```sql
> Select c_nationkey, sum(rev)
> From customer,
>     (select o_custkey,
>             sum(l_quantity*l_extendedprice) as rev
>     From lineitem, orders
>     Where l_orderkey = o_orderkey
>     Group by o_custkey) as iq
> Where c_custkey = o_custkey
> Group by c_nationkey
> ```
>
> When the view-matching algorithm is invoked on the inner query, it easily recognizes that the expression can be computed from v4. Substituting in the view then produces exactly the desired expression, namely,
>
> ```sql
> Select c_nationkey, sum(revenue)
> From customer, v4
> Where c_custkey = o_custkey
> Group by c_nationkey
> ```
>

本节我们考虑聚合查询和视图。SQL Server允许在查询和物化视图中使用 `Group By` 表达式，而不仅仅是列。在物化视图中，所有 `Group By` 表达式也必须在输出字段中，以确保每行有唯一的键。为了可以增量删除，输出字段必须包含 `count_big(*)` 列，除此之外，`sum`是物化视图当前唯一允许的聚合函数。

我们将聚合查询视为由SPJ查询加后续的分组操作组成，聚合视图也类似组成。 如果视图满足以下要求，则可以从该视图计算聚合查询：

1. 视图的SPJ部分将生成查询的SPJ部分所需的所有行，并具有正确的重复因子。
2. 视图输出中提供了补偿谓词（如果有）所需的所有列。
3. 视图不包含聚合或聚合粒度比查询细，即可以在视图输出的基础上通过进一步聚合来计算查询所需要的分组。
4. 视图输出中提供了执行进一步分组（如果需要）所需的所有列。
5. 视图输出中提供了计算输出表达式所需的所有列。

前两个要求与SPJ查询相同。如果查询的 `Group by` 字段是视图的 `Group by` 字段的子集，则满足第三个要求。也就是说，如果视图分组在表达式A、B、C上，则查询可以在A、B、C的任何子集上分组。还包括空集，对应于不带 `Group by 子句`的聚合查询。我们目前要求查询中的每个 `Group by` 表达式与视图中的某个 `Group by` 表达式完全匹配（考虑到列等价性），但可以放松，如[16]所示，视图的分组表达式能满足查询分组表达式的功能就足够了。

如果查询的 `Group by` 字段等于视图 `Group by` 字段，则不需要进一步的聚合，自动满足了第四个要求。如果它是一个严格的子集，那么我们必须在视图的顶部添加一个补偿的 `Group by`，让分组表达式与查询的相同。因为此时是视图分组表达式的子集，并且视图的所有分组表达式都必须是视图输出的一部分，所以它们始终在视图输出中可用。因此，自动满足第三个要求。

测试是否满足第四项要求，实际上与测试SPJ查询讨论的内容一样。在处理聚合表达式时，仅有一点细微的差别。如果查询指定了 `count(*)`，并且视图是聚合视图，则 `count(*)` 必须替换为视图 `count_big(*)` 列上的SUM。如果查询输出包含一个 `SUM(E)`，其中*E*是某个标量表达式，则我们要求视图包含一个完全匹配的输出列（考虑到列的等价性）。 `AVG(E)` 转换为 `SUM(E)/count_big(*)`。

**例4**：这听起来很简单，也许使一些读者怀疑我们是否处理下例中视图和查询所说明的情况。

视图：

```sql
Create view v4 with schemabinding as
Select o_custkey, count_big(*) as cnt
       sum(l_quantity*l_extendedprice)as revenue
From dbo.lineitem, dbo.orders
Where l_orderkey = o_orderkey
Group by o_custkey
```

查询：

```sql
Select c_nationkey,
       sum(l_quantity*l_extendedprice)
From lineitem, orders, customer
Where l_orderkey = o_orderkey
  And o_custkey = c_custkey
Group by c_nationkey
```

很容易看出可以从视图算出查询，方法是将视图与 *customer* 表关联，然后在 *c_nationkey* 上聚合。然而，该视图不满足上面列出的任何条件，因此可能会认为我们将错失这一机会。并非如此——这是一个与优化器集成有帮助的例子。对于此类查询，SQL Server优化器还生成包含预聚合的替代项。也就是说，它将生成以下形式的查询表达式。

```sql
Select c_nationkey, sum(rev)
From customer,
    (select o_custkey,
            sum(l_quantity*l_extendedprice) as rev
    From lineitem, orders
    Where l_orderkey = o_orderkey
    Group by o_custkey) as iq
Where c_custkey = o_custkey
Group by c_nationkey
```

在内部子查询上调用视图匹配算法，很容易识别出可以从*v4*计算出查询结果。 然后，替换视图即可产生所需的表达式，即：

```sql
Select c_nationkey, sum(revenue)
From customer, v4
Where c_custkey = o_custkey
Group by c_nationkey
```

## 4. 视图的快速过滤（Fast filtering of views）

> To speed up view matching we maintain in memory a description of every materialized view. The view descriptions contain all information needed to apply the tests described in the previous section. Even so, it is slow to apply the tests to all views each time the view-matching rule is invoked if the number of views is very large. In this section, we describe an in-memory index, called a filter tree, which allows us to quickly discard views that cannot be used by a query.
>
> A filter tree is a multiway search tree where all the leaves are on the same level. A node in the tree contains a collection of (key, pointer) pairs. A key consists of a set of values, not just a single value. A pointer in an internal node points to a node at the next level while a pointer in a leaf node points to a list of view descriptions. A filter tree subdivides the set of views into smaller and smaller partitions at each level of the tree.
>
> A search in a filter tree may traverse multiple paths. When the search reaches a node, it continues along some of the node’s outgoing pointers. Whether to continue along a pointer is determined by applying a search condition on the key associated with the pointer. The condition is always of the same type: <u>a key qualifies</u> if it is a subset (superset) of or equal to a given search key. The search key is also a set. We can always do a linear scan and check every key but this may be slow if the node contains many keys. To avoid a linear scan, we organize the keys in a **lattice** structure, which allows us to find all subsets (supersets) of a given search key easily. We call this internal structure a **lattice index**.
>
> We describe the lattice index in more detail in the next section and then explain the <u>partitioning conditions</u> applied at different levels of the tree.

为了加快视图匹配，在内存中保留了每个物化视图的描述，包含了上一节视图匹配算法所需的所有信息。即使如此，每次调用匹配规则时，如果视图的数量非常大，匹配所有视图会很慢。本节描述了一个称为**过滤树**的内存索引，可快速丢弃查询不匹配的视图。

**过滤树**是一种多路搜索树，其中所有叶子都处于同一级别。 树中的节点包含（键、指针）对的集合。 键由一组值组成，而不仅仅是一个值。 内部节点的指针指向下一级的节点，叶节点的指针指向视图描述列表。过滤树在树的每一级将视图集细分为越来越小的**分区**。

**过滤树**中的搜索可遍历多个路径。 搜索到达某个节点后，它将沿着该节点的某些传出指针继续。 在<u>与指针关联的键上</u>应用搜索条件，决定是否沿着指针继续。条件总是属于同一类型：<u>键限定</u>它是给定搜索键的子集（超集）还是等于给定搜索键。搜索键也是一个集合。我们总是执行线性扫描并检查每个键，但如果节点包含多个键，可能会很慢。为了避免线性扫描，我们将<u>键</u>组织在一个称为**lattice**的结构中，这样我们就可以轻松地找到给定<u>键</u>的所有子集（超集）。我们称这种内部结构为 **lattice 索引**。

我们将在下一节更详细地描述**lattice 索引**，然后说明在树的不同层上应用的<u>分区条件</u>。

### 4.1 Lattice 索引（Lattice index）

> The subset relationship between sets imposes a **partial order** among sets, which can be represented as a lattice. As the name indicates, a lattice index organizes the keys in a graph that correspond to the lattice structure. In addition to the (key, downward pointer) pair described above, a node in the lattice index contains two collections of pointers, **superset pointers** and **subset pointers**. A superset pointer of a node V points to a node that represents a minimal superset of the set represented by V. Similarly, a subset pointer of V points to a node that represents a maximal subset of the set represented by V. Sets with no subsets are called roots and sets without supersets are called tops. A lattice index also contains an array of pointers to tops and an array of pointers to roots. Figure 1 shows a lattice index storing eight key sets.
>
> > 图1
>
> Searching a lattice index is a simple recursive procedure. Suppose we want to find supersets of AB. We start from the top nodes, where we find that ABC and ABF are supersets of AB. From each qualifying node, we recursively follow the subset pointers, at each step checking whether the target node is subsets of AB. AB is acceptable but none if its subset nodes are. The search returns ABC, ABF, and AB. Note that AB is reached twice, once from ABC and once from ABF. To avoid visiting and possibly returning the same node multiple times, the search procedure must remember which nodes have been visited. The algorithm for finding subsets is similar; the main difference is that the search starts from root nodes and proceeds upwards following superset pointers.
>
> Due to space constraints, we will not describe insertion and deletion algorithms for lattice indexes. They are not complex but some care is required with the details.
>

集合间<u>子集的关系</u>在集合间强加了一个**偏序**，它可以表示为一个 lattice。顾名思义，lattice 索引将键组织在与 lattice 结构相对应的图中。除了前述的（键，向下指针）对之外，lattice索引中的节点还包含两个指针集合：**超集指针**和**子集指针**。节点 *V* 的超集指针指向的节点，是 *V* 所表示集合的最小超集。类似，*V* 的子集指针指向的节点，是 *V* 所表示集合的最大子集。 没有子集的集合称为根，没有超集的集合称为顶部。lattice 索引还包含一个指向顶部的指针数组和一个指向根的指针数组。图1显示了存储八个键集的lattice 索引。

> 图1

搜索 lattice 索引是一个简单的递归过程。假设我们要查找AB的超集。我们从顶部节点开始，我们发现ABC和ABF是AB的超集。从每个符合条件的节点开始，我们递归地遍历其子集指针，每步检查目标节点是否为AB的超集。可接受AB节点，但不接受其子集节点。搜索返回ABC、ABF和AB。注意AB是两次到达的，一次来自ABC，一次来自ABF。为了避免访问并多次返回同一个节点，搜索过程必须记住访问了哪些节点。查找子集的算法是相似的；主要区别是搜索从根节点开始，然后沿着超集指针向上进行。

由于空间的限制，我们将不描述 lattice 索引的插入和删除算法。并不复杂，但需要注意细节。

### 4.2 分区条件（Partitioning conditions）

> A filter tree recursively subdivides the set of views into smaller and smaller non-overlapping partitions. At each level, a different partitioning condition is applied. In this section, we describe the partition conditions used in our prototype.

过滤树递归地将视图集细分为越来越小的不重叠分区。在每层上，使用不同的分区条件。本节，我们将描述原型中使用的分区条件。

#### 4.2.1 源表条件（Source table condition）

> Views that lack some of the tables required by the query can be discarded. This in captured by the following condition. 
>
> **Source table condition**: A query cannot be computed from a view unless the view’s set of source tables is a superset of the query’s set of source tables.
>
> We build a lattice index using the view’s set of source tables as the key. Given a query’s set of source tables, we search the lattice index for partitions containing views that satisfy this condition.

可以丢弃<u>缺少查询所需表的视图</u>。由下面的条件决定：

**源表条件**：除非视图源表集是查询源表集的**超集**，否则无法从视图计算查询。

我们使用<u>视图的源表集</u>作为键来构建 lattice 索引。给定查询的源表集，我们在 lattice 索引中搜索包含满足此条件的视图分区。

> 等价于在视图源表集的 lattice 索引上，搜索查询源表集的超集，

#### 4.2.2 视图中心条件（Hub condition）

> Recall the algorithm explained in section 3.2 for eliminating extra tables from a view. In that section, it was sufficient to have the algorithm reduce the set of source tables to the same set as that of the query. However, we can let the algorithm run until no further tables can be eliminated from the view, thereby reducing the remaining set of tables to the smallest set possible. **We call the remaining set the hub of the view**. As discussed in section 3.2, a view cannot be used to answer a query unless we can eliminate all extra tables through cardinality-preserving joins. The hub cannot be reduced further so clearly we can disregard any view whose hub is not a subset of the query’s set of source tables. This observation gives us the following condition.
>
> **Hub condition**: A query cannot be computed from a view unless the hub of the view is a subset of the query’s set of source tables.
>
> The previous condition gave us a lower bound on a view’s set of source tables while this condition gives us an upper bound. We again use a lattice index structure but this time with view hubs as the key instead of the complete set of source tables. Given a query, we then search the index for nodes whose key is a subset of the query’s set of source tables.
>
> The algorithm outlined above for computing view hubs tends to produce hubs that are unnecessarily small because it takes into account only foreign-key joins. It can be improved by also taking into account other predicates. Suppose *T* is a table that would be eliminated from the hub by the algorithm above. **Let *T.C* be a column not participating in any non-trivial equivalence class**. If *T.C* is referenced in a range or other predicate, we can leave *T* in the hub. The join is no longer guaranteed to be cardinality preserving because the predicate on *T.C* may reject some rows in *T*. The only way the reference to *T.C* can be rerouted to another column is if the query contains a column equality predicate involving *T.C*. However, if that is the case, then *T* must also be among the query’s source tables so leaving *T* in the hub will not cause the view to be rejected.

回顾[3.2节]()中从视图中删除多余表的算法。在那里，算法将源表的集合减少到与查询一样就足够了。但可以让算法继续运行，直到无法从视图中删除更多表为止，从而将剩余的表减少到最小可能的集合。**我们将剩下的表集合称为视图中心**。如3.2节所述，除非我们可以通过保留基数的关联消除所有多余的表，否则视图不能用于回答查询。 当无法进一步减少视图中心时，很明显，我们可以忽略视图中心不是查询源表集合子集的任何视图。 这为我们提供了以下条件。

**中心条件**：视图中心必须是查询源表集合的子集，否则无法从视图计算查询。

前面的条件给出了视图源表集合的下限，而这个条件给出了上限。我们再次使用 lattice 索引结构，但是这次使用视图中心作为键，而不是完整源表集合（的lattice索引）。给定一个查询，然后我们在索引中搜索其键是该查询源表集合子集的节点。

上面概述的计算视图中心的算法因为只考虑了外键关联，往往会产生不必要的小中心。可以通过考虑其他谓词来改进它。假设 *T* 是可以通过上述算法从视图中心中删除的表。**令 *T.C* 属于简单的列等价分类**。如果在范围或其他谓词中引用了 *T.C*，可以将 *T* 留在中心。 由于 *T.C* 上的谓词可能会拒绝 *T* 中的某些行，因此该关联不再保证保留基数。对 *T.C* 的引用可以重新路由到另一列的唯一方法是，如果查询包含涉及 *T.C* 的相等谓词 但这种情况，则 *T* 也必须位于查询的源表中，因此将 *T* 保留在中心中不会导致视图被拒绝。

#### 4.2.3 输出列条件（Output column condition）

> Assume for the moment that the output lists of queries and views are all simple column references. We will deal with more complex output expressions separately. As stated earlier, a query cannot be computed from a view unless all its output expressions can be computed from the output of the view. However, this does not mean that a query output column has to match an output column because of equivalences among columns. The following example illustrates what is required.
>
> **Example 6**: Suppose the query outputs columns A, B, and C. Furthermore, suppose the query contains column equality predicates generating the following equivalence classes: {A, D, E}, {B, F} {C}. The columns within an equivalence class all have the same value so they can be used interchangeably in the output list. We indicate this choice by writing the output list as {A, D, E}, {B, F} {C}.
>
> Now consider a view that outputs {<u>A</u>，D，G}, {<u>E</u>}, {<u>B</u>} and {<u>C</u>, H} where the column equivalences have been computed from the column equality predicates of the view. The columns that are actually included in the output list are indicated by underlining. Logically, we can then treat the view as outputting all of the columns, that is, as if its output list were extended to A, D, G, E, B,C, H.
>
> The first output column of the query can be computed from the view if at least one of the columns A, D, or E exists in the view’s extended output list. In this case, all of them do. Similarly, the second column can be computed if B or F exists in the extended output list. B does (but F does not). Finally, the third output column requires C, which also exists in the extended output list. Consequently, the query output can be computed from the view.
>
> As this example illustrated, to correctly test availability of output columns we must take into account column equivalences in the query and in the view. We do this by replacing <u>each column reference in the output list</u> by <u>a reference to the columns equivalence class</u>. For a view, we then compute the extended output list by including every column in the referenced equivalence classes. We can now state the condition that must hold. 
>
> **Output column condition**: A view cannot provide all requiredoutput columns unless, for each equivalence class in the query’s output list, at least one of its columns is available in the view’s extended output list.
>
> To exploit this condition, we build lattice indexes using the extended output lists of the views as keys. Given a query, we search the index recursively beginning from the top nodes. A node qualifies if its extended output list satisfies the condition above. If so, we follow its subset pointers. If not, it is not necessary to follow the pointers because, if a view V does not provide all required columns, neither does any view whose extended output list is a subset of V’s extended output list.

现在假设查询和视图的输出列表都是简单的列引用。我们将在后面的小节里论述如何处理更复杂的输出表达式。如前所述，除非可以从视图的输出中计算出查询的所有输出表达式，否则无法从视图中计算出查询。但是，这并不意味着查询输出列必须与视图输出列匹配，因为有等价的列存在。下面的例子说明了所需条件。

**例 6**：假设查询输出列A，B和C。此外，假设查询包含列相等谓词，它们生成的列等价分类为：{A，D，E}，{B，F}，{C}。等价分类中列，值都相等，因此可以在输出中互换使用。 我们通过将输出列写为{A，D，E}，{B，F} 和 {C}来表示这一选择。

现在假设视图的列等价分类为：{<u>A</u>，D，G}，{<u>E</u>}，{<u>B</u>} 和 {<u>C</u>，H}，下划线表示实际输出的列。逻辑上，我们可以认为视图输出所有这些列，即，输出列扩展为A，D，G，E，B，C，H。

如果视图扩展输出中至少存在A，D或E中一列，则可以从视图中计算出查询的第一输出列。本例中都存在。同样，如果扩展输出列表中存在B或F，则可以计算第二列，这里B存在（但F不存在）。最后，第三输出列需要C，它也存在于扩展输出列表中。 因此，可以从视图中计算查询输出。

如本例所示，要正确测试输出列的可用性，我们必须考虑查询和视图中的列等价性。为此，我们将<u>查询输出列表中的每个列引用</u>替换为<u>列等价分类中的所有列的引用</u>。 对于视图，我们用列等价分类中的所有列来计算扩展输出列的列表。现在可以说明必须满足的条件。

**输出列条件**：查询输出列表中的每个列等价分类，至少有一列存在于视图的扩展输出列中。否则，视图无法提供所有必需的输出列。

为了利用这个条件，我们使用视图的扩展输出列表作为键来构建 lattice 索引。给定查询，我们从顶部节点开始递归搜索索引。如果节点的扩展输出列表满足上述条件，则该节点合格。，我们将继续检查其子集指针。 如果不是，则停止，因为如果视图V没有提供所有必需的列，则其扩展输出列表是V扩展输出列表子集的视图也不能提供。

#### 4.2.4 分组列（Grouping columns）

> An aggregation query cannot be computed from an aggregation view unless the query’s grouping columns are a subset of the view’s grouping columns, again taking into account column equivalences. This is exactly the same relationship as the one that must hold between the output columns of the query and the view. Consequently, we can extend the views’ grouping lists in the same way as for output columns and build lattice indexes on the extended grouping lists. For completeness, here is the condition that must hold between grouping columns.
>
> **Grouping column condition**: An aggregation query cannot be computed from an aggregation view unless, for each equivalence class in the query’s grouping list, at least one of its columns is present in the view’s extended grouping list.

<u>查询分组列</u>必须是<u>视图分组列</u>的子集（亦要考虑到列等价性），否则不能从聚合视图算出聚合查询。 这与查询和视图的输出列之间必须保持的关系完全相同。因此，我们可以按照与输出列相同的方式扩展视图的分组列表，并在扩展的分组列表上建立 lattice 索引。为了完整起见，下面是分组列之间必须满足的条件。

**分组列条件**：能否从聚合视图计算聚合查询，取决于查询的分组列表中的每个列等价分类，在视图的扩展分组列表中至少存在一列。

#### 4.2.5 范围约束列（Range constrained columns）

> A query cannot be computed from a view that specifies range constraints on a column that is not range constrained in the view, again taking into account column equivalences. We associate with each query and view a range constraint list, where each entry references a column equivalence class. A column equivalence class is included in the list if it has a constrained range, that is, at least one of the bounds has been set. Next, we compute an extended constraint list in the same way as for output columns but this time for the query but not the view. We can now state the condition that must hold.
>
> **Range constraint condition**: A query cannot be computed from a view unless, for each equivalence class in the view’s range constraint list, at least one of its columns is present in the query’s extended range constraint list.
>
> Note that the extended range constraint list is associated with the query, and not the view. Hence, lattice indexes on the extended constraint lists of views, mimicking the indexes on output columns and grouping columns, cannot be used. However, we can build lattice indexes based on a weaker condition involving a reduced range constraint list. The reduced range constraint list contains only columns that reference trivial equivalence classes, i.e. **columns that are not equivalent to any other columns**.
>
> **Weak range constraint condition**: A query cannot be computed from a view unless the view’s reduced range constraint list is a subset of the query’s extended range constraint list.
>
> When building a lattice index based on this condition, the complete constraint list of a view is included and used as the key of a node but the subset-superset relationship is computed solely based on reduced constraint lists. A search starts from the roots and proceeds upwards along superset edges. If a node passes the weak range constraint condition, we follow its superset pointers but the node is returned only if it also passes the range constraint. If a node fails the weak range constraint condition, all of its superset nodes will also fail so there is no need to check them.

如果视图指定了列的范围约束，而查询未指定列的范围约束，则无法从视图中计算出查询（仍需考虑列等价性）。我们与每个查询和视图关联一个范围约束列表，其中每个项都引用一个列等价分类。如果列等价分类存在约束范围（即至少设置了一个边界），则在列表中包含该分类。接下来，我们使用与输出列相同的方式计算扩展约束列表，但这次是针对查询而不是视图。现在可以说明必须满足的条件。

**范围约束条件**：视图范围约束列表中每个列等价分类，至少有一列出现在查询的扩展范围约束列表中，否则无法从视图计算查询。

> 如果视图有范围约束，查询没有。显然视图没有包含查询所需要的行。

请注意，扩展范围约束列表与查询关联，而不是与视图关联。因此，不能使用视图的扩展约束列表上的 lattice 索引（类似于输出列和分组列上的索引）。然而，我们可以基于一个较弱的条件建立 lattice 索引，这个条件涉及一个缩小的范围约束列表。缩减范围约束列表只包含引用普通的列等价分类中的列，即**不与任何其他列均不等价的列**。

**弱范围约束条件**：除非视图缩小的范围约束列表是查询扩展范围约束列表的子集，否则无法从视图计算查询。

基于此条件构建 lattice 索引时，视图的完整约束列表将被包含并作为节点的键，但子集-超集关系只基于简化的约束列表计算。搜索从根开始，沿着超集指针向上遍历。如果节点通过了弱范围约束条件，我们将沿着其超集指针继续，但仅当节点也通过范围约束时才返回该节点。如果节点未通过弱范围约束条件，则其所有超集节点也将失败，因此无需检查它们。

#### 4.2.6 剩余谓词条件（Residual predicate condition）

> Recall that we treat all predicates that are neither column-equality predicates nor range predicates as residual predicates. The residual subsumption test checks that every residual predicate in the view also exists in the query, again taking into account column equivalences. Our implementation of the test uses a matching function that compares predicates converted to text strings, omitting column references, and then matches column references separately. <u>We associate with each view and query, a residual predicate list containing just the text strings of the residual predicates</u>. Then the following condition must hold.
>
> **Residual predicate condition**: A query cannot be computed from a view unless the view’s residual predicate list is a subset of the query’s residual predicate list. 
>
> For filtering purposes, we then build lattice indexes using the residual predicate lists of the views as keys. Given a query’s residual list, we search for nodes whose key is a subset of the query’s residual list.

回想一下，我们将所有既不是列相等谓词也不是范围谓词的谓词视为剩余谓词。剩余谓词的包含测试检查视图中的剩余谓词也存在于查询中，<u>**再次考虑列等价性**</u>。我们实现的测试使用了匹配函数，比较转换为文本字符串的谓词，省略列引用，然后分别匹配列引用。我们将每个视图和查询相关联，**剩余谓词列表**只包含剩余谓词的文本字符串。那么以下条件必须成立。

**剩余谓词条件**：视图的剩余谓词列表必须是查询剩余谓词列表的子集，否则无法从视图计算查询。

为了进行过滤，我们使用视图的剩余谓词列表作为键来构建 lattice 索引。给定查询的剩余谓词列表，我们搜索其键是查询剩余列表子集的节点。

#### 4.2.7 输出表达式条件（Output expression condition）

> Output expressions are handled in much the same way as residual predicates. We convert the expressions to text strings, omitting column references, and associate with each view and query, <u>an output expression list consisting of the text strings of its output expressions</u>. We can then build lattice indexes based on the following condition.
>
> **Output expression condition**: A query cannot be computed from a view unless its (textual) output expression list is a subset of the view’s (textual) output expression list.
>
> A search then looks for nodes whose key is a superset of <u>the query’s (textual) output expression list</u>. The condition is conservative in the sense that <u>we ignore the possibility of computing an expression from “scratch” using plain columns or precomputed parts</u>. The condition can be weakened to cover this possibility but the details are beyond the scope of this paper.

输出表达式的处理方式与剩余谓词基本相同。我们将表达式转换为文本字符串，省略列引用，让每个视图和查询关联，<u>输出表达式列表由其输出表达式的文本字符串组成</u>。然后，我们可以根据以下条件构建 lattice 索引。

**输出表达式条件**：查询的（文本）输出表达式列表必须是视图的（文本）输出表达式列表的子集，否则无法从视图计算查询。

然后，搜索将查找其键是查询的<u>文本输出表达式列表</u>的超集节点。<u>我们忽略了单纯使用列或预先计算的部分“从头开始”计算表达式的可能性</u>，从这个意义上来说，这个条件比较保守。 可以弱化条件以涵盖这种可能性，但是细节超出了本文的范围。

#### 4.2.8 分组表达式条件（Grouping expression condition）

> Expressions in the grouping clause can be handled in the same way as expressions in the output list. For completeness, we state the condition.
>
> **Grouping expression condition**: An aggregation query cannot be computed from an aggregation view unless its (textual) grouping expression list is a subset of the view’s (textual) grouping expression list.

可以按照处理输出列表中表达式的方式来处理分组子句中的表达式。为了完整起见，我们声明条件。

**分组表达式条件**：聚合查询的文本分组表达式列表必须是聚合视图文本分组表达式列表的子集，否则无法从聚合视图计算聚合查询。

### 4.3 小结（Summary）

> As we saw, each condition above can be the basis for a lattice index subdividing a collection of views. The conditions are independent and can be composed in any order to create a filter tree. For instance, we can create a filter tree where the root node partitions the views based on their hubs and the second level nodes further subdivide each partition according to the views’ extended output column lists. We can stop there or add more levels using any other conditions. Our implementation uses a filter tree with eight levels. From top to bottom, the levels are: <u>**hubs**</u>, source tables, output expressions, output columns, residual constraints, and range constraints. For aggregation views, there are two additional levels: grouping expressions and grouping columns.

如我们所见，上述每个条件都可以作为细分视图 lattice 索引的基础。这些是独立条件，可以按任何顺序组合以创建**过滤树**。例如，可以这样创建，根节点基于视图中心对视图进行分区，第二层节点根据视图的扩展输出列进一步细分每个分区。可以就此停下，也可以使用其他条件添加更多层次。我们使用的是**八层过滤器树**。从上到下，分别是：**<u>集线器</u>**，源表，输出表达式，输出列，剩余谓词约束和范围约束。对于聚合视图，还有两个附加级别：分组表达式和分组列。

