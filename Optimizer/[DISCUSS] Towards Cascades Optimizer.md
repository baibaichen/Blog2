# [DISCUSS] Towards Cascades Optimizer
## Haisheng Yuan - Sunday, April 19, 2020 11:52:22 AM GMT+8

In the past few months, we have discussed a lot about Cascades style top-down optimization, including on-demand trait derivation/request, rule apply, branch and bound space pruning. Now we think it is time to move towards these targets.

We will separate it into several small issues, and each one can be integrated as a standalone, independent feature, and most importantly, meanwhile keep backward compatibility.

### 1 Top-down trait request
In other words, pass traits requirements from parent nodes to child nodes. The trait requests happens after all the logical transformation rules and physical implementation rules are done, in a top-down manner, driven from root set. e.g.:

```sql
SELECT a, sum(c) FROM
(SELECT * FROM R JOIN S USING (a, b)) t
GROUP BY a;
```

Suppose we have the following plan tree in the **MEMO**, and let's only consider distribution for simplicity, each group represents a RelSet in the MEMO.

```
Group 1: Agg on [a]
Group 2: +-- MergeJoin on [a, b]
Group 3: |--- TableScan R
Group 4: +--- TableScan S
```


| Group No | Operator | Derived Traits | Required Traits |
| ----------- | ------------- | --------------- | --------------- |
| Group 1 | Aggregate | Hash[a] | N/A |
| Group 2 | MergeJoin | Hash[a,b] | Hash[a] |
| Group 3 | TableScan R | None | Hash[a,b] |
| Group 4 | TableScan S | None | Hash[a,b] |

We will add new interface PhysicalNode (or extending RelNode) with methods:

- `Pair<RelTraitSet,List<RelTraitSet>> requireTraits(RelTraitSet required);`
`pair.left` is the current operator's new traitset, `pair.right` is the list of children's required traitset.

- `RelNode passThrough(RelTraitSet required);`
Default implementation will call above method `requireTraits()` and `RelNode.copy()` to create new `RelNode`. Available to be overriden for physical operators to customize the logic.

The planner will call above method on  `MergeJoin` operator to pass the required traits (Hash[a]) to Mergejoin's child operators.

We will get a new `MergeJoin`:

```
MergeJoin hash[a]
|---- TableScan R hash[a] (RelSubset)
+---- TableScan S hash[a] (RelSubset)
```

Now the MEMO group looks like:
| Group No | Operator | Derived Traits | Required Traits |
| ---------- | -------- ----- | -------------------- | --------------------- |
| Group1 | Aggregate | Hash[a] | N/A |
| Group2 | MergeJoin | Hash[a,b], Hash[a]| Hash[a] |
| Group3 | TableScan R | None | Hash[a,b], Hash[a] |
| Group4 | TableScan S | None | Hash[a,b], Hash[a] |

Calcite user may choose to ignore / not implement the interface to keep the original behavior. Each physical operator, according to its own logic, decides whether `passThrough()` should pass traits down or not by returning:
- a non-null RelNode, which means it can pass down
- null object, which means can't pass down

### 2. Provide option to disable AbstractConverter
Once the plan can request traits in top-down way in the framework, many system don't need `AbstractConverter` anymore, since it is just a intermediate operator to generate physical sort / exchange. For those, we can provide option to disable `AbstractConverter`, generate physical enforcer directly by adding a method to interface Convention:
- `RelNode enforce(RelNode node, RelTraitSet traits);`

The default implementation may just calling `changeTraitsUsingConverters()`, but people may choose to override it if the system has special needs, like several traits must implement together, or the position of collation in `RelTraitSet` is before distribution.

###  3. Top-down driven, on-demand rule apply
For every `RelNode` in a RelSet, rule is matched and applied sequentially, newly generated `RelNode`s are added to the end of `RelNode` list in the `RelSet` waiting for rule apply. `RuleQueue` and `DeferringRuleCall` is not needed anymore. This will make space pruning and rule mutual exclusivity check possible.

There are 3 stages for each `RelSet`:
a). **Exploration**: logical transformation, yields logical nodes
b). **Implementation**: physical transformation, yields physical nodes
c). **Optimization**: trait request, enforcement

The general process looks like:
- Optimize `RelSet` X:
```
implement RelSet X
for each physical relnode in RelSet X:
// pass down trait requests to child RelSets
for each child RelSet Y of current relnode:
optimize RelSet Y
```

- Implement `RelSet` X:
```
if X has been implemented:
  return
explore RelSet X
for each relnode in RelSet X:
apply physical rules
```

- explore RelSet X:
```
if X has been explored
  return
for each relnode in RelSet X:
// ensure each child RelSet of current relnode is explored
for each child RelSet Y of current relnode:
explore RelSet Y
apply logical rules on current relnode
```

Basically it is a state machine with several states: Initialized, Explored, Exploring, Implemented, Implementing, Optimized, Optimizing and several transition methods: exploreRelSet, exploreRelNode, implementRelSet, implementRelNode, optimizeRelSet, optimizeRelNode...

To achieve this, we need to mark the rules either logical rule or physical rule.
To keep backward compatibility, all the un-marked rules will be treated as logical rules, except rules that uses `AbstractConverter` as rule operand, these rules still need to applied top-down, or random order.

###  4. On-demand, bottom-up trait derivation
> 按需、自下而上的特征推导

It is called bottom-up, but actually driven by top-down, happens same time as top-down trait request, in optimization stage mentioned above. Many Calcite based bigdata system only propagate traits on Project and Filter by writing rules, which is very limited. In fact, we can extend trait propagation/derivation to all the operators, without rules, by adding interface `PhysicalNode` (or extending RelNode) with method:
- `RelNode derive(RelTraitSet traits, int childId);`

Given the following plan (only consider distribution for simplicity):

```
Agg [a,b]
+-- MergeJoin [a]
|---- TableScan R
+--- TableScan S
```

`Hash[a]` won't satisfy `Hash[a,b`] without special treatment, because there isn't a mechanism to coordinate traits between children.

Now we call derive method on Agg [a,b] node, derive(Hash[a], 0), we get the new node:

```
Agg [a]
+-- MergeJoin [a] (RelSubset)
```

We will provide different matching type, so each operator can specify what kind of matching type it requires its children:
- `MatchType getMatchType(RelTrait trait, int childId);`

a) Exact: Hash[a,b] exact match Hash[a,b], aka, satisfy
b) Partial: Hash[a] partial match Hash[a,b]
c) Permuted: Sort[a,b,c] permuted match Sort[c,b,a]

In addition, optimization order is provided for each opertor to specify:
a) left to right
b) right to left
c) both

For example, for query `SELECT * FROM R join S on R.a=S.a and R.b=S.b and R.c=S.c`:
Suppose R is distributed by a,b, and S is distributed by c.

```
MergeJoin [a,b,c]
|--- TableScan R [a,b]
+-- TableScan S [c]
```

a) left to right, call derive(Hash[a,b], 0), we get MergeJoin [a,b]
b) right to left, call derive(Hash[c], 1), we get MergeJoin [c], most likely a bad plan
c) both, get above 2 plans.

For system that doesn't have a fine-tuned stats and cost model, it may not be able to make a right decision based purely on cost. Probably we need to provide the MergeJoin with both children's derived traitset list.
- `List<RelNode> derive(List<List<RelTraitSet>>);`

Of course, all above methods are optional to implement for those who doesn't need this feature.

### 5. Branch and Bound Space Pruning
After we implement on-demand, top-down trait enforcement and rule-apply, we can pass the cost limit at the time of passing down required traits, as described in the classical Cascades paper. Right now, Calcite doesn't provide group level logical properties, including stats info, each operator in the same group has its own logical property and the stats may vary, so we can only do limited space pruning for trait enforcement, still good. But if we agree to add option to share group level stats between relnodes in a RelSet, we will be able to do more aggresive space pruning, which will help boost the performance of join reorder planning.


With all that being said, how do we move forward?

There are 2 ways:
a) Modify on current VolcanoPlanner.
Pros: code reuse, existing numerous test cases and infrastructure, fast integration
Cons: changing code always brings risk

b) Add a new XXXXPlanner
Pros: no risk, no tech debt, no need to worry about backward compatability
Cons: separate test cases for new planner, one more planner to maintain

We'd like to hear the community's thoughts and advices.

Thanks.

------------

RelSubset 是 Apache Calcite 中描述具有相同物理属性的关系表达式集合的概念。RelSubset 能够帮助优化器找到最佳的查询计划，主要体现在以下几个方面：

1. 表示不同的执行策略：每个 RelSubset 代表了一个查询执行的可能策略。例如，一个查询可能可以通过哈希连接或者排序合并连接来执行。这些都是同一查询的不同执行策略，它们会在同一个 RelSet 中以不同的 RelSubset 形式存在。
2. 提供成本比较的基础：对于每一个 RelSubset，优化器会按照一定的模型计算其执行成本，然后在所有的 RelSubset 中选择成本最低的一个。因此，RelSubset 为优化器提供了一个成本评估和比较的基础。
3. ==生成更多的执行策略：在查询优化的过程中，优化器还会通过转换规则（Transformation Rules）生成新的 RelSubset，进一步寻找可能的最优解==。
4. 加快查询优化过程：由于 RelSubset 中的关系表达式是物理相等的，所以能避免在物理优化阶段进行无意义的比较和计算。这一点对于加快查询优化过程和提高优化效率是非常有帮助的。

通过以上方式，RelSubset 可以帮助优化器更好地找到最佳的查询计划。
