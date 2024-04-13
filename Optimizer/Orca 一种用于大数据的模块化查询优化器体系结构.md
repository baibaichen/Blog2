# Orca: A Modular Query Optimizer Architecture for Big Data

## 4 QUERY OPTIMIZATION

## 4.1 Optimization Workflow

We illustrate query optimization workflow using the following running example:

``` SQL
SELECT T1.a FROM T1, T2
WHERE T1.a = T2.b
ORDER BY T1.a;
```

where the distribution of T1 is Hashed(T1.a) and the distribution of T2 is Hashed(T2.a) (cf. Section 2.1).

Listing 1 shows the representation of the previous query in DXL, where we give the required output columns, sorting columns, data distribution and logical query. Metadata (e.g., tables and operators definitions) are decorated with metadata ids (Mdid’s) to allow requesting further information during optimization. An Mdid is a unique identifier composed of a database system identifier, an object identifier and a version number. For example, ‘0.96.1.0’ refers to GPDB’s integer equality operator with version ‘1.0’. Metadata versions are used to invalidate cached metadata objects that have gone through modifications across queries. We discuss metadata exchange in more detail in Section 5.

The DXL query message is shipped to Orca, where it is parsed and transformed to an in-memory logical expression tree that is copied-in to the Memo. Figure 4 shows the initial contents of the Memo. The logical expression creates three groups for the two tables and the InnerJoin operation. We omit the join condition for brevity. Group 0 is called the *root group* since it corresponds to the root of the logical expression. The dependencies between operators in the logical expression are captured as references between groups. For example, InnerJoin[1,2] refers to Group 1 and Group 2 as children. Optimization takes place as described in the following steps.

**Exploration.** Transformation rules that generate logically equivalent expressions are triggered. For example, a Join Commutativity rule is triggered to generate InnerJoin[2,1] out of InnerJoin[1,2]. Exploration results in adding new group expressions to existing groups and possibly creating new groups. The Memo structure has a built-in duplicate detection mechanism, based on expression topology, to detect and eliminate any duplicate expressions created by different transformations.

**Statistics Derivation.** At the end of exploration, the Memo maintains the complete logical space of the given query. Orca’s statistics derivation mechanism is then triggered to compute statistics for the Memo groups. A statistics object in Orca is mainly a collection of column histograms used to derive estimates for cardinality and data skew. Derivation of statistics takes place on the compact Memo structure to avoid expanding the search space.

> **统计推导**。 在探索结束时，备忘录维护给定查询的完整逻辑空间。 然后触发 Orca 的统计推导机制来计算 Memo 组的统计数据。 Orca 中的统计对象主要是用于导出基数和数据倾斜估计的列直方图的集合。 统计数据的推导发生在紧凑的 Memo 结构上，以避免扩大搜索空间。

In order to derive statistics for a target group, Orca picks the group expression with the highest promise of delivering reliable statistics. Statistics promise computation is expression-specific. For example, an InnerJoin expression with a small number of join conditions is more promising than another equivalent InnerJoin expression with a larger number of join conditions (this situation could arise when generating multiple join orders). The rationale is that the larger the number of join conditions, the higher the chance that estimation errors are propagated and amplified. Computing a confidence score for cardinality estimation is challenging due to the need to aggregate confidence scores across all nodes of a given expression. We are currently exploring several methods to compute confidence scores in the compact Memo structure.

> 为了获得目标群体的统计数据，Orca 选择最有希望提供可靠统计数据的群体表达。 统计承诺计算是特定于表达式的。 例如，具有少量连接条件的 InnerJoin 表达式比另一个具有大量连接条件的等效 InnerJoin 表达式更有前景（在生成多个连接顺序时可能会出现这种情况）。 其基本原理是，连接条件的数量越多，估计误差传播和放大的机会就越大。 由于需要聚合给定表达式的所有节点的置信度分数，计算基数估计的置信度分数具有挑战性。 我们目前正在探索几种方法来计算紧凑的备忘录结构中的置信度分数。

After picking the most promising group expression in the target group, Orca recursively triggers statistics derivation on the child groups of the picked group expression. Finally, the target group’s statistics object is constructed by combining the statistics objects of child groups.

Figure 5 illustrates statistics derivation mechanism for the running example. First, a top-down pass is performed where a parent group expression requests statistics from its child groups. For example, `InnerJoin(T1,T2) on (a=b)` requests histograms on T1.a and T2.b. The requested histograms are loaded on demand from the catalog through the registered MD Provider, parsed into DXL and stored in the MD Cache to service future requests. Next, a bottom-up pass is performed to combine child statistics objects into a parent statistics object. This results in (possibly modified) histograms on columns T1.a and T2.b, since the join condition could impact columns’ histograms.

> - [ ] **Figure 5: Statistics derivation mechanism**

Constructed statistics objects are attached to individual groups where they can be incrementally updated (e.g., by adding new histograms) during optimization. This is crucial to keep the cost of statistics derivation manageable.

**Implementation.** Transformation rules that create physical implementations of logical expressions are triggered. For example, `Get2Scan` rule is triggered to generate physical table Scan out of logical `Get`. Similarly, `InnerJoin2HashJoin` and `InnerJoin2NLJoin` rules are triggered to generate Hash and Nested Loops join implementations.

**Optimization.** In this step, properties are enforced and plan alternatives are costed. Optimization starts by submitting an initial *optimization request* to the Memo’s root group specifying query requirements such as result distribution and sort order. Submitting a request *r* to a group *g* corresponds to requesting the least cost plan satisfying *r* with a root physical operator in *g*.

**优化**。 在此步骤中，将<u>强制执行属性</u>并<u>计算计划替代方案的成本</u>。 优化首先向 Memo 的根组提交初始**优化请求**，指定查询要求，例如结果分布和排序顺序。向组 *g* 提交请求 *r* 对应于用 *g* 中**根物理运算符成本最小的==执行==计划**来满足 *r* 。

For each incoming request, each physical group expression passes corresponding requests to child groups depending on the incoming requirements and operator’s local requirements. During optimization, many identical requests may be submitted to the same group. Orca caches computed requests into a group hash table. An incoming request is computed only if it does not already exist in group hash table. Additionally, each physical group expression maintains a local hash table mapping incoming requests to the corresponding child requests. Local hash tables provide the linkage structure used when extracting a physical plan from the Memo, as we show later in this section.

对于每个传入请求，每个物理组表达式根据传入要求和操作员的本地要求将相应的请求传递给子组。 在优化过程中，可能会向同一个组提交许多相同的请求。 Orca 将计算出的请求缓存到组哈希表中。 仅当组哈希表中尚不存在传入请求时，才会计算传入请求。 此外，每个物理组表达式维护一个本地哈希表，将传入请求映射到相应的子请求。 本地哈希表提供了从备忘录中提取物理计划时使用的链接结构，如本节后面所示。

对于每个传入请求，每个物理组表达式根据传入要求和操作员的本地要求将相应的请求传递给子组。在优化期间，许多相同的请求可以被提交到同一组。Orca将计算出的请求缓存到一个组哈希表中。只有在组哈希表中不存在传入请求时，才会计算该请求。此外，每个物理组表达式都维护一个本地哈希表，将传入请求映射到相应的子请求。本地哈希表提供了从Memo中提取物理计划时使用的链接结构，如我们在本节后面所示。

Figure 6 shows optimization requests in the Memo for the running example. The initial optimization request is *req.* \#*1:* {*Singleton, \<T1.a\>*}, which specifies that query results are required to be gathered to the master based on the order given by T1.a[^1]. We also show group hash tables where each request is associated with the best group expression (GExpr) that satisfies it at the least estimated cost. The black boxes indicate enforcer operators that are plugged in the Memo to deliver sort order and data distribution. Gather operator gathers tuples from all segments to the master. GatherMerge operator gathers sorted data from all segments to the master, while keeping the sort order. Redistribute operator distributes tuples across segments based on the hash value of given argument.

> [^1]: Required properties also include output columns, rewindability, common table expressions and data partitioning. We omit these properties due to space constraints.

Figure 7 shows the optimization of *req.* \#*1* by InnerHashJoin[1,2]. For this request, one of the alternative plans is aligning child distributions based on join condition, so that tuples to be joined are co-located[^2]. This is achieved by requesting Hashed(T1.a) distribution from group 1 and Hashed(T2.b) distribution from group 2. Both groups are requested to deliver Any sort order. After child best plans are found, InnerHashJoin combines child properties to determine the delivered distribution and sort order. Note that the best plan for group 2 needs to hash-distribute T2 on T2.b, since T2 is originally hash-distributed on T2.a, while the best plan for group 1 is a simple Scan, since T1 is already hash-distributed on T1.a.

> [^2]: There can be many other alternatives (e.g., request children to be gathered to the master and perform the join there). Orca allows extending each operator with any number of possible optimization alternatives and cleanly isolates these alternatives through property enforcement framework.

When it is determined that delivered properties do not satisfy the initial requirements, unsatisfied properties have to be *enforced*. Property enforcement in Orca in a flexible framework that allows each operator to define the behavior of enforcing required properties based on the properties delivered by child plans and operator local behavior. For example, an order-preserving NL Join operator may not need to enforce a sort order on top of the join if the order is already delivered by outer child.

Enforcers are added to the group containing the group expression being optimized. Figure 7 shows two possible plans that satisfy *req.* \#*1* through property enforcement. The left plan sorts join results on segments, and then gathermerges sorted results at the master. The right plan gathers join results from segments to the master, and then sorts them. These different alternatives are encoded in the Memo and it is up to the cost model to differentiate their costs.

Finally, the best plan is extracted from the Memo based on the linkage structure given by optimization requests. Figure 6 illustrates plan extraction for the running example. We show the local hash tables of relevant group expressions. Each local hash table maps incoming optimization request to corresponding child optimization requests.

We first look-up the best group expression of *req.* \#*1* in the root group, which leads to GatherMerge operator. The corresponding child request in the local hash table of GatherMerge is *req* \#*3*. The best group expression for *req* \#*3* is Sort. Therefore, we link GatherMerge to Sort. The corresponding child request in the local hash table of Sort is *req* \#*4*. The best group expression for *req* \#*4* is InnerHashJoin[1,2]. We thus link Sort to InnerHashJoin. The same procedure is followed to complete plan extraction leading to the final plan shown in Figure 6.

The extracted plan is serialized in DXL format and shipped to the database system for execution. DXL2Plan translator at the database system translates DXL plan to an executable plan based on the underling query execution framework.
