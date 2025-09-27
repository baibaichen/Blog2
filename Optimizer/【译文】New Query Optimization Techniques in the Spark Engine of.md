# New Query Optimization Techniques in the Spark Engine of Azure Synapse


## 1 引言

现代查询编译器依赖于逻辑 SQL 层面的查询优化技术与底层代码生成技术的结合，以生成高效的查询可执行程序。在大数据场景下，它们生成包含多个阶段的执行计划，使得每个阶段都可以跨多台机器以数据并行的方式运行。同一阶段内的算子进一步被分组到代码生成块（code-generation blocks）中，这些块被编译，使得数据仅在块边界处物化 [23]。SPARK [6] 是一种基于此类编译方法的流行大数据系统。

正如预期的那样，在这些环境中，<u>有状态算子（即在阶段或代码生成边界处物化数据的算子）主导了执行成本</u>。特别是，我们发现 exchange，hash aggregate 和 sort 是 SPARK 中开销最大的三个算子。exchange 算子用于在**阶段**之间传输数据，它要求在每个阶段结束时将数据物化到磁盘，并通过网络 shuffle 到下一阶段的任务中。**而 hash aggregate 和 sort 是在阶段内物化数据的算子，因此它们划分了代码生成块。这两个算子都在内存中维护状态，必要时会溢出到磁盘**。

本文聚焦于一组降低这些算子开销的技术。这些优化可分为三类。

**Exchange placement**。首先，我们引入一种新算法，用于确定 exchange 算子应放置的位置以及每个 exchange 应使用的 exchange key。exchange 算子具有双重目的：它们重新分区数据，以满足基于 key 的算子（如 group-by、join 和 window 函数）的需求，从而使其能够以数据并行的方式运行；此外，exchange 使得不同子树之间的计算可以复用。如果以<u>两个不同 exchange 为根的子树</u>执行完全相同的计算，则可以只执行一次该计算，在**源阶段**以分区方式持久化输出，并多次消费它。

现有系统 [14,27,29,35] 在确定 exchange 放置位置时并未考虑复用机会。我们发现 exchange 放置与 exchange 复用之间存在若干冲突，导致整体计划次优。为解决此问题，我们提出一种新算法，在确定 exchange 放置时考虑 exchange 复用的可能性，从而生成具有有益权衡的候选计划（参见第 2.2.1 节中的示例）。我们对这些备选方案进行代价估算，并选择代价最低的计划。

为高效实现该算法，我们引入一种称为 **plan-marking** 的新实现机制，使其能够在树的不同部分之间进行全局推理。我们的 exchange placement 算法利用 plan-marking 将相同的子树标记为相同的标识符，以指示复用机会。

**Partial push-down**。其次，我们将 partial push-down 技术引入大数据查询优化器。这些技术并不替代某个算子，**而是派生出一个辅助算子**，可以将其下推到树中。我们扩展了 SPARK 优化器，以支持三种不同的 partial push-down 技术，即 partial aggregation、semi-join push-down 和 bit-vector filtering。

我们的 partial aggregate push-down 机制基于已知技术，将 group-by 部分下推到 join 之下 [10, 20, 22, 30]。我们将这些技术扩展，不仅将 partial aggregates 下推到 select 和 join 之下（如现有文献所提），还扩展到 unions、project 和 expand [2]。当前的 SPARK 优化器仅在物理计划阶段，在 group-by 之前直接插入 partial aggregate。相比之下，我们通过引入一个新的逻辑算子来表示 partial aggregates，并设计新的规则逐步将其下推，从而实现更激进的下推。此外，我们提出新的重写规则，从其他算子（semi-join 和 intersect）中派生 partial aggregates。

我们还提出了一种新的 partial semi-join push-down 规则，该规则将根为 semi-join 的树中的 inner-join 转换为 semi-join，而不改变根节点（参见第 2.2.2 节中的示例）。我们证明（见第 7.3 节），与传统的单机数据库（scale-up）环境相比，partial aggregation 和 semi-join push-down 在大数据（scale-out）环境中具有更大的影响。

最后，我们将 bit-vector filters 的下推集成到 SPARK 优化器中。虽然 bit-vector filtering 已被广泛研究 [11-13,15]，但我们提出了一种基于 plan-marking 的高效实现，以避免在大数据环境中不必要的物化。此外，我们依赖 SPARK 的执行策略，从任务（tasks）开始并行构建 filters，最后在执行器（executors）之间合并。

Partial push-down 会带来额外计算，但可能节省 exchange。因此，我们以基于代价的方式引入这些优化。==我们的代价函数以新颖方式结合列级统计信息与分区属性==，判断这些 partial push-down 是否可能带来收益。

**Peephole optimizations**。第三，我们提出一组 peephole 优化，以改进有状态算子的实现。例如，我们优化了多列排序的 key 顺序。SPARK 的排序器在字节空间比较 key，并延迟反序列化数据。我们的优化通过选择导致更少反序列化和比较次数的顺序来降低成本。注意，虽然 sort 对顺序敏感，但 (sort-merge) join 等算子仅要求两侧 key 保持一致顺序。此类优化需要全局推理，我们的实现再次依赖 plan-marking 来强制一致排序。

> [!CAUTION]
>
> ![](http://darwin-controller-pro.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_3.jpg?Expires=1759036560&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=or%2Fs4svGE4MFf81pdP6ul1kwKgQ%3D) 图1：AZURE SYNAPSE 的 SPARK ENGINE 相对于 Apache Spark 最新版本的优化带来的加速比
>

**性能收益总结**。我们在 AZURE SYNAPSE 的 SPARK ENGINE（简称 SYNAPSE SPARK）中实现了所有这些优化，并与 Apache Spark 最新版本 Spark 3.0.1 进行比较（本文中提到 SPARK 时均隐含指代此发行版）。图1展示了在 TPCDS 标准数据分析基准（1TB 规模因子）的所有查询中，各项优化带来的加速效果。可以看出，这些优化共同使基准测试套件提速 1.8 倍。其中，exchange placement 带来 27% 的加速，partial push-down 技术共同带来 40% 的加速，其余收益来自我们的 peephole 优化。

**优化的适用性**。SYNAPSE SPARK 是一个源自 Apache Spark 的横向扩展（scale-out）大数据系统。我们提出的 peephole 优化特定于基于 Spark 的系统，而其他优化则更具普适性。exchange placement 算法适用于所有需要 exchange 算子的大数据系统 [14, 27, 29, 35]。partial push-down 技术不仅适用于 scale-out 系统，也适用于 scale-up 单机数据库。然而，我们的实证评估揭示了一个有趣发现：bit-vector filtering 在 scale-up 环境中带来显著收益（因其在扫描后立即过滤数据），但 partial-aggregation 和 semi-join push-down 在 scale-up 环境中收益较小。我们观察到，它们仅在减少 exchange 数据量时才带来收益。

总之，本文做出了以下核心贡献：

- 我们刻画了 SPARK 中的性能瓶颈。先前的分析 [24] 是在 Spark 引入代码生成之前进行的，已过时。
- 我们提出一种新的 exchange placement 算法，优于现有技术水平，显著减少了评估查询所需的 exchange 数量。
- 我们扩展了现有文献中的思想，为 partial aggregation 提供了全面支持。我们增加了新规则，将其下推到以往未考虑的算子之下，并为大数据系统提出了一个结合分区信息的专用代价模型。
- 我们提出一种新颖的 semi-join push-down 技术，发现其对 scale-out 大数据系统的好处远大于对 scale-up 数据库（partial aggregation 类似）。
- 我们提出一组 peephole 优化，显著提升了 SPARK 排序实现的性能。
- 所有这些优化均已实现在 SYNAPSE SPARK 中，这是一个可供通用使用的生产系统。我们证明了这些优化带来了显著的性能提升。

- [ ] 图 2

## 2 动机与示例

我们首先对 SPARK 进行性能特征分析。

### 2.1 工作负载特征分析

我们增强了 SPARK 的监控功能，以测量每个任务在各个算子上花费的时间[^1]。图 2 展示了 TPCDS 中最耗时的 20 个查询（1TB 规模因子）中各算子所花费的时间。对每个查询，图中显示了优化前后的耗时分解，本节我们重点关注优化前（左侧柱状图）的成本。我们得出以下观察结果：

- exchange、hash-aggregate 和 sort 是开销最大的三个算子。在一半的查询中，它们占总任务时间的 80%；在另外四分之一的查询中，占比为 50-80%。
- exchange 的开销始终较高，在除少数（5%）以 scan 为主的查询外，其成本占比稳定在 20-40%。
- sort 和 hash-aggregate 的开销几乎相当，在大多数查询中两者合计占成本的 20-50%。
- scan 和 join 是另外两个重要算子，平均开销低得多。然而，在特定查询中（如 Q88 和 Q95），它们分别是开销最大的算子。

[^1]:当前 SPARK 仅报告每个代码生成块（code generation block）的指标，而非每个算子。

表1：SQL 算子使用的符号如下所示。我们使用 T、T1、T2、T3 作为表名，a、b、c、d、e 作为列名。列名后加上其来源表的数字下标。例如 $b_2$ 来自表 T2。union 会重命名列，我们确保输入具有相同的列名但后缀不同，并为输出分配新的后缀。实线表示 exchange，虚线连接同一阶段内的算子。

| 算子 | 符号 |
|----------|----------------|
| Select | $\sigma_{pred}(T)$ |
| Project | $\Pi_{expr}(T)$ |
| Group-by | $\Gamma_{keys, [aggs(exprs)]}(T_{1})$ |
| Inner Join | $\bowtie_{a_1=a_2 \wedge b_1=b_2 \ldots}$ |
| Left/right Semi Join | $\ltimes / \rtimes_{a_1=a_2 \wedge b_1=b_2 \ldots}$ |
| Union (all) | $\bigcup(T_{1},T_{2} \cdots T_{n})$ |
| Intersect (distinct) | $\bigcap(T_{1},T_{2})$ |
| Partial aggregate | $\gamma_{keys, [aggs(exprs)]}(T)$ |

### 2.2 优化示例

接下来，我们通过 TPCDS 中的示例说明所提出的优化。表 1 描述了我们用于表示查询的符号。

#### 2.2.1 Exchange placement

考虑 Q23 的一个变体（为便于说明，我们仅展示 4 个子树中的 2 个，并修改了一些算子），如图 3 所示。树中节点表示算子，边上的标注表示其所需的分区属性。若存在多种可能，边会标注一组分区选项，满足任一即可。例如，边 $e_4$ 要求按 $a_1,b_1$ 列对、或仅 $a_1$、或仅 $b_1$ 进行分区。这些均为有效选项，因为基于 key 的算子（join、group-by 等）只要输入在 key 的某个子集上分区，即可并行执行。注意，查询执行了两次 $T_1 \bowtie T_2$ 连接，但父算子不同。

一个 exchange 算子以一组列（和一个分区计数）作为输入，并按这些列对数据进行分区。图 4 显示了在此查询中放置 exchanges 的两种方式。左侧的执行计划由最先进的算法生成，目标是引入最少的 exchange 算子，以满足所有算子的分区要求。为此，算法会为各边选择分区键，以便能够利用树中下游已存在的 exchange 来满足这些分区要求。例如，如果我们在 $e_8$ 选择==分区选项 $a_1$==，它可以通过 $e_6$ 处先前的 exchange on $a_1$ 来满足（我们使用简写 $e_6←a_1$ 来表示 exchange 分配）。类似地，如果选择 $e_4$ 处的分区选项 $a_1$，它可以利用 $e_1←a_1$。我们将这种谨慎选择分区选项以使用先前 exchange 的做法称为 ==overlapping an exchange==。这样的分配将导致六个 exchanges（在除 $e_8$ 和 $e_4$ 外的所有位置）。对于此示例，上述分配在满足所有算子分区要求所需的 exchanges 数量上是最小的。然后，exchange reuse 规则会将此列表修剪为4个（图4(a)显示了最终计划）。注意，在此计划中，$T_1$ 和 $T_2$ 之间的 join 被执行了两次，并且 $T_1$ 和 $T_2$ 之后的 exchanges 被重用，每个都被两个消费者阶段读取。
> [!CAUTION]
> | ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_5.jpg?Expires=1759036561&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=dQbm2%2BWV%2F4yame5ItPNruhc3TeQ%3D) | ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_8.jpg?Expires=1759036561&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=8qzCYQapPr5RpNfZMWyJvTFJ%2BJU%3D) |
> | ------------------------------------------------------------ | ------------------------------------------------------------ |
> | 图3：具有多个分区选项的查询。每条边都标注了一组分区选项，其中任一选项都能满足父算子的要求。 | 图4：图 3 查询中的 exchange placement。最大化重叠会导致次优计划。结合重叠与复用信息可得到更优计划。 |
>

然而，如图 4(b) 所示，存在另一种分配方式，其 exchange 重叠较少但效果更好。考虑仅重叠 exchange $e_3←b_3$（与 $e_5$）的计划。这将导致七次 exchange 分配（在复用前）。此处我们故意在 $e_8$ 选择分区选项 $b_1$，这从 exchange 重叠角度看显然是次优的。尽管如此，在应用 exchange 复用规则后，我们得到了更优的计划（如图4(b)所示）。此计划直接在 $e_8$ 复用 exchange $e_4←b_1$（从而复用 join 的结果），生成一个包含 4 个 exchange 的计划。由于这是更深层次的 exchange 复用，该计划不仅避免了 $e_6$、$e_7$ 和 $e_8$ 处的 exchange，还避免了第二次执行 join。此外，注意此计划还可能减少 I/O，因为仅复用一个 exchange 而非两个（2次读取而非4次）。因此，总体上我们预期此计划更优。

总之，将 exchange 复用机会与 exchange 重叠相结合可产生更优计划，这正是我们提出的 exchange placement 算法的重点。

#### 2.2.2 Partial pushdown 优化
> [!CAUTION]
>
> ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_10.jpg?Expires=1759036561&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=Q6m9Pw5kSSk8jHrTDXhzdoR6IDI%3D) 
>
> 图5：图中展示了当前 Spark 中的 partial aggregation 优化、文献中提出的 group-by 下推以及本文的提议。

接下来，我们演示 partial aggregate push-down 和 semi-join push-down 的示例。图5展示了一个基本查询，该查询在列 b 上执行 join，然后在另一个 key a 上进行聚合。图中还展示了此类查询的三种现有优化。这些优化在下方框中描述。

> [!NOTE]
>
> **先前关于聚合部分下推的工作**
>
> 第一种优化针对大数据场景，旨在减少 exchange 的数据量。注意，图5（左下）中的未优化计划需要 3 次 exchange（在 $b_1$、$b_2$ 和 $a_1$ 上），由粗线标出。此优化（右下）执行 partial aggregation，在 exchange 前额外进行一次聚合，即在数据按分组 key 分区前就进行。这种 partial aggregation 会减少 exchange 的数据量，因为它在最终聚合前的每个阶段任务中，每组仅生成一行。
>
> 第二种优化是将整个聚合下推到 join 之下 [10, 20, 30]。此优化计划（如左上所示）在 join 的输入上执行聚合，聚合的 key 集包含该输入处的 join key 和聚合 key。先前文献描述了此类重写的安全条件[^注2]。它主张以基于代价的方式进行此类下推，以确保 group-by 确实减少了 join 的数据量。注意，在大数据场景中，此优化本身不会节省 exchange，因为 group-by 和 join 很可能由 exchange placement 规则置于同一阶段。
>
> 第三种优化 [22] 最接近我们的提议，它结合了上述两种优化，生成右上所示的单机计划，其中在 join 前执行 partial aggregation 而非 full aggregation。由于在单机上所有中间数据保留在内存中，他们还提出对此类树的特殊实现，即在后续 join 的输入阶段执行 partial aggregation。这种实现在大数据场景中不可行，因为数据在 exchange 处物化。

[22] 中的提议专门针对将聚合下推到 join 之下。我们将其扩展到所有其他 SQL 算子，并通过在查询优化期间为 partial aggregation 提供一等支持来实现。我们引入一个新的逻辑算子（$\gamma$）表示 partial aggregates，并在优化器中引入新规则来转换它们。图5右上所示的分布式计划需要两次重写：第一次在 join 上方引入 partial aggregation 算子（$\gamma$），第二次将其下推到 join 之下。注意，在我们的优化计划中，下推不会引入额外的 exchange。在大数据场景中，此优化引入了一个有趣的权衡：它增加了 hash-aggregate 的数量，但减少了 exchange 的数据量。我们提出一种代价评估机制来判断该优化是否有益。

接下来，我们展示从 group-by 以外的算子派生 partial aggregates 并将其下推到标准 SQL 算子之下的示例。图6(a) 展示了一个标准查询模板，在执行聚合前进行一系列 join 和（可选）union。如图所示，我们可以将此类查询中的 partial aggregates 一路下推到叶子节点。此类下推之所以可能，是因为我们将 partial aggregates 作为一等逻辑算子添加，并逐个算子下推它们。注意，图中显示了 partial aggregates 的所有候选位置，并非所有位置都能减少 exchange 的数据量。事实上，某些下推（灰色/浅色显示）根本不会影响 exchange。我们的代价机制会消除此类选项。图6(b) 展示了包含 semi-join 查询中的 partial push-down 机会。left semi-join 仅检查左表中的行在右表中是否有匹配，因此只需要右表中在 join 谓词中引用的列的唯一值。这导致两种优化：首先，我们可以引入 partial aggregates（见图）以消除重复项；其次，右子树中的其他 inner join 可转换为 semi-joins。这是另一个先前未探索的 partial push-down 示例，它在不修改父 semi-join 的情况下将 inner-joins 转换为 semi-joins。

> [!CAUTION]
>
> ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_12.jpg?Expires=1759036562&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=CR94PgTTWPndhp%2FU%2FDstYRHpfzg%3D) 
>
> 图6：partial push-down 示例。左图：partial-agg 下推到 union 之下，如 Q11。右图：semi-join push-down 及从 semi-join 派生 partial-agg，如 Q95

## 3 EXCHANGE PLACEMENT

本节描述了我们在 SYNAPSE SPARK 中使用的 exchange 放置算法。图 7 概述了现有系统的工作方式以及我们的提议。大致上存在两种类型的系统。ScoPE [35] 使用基于代价的探索来选择不同的 exchange 放置选项 [34]。正如我们后面所描述的，这种探索允许它最大程度地 overlapping exchanges。另一方面，像 SPARK 这样的系统不支持探索，而是仅维护一个单独的计划。它们自底向上遍历计划，并在执行局部 overlap 检查后引入 exchanges。如图所示，两个系统都在 exchange 放置之后分别应用 exchange reuse 规则。在这两个系统中，它转换最终选定的计划而无需探索。

> [!CAUTION]
>
>
> ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_13.jpg?Expires=1759036562&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=8tg8BijDWrvWAhv1OtLd64ULNJ8%3D) 
>
> Figure 7: Exchange placement overview

在 SYNAPSE SPARK 中，我们以基于成本的方式执行 exchange placement，同时考虑 exchange overlap 和 exchange reuse 机会。现在，基于成本的探索可能很昂贵，ScoPE 使用了较大的优化时间预算（几分钟）。另一方面，在 SYNAPSE SPARK 中，我们对优化器时间施加了严格的约束（以秒为单位）以满足客户期望。为了实现这一目标，我们改进了具有大探索空间的最先进算法（第3.1节）。我们只在存在多种重叠 exchanges 的方式或 exchange overlap 与 exchange reuse 冲突时，才通过探索多个选项来实现这一点（第3.2节）。最后，为了确定冲突的选项，我们需要尽早识别 exchange reuse 的潜力。我们为此采用了 plan marking（第3.3节）。

### 3.1 基于探索的 exchange 放置

让我们首先考察用于 exchange 放置的==最先进算法== [34]。算法 1 展示了用于计算计划中每个算子的==有趣分区选项==的递归例程的伪代码。为了便于说明，我们假设该计划仅由基于 key 的算子组成（实际实现当然会处理所有 SQL 算子）。首先，我们定义 \( \mathcal{P}'(\mathrm{X}) = \mathcal{P}(\mathrm{X}) \setminus \varnothing \)，其中 \( \mathcal{P}(\mathrm{X}) \) 是集合 \( \mathrm{X} \) 的幂集[^注3]。当我们在本节提到幂集时，指的是 \( \mathcal{P}' \)。该方法中，==有趣的分区选项==包含算子所有 key 的所有可能组合，即 \( \mathcal{P}'(\mathrm{plan.keys}) \)。如图 3 所示，以 \( \{a_{1},b_{1}\} \) 作为 key 的 join，其 \( i\mathrm{keysSet} \) 将包含 \( \{a_{1}|b_{1}|a_{1},b_{1}\} \)。

$$
\begin{aligned}
&\text{Algorithm 1: DetermineInterestingPartitionKeysDefault} \\
&\text{Require: Physical Plan } plan \\
&1:\text{ for all child } \in plan.children \text{ do} \\
&2：\quad \text{ DetermineInterestingPartitionKeysDefault(child)} \\
&3: plan.iKeysSet \leftarrow \mathcal{P}'(plan.keys) \\
&\text{end for}
\end{aligned}
$$

接下来，使用标准的计划空间探索算法探索具有不同分区 key 组合的计划。算法 2 展示了在 Synapse Spark  和 Scope 中使用的基于动态规划的探索算法的简化版本[^2]。该算法在每个节点上最多跟踪 $k$ 个计划。我们将在本节末尾讨论 $k$ 的选择方式。
$$
\begin{aligned}
&\text{\textbf{Algorithm 2 OptimizePlan}} \\
&\text{\textbf{Require:} Physical Plan } \mathbf{plan} \\
&\text{\textbf{Require:} Required Distribution } \mathbf{reqdDistr} \\
1&: \text{If the plan has } \mathbf{top\ k\ plans} \text{ computed for } \mathbf{reqdDistr} \text{ already, fetch them}\\ 
&\quad \text{from the map;} \\
2&: \mathbf{for\ all} \ partnKeys \in plan.iKeysSet \ \mathbf{do} \\
3&: \quad childrenTopPlans \leftarrow \emptyset \quad \blacktriangleright \text{ Compute top K plans for children} \\
4&: \quad \mathbf{for\ all} \ child \in plan.children \ \mathbf{do} \\
5&: \qquad childTopPlans \leftarrow \text{OptimizePlan}(child, \text{Distr}(partnKeys)) \\
6&: \qquad childrenTopPlans.\text{add}(childTopPlans) \\
7&: \quad \mathbf{for\ all} \ childrenCombo \in \text{allCombinations}(childrenTopPlans) \ \mathbf{do} \\
8&: \qquad newPlan \leftarrow plan.\text{updateChildren}(childrenCombo) \\
9&: \qquad optPlan \leftarrow \text{EnforceExchange}(newPlan, reqdDistr) \\
10&: \qquad plan.\text{updateTopKPlans}(reqdDistr, (optPlan, \text{getCost}(optPlan))) \\
11&: \mathbf{return} \ plan.\text{getTopKPlans}(reqdDistr)
\end{aligned}
$$
在第 2 行中，对于该算子的每个==有趣分区 key \( \mathrm{partnKeys} \)==，首先计算其子节点的最佳计划（最多 $k$ 个）。接着，将这些子计划组合生成当前算子的候选计划。例如，若某计划有两个子节点 \( C_{1} \)（含 2 个候选）和 \( C_{2} \)（含 3 个候选），则将产生 6 种组合——子节点组合为 \( \{\{C_{1}^{1},C_{2}^{1}\},\{C_{1}^{1},C_{2}^{2}\},\{C_{1}^{1},C_{2}^{3}\},\{C_{1}^{2},C_{2}^{1}\},\{C_{1}^{2},C_{2}^{2}\},\{C_{1}^{2},C_{2}^{3}\}\} \)。然后遍历这些候选计划，通过 `EnforceExchange`（第 9 行）插入 exchange，并选择成本最低的前 $k$ 个计划。`EnforceExchange` 仅在子节点分区不满足父节点的==分区选项==时插入 exchange，这一点在 [34] 中有更详细的解释。具体来说，它会检查 exchange overlap，即子节点分区是否是正在探索的==分区选项==的（非空）子集。

> [^2]: 两个系统使用的算法在具体细节上存在若干差异。我们在此重点关注与 exchange 放置相关的方面。

该算法在枚举==有趣分区选项==方面是完备的。ScoPE 是现有使用该算法的系统，能够承担使用较大的 $k$ 值（因为它有较大的时间预算）。这确保了它能够生成像图4(a)中所示的最大重叠计划。

### 3.2 通过 overlap 推理剪枝搜索空间


$$
\begin{aligned}
&\text{\textbf{Algorithm 3 DetermineInterestingPartitionKeys}} \\
&\text{\textbf{Require:} Physical Plan } \mathbf{plan} \\
1&: \mathbf{for\ all}\ child \in plan.children\ \mathbf{do} \\
2&: \quad \text{DetermineInterestingPartitionKeys}(child) \\
3&: iKeys, iKeysSet \leftarrow \emptyset \\
4&: \blacktriangleright\text{Pruning } plan.keys \\
5&: iKeys.addAll(plan.keys \cap parent.keys) \\
6&: \mathbf{for\ all}\ child \in plan.children\ \mathbf{do} \\
7&: \qquad iKeys.addAll(plan.keys \cap child.keys) \\
8&: \blacktriangleright\text{Pruning the power set of above} \\
9&: iKeysSet.checkAndAddAll(\mathcal{P}'(iKeys) \cap \mathcal{P}'(parent.keys)) \\
10&: \mathbf{for\ all}\ child \in plan.children\ \mathbf{do} \\
11&: \quad iKeysSet.checkAndAddAll(\mathcal{P}'(iKeys) \cap \mathcal{P}'(child.keys)) \\
12&: \blacktriangleright \text{Add additional keys if child is a reusable sub-tree} \\
13&: \mathbf{for\ all}\ child \in plan.children\ \mathbf{do} \\
14&: \quad \mathbf{if}\ child.marker \in reuseMap\ \mathbf{then} \\
15&: \qquad cmmnParntKeysForReuse \leftarrow \cap reuseMap(child.marker) \\
16&: \qquad iKeysSet.addAll(cmmnParntKeysForReuse) \\
17&: \mathbf{if}\ iKeysSet \neq \emptyset\ \mathbf{then} \\
18&: \quad plan.iKeysSet \leftarrow iKeysSet \\
19&: \mathbf{else} \\
20&: \quad plan.iKeysSet \leftarrow \{plan.keys\}
\end{aligned}
$$

算法 3 描述了我们的实现，通过减少分区选项（第5-7行）来剪枝探索空间。我们不再依赖 `EnforceExchange` 来检测 overlap 机会，而是分两个阶段对==选项==进行剪枝。首先，我们计算算子的各个分区 key ，这些 key 与其父节点或子节点的 key 有重叠。我们将它们全部[^3]添加到集合 `iKeys` 中。

[^3]: X.addAll(Y) 表示将集合 Y 中的所有元素添加到集合 X 中。X.add(Y) 表示将集合 Y 作为一个整体添加到集合 X 中。

在第二阶段，我们通过将 `iKeys` 的幂集与父节点 key 的幂集以及子节点 key 的幂集取交集，得到所有 overlap 的==选项==。我们使用 `checkAndAddAll` 方法，仅将这些选项插入到 `iKeySet` 中。该方法在将某个集合添加为==分区选项==之前，会检查该集合的不同值数量是否超过所需的分区数（一个作业参数）。表 2 展示了如何添加所有 overlap 选项。第三行（标记为 Total）显示了父节点（$P1$）和子节点（$ST1$）之间有 3 种不同的 overlap 方式，这些都被添加为==选项==。==部分重叠行==（Partial，代表图 3 中的示例）仅添加了一个==选项==。这已足以生成像图 4(a) 所示的最大==重叠计划==。最后，如果基于 overlap 没有添加任何选项（表中的 None 行），则我们只考虑一个==选项==，即完整的 key 集合（第 20 行）。当算子涉及多个列作为 key 时（如 TPCDS 查询中常见的情况），这种剪枝显著减少了搜索空间。

-----
## 6 小小优化

本节重点介绍我们在 SYNAPSE SPARK 中实现的一些小小优化。在本文中，我们专注于排序优化，因为它们带来了显著的收益。由于篇幅限制，本文未包含其他优化（在报告结果时也排除了它们）。

Spark 采用的排序算法是插入排序的一种变体，称为 Tim sort [5]。该算法的核心步骤（反复执行）是将新行插入到先前已排序的数组中。Spark 中的排序实现采用了延迟反序列化。它首先尝试基于序列化行的（4字节）固定宽度前缀进行排序。仅在发生冲突时，即排序数组中存在另一个具有相同前缀的行，它才会反序列化该行并执行比较。我们对排序实现应用了两种小小优化，在 TPCDS 中一些最昂贵的查询中显著节省了 10 倍的比较次数。

## 6.1 排序键重排序（Sort key re-ordering）

我们调整**排序键（sort keys）**的顺序，让高基数（high-cardinality）的列排在低基数列之前。这降低了冲突的概率。减少冲突可以降低数据反序列化的次数以及需要执行的比较次数。

请注意，排序对顺序敏感，调整排列键可能会产生不同的输出。然而，当排序是为了满足特定算子（如 sort-merge-join）的要求时，只要保证算子各个输入之间具有一致的排序顺序，就是安全的。我们依赖 plan-marking 来强制执行这种一致性约束。

> [!CAUTION]
>
> ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_27.jpg?Expires=1759036563&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=9cdExBgMmzh5X%2B6f%2BAXRCMFrlbg%3D) 图 13：各项优化带来的逐查询加速比。查询按执行时间降序排列，每个条形图上的标签报告了以秒为单位的执行时间。

### 6.2 两级排序（Two-level sort）

某些算子（如窗口函数）不允许对排序键进行重新排序。第一列不同值较少的场景下，前缀比较会产生大量冲突。在这种情况下，我们采用两级排序[^注6]。我们首先根据第一列的值行进行分桶。然后，使用标准排序算法**对每个桶内的行**进行排序，最后按第一列值的升序输出（<u>降序排序</u>则为降序输出）各个桶。只要第一列的不同值数量低于某个（可配置的）阈值，我们就会采用这种技术。

--------
## 7 评估

我们使用 TPCDS 基准测试套件在 1TB 规模因子下，将 SYNAPSE SPARK 与 SPARK（Apache Spark 3.0.1）进行了比较。这些实验在一个包含 64 个核心和 512GB 主内存的集群上进行，分布在 8 个工作节点上。每个查询执行了 5 次，我们报告了平均加速比（以及 95% 置信区间的宽度）。我们还在一个纵向扩展的单机数据库上评估了一些优化。这在 30GB 规模因子下使用 SQL Server 在一个具有 8 个核心和 64GB 内存的节点上完成。


> [!CAUTION]
>
>
> Table 3: Number of queries affected by each optimization and the reduction in execution time in seconds
>
>
> | Optimization|Optimization|#Rules|#Queries|Improvement|
> | ---|---|---|---|---|
> | Exchange Placement|Exchange Placement|3|26|1149(27%)|
> | Partial-Aggregate|Partial-Aggregate|10|19|888(21%)|
> | Other Partial Push-down |Semi-Join|6|10|289(7%)|
> | Other Partial Push-down |Bit vector|2|13|510(12%)|
> | Peephole|key re-order|1|11|324(7%)|
> | Peephole|Two-level|1|1|196(5%)|
>

### 7.1 性能概要

表 3 报告了实现每项优化所需的规则数量、受影响的查询数量以及相应的执行时间减少（以绝对值和百分比表示）。

部分下推（partial push-downs）贡献了我们新增规则的 75%。总体而言，这些优化影响了大约一半的查询（基准测试套件中的 103 个中有 53 个，前 20 个中有 17 个），使这部分查询的执行速度提升了 2.1 倍，整个套件提升了 1.8 倍（如图 1 所示）。交换（Exchange）放置（第 3 节）和部分聚合（partial-aggregation）（第 4 节）在受影响的查询数量和整体加速比方面影响最大。图 13 报告了这 53 个查询中每项优化带来的加速比分解。我们观察到在长时间运行的查询中显著的改进，这些查询通常应用了多个优化，并带来了非重叠的收益。

### 7.2 各项优化的影响

接下来，我们重点介绍各项优化在前 20 个查询中受影响的查询上带来的一些最显著的改进（有关优化前后的算子成本，请参见图 2）。

**Exchange Placement（交换放置）**：该优化带来的一些最大收益得益于通过计划标记（plan-marking）实现的重用推理。Q23b、14a、14b、Q47、O57 利用这一点实现了 2-4 倍的加速。除了我们针对的瓶颈算子外，该优化还通过避免冗余扫描（14a、14b）降低了扫描成本。

**Partial aggregate push-down（部分聚合下推）**：在除两个受影响的查询外的所有查询中，我们都成功将聚合下推到第一阶段（19 个中有 17 个）。当部分聚合源自 intersect（Q14a, Q14b）和 semi-join（Q82, Q37）时，收益最为显著。这一切之所以成为可能，是因为我们对部分聚合进行了根本性的扩展，提供了头等支持。仔细观察算子分解可以发现，成本模型在评估收益方面非常有效。该优化总是会降低瓶颈算子的成本。事实上，该模型在大约 25 个查询中拒绝了部分聚合的下推（未显示），我们通过交叉验证（参见敏感性分析）确认这些查询均不会看到显著收益。

**Other partial push-down（其他部分下推）**：semi-join 下推和 bit-vector filtering 共同对 Q95（基准测试中唯一的重度连接查询）产生了重大影响，它们不仅节省了 exchange 成本，还节省了连接成本。有趣的是，有两个实例（Q82, Q37）中，inner-join 和根 semi-join 之间没有 exchange，而在这些实例中，semi-join 下推没有带来任何收益。

> [!CAUTION]
>
>
> ![](http://darwin-controller-pro-01.oss-cn-hangzhou.aliyuncs.com/docs/1421069864619057152/%E3%80%90%E5%8E%9F%E6%96%87%E3%80%91New%20Query%20Optimization%20Techniques%20in%20the%20Spark%20Engine%20of_29.jpg?Expires=1759036564&OSSAccessKeyId=LTAI5tBVMtznbk7xyCa56gof&Signature=DunHX6lBKyVoIw4AD1iD9IUC2tw%3D) 
>
> 图 14：在纵向扩展和横向扩展系统中，部分聚合和 semi-join 下推带来的加速比比较。
>

受 bit-vector filtering 影响的大约一半查询受益于计划标记以避免重复计算。如图 2（bloom）所示，我们优化的分布式实现确保了构建过滤器的开销可以忽略不计。

**Peephole（小小优化）**：除了部分下推外，排序键重排序（sort key re-ordering）进一步将 Q50 和 Q93 的执行时间平均减少了 38%。在 Q93 中，记录比较次数从 130 亿减少到 1.2 亿（10 倍改进），几乎完全消除了排序成本。两级排序（Two-level sort）将 Q67 的记录比较次数减少了 89 倍（从 85 亿到 9.5 亿），并将排序时间减少了 7 倍。

### 7.3 对纵向扩展数据库的影响

我们还在纵向扩展环境中评估了两种部分下推优化，即部分聚合下推和 semi-join 下推。对于这些实验，我们手动修改了查询以反映优化，并验证了它们对执行计划产生了预期效果。请注意，对于部分聚合下推，我们引入了额外的完全聚合来替代部分聚合。本质上，我们的手动修改模拟了如果将 [10, 20, 30] 中的聚合下推扩展到本文提出的其他算子会发生的情况。

图 14 显示了受这两项优化影响最大的查询的加速比。可以看出，在纵向扩展环境中的收益远低于 SYNAPSE SPARK。部分下推在纵向扩展环境中最多带来 20% 的改进，许多查询根本没有收益，而在横向扩展环境中我们看到 1.5 - 3 倍的改进。我们得出结论，虽然这两项优化适用于纵向扩展环境，但它们在纵向扩展环境中的效果不如在横向扩展环境中显著。

### 7.4 敏感性分析

**Partial aggregate sensitivity analysis（部分聚合敏感性分析）**：我们测量了增加阈值 Th（参见第 4.3 节）对部分聚合优化的适用性和性能的影响。我们观察到，将值从 0.5 增加到 0.95 会增加受影响的查询数量（增加 4 个），但这些查询没有看到任何显著的改进或退化。

**Sensitivity to k for exchange placement（交换放置对 k 的敏感性）**：回想一下，我们的交换放置算法对搜索空间进行了激进的剪枝。使用我们的算法，优化器需要 1-12 秒来优化一个 TPCDS 查询，从不需要超过 4 的 k 值（每个节点缓存的计划数量）来搜索。

对于 7 个查询（包括从交换放置中受益很多的 Q24、Q47、O57），k 值需要达到 16 或以上才能搜索完整空间，而我们的算法无法搜索到完整的空间，因此无法找到这些查询的最优计划。实际上，Q24 需要更多时间来优化并达到相同的最优计划，而不是直接运行。这是不可接受的。

## 8 相关工作

查询优化是一个研究非常充分的领域，拥有数十年的文献和显著的工业影响。我们已经在前面章节的文本框中描述了一些重要且密切相关的工作。我们在此提供一些额外的细节。

**基础组件**：查询成本估算、统计信息传播和计划空间探索是研究丰富的领域 [7, 9, 18, 19]。我们提出了针对大数据系统的特定改进。我们提出了一个成本模型（用于部分下推），该模型考虑了 exchanges，并扩展了 SPARK 以进行基于成本的探索。

**Exchange 和排序**：近期文献提出了引入和实现 exchanges 的算法 [26, 28, 32-35]。我们在最佳交换放置算法 [34] 的基础上进行了改进。先前算法的一个有趣方面是，它以基于成本的方式同时优化排序和分区。他们支持一种保序 exchange，该 exchange 交错地从多台机器读取数据。SPARK 目前不支持此类 exchange，而是采用精心优化的排序实现（排序竞赛 [5] 的获胜者），并在需要时依赖 exchange 后重新排序数据。在 SYNAPSE SPARK 中，我们提出了一种小小优化，直接选择最佳键顺序，而不是探索所有组合。

最后，我们的计划标记（plan tagging）机制类似于其他领域（如视图物化和多查询优化 [17, 21]）中使用的方法。但我们使用场景非常不同，我们将其用于独立优化单个查询的过程中。

**Partial push-down（部分下推）**：SYNAPSE SPARK 与先前工作 [10, 20, 22, 30] 的不同之处在于，它通过为部分聚合提供头等支持来扩展大数据优化器。我们添加了一个新的逻辑算子，并引入了多个规则来生成部分聚合并将其下推到所有 SQL 算子之下。[22] 还提出了通过使用有界大小的哈希表来限制部分聚合内存需求的方法，该哈希表可以为每组部分聚合键发出多个结果。他们还提出了一个成本模型来专门化其实现的参数。我们探索了不同的权衡（哈希聚合和 exchange 之间），这在大数据环境中更为重要，并提出了一个成本模型来决定哪些部分聚合可能有益。通过 bit-vector filtering 实现的部分下推 [11-13, 15] 已被广泛研究。我们提出了一种专门的分布式实现。

## 9 结论

本文描述了我们在 SYNAPSE SPARK 中集成的新查询优化技术。**我们识别了大数据系统中的主要瓶颈，并提出了三种类型的优化来解决它们**。我们通过添加新的算子以及多个新的逻辑和物理规则来扩展 SPARK 查询优化器，以实现这些优化。

### 参考文献

-----

# 注解

## 注 2
[^注2]: 好的，这是一个非常好的问题。这个优化之所以能够成立，核心在于**关系代数的等价变换**和**查询结果的正确性保证**。

简单来说，这个优化成立的前提是：**将聚合操作下推到 join 操作下方之后，最终的查询结果必须与原始查询完全一致。**

下面详细解释为什么在特定条件下这是可行的：

### 成立的关键条件

这个优化通常需要满足以下一个或多个条件：

1.  **保持连接键的唯一性（最常见且关键的条件）**:
    - 想象一下，如果你在 join 之前对其中一张表进行聚合，你必须确保聚合操作**不会丢失 join 所需的信息**。
    - 具体来说，**聚合操作的分组键（GROUP BY key）必须包含与该表相关的 join 键**。
    - **为什么？** 这样可以保证对于原始表中的每一行（在 join 键上）可能存在的多个值，在聚合后，这些行会被合并成一行，但 join 键的值保持不变。因此，它仍然可以与另一张表在相同的键上进行正确的 join，不会导致连接失败或产生重复数据。

2.  **聚合函数的兼容性**:
    - 聚合函数必须是可以在 join 之前安全计算的。例如：
        - **可下推的**: `SUM`, `COUNT`, `MIN`, `MAX`。这些函数在部分数据上计算后再汇总，结果与整体计算一致。
        - **需要谨慎处理的**: `COUNT(DISTINCT ...)` 在分布式环境下更复杂，但理论上也可以下推，不过需要额外的处理来在最终聚合时去重。
        - **不能简单下推的**: `AVG`。你不能直接对平均值再求平均值。但 `AVG` 可以分解为 `SUM(column)` 和 `COUNT(column)` 两个部分聚合下推，然后在最终聚合时用 `SUM / COUNT` 来计算真正的平均值。

### 举例说明

假设有两个表：
- **`orders`（订单表）**: `order_id`, `customer_id`, `order_amount`
- **`customers`（客户表）**: `customer_id`, `customer_name`, `country`

**原始查询**：计算每个国家的总订单金额。
```sql
SELECT c.country, SUM(o.order_amount) as total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.country;
```
这个查询的执行流程是：先进行 `customers` 和 `orders` 的大表连接，然后对结果集按 `country` 分组求和。

**优化后的查询（逻辑上等价）**：我们可以将聚合部分下推到 `orders` 表上。
1.  **先对 `orders` 表进行预聚合**：按 `customer_id` 对订单金额求和。因为 `customer_id` 正是 join 的键。
    ```sql
    -- 第一步：下推的聚合
    SELECT customer_id, SUM(order_amount) as customer_total
    FROM orders
    GROUP BY customer_id;
    ```
    现在，我们得到了一个更小的中间结果，每个 `customer_id` 对应一行总金额。

2.  **再将这个聚合结果与 `customers` 表连接**：
    ```sql
    -- 第二步：连接
    SELECT c.country, pt.customer_total
    FROM customers c
    JOIN precomputed_totals pt ON c.customer_id = pt.customer_id;
    ```
3.  **最后按国家分组求和**：
    ```sql
    -- 第三步：最终聚合（数据量已大大减少）
    SELECT country, SUM(customer_total) as total_amount
    FROM ... -- 上一步的结果
    GROUP BY country;
    ```

### 为什么这个优化是有效的？

- **减少数据传输（Shuffle）**：在分布式系统如 Spark 中，最大的开销往往是数据传输。原始计划需要将两张完整的表（或扫描后的数据）根据 `customer_id` 进行 shuffle 来执行 join。而优化后的计划，先在 `orders` 表上本地聚合，每个 `customer_id` 只产生一行数据，**大大减少了需要通过网络 shuffle 到 join 操作的数据量**。
- **减少连接操作的计算负担**：Join 操作处理的数据行数显著减少，因此速度更快，占用内存更少。

### 文中提到的“不能节省 exchanges”是什么意思？

文章指出，在大数据设置中，这个优化本身可能不会减少 **exchange 的数量**。这是因为：
- 无论是原始计划还是优化后的计划，为了执行 `GROUP BY country` 和基于 `customer_id` 的 `JOIN`，系统都需要进行 shuffle（即 exchange 操作）。
- 优化带来的收益主要在于 **每次 exchange 所传输的数据量大大减少**，而不是 exchange 步骤的数目本身。计算和网络开销都因此降低。

### 总结

这个优化成立的根本原因是**在保持查询语义完全不变的前提下，通过改变操作顺序，提前减少中间结果的数据量**。它是一种用“提前计算局部结果”的CPU开销，来换取“大幅减少数据传输和连接计算”的IO和网络开销的经典权衡，在分布式数据处理中尤其有效。优化器需要基于统计信息（如数据基数）进行成本估算，来决定是否应用此优化。

## 注 3
[^注3]: “**幂集**”（Power Set）是集合论中的一个基本概念。一个集合的幂集，就是这个集合所有可能的子集组成的集合。

### 举个例子 🌰

假设我们有一个集合：  
**A = {a, b}**

这个集合的所有子集有哪些？

1.  空集：**{}**（也写作 ∅）
2.  只包含 `a` 的集合：**{a}**
3.  只包含 `b` 的集合：**{b}**
4.  包含 `a` 和 `b` 的集合：**{a, b}**

所以，集合 A 的**幂集**就是：  
**P(A) = { {}, {a}, {b}, {a, b} }**


### 原文中的应用

原文中提到了：

> \( \mathcal{P}'(\mathrm{X}) = \mathcal{P}(\mathrm{X}) \setminus \varnothing \)

这表示：
- \( \mathcal{P}(\mathrm{X}) \) 是集合 X 的**幂集**（所有子集）。
- \( \mathcal{P}'(\mathrm{X}) \) 是从幂集中**去掉空集**后的结果。

比如，如果 X = {a1, b1}，那么：

- \( \mathcal{P}(\mathrm{X}) = \{ \varnothing, \{a1\}, \{b1\}, \{a1,b1\} \} \)（所有子集）
- \( \mathcal{P}'(\mathrm{X}) = \{ \{a1\}, \{b1\}, \{a1,b1\} \} \)（去掉空集）

这在数据库优化中很有意义：**分区不能按“空列”进行**，所以我们要排除空集。

### 总结

| 术语 | 含义 |
|------|------|
| **集合** | 一组元素，如 $\{a1, b1\}$ |
| **子集** | 包含原集合部分或全部元素的集合，如 $\{a1\}、\{b1\}、\{a1,b1\}、\{\}$ |
| **幂集** | 所有子集构成的集合，如 $P(\{a1,b1\}) = \{ \{\}, \{a1\}, \{b1\}, \{a1,b1\} \}$ |
| **去掉空集的幂集** | 排除 $\{\}$，只保留非空子集，用于表示**有效的分区键组合** |

所以，在查询优化中，“幂集”用来枚举一个算子（如 join 或 group-by）**所有可能的分区方式**，以便优化器进行比较和选择。


## 注 6
[^注6]:详细解释一下第6.2节**两级排序**的内容。它描述了一种针对特定场景的优化技术，其核心思想是**分而治之**，通过先分组再排序来大幅减少排序过程中的比较次数，从而提升性能。

### 背景与问题

1.  **排序的瓶颈：** Spark 的排序算法（Tim sort）在比较两行数据时，会先比较它们序列化后的前几个字节（前缀）。如果前缀相同（即发生“冲突”或“碰撞”），则必须将整行数据反序列化出来，再进行完整的比较。反序列化和完整比较是非常耗时的操作。
2.  **不能重排序的情况：** 在 6.1 节中，我们通过将“区分度高”（不同值多）的列放在排序键前面来减少冲突。但这招并非万能。例如，**窗口函数（window functions）** 的排序要求非常严格，排序键的顺序是语义的一部分，不能随意更改。因此，我们无法对这类查询的排序键进行重排序。
3.  **特定的糟糕场景：** 假设排序键的第一个列（即最优先的排序列）的“区分度”很低，比如是一个状态码（只有 'A', 'B', 'C' 三个值）或一个年份（只有 '2020', '2021', '2022' 几个值）。那么，成千上万行数据的前缀都会是相同的（因为它们属于同一个状态或年份）。这会导致排序算法在第一步就产生海量的“冲突”，从而引发大量的、昂贵的反序列化和完整比较操作，性能会急剧下降。

### 解决方案：两级排序

为了解决上述问题，作者提出了“两级排序”技术：

1.  **第一级：分桶（Bucketing）**
    *   首先，根据排序键**第一个列的值**，将所有数据行划分到不同的“桶”（bucket）中。
    *   例如，如果第一列是 `year`，那么所有 `year=2020` 的行放入一个桶，`year=2021` 的行放入另一个桶，`year=2022` 的行放入第三个桶。
    *   由于第一列的值种类很少，所以产生的桶的数量也很少。

2.  **第二级：桶内排序**
    *   在每个桶内部，使用 Spark 标准的排序算法（如 Tim sort）对行进行排序。
    *   此时，桶内的所有行在第一列上是相同的。排序算法会直接比较第二列、第三列等后续的排序键。由于我们跳过了第一列的比较，直接进入后续列，这大大减少了前缀冲突的可能性。

3.  **合并输出**
    *   最后，将所有桶按第一列的值**升序**（如果是降序排序则为降序）依次输出。
    *   例如，先输出 `year=2020` 桶中已排好序的所有行，然后是 `year=2021` 桶的行，最后是 `year=2022` 桶的行。

### 为什么能提升性能？

*   **减少冲突：** 最关键的优化在于，我们避免了在成千上万行数据之间进行第一列的比较。第一列的比较被简化为在少数几个桶之间进行。
*   **局部化排序：** 每个桶内部的数据量远小于原始总数据量，排序更高效。
*   **利用数据特性：** 该优化特别适用于第一列区分度低的场景，这正是标准排序算法最慢的情况。

### 触发条件

这种技术并非总是启用。它有一个前提条件：**第一列的不同值的数量必须低于一个可配置的阈值**。如果第一列的值非常多（比如一个用户ID列），那么会产生大量的桶，每个桶的数据量很小，分桶的开销可能就超过了其带来的收益，此时使用标准排序反而更高效。

**总结来说，6.2 节介绍的“两级排序”是一种聪明的优化：当无法改变排序键顺序，且排序键首列区分度很低时，它通过先按首列分桶，再在桶内排序的方式，巧妙地绕开了排序算法的性能瓶颈，显著减少了昂贵的比较和反序列化操作，从而大幅提升排序性能。**