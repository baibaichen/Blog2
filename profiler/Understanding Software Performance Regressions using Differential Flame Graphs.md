# Understanding Software Performance Regressions using Differential Flame Graphs

> **Abstract**—Flame graphs are gaining rapidly in popularity in industry to visualize performance profiles colected by stack-trace based profilers. In some cases, for example, during performance regression detection, profiles of different software versions have to be compared. Doing this manually using two or more flame graphs or textual profiles is tedious and error-prone.
>
> In this ‘Early Research Achievements’-track paper, we present our preliminary results on using differential flame graphs instead. Differential flame graphs visualize the differences between two performance profiles. In addition, we discuss which research fields we expect to benefit from using differential flame graphs. We have implemented our approach in an open source prototype called FLAMEGRAPHDIFF, which is available on GitHub. FLAMEGRAPHDIFF makes it easy to generate interactive differential flame graphs from two existing performance profiles. These graphs facilitate easy tracing of elements in the different graphs to ease the understanding of the (d)evolution of the performance of an application
>

**摘要** —— 火焰图在行业中迅速流行，用于可视化由分析器收集的堆栈信息。在某些情况下，例如，在性能回归检测期间，必须比较不同软件版本的堆栈信息。手动比较两个或多个火焰图，或者比较堆栈的文本信息，既乏味又容易出错。

在这篇**早期研究成果**的跟踪论文中，我们展示了使用**差分火焰图**的初步结果。**==差分火焰图可视化两个性能曲线之间的差异==**。此外，<u>我们还讨论了使用差分火焰图可以使哪些研究领域获益</u>。在 `FLAMEGRAPHDIFF` 的开源原型中实现了我们的方法，可在 GitHub 上获得。 `FLAMEGRAPHDIFF` 可以方便地从两个现有的堆栈信息中生成<u>交互式差分火焰图</u>，有助于跟踪不同图表中对应的方法，以简化对应用程序性能退化或进化的理解

## I.   简介

> One of the major challenges in performance analysis is understanding the large amounts of data collected. Several visualization methods, such as heat maps [1] and icicle plots [2], have been introduced to assist with this understanding. Over the past few years, the flame graph [3], [4], a visualization based on the icicle plot, has gained rapidly in popularity in industry. A flame graph is a visualization of hierarchical data. More specifically, it visualizes a collection of (*stack trace*^1^, *value*)-pairs in which *value* represents a metric monitored or calculated for that specific *stack trace*. These pairs can, for example, be obtained by using a stack trace-based profiler: such a profiler records and aggregates metrics per executed stack trace.
>
> > ^1^Throughout this paper we consider a stack trace a report of the active stack frames at a certain point in time during the execution of a program.
>
> In a flame graph, elements are shown in a stacked fashion. Stack traces are shown from bottom to top, where the top element represents the function called latest in the stack trace. As a result, the height of the graphed stack represents the depth of the stack trace. The width of the stack represents the relative size of the monitored values compared to the other values. Hence, the element with the largest value (e.g., the stack trace in which most time is spent) in the profiled data is identified by finding the widest element in the graph.
>
> > - [ ] Figure 1 and Figure 2
>
> Figure 1 depicts a sample program and its corresponding CPU profile. In this profile, the CPU time spent within each stack trace is recorded during execution of the program. Note that the times represent the total time spent within a stack trace and that the profile does not contain information about the execution order of these stack traces or about the time spent in a single call. Because of this, the x-axis of a flame graph does not and cannot show the passage of time, but instead spans the sample population, with the ordering of stacks sorted alphabetically to maximize merging of profiled elements. Figure 2 depicts the corresponding flame graph^2^. From this figure, it is easy to spot that most time is spent within stack trace *a()*.
>
> > ^2^Note that a random color palette is used to generate flame graphs, i.e., the colors do not have a meaning.
>
> In various cases, it is desirable to compare the performance profiles of two or more different software versions. One of these cases is performance regression analysis. The goal of performance regression analysis is to find out whether and why the performance of software degraded after an update to the code [5], [6]. Current practice is to manually compare profiles which is time consuming and tedious. In this paper, we propose a method for doing this comparison using *differential flame graphs (DFGs)*. In a DFG, the differences between two performance profiles are depicted using a flame graph.
>
> In Section II, we present the DFG-set, explain its components and give examples on how they can be used for performance analysis. In Section III, we describe scenarios in which we expect DFGs to be useful. We discuss the challenges and the open source implementation of our approach in Section IV. We discuss related work in Section V and we conclude our paper in Section VI.

性能分析的一个主要挑战是理解大量收集的数据。已经引入了几种可视化方法以帮助理解，例如热力图 [1] 和冰柱图 [2]。 过去几年，基于冰柱图的可视化火焰图 [3]、[4] 在行业中迅速流行。火焰图是层次数据的可视化。更具体地说，它可视化了 <**stack trace**^1^, **value**> 数据对的集合，其中 **value** 代表该特定 **stack trace** 监控或计算的指标。 分析器收集堆栈信息和指标，并基于每次收集到的堆栈信息聚合指标。

> ^1^在本文中，我们视 **stack trace** 为程序执行期间某个时间点**活动堆栈的报告**。

在火焰图中，元素以堆叠的方式显示。 堆栈从下到上显示，其中顶部元素表示堆栈中最新调用的函数。 因此，图形堆栈的高度代表堆栈轨迹的深度。堆栈的宽度表示监控指标的相对大小。 因此，通过查找图中最宽的元素来识别分析数据中指标值最大的元素（例如，花费最多时间的堆栈）。

> - [ ] Figure 1 and Figure 2

图 1 描述了一个示例程序及其相应的 CPU 采样，记录了程序执行期间，在每个堆栈采样上所花费的 CPU 时间。 请注意，时间表示在堆栈采样中花费的总时间，并且采样不包含这些堆栈的执行顺序，也不包含单个调用所花费的时间。 因此，火焰图的 x 轴没有也不能显示时间的流逝，而是跨越样本总体，堆栈的顺序按字母顺序排序，以最大限度地合并异形元素。 图 2 描绘了相应的火焰图^2^。 从这个图中，很容易发现大部分时间都花在了堆栈中的函数 **a()** 上。

> ^2^请注意，这里生成火焰图的颜色是随机的，没有意义。

在各种情况下，需要比较两个或多个不同软件版本的性能，**其中一种情况是性能回归分析**。 性能回归分析的目标是找出在更新代码后软件性能是否下降以及为什么下降 [5]、[6]。 当前的做法是手动比较堆栈采样，既费时又乏味。我们在本文提出了一种使用**差分火焰图 (DFG)** 进行比较的方法。在 DFG 中，使用火焰图描述两种性能曲线之间的差异。

第二节介绍了 DFG 集，解释了它的组成部分，并举例说明如何将它们用于性能分析。 第三节描述了预期 DFG 有用的场景。第四部分讨论了该方法面临的挑战和开源实现。 第五节讨论相关工作，并在第六节总结本文。

## II.     USING DFGS FOR PERFORMANCE ANALYSIS

> Our main proposed application for DFGs is in the performance analysis process. We propose to use DFGs in the three following cases:
>
> - To detect performance regressions (Section II-B)
> - To validate the effect of a performance fix (Section II-C)
> - To compare the performance of an application on different systems (Section II-D)
>
> Our approach is based on a combination of DFGs, the DFGset. In this section, we will first elaborate on the components of a DFG-set and after that, explain how to use them in the cases above.

我们建议 DFGs 主要应用在性能分析中，一般在以下三种情况下使用 DFGs：

- 检测性能回归（第 II-B 节）
- 验证性能修复的效果（第 II-C 节）
- 比较应用程序在不同系统上的性能（第 II-D 节）

我们的方法基于 DFGs 的组合，即 DFGset。在本节中，我们将首先详细介绍 DFG-set 的组件，然后解释如何在上述三种场景中使用它们。

### A.   Differential Flame Graph-Sets (DFG-sets)

For any two software versions *v*~1~ and a newer version *v*~2~, we can record stack trace-based performance profiles *p*~1~ (for *v*~1~) and *p*~2~ (for *v*~2~). A DFG-set visualizes the differences between *p*~1~ and *p*~2~ using three components:

1. DFG~1~: A comparison of p~1~ and p~2~ with p~1~ as base
2. DFG~2~: A comparison of p~1~ and p~2~ with p~2~ as base
3. DFG~diff~ : A flame graph based on the differences of DFG~2~

To generate a flame graph with *p*~1~ as base we draw the base profile as a flame graph, so that the frames and their widths reflect the base. We then add color to show the profile differences. Note that we must compare the profiles both with *p*~1~ and *p*~2~ as base to deal with stack traces that may be added or removed in *v*~2~. *DFG*~1~ and *DFG*~2~ visualize the two options for the performance engineer: either stay with *v*~1~ instead of *v*~2~ (*DFG*~1~), or move from *v*~1~ to *v*~2~ (*DFG*~2~). The DFG-set of three standard flame graphs does visualize all the necessary profile data for regression analysis. However, we introduce color as a dimension to show profile differences within each flame graph. The colors of the components within the flame graph depicting the comparison of *p*~1~ and *p*~2~ with *p*~2~ as base (*DFG*~2~) represent the following:

- *White* – profile value unchanged in version *v*~2~
- *Blue* – profile value reduced in version *v*~2~
- *Red* – profile value grew in version *v*~2~

The interpretation of these colors depends upon the type of profile: for a metric such as time spent, red represents regression, while for a metric such as throughput, it represents an improvement. In addition, we add intensity to the color - a darker shade of blue or red indicates a reduction or growth that is relatively large compared to the other elements that have changed in *v*~2~. In *DFG*~1~, *p*~1~ is used as the base, and the colors show the profile difference if we revert the changes from *v*~2~ back to *v*~1~.

To further highlight the differences in performance when using software version *v*~2~ instead of *v*~1~, we draw *DFG*~diff~ which contains only the differences. This allows us to draw the element width size relative to the size of the difference, making it easy to spot the largest differences. We have chosen to draw the differences of *DFG*~2~ in *DFG*~diff~ only as these are in our opinion the most often investigated ones when searching for performance regressions.


对于软件的任意两个版本 *v*~1~ 和新版本 *v*~2~，我们可以有两个性能采样文件 *p*~1~（对于 *v*~1~）和 *p*~2~（对于*v*~2~）。 DFG 集合使用三个组件可视化 *p*~1~ 和 *p*~2~ 之间的差异：

1. DFG~1~：以 p~1~ 为基础，比较 p~1~和p~2~
2. DFG~2~：以 p~2~ 为基础，比较 p~1~和p~2~
3. DFG~diff~：基于 DFG~2~ 差异的火焰图

我们**首先**生成以 *p*~1~ 为基础的火焰图，以便==框架==及其宽度反映基础。然后我们添加颜色以显示采样文件的差异。

---

请注意，我们必须比较以*p*~1~和*p*~2~为基础的概要文件，以处理可能在*v*~2~中添加或删除的堆栈跟踪*DFG*~1~和*DFG*~2~将性能工程师的两个选项可视化：要么留在*v*~1~而不是*v*~2~（*DFG*~1~），要么从*v*~1~移动到*v*~2~（*DFG*~2~）。DFG由三个标准火焰图组成，可将回归分析所需的所有轮廓数据可视化。然而，我们引入颜色作为维度，以显示每个火焰图中的轮廓差异。火焰图中描述*p*~1~和*p*~2~与以*p*~2~为基准（*DFG*~2~）比较的组件颜色表示如下：

-*白色*–配置文件值在版本*v*~2中保持不变~

-*蓝色*–外形值在版本*v*~2中降低~

-*红色*–配置文件值在版本*v*~2中增加~

这些颜色的解释取决于配置文件的类型：对于时间花费等度量，红色表示回归，而对于吞吐量等度量，红色表示改进。此外，我们还增加了颜色的强度-较深的蓝色或红色表示与在*v*~2~中变化的其他元素相比，减少或增长相对较大。在*DFG*~1~中，*p*~1~用作基础，如果我们将更改从*v*~2~还原回*v*~1~，则颜色显示轮廓差异。

为了进一步强调使用软件版本*v*~2~而不是*v*~1~时的性能差异，我们绘制了只包含这些差异的*DFG*~diff~。这使我们能够绘制相对于差异大小的元素宽度大小，从而很容易发现最大的差异。我们选择在*DFG*~diff~中画出*DFG*~2~的差异，因为我们认为这是搜索性能回归时最常调查的差异。

---


请注意，我们必须比较以 *p*~1~ 和 *p*~2~ 为基础的配置文件，以处理可能在 *v*~2~ 中添加或删除的堆栈跟踪。 *DFG*~1~ 和 *DFG*~2~ 为性能工程师可视化两个选项：要么留在 *v*~1~ 而不是 *v*~2~ (*DFG*~1~)，要么移动从 *v*~1~ 到 *v*~2~ (*DFG*~2~)。三个标准火焰图的 DFG 集确实可视化了回归分析所需的所有轮廓数据。但是，我们引入颜色作为维度来显示每个火焰图中的轮廓差异。描述*p*~1~和*p*~2~以*p*~2~为基数（*DFG*~2~）的比较的火焰图中各分量的颜色表示如下：

- *White* – 版本 *v*~2~ 中的配置文件值未更改
- *Blue* – 版本 *v*~2~ 中的配置文件值减少
- *红色* - 配置文件值在版本 *v*~2~ 中增长

这些颜色的解释取决于配置文件的类型：对于诸如花费的时间之类的指标，红色代表回归，而对于诸如吞吐量之类的指标，它代表改进。此外，我们为颜色增加了强度 - 较深的蓝色或红色阴影表示与 *v*~2~ 中发生变化的其他元素相比，减少或增加相对较大。在 *DFG*~1~ 中，*p*~1~ 用作基础，如果我们将更改从 *v*~2~ 还原回 *v*~1~，则颜色显示轮廓差异。

为了进一步突出使用软件版本 *v*~2~ 而不是 *v*~1~ 时的性能差异，我们绘制了仅包含差异的 *DFG*~diff~。这使我们能够绘制相对于差异大小的元素宽度大小，从而很容易发现最大的差异。我们选择在 *DFG*~diff~ 中绘制 *DFG*~2~ 的差异，只是因为我们认为这些是搜索性能回归时最常研究的。

### B.   Detecting Performance Regressions

> Performance regression can occur for various performance metrics, such as CPU time and I/O traffic [6]. Below we give examples on how to use a DFG-set to detect such regressions.
>
> 1. **CPU Time Regression**: We demonstrate the applicability of a DFG-set on finding CPU time regressions using the rsync^3^ test suite as an example. Rsync is a widely-used utility software for synchronizing files and directories from one location to another while minimizing data transfer by using delta encoding. We used perf^4^ to record the number of CPU cycles spent in each function during an execution of the test suite of rsync, resulting in performance profile *p*~1~. To generate profile *p*~2~, we have altered *p*~1~ to simulate a performance regression which increases the cycles spent within the main and md5_process functions.
>
>    > ^3^http://rsync.samba.org/
>    >
>    > ^4^https://perf.wiki.kernel.org/index.php/Main_Page
>
>    Figure 3, 4 and 5 depict the DFG-set that results from comparing *p*~1~ and *p*~2~. Figure 3 and 4 show that a regression occurred in a function called by main and in the md5_process function, which are the regressions seeded by us. Figure 5 further highlights these regressions. This can especially be helpful in flame graphs with a large number of elements or differences.
>
> 2. **I/O Writes Regression**: In earlier work [6], we have proposed an approach for detecting regressions in the amount of I/O write traffic. This approach generates a report when comparing two code revisions, which contains a ranking of the stack traces which were the most likely to have increased their write traffic (*impact*). Table I depicts (part of) such a ranking. The actual ranking contains 204 records. Because this ranking is textual, it can be tedious to see relations between the stack traces such as relative size and overlap. The interpretation of the textual ranking can be made easier^5^ by using a DFGset instead, because a DFG-set allows us to see the relative size and groups stack traces that share common elements together. Figure 6 depicts the DFG-set corresponding to the (full) ranking of Table I. An advantage is that minor increases are easily ignored in the DFG-set. One can clearly see that the database commit in the `store_update_forward` function causes the largest part of the regression and that the increase in writes caused by other functions is negligible in comparison. In addition, we would not have been able to display both profiles and the ranking on one page in a textual form, while using flame graphs this is possible.
>
>    > ^5^Although one can argue that in this specific case the textual ranking is already easy to read due to the large increase.
>
> > Figure 3, 4, 5
>

各种性能指标都可能发生**性能回退**，例如 CPU 时间和 I/O 流量 [6]。下面我们举例说明如何使用 DFG 集来检测此类问题。

1. **CPU 时间**：我们以 rsync^3^ 测试套件为例，演示了 DFG 集在查找 CPU 时间回归方面的适用性。rsync 是一种广泛使用的实用软件，用于将文件和目录从一个位置同步到另一个位置，同时通过使用增量编码最大限度地减少数据传输。 我们使用 perf^4^ 记录在执行 rsync 测试套件期间每个函数花费的 CPU 周期数，从而得到性能采样文件 *p*~1~。 为了生成采样文件 *p*~2~，我们增加 `main` 和 `md5_process` 函数中花费的 cpu 周期，以模拟性能回退。

   > ^3^http://rsync.samba.org/
   >
   > ^4^https://perf.wiki.kernel.org/index.php/Main_Page

   图 3、4 和 5 描绘了通过比较 *p*~1~ 和 *p*~2~ 产生的 DFG 集。 图 3 和图 4 显示在 `main` 调用的函数和 `md5_process` 函数中发生了回退。这是我们故意产生的回退。 图 5 进一步突出了这些回退。 这对于包含大量元素或差异的火焰图尤其有用。

2. ==**I/O 写入回归**：在早期的工作 [6] 中，我们提出了一种检测 I/O 写入性能回退的方法。这种方法在比较两个代码修订时会生成一个报告，其中包含最有可能退化（**影响**）写入性能的堆栈排名。表 I 描述了（部分）这样的排名。实际排名包含 204 条记录。由于此排名是文本，因此查看堆栈之间的关系（例如相对大小和重叠）可能会很乏味。通过使用 DFG 集可以更轻松地解释文本排名^5^，因为 DFG 集允许我们查看相对大小，并将共享公共元素的堆栈分组在一起。图 6 描绘了对应于表 I 的（完整）排名的 DFG 集。一个优点是在 DFG 集中很容易忽略微小的增加。可以清楚地看到，`store_update_forward` 函数中的数据库提交导致了最大的性能回退，相比之下其他函数引起的写入增加可以忽略不计。此外，我们无法以文本形式在一个页面上同时显示采样文件和排名，而使用火焰图可以做到这一点。==

   > ^5^尽管有人会争辩说，在这种特定情况下，由于性能大幅退化，文本排名已经很容易阅读了。

   > 图 3、4、5

### C.   Validating a Performance Fix

> After a regression occurred, or another performance issue was found, the responsible code should be fixed. After applying this fix, a DFG-set can be used to validate the effect of the fix. *DFG*~1~ in Figure 6 shows us what happens to the performance of our application if we revert from the new version of the code to the old version. Hence, we can validate the effect of the ‘fix’ of undoing these changes. Likewise, we can use blue-colored elements in a DFG to analyze whether a performance fix had the desired effect.
>
> > Figure 6
>

在发生性能回退或发现其他性能问题后，会修复出问题的代码。修复之后，可使用 DFG 集来验证修复效果。图 6 中的 *DFG*~1~ 展示了如果我们把代码从新版本 **revert** 回旧版本，程序的性能会发生什么变化。因此，我们可以验证 revert 的==修复==效果。同样，我们可以在 DFG 中使用蓝色元素来分析性能修复是否具有预期效果。

### D.   Comparing Performance on Different Systems

> The DFG-set is a representation of the absolute difference between two profiles. In some cases, it may be more useful to compare their relative difference, i.e., the proportion that each stack trace takes up in the profile. An example of such a case is when we want to compare two profiles recorded on different systems, for example, when analyzing debug data which was submitted through a number of crash reports by client users. In this case, it may not be useful to compare the absolute values in this data but to use normalized values instead. The differences may help to learn more about the limitations and system requirements of an application.

DFG 集是两个堆栈采样文件之间绝对差异的表示。某些情况下，**比较它们的相对差异可能更有用**，即每个堆栈采样在整体采样中所占的比例。当我们想要比较不同系统上的两个堆栈采样文件时就是这种情况，一个例子是分析客户端因为崩溃提交的调试数据。这时，比较绝对值可能没意义，而应该比较**归一化值**。 这些差异可能有助于更多地了解应用程序的限制和系统要求。

## III.       DIFFERENT  APPLICATIONS

> In this section, we present various different scenarios we expect to be suitable for analysis with DFGs. ==These scenarios can be used to guide the formation of new research questions regarding DFGs==.

在本节中，我们将介绍各种不同的场景，希望这些场景适合使用 DFGs 进行分析。==这些情景可用于指导有关DFG的新研究问题的形成==。

### A.   Parallel/Distributed Computing

An important challenge in parallel and distributed computing is to divide a large task into several smaller subtasks. We expect that DFGs can assist with the validation of this division as DFGs allow easier analysis of differences between profiles. Hence, DFGs make it easier to analyze the difference in workload between various nodes performing similar tasks. 

Another scenario in which we expect DFGs to help out, is with the analysis of distributed algorithms, such as those used in peer-to-peer networks. In such algorithms, the goal is often to distribute the workload evenly over the available peers. If such an algorithm contains a bug, it is difficult to debug because the bug may only be exhibited when a large number of peers is in the network. We expect that DFGs can assist in debugging scenarios by allowing a quick comparison of the profile of a large number of nodes. Likewise, we expect DFGs can assist with the debugging process of load balancers.

### B.   GUI and Website Analysis

We expect that DFGs can be applied in fields other than software performance analysis as well. GUI analysis exhibits similarities with software performance: GUI usage can be monitored by counting click-paths [7], which can be considered a stack trace of the actions performed in the GUI. After adding a new option to the GUI, the DFG-set can be used to investigate how the new click-path affects usage of existing functionality. Note that these ideas apply to website analysis as well.

## IV.       DISCUSSION

### A.   Challenges

> The most important challenge of DFGs is data collection. Because DFGs require full stack traces, profiles must be recorded using profilers that can generate such traces. In practice collecting such data appeared to be difficult for some languages (e.g., Java and Python), due to the inavailability of suitable profilers.
>
> In large flame graphs it can be difficult to locate targets. In future work, we will add a keyword search to FLAMEGRAPHDIFF to make this easier.

DFG 最重要的挑战是数据收集。 由于 DFG 需要完整的堆栈采样，因此必须使用可以生成此类采样的分析器来收集。 在实践中，由于没有合适的分析器，对于某些语言（例如 Java 和 Python）来说，收集此类数据似乎很困难。

可能很难在大型火焰图中定位目标。接下来我们将向 `FLAMEGRAPHDIFF` 添加关键字搜索，以使其更容易。

### B.   Implementation

> The prototype implementation of our approach is available as an open source project called FLAMEGRAPHDIFF^6^. FLAMEGRAPHDIFF takes two files containing *(stack, value)*-pairs as input and generates the corresponding DFG-set. Optionally, values can be normalized before they are being graphed. To generate the DFG-set, first the flame graphs are generated^7^. Then, the profiles are compared and the elements of the flame graphs are colored accordingly. Finally, *DFG*~diff~ is generated by hiding all stack traces from *DFG*~2~ of which the value of the last function on the stack did not change.
>
> > ^6^http://corpaul.github.io/flamegraphdiff/
> >
> > ^7^For more information on flame graph generation see the original FlameGraph repository: https://github.com/brendangregg/FlameGraph
>
> FLAMEGRAPHDIFF generates the three DFGs in the DFGset as interactive SVGs. When the user hovers the mouse over an element in any of the graphs in the set, the corresponding elements are highlighted in the other graphs and their values are displayed. This allows for easy tracing of elements over the various graphs. A demonstration of several scenarios can be found at the project website.
>

我们的方法的原型实现是一个名为 FLAMEGRAPHDIFF^6^ 的开源项目。FLAMEGRAPHDIFF 将包含 **(stack, value)** 的两个堆栈采样文件作为输入并生成相应的 DFG-set。 或者可在绘制图形之前对值进行**==标准化==**。为了生成 DFG-set，首先生成火焰图^7^。 然后，比较采样文件，并对火焰图的元素进行相应的着色。最后，*DFG*~diff~ 是通过隐藏 *DFG*~2~ 的所有堆栈采样来生成的，其中堆栈上最后一个函数的值没有改变。

> ^6^http://corpaul.github.io/flamegraphdiff/
>
> ^7^有关火焰图生成的更多信息，请参阅 FlameGraph 的[原始仓库](https://github.com/brendangregg/FlameGraph)

FLAMEGRAPHDIFF 在 DFG-set 中生成三个 DFG 作为交互式 SVG。当用户将鼠标悬停在集合图形中任何元素上时，**相应的元素会在其他图形中突出显示**，并显示它们的值。 这允许在各种图形上轻松跟踪元素。 可在项目网站上找到几个场景的演示。

## V.       RELATED WORK

Performance regression analysis through visualization has received surprisingly little attention in research. The widelyused profiler OProfile [8] implements a technique known as differential profiles, which expresses differences between profiles in percentage. However, this is a textual approach and does not offer a visualization.

Bergel et al. [9] have proposed a profiler for Pharo which compares profiles using visualization. In their visualization, the size of an element describes the execution time and number of calls. Alcocer [10] extends Bergel’s approach by proposing a method for reducing the generated callgraph. Additionally, Alcocer et al. [11] propose Performance Evolution Blueprints (PEBs), which show the evolution of an application. The data graphed by PEBs is similar to the data graphed by DFGs, however, DFGs appear to do this in a more compact fashion. In future work, we will do a thorough comparison of the opportunities and limitations of PEBs and DFGs.

Nguyen et al. [12] propose an approach for detecting performance regressions using statistical process control techniques. Nguyen et al. use control charts to decide whether a monitored value is outside an accepted range. The violation ratio defines the relative number of times a value is outside this range. The main difference in the approach used by Nguyen and our approach is the granularity. Their approach identifies performance regressions in system-level metrics, while our approach identifies regressions on the function-level, making analysis of the regression easier. In future work, we will investigate how our approach and Nguyen’s approach can complement each other.

Trumper et al. [13] use icicle plots and edge bundles to visualize differences between execution traces. They focus on the functional aspects of an application, while our approach focuses on a non-functional aspect (performance). In addition, they focus on ordered sequences, while for our visualization, the order of events is not important as we work with aggregated data. Finally, the use of a color scheme to represent differences rather than colored edge bundles results in a clearer graph, which is beneficial for graphs with many elements.

Other visualizations have been proposed for large amounts of performance data, such as heat maps [1], [14], but these have not been applied to performance regression detection.

## VI.       CONCLUSION

In this paper, we have presented the differential flame graph (DFG) for visualizing differences between performance profiles. A DFG is a flame graph depicting the differences of two performance profiles, using one of those profiles as a base. A DFG-set combines three DFGs in one figure: one using the first profile as a base, one using the second profile as a base, and one in which the differences in the second DFG are emphasized to facilitate easier analysis. Without a DFG-set, comparing performance profiles is tedious and error-prone. In this ERA-track paper, we have indicated and given examples of how DFGs can be used for detecting performance regression, validating performance fixes and comparing performance profiles recorded on different systems.

In addition, we present the prototype open source implementation of our approach, FLAMEGRAPHDIFF, which makes it easier to generate and analyze DFGs and to trace elements in multiple graphs. We expect this implementation to be useful in several research areas, such as performance analysis, parallel and distributed computing and GUI and website analysis. Hence, we invite researchers from other fields to use our prototype in their research or to contact us for research collaborations. In future work, we will focus on thoroughly evaluating DFGs in large research and industrial projects.
