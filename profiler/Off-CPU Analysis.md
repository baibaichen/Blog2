# [Off-CPU 分析](https://www.brendangregg.com/offcpuanalysis.html)

<p align="center">
<img src="https://www.brendangregg.com/Perf/thread_states.png"/>
线程状态
</p>

性能问题可以分为以下两种类型之一：

- **`On-CPU`**：线程在CPU上的**运行时间**。
- **`Off-CPU`**：在 I/O、锁、定时器、分页/交换等被阻塞的情况下的**等待时间**。

`Off-CPU` 分析是一种性能分析方法论，测量和研究 `off-CPU` 的时间，以及堆栈采样等上下文。CPU 分析只检查线程是否正在 CPU 上执行。`Off-CPU` 分析的目标是线程被阻塞或不在执行时的状态，如图中的蓝色所示。

`Off-CPU` 分析是对 CPU 分析的补充，因此可以 100% 了解线程时间。这种方法也不同于 `trace`，**<u>跟踪技术通常是为阻塞的应用程序提供工具</u>**，因为这种方法的目标是内核调度器的阻塞概念，是一种方便的通用方法。

线程可以出于多种原因离开 CPU，包括 I/O 和锁，但也有一些与当前线程的执行无关，包括由于对 CPU 资源的高需求而导致的<u>非自愿上下文切换</u>和<u>中断</u>。不管是什么原因，只要这发生干活期间，就会引入延迟。

我将在本页==介绍 `off-CPU` 时间作为一个指标==，并总结 `off-CPU` 分析的技术。作为 `off-CPU` 分析的一个示例实现，我将把它应用到 Linux上，然后在后面介绍其他操作系统。

## 先决条件

> Off-CPU analysis require stack traces to be available to tracers, which you may need to fix first. Many applications are compiled with the -fomit-frame-pointer gcc option, breaking frame pointer-based stack walking. VM runtimes like Java compile methods on the fly, and tracers may not find their symbol information without additional help, causing the stack trace to be hexadecimal only. There are other gotchas as well. See my previous write ups on fixing [Stack Traces](http://www.brendangregg.com/perf.html#StackTraces) and [JIT Symbols](http://www.brendangregg.com/perf.html#JIT_Symbols) for perf.

Off-CPU 分析需要堆栈跟踪可用。许多应用程序都是使用 `-fomit-frame-pointer` 的 gcc 选项编译的，这打破了基于帧指针的堆栈方法。VM 运行时（如 Java）可自由编译方法，在没有额外帮助的情况下可能无法找到其符号信息，从而导致仅能十六进制堆栈跟踪。请参阅关于修复 [Stack Traces](http://www.brendangregg.com/perf.html#StackTraces) 和 [JIT Symbols for perf](http://www.brendangregg.com/perf.html#JIT_Symbols)。

## 简介

为了解释 `off-CPU` 分析的作用，我将首先总结 CPU 采样和跟踪并进行比较。然后我将总结两种 `off-CPU` 分析方法：**跟踪**和**采样**。 虽然十多年来我一直在推动 `off-CPU` 分析，但它仍然不是一种广泛使用的方法，部分原因是在生产 Linux 环境中缺乏测量它的工具。现在，随着 `eBPF` 和 Linux 内核（4.8+）的不断更新，情况正在发生变化。

> 参考 [JProfiler 文档](https://www.ej-technologies.com/resources/jprofiler/v/12.0/help_zh_CN/doc/main/methodCallRecording.html)

### 1. CPU 采样

许多传统的分析工具定时采样所有 CPU 的活动，以特定时间间隔或频率（例如，99 赫兹）收集当前指令地址（程序计数器）或整个堆栈回溯的快照。 这将给出正在运行的函数或堆栈跟踪的计数，从而可以计算出 CPU 周期花费在何处的合理估计。 在 Linux 上，采样模式下的 [perf](https://www.brendangregg.com/perf.html) 工具（例如 -F 99）会进行 CPU 定时采样。

考虑应用程序函数 `A()` 调用函数 `B()`，`B()` 进行的系统调用导致阻塞：

```
    CPU Sampling ----------------------------------------------->
     |  |  |  |  |  |  |                      |  |  |  |  |         
     A  A  A  A  B  B  B                      B  A  A  A  A         
    A(---------.                                .----------)        
               |                                |                   
               B(--------.                   .--)                   
                         |                   |         user-land    
   - - - - - - - - - - syscall - - - - - - - - - - - - - - - - -    
                         |                   |         kernel       
                         X     Off-CPU       |                      
                       block . . . . . interrupt                    
```

虽然这对于研究 `on-CPU` 问题非常有效，包括热代码路径和自适应互斥自旋，但它不会在应用程序处于阻塞并等待的 `off-CPU` 时收集数据。

### 2. 应用程序追踪

```
    App Tracing ------------------------------------------------>
    |          |                                |          |        
    A(         B(                               B)         A)       
                                                                    
    A(---------.                                .----------)        
               |                                |                   
               B(--------.                   .--)                   
                         |                   |         user-land    
   - - - - - - - - - - syscall - - - - - - - - - - - - - - - - -    
                         |                   |         kernel       
                         X     Off-CPU       |                      
                       block . . . . . interrupt                    
```



这会动态修改（`Instrumentation`）函数，以便在它们开始 `(` 和结束 `)` 时收集时间戳，因此可以计算在函数中花费的间。 如果时间戳包括已用时间和 CPU 时间（例如，使用 times(2) 或 getrusage(2)），那么还可以计算哪些函数在 CPU 上慢，哪些函数因为在 CPU 外被阻塞而慢 . 与采样不同，这些时间戳可以具有非常高的分辨率（纳秒）。

虽然可行，但缺点是您要么跟踪所有应用程序函数，这可能会对性能产生重大影响（并影响到你的测量），要么选择可能会阻塞的函数，但可能会遗漏。

### 3. Off-CPU 跟踪

我将在这小结一下，然后在接下来的部分对其进行更详细的解释。

```
    Off-CPU Tracing -------------------------------------------->
                         |                   |                   
                         B                   B                   
                         A                   A                   
    A(---------.                                .----------)        
               |                                |                   
               B(--------.                   .--)                   
                         |                   |         user-land    
   - - - - - - - - - - syscall - - - - - - - - - - - - - - - - -    
                         |                   |         kernel       
                         X     Off-CPU       |                      
                       block . . . . . interrupt                    
```

使用这种方法，只跟踪将线程切换到 CPU 之外（`off-CPU` ）的内核函数，以及时间戳和用户态堆栈。这侧重于 `off-CPU` 事件，不需跟踪应用程序的所有函数，也不需知道应用程序是什么。这种方法可用于任何阻塞事件，适用于任何应用程序：MySQL、Apache、Java 等。

**`Off-CPU` 跟踪**捕获应用程序的**所有等待事件**。 

本页后面，我将跟踪内核`off-CPU` 事件，并包括一些应用程序级别的**<u>检测</u>**来过滤掉==异步等待时间==（例如，等待工作的线程）。 与应用程序级**<u>检测</u>**不同，我不需要寻找所有可能阻塞 CPU 的地方； 我只需要确定应用程序处理工作期间，位于时间敏感的代码路径中（例如，在 MySQL 查询期间）同步的延迟。

`Off-CPU` 跟踪一直是我分析 `Off-CPU` 的主要方法。但也有抽样。

### 4. Off-CPU 取样

```
    Off-CPU Sampling ------------------------------------------->
                          |  |  |  |  |  |  |                       
                          O  O  O  O  O  O  O                       
    A(---------.                                .----------)        
               |                                |                   
               B(--------.                   .--)                   
                         |                   |         user-land    
   - - - - - - - - - - syscall - - - - - - - - - - - - - - - - -    
                         |                   |         kernel       
                         X     Off-CPU       |                      
                       block . . . . . interrupt                    
```

这种方法定时采样被阻塞线程的堆栈。也可以通过**挂墙时间（wall-time）分析器**来完成：无论线程处于 `on-CPU ` 还是 `off-CPU`，总是对所有线程进行采样。然后，可以过滤 wall-time 分析器的输出， 只输出 `off-CPU` 堆栈。

系统分析器很少使用 `off-CPU` 采样。**采样通常实现为 CPU 定时器的中断**，然后检查当前正在运行的中断进程：生成一个 `on-CPU` 采样文件。`off-CPU` 采样器必须以不同的方式工作：要么在每个应用程序线程中设置定时器来唤醒它们并捕获堆栈，要么让内核每隔一段时间遍历所有线程并捕获它们的堆栈。

## 开销

**警告**：使用 `off-CPU` 跟踪时，调度程序事件可能非常频繁——在极端情况下，每秒有数百万个事件——尽管跟踪器可能只会给每个事件增加少量开销，但是由于事件速率，开销累积起来将变得很显著。`Off-CPU` 采样也有开销问题，因为系统可能有数万个线程必须不断采样，这比 `on-CPU` 采样的开销高出几个数量级。

使用 `off-CPU` 分析，需要注意每一步的开销。将每个事件转储到用户空间，以进行后期处理的跟踪器每分钟创建  GB 级的跟踪数据，很容易令人望而却步。同时将数据写入文件系统和存储设备，进行后期处理，也会消耗更多的 CPU。由于**==在内核中进行摘要==**（如 Linux eBPF）的跟踪器可以减少开销，使得 `off-CPU` 分析变得切实可行，这就是它们为什么这么重要的原因。还要注意反馈循环：跟踪器跟踪由自己引起的事件。

> If I'm completely in the dark with a new scheduler tracer, I'll begin by tracing for one tenth of a second only (0.1s), and then ratchet it up from there, while closely measuring the impact on system CPU utilization, application request rates, and application latency. I'll also consider the rate of context switches (eg, measured via the "cs" column in vmstat), and be more careful on servers with higher rates.
>
> To give you some idea of the overheads, I tested an 8 CPU system running Linux 4.15, with a heavy MySQL load causing 102k context switches per second. The server was running at CPU saturation (0% idle) on purpose, so that any tracer overhead will cause a noticeable loss in application performance. I then compared off-CPU analysis via scheduler tracing with Linux perf and eBPF, which demonstrate different approaches: perf for event dumping, and eBPF for in-kernel summarizing:
>
> - Using perf to trace every scheduler event caused a 9% drop in throughput while tracing, with occasional 12% drops while the perf.data capture file was flushed to disk. That file ended up 224 Mbytes for 10 seconds of tracing. The file was then post processed by running perf script to do symbol translation, which cost a 13% performance drop (the loss of 1 CPU) for 35 seconds. You could summarize this by saying the 10 second perf trace cost 9-13% overhead for 45 seconds.
> - Using eBPF to count stacks in kernel context instead caused a 6% drop in throughput during the 10 second trace, which began with a 13% drop for 1 second as eBPF was initialized, and was followed by 6 seconds of post-processing (symbol resolution of the already-summarized stacks) costing a 13% drop. So a 10 second trace cost 6-13% overhead for 17 seconds. Much better.
>
> What happens when the trace duration is increased? For eBPF it's only capturing and translating unique stacks, which won't scale linearly with the trace duration. I tested this by increasing the trace from 10 to 60 seconds, which only increased eBPF post processing from 6 to 7 seconds. The same with perf increased its post processing from 35 seconds to 212 seconds, as it needed to process 6x the volume of data. To finish understanding this fully, it's worth noting that post processing is a user-level activity that can be tuned to interfere less with the production workload, such as by using different scheduler priorities. Imagine capping CPU at 10% (of one CPU) for this activity: the performance loss may then be negligible, and the eBPF post-processing stage may then take 70 seconds – not too bad. But the perf script time may then take 2120 seconds (35 minutes), which would stall an investigation. And perf's overhead isn't just CPU, it's also disk I/O.
>
> How does this MySQL example compare to production workloads? It was doing 102k context switches per second, which is relatively high: many production systems I see at the moment are in the 20-50k/s range. That would suggest that the overheads described here are about 2x higher than I would see on those production systems. However, the MySQL stack depth is relatively light, often only 20-40 frames, whereas production applications can exceed 100 frames. That matters as well, and may mean that my MySQL stack walking overheads are perhaps only half what I would see in production. So this may balance out for my production systems.
>

如果我完全使用新的调度程序跟踪器，我将开始仅跟踪十分之一秒（0.1 秒），然后从那里向上加长，同时密切测量对系统 CPU 利用率、应用程序请求速率和应用程序延迟的影响。我还将考虑上下文切换的速率（例如，通过 vmstat 中的"cs"列进行测量），并在具有较高速率的服务器上更加小心。

为了让您了解开销，我测试了运行 Linux 4.15 的 8 CPU 系统，大量 MySQL 负载导致 102k 个上下文交换/秒。服务器以 CPU 饱和度（0% 空闲）运行，因此任何跟踪开销都会导致应用程序性能明显损失。然后，我比较了通过调度程序跟踪进行 CPU 分析与 Linux perf 和 eBPF，它们演示了不同的方法：用于事件转储的 perf 和用于内核中的 eBPF 汇总：

- 使用 perf 跟踪每个调度程序事件导致跟踪时吞吐量下降 9%，在 perf.data 捕获文件刷新到磁盘时，吞吐量偶尔会下降 12%。该文件最终为 224 MB，用于 10 秒的跟踪。然后通过运行 perf 脚本进行符号转换对文件进行发布处理，这会花费 13% 的性能下降（丢失 1 个 CPU）35 秒。您可以总结这一点，说 10 秒 perf 跟踪花费 9-13% 开销 45 秒。
- 使用 eBPF 对内核上下文中的堆栈进行计数，在 10 秒跟踪期间导致吞吐量下降 6%，从初始化 eBPF 时 1 秒内的吞吐量下降 13%开始，随后是 6 秒的后处理（已汇总堆栈的符号分辨率），成本下降了 13%。因此，10 秒跟踪需要 6-13% 的开销 17 秒。

增加跟踪持续时间时会发生什么？对于 eBPF，它只捕获和转换唯一堆栈，不会随着跟踪持续时间线性扩展。我通过将跟踪从 10 秒增加到 60 秒来测试这一点，这仅将 eBPF 后处理从 6 秒增加到 7 秒。perf 将其后期处理从 35 秒增加到 212 秒，因为它需要处理 6 倍的数据量。为了完全了解这一点，值得注意的是，后期处理是一种用户级活动，可以调整以减少对生产工作负载的干扰，例如使用不同的计划程序优先级。想象一下，此活动的 CPU 上限为 10%：性能损失可能微不足道，eBPF 后处理阶段可能需要 70 秒 - 还不算太坏。但是，perf 脚本时间可能需要 2120 秒（35 分钟），这将阻碍调查。perf 的开销不仅仅是 CPU，它也开销磁盘 I/O。

此 MySQL 示例与生产工作负载相比如何？它当时在进行102k的上下文开关/秒，这是相对较高的：目前我看到的许多生产系统都在20-50k/s范围内。这表明，这里描述的开销比我在这些生产系统上看到的要高2倍。但是，MySQL 堆栈深度相对较轻，通常只有 20-40 帧，而生产应用程序可以超过 100 帧。这也很重要，而且可能意味着我的 MySQL 堆栈行走开销可能只有我在生产中看到的一半。因此，这可以平衡我的生产系统。

## Linux: perf, eBPF

> Off-CPU analysis is a generic approach that should work on any operating system. I'll demonstrate doing it on Linux using off-CPU tracing, then summarize other OSes in later sections.
>
> There are many tracers available on Linux for off-CPU analysis. I'll use [eBPF](https://www.brendangregg.com/ebpf.html) here, as it can easily do in-kernel summaries of stack traces and times. eBPF is part of the Linux kernel, and I'll use it via the [bcc](https://www.brendangregg.com/ebpf.html#bcc) frontend tools. These need at least Linux 4.8 for stack trace support.
>
> You may wonder how I did off-CPU analysis before eBPF. Lots of different ways, including completely different approaches for each blocking type: storage tracing for storage I/O, kernel statistics for scheduler latency, and so on. To actually do off-CPU analysis before, I've used SystemTap, and also [perf](https://www.brendangregg.com/perf.html) event logging – although that has higher overhead (I wrote about it in [perf_events Off-CPU Time Flame Graph](http://www.brendangregg.com/blog/2015-02-26/linux-perf-off-cpu-flame-graph.html)). At one point I wrote a simple wall-time kernel-stack profiler called [proc-profiler.pl](https://github.com/brendangregg/proc-profiler/blob/master/proc-profiler.pl), which sampled /proc/PID/stack for a given PID. It worked well enough. I'm not the first to hack up such a wall-time profiler either, see [poormansprofiler](http://poormansprofiler.org/) and Tanel Poder's [quick'n'dirty](https://blog.tanelpoder.com/2013/02/21/peeking-into-linux-kernel-land-using-proc-filesystem-for-quickndirty-troubleshooting/) troubleshooting.
>

Off-CPU 分析是一种通用方法，可在任何操作系统上工作。我将演示使用 Off-CPU 跟踪在 Linux 上执行该方法，然后在后两节中总结其他操作系统。

Linux 上有许多用于 Off-CPU 分析的跟踪器。我将在这里使用 eBPF，因为它可以很容易地执行堆栈跟踪和时间内核中的摘要。eBPF 是 Linux 内核的一部分，我通过 bcc 前端工具使用它。这些至少需要 Linux 4.8 来支持堆栈跟踪。

你可能想知道我在 eBPF 之前是如何进行 CPU 外分析的。许多不同的方法，包括每种阻塞类型的完全不同的方法：存储 I/O 的存储跟踪、调度程序延迟的内核统计信息等等。要实际执行 Off-CPU 分析之前，我曾使用过 SystemTap，也使用过 perf 事件日志记录 ， 尽管这具有更高的开销（我在 perf_events 非 CPU 时间火焰图中写过）。有一次，我写了一个简单的wall-time内核堆栈探查器proc-profiler.pl，它采样/proc/PID/堆栈给定的PID。它工作得很好。我也不是第一个破解这样的墙时间分析器， 看poormansprofiler和Tanel Poder's quick'n'dirty故障排除。

## Off-CPU Time

> This is the time that threads spent waiting off-CPU (blocked time), and not running on-CPU. It can be measured as totals across a duration (already provided by /proc statistics), or measured for each blocking event (usually requires a tracer).
>
> To start with, I'll show total off-CPU time from a tool that may already be familiar to you. The time(1) command. Eg, timing tar(1):

这是线程等待 Off-CPU （阻塞时间）而不是On-CPU 的时间。它可以作为持续时间（已由 /proc 统计信息提供）的总计进行测量，或测量每个阻塞事件（通常需要一个跟踪器）。

首先，我将展示您可能已经熟悉的工具的总关闭 CPU 时间。 The time(1) command. Eg, timing tar(1):

```bash
$ time tar cf archive.tar linux-4.15-rc2

real	0m50.798s
user	0m1.048s
sys	0m11.627s
```

> tar took about one minute to run, but the time command shows it only spent 1.0 seconds of user-mode CPU time, and 11.6 seconds of kernel-mode CPU time, out of a total 50.8 seconds of elapsed time. We are missing 38.2 seconds! That is the time the tar command was blocked off-CPU, no doubt doing storage I/O as part of its archive generation.
>
> To examine off-CPU time in more detail, either dynamic tracing of kernel scheduler functions or static tracing using the sched tracepoints can be used. The bcc/eBPF project includes cpudist that does this, developed by Sasha Goldshtein, which has a -O mode that measures off-CPU time. This requires Linux 4.4 or higher. Measuring tar's off-CPU time:

tar 运行大约一分钟，但时间命令显示，它只花了 1.0 秒的用户模式 CPU 时间，以及 11.6 秒的内核模式 CPU 时间，总共 50.8 秒的运行时间。我们错过了 38.2 秒！这是 tar 命令在 Off-CPU 的时间，毫无疑问，作为其存档生成一部分，执行存储 I/O。

为了更详细地检查 Off-CPU 时间，可以使用内核调度程序函数的动态跟踪或使用 sched 跟踪点的静态跟踪。bcc/eBPF 项目包括由 Sasha Goldshtein 开发的 cpudist，该项目具有测量 Off-CPU 时间的 -O 模式。这需要 Linux 4.4 或更高版本。Measuring tar's off-CPU time:

```bash
# /usr/share/bcc/tools/cpudist -O -p `pgrep -nx tar`
Tracing off-CPU time... Hit Ctrl-C to end.
^C
     usecs               : count     distribution
         0 -> 1          : 3        |                                        |
         2 -> 3          : 50       |                                        |
         4 -> 7          : 289      |                                        |
         8 -> 15         : 342      |                                        |
        16 -> 31         : 517      |                                        |
        32 -> 63         : 5862     |***                                     |
        64 -> 127        : 30135    |****************                        |
       128 -> 255        : 71618    |****************************************|
       256 -> 511        : 37862    |*********************                   |
       512 -> 1023       : 2351     |*                                       |
      1024 -> 2047       : 167      |                                        |
      2048 -> 4095       : 134      |                                        |
      4096 -> 8191       : 178      |                                        |
      8192 -> 16383      : 214      |                                        |
     16384 -> 32767      : 33       |                                        |
     32768 -> 65535      : 8        |                                        |
     65536 -> 131071     : 9        |                                        |
```

> This shows that most of the blocking events were between 64 and 511 microseconds, which is consistent with flash storage I/O latency (this is a flash-based system). The slowest blocking events, while tracing, reached the 65 to 131 millisecond second range (the last bucket in this histogram).
>
> What does this off-CPU time consist of? Everything from when a thread blocked to when it began running again, including scheduler delay.
>
> At the time of writing this, cpudist uses kprobes (kernel dynamic tracing) to instrument the finish_task_switch() kernel function. (It should use the sched tracepoint, for API stability reasons, but the first attempt wasn't successful and was [reverted](https://github.com/iovisor/bcc/commit/06d90d3d4b35815027b7b7a7fc48167d497d2de3#diff-8db0718fb1ee9a9dcbb8db1a14a146e8) for now.)
>
> The prototype for finish_task_switch() is:

这表明大多数阻塞事件在 64 到 511 微秒之间，这与闪存存储 I/O 延迟（这是基于闪存的系统）一致。跟踪时最慢的阻塞事件达到 65 到 131 毫秒的范围（此直方图中的最后一个存储桶）。

此 Off-CPU 关闭时间由什么组成？从线程阻塞到再次开始运行的所有内容，包括调度程序延迟。

在编写本文时，cpudist 使用 kprobes（内核动态跟踪）来检测  `finish_task_switch()` 内核函数。（出于 API 稳定性原因，它应该使用 sched 跟踪点，但第一次尝试未成功，现在已 [reverted](https://github.com/iovisor/bcc/commit/06d90d3d4b35815027b7b7a7fc48167d497d2de3#diff-8db0718fb1ee9a9dcbb8db1a14a146e8)。）

`finish_task_switch()` 的原型是：

```C
static struct rq *finish_task_switch(struct task_struct *prev)
```

> To give you an idea of how this tool works: The finish_task_switch() function is called in the context of the next-running thread. An eBPF program can instrument this function and argument using kprobes, fetch the current PID (via `bpf_get_current_pid_tgid()`), and also fetch a high resolution timestamp (bpf_ktime_get_ns()). This is all the information needed for the above summary, which uses an eBPF map to efficiently store the histogram buckets in kernel context. Here is the full source to [cpudist](https://github.com/iovisor/bcc/blob/master/tools/cpudist.py).
>
> eBPF is not the only tool on Linux for measuring off-CPU time. The [perf](https://www.brendangregg.com/perf.html) tool provides a "wait time" column in its [perf sched timehist](http://www.brendangregg.com/blog/2017-03-16/perf-sched.html) output, which excludes scheduler time as it's shown in the adjacent column separately. That output shows the wait time for each scheduler event, and costs more overhead to measure than the eBPF histogram summary.
>
> Measuring off-CPU times as a histogram is a little bit useful, but not a lot. What we really want to know is context – *why* are threads blocking and going off-CPU. This is the focus of off-CPU analysis.
>

为了让您了解此工具的工作原理：`finish_task_switch()`  函数在下一个运行线程的上下文中调用。eBPF 程序可以使用 `kprobes` 检测此函数和参数，获取当前 PID（通过 `bpf_get_current_pid_tgid()`），还可以获取高分辨率时间戳 （`bpf_ktime_get_ns()`）。这是上述摘要所需的全部信息，它使用 eBPF 映射在内核上下文中有效地存储直方图存储桶。这里是 [cpudist](https://github.com/iovisor/bcc/blob/master/tools/cpudist.py) 的完整来源。

eBPF 不是 Linux 上测量 Off-CPU 外时间的唯一工具。perf 工具在其 perf sched timehist 时间设置输出中提供 "wait time" 列，该列排除了计划程序时间，因为它分别显示在相邻列中。该输出显示每个调度程序事件的等待时间，并且与 eBPF 直方图摘要更需要测量的开销。

将 Off-CPU 时间作为直方图进行测量有点有用，但不是很多。我们真正想知道的是上下文 - 为什么线程会阻塞和 Off-CPU。这是 Off-CPU 分析的重点。

## Off-CPU Analysis

> Off-CPU analysis is the methodology of analyzing off-CPU time along with stack traces to identify the reason that threads were blocking. The off-CPU tracing analysis technique can be easy to implement due to this principle:
>
> > Application stack traces don't change while off-CPU.
>
> This means we only need to measure the stack trace once, either at the beginning or end of the off-CPU period. The end is usually easier, since you're recording the time interval then anyway. Here is tracing pseudocode for measuring off-CPU time with stack traces:

Off-CPU 分析是分析 Off-CPU 时间以及堆栈跟踪以确定线程阻塞原因的方法。由于以下原因，Off-CPU 跟踪分析技术很容易实现：

> off-CPU 时，应用程序堆栈跟踪不会更改。

这意味着我们只需要在 Off-CPU 周期的开始或结束时测量一次堆栈跟踪。通常测量结束更容易，因为你总是在记录时间间隔。以下是用于使用堆栈跟踪测量Off-CPU 时间的伪代码：

```
on context switch finish:
	sleeptime[prev_thread_id] = timestamp
	if !sleeptime[thread_id]
		return
	delta = timestamp - sleeptime[thread_id]
	totaltime[pid, execname, user stack, kernel stack] += delta
	sleeptime[thread_id] = 0

on tracer exit:
	for each key in totaltime:
		print key
		print totaltime[key]
```

Some notes on this: all measurements happen from one instrumentation point, the end of the context switch routine, which is in the context of the next thread (eg, the Linux finish_task_switch() function). That way, we can calculate the off-CPU duration at the same time as retrieving the context for that duration by simply fetching the current context (pid, execname, user stack, kernel stack), which tracers make easy.

This is what my offcputime bcc/eBPF program does, which needs at least Linux 4.8 to work. I'll demonstrate using bcc/eBPF offcputime to measure blocking stacks for the tar program. I'll restrict this to kernel stacks only to start with (-K):

```
# /usr/share/bcc/tools/offcputime -K -p `pgrep -nx tar`
Tracing off-CPU time (us) of PID 15342 by kernel stack... Hit Ctrl-C to end.
^C
[...]

    finish_task_switch
    __schedule
    schedule
    schedule_timeout
    __down
    down
    xfs_buf_lock
    _xfs_buf_find
    xfs_buf_get_map
    xfs_buf_read_map
    xfs_trans_read_buf_map
    xfs_da_read_buf
    xfs_dir3_block_read
    xfs_dir2_block_getdents
    xfs_readdir
    iterate_dir
    SyS_getdents
    entry_SYSCALL_64_fastpath
    -                tar (18235)
        203075

    finish_task_switch
    __schedule
    schedule
    schedule_timeout
    wait_for_completion
    xfs_buf_submit_wait
    xfs_buf_read_map
    xfs_trans_read_buf_map
    xfs_imap_to_bp
    xfs_iread
    xfs_iget
    xfs_lookup
    xfs_vn_lookup
    lookup_slow
    walk_component
    path_lookupat
    filename_lookup
    vfs_statx
    SYSC_newfstatat
    entry_SYSCALL_64_fastpath
    -                tar (18235)
        661626

    finish_task_switch
    __schedule
    schedule
    io_schedule
    generic_file_read_iter
    xfs_file_buffered_aio_read
    xfs_file_read_iter
    __vfs_read
    vfs_read
    SyS_read
    entry_SYSCALL_64_fastpath
    -                tar (18235)
        18413238
```



I've truncated the output to the last three stacks. The last, showing a total of 18.4 seconds of off-CPU time, is in the read syscall path ending up with io_schedule() – this is tar reading file contents, and blocking on disk I/O. The stack above it shows 662 milliseconds in a stat syscall, which also ends up waiting for storage I/O via xfs_buf_submit_wait(). The top stack, with a total of 203 milliseconds, appears to show tar blocking on locks while doing a getdents syscall (directory listing).

Interpreting these stack traces takes a little familiarity with the source code, which depends on how complex the application is and its language. The more you do this, the quicker you'll become, as you'll recognize the same functions and stacks.

I'll now include user-level stacks:

```
# /usr/share/bcc/tools/offcputime -p `pgrep -nx tar`
Tracing off-CPU time (us) of PID 18311 by user + kernel stack... Hit Ctrl-C to end.
[...]

    finish_task_switch
    __schedule
    schedule
    io_schedule
    generic_file_read_iter
    xfs_file_buffered_aio_read
    xfs_file_read_iter
    __vfs_read
    vfs_read
    SyS_read
    entry_SYSCALL_64_fastpath
    [unknown]
    -                tar.orig (30899)
        9125783
```



This didn't work: user-level stacks are just "[unknown]". The reason is that the default version of tar is compiled without frame pointers, and this version of bcc/eBPF needs them to walk stack traces. I wanted to show what this gotcha looks like in case you hit it as well.

I did fix tar's stacks (see Prerequisites earlier) to see what they looked like:

```
# /usr/share/bcc/tools/offcputime -p `pgrep -nx tar`
Tracing off-CPU time (us) of PID 18375 by user + kernel stack... Hit Ctrl-C to end.
[...]

    finish_task_switch
    __schedule
    schedule
    io_schedule
    generic_file_read_iter
    xfs_file_buffered_aio_read
    xfs_file_read_iter
    __vfs_read
    vfs_read
    SyS_read
    entry_SYSCALL_64_fastpath
    __read_nocancel
    dump_file0
    dump_file
    dump_dir0
    dump_dir
    dump_file0
    dump_file
    dump_dir0
    dump_dir
    dump_file0
    dump_file
    dump_dir0
    dump_dir
    dump_file0
    dump_file
    create_archive
    main
    __libc_start_main
    [unknown]
    -                tar (15113)
        426525
[...]
```



Ok, so it looks like tar has a recursive walk algorithm for the file system tree.

Those stack traces are great – it's showing why the application was blocking and waiting off-CPU, and how long for. This is exactly the sort of information I'm usually looking for. However, blocking stack traces aren't always so interesting, as sometimes you need to look for request-synchronous context.



## Request-Synchronous Context

Applications that wait for work, like web servers with pools of threads waiting on a socket, present a challenge for off-CPU analysis: often most of the blocking time will be in stacks waiting for work, rather than doing work. This floods the output with stacks that aren't very interesting.

As an example of this phenomenon, here are off-CPU stacks for a MySQL server process that is doing nothing. Zero requests per second:

```
# /usr/share/bcc/tools/offcputime -p `pgrep -nx mysqld`
Tracing off-CPU time (us) of PID 29887 by user + kernel stack... Hit Ctrl-C to end.
^C
[...]

  finish_task_switch
    __schedule
    schedule
    do_nanosleep
    hrtimer_nanosleep
    sys_nanosleep
    entry_SYSCALL_64_fastpath
    __GI___nanosleep
    srv_master_thread
    start_thread
    -                mysqld (29908)
        3000333

    finish_task_switch
    __schedule
    schedule
    futex_wait_queue_me
    futex_wait
    do_futex
    sys_futex
    entry_SYSCALL_64_fastpath
    pthread_cond_timedwait@@GLIBC_2.3.2
    os_event::wait_time_low(unsigned long, long)
    srv_error_monitor_thread
    start_thread
    -                mysqld (29906)
        3000342

    finish_task_switch
    __schedule
    schedule
    read_events
    do_io_getevents
    SyS_io_getevents
    entry_SYSCALL_64_fastpath
    [unknown]
    LinuxAIOHandler::poll(fil_node_t**, void**, IORequest*)
    os_aio_handler(unsigned long, fil_node_t**, void**, IORequest*)
    fil_aio_wait(unsigned long)
    io_handler_thread
    start_thread
    -                mysqld (29896)
        3500863
[...]
```

Various threads are polling for work and other background tasks. These background stacks can dominate the output, even for a busy MySQL server. What I'm usually looking for is off-CPU time during a database query or command. That's the time that matters – the time that's hurting the end customer. To find those in the output, I need to hunt around for stacks in query context.

For example, now from a busy MySQL server:

```
# /usr/share/bcc/tools/offcputime -p `pgrep -nx mysqld`
Tracing off-CPU time (us) of PID 29887 by user + kernel stack... Hit Ctrl-C to end.
^C
[...]

   finish_task_switch
    __schedule
    schedule
    io_schedule
    wait_on_page_bit_common
    __filemap_fdatawait_range
    file_write_and_wait_range
    ext4_sync_file
    do_fsync
    SyS_fsync
    entry_SYSCALL_64_fastpath
    fsync
    log_write_up_to(unsigned long, bool)
    trx_commit_complete_for_mysql(trx_t*)
    [unknown]
    ha_commit_low(THD*, bool, bool)
    TC_LOG_DUMMY::commit(THD*, bool)
    ha_commit_trans(THD*, bool, bool)
    trans_commit_stmt(THD*)
    mysql_execute_command(THD*, bool)
    mysql_parse(THD*, Parser_state*)
    dispatch_command(THD*, COM_DATA const*, enum_server_command)
    do_command(THD*)
    handle_connection
    pfs_spawn_thread
    start_thread
    -                mysqld (13735)
        1086119

[...]
```

This stack identifies some time (latency) during a query. The do_command() -> mysql_execute_command() code path is a give away. I know this because I'm familiar with the code from all parts of this stack: MySQL and kernel internals.

You can imagine writing a simple text post-processor, that plucked out the stacks of interest based on some application-specific pattern matching. And that might work fine. There's another way, which is a little more efficient, although also requires application specifics: extending the tracing program to also instrument application requests (the do_command() function, in this MySQL server example), and to then only record off-CPU time if it occurred during the application request. I've done it before, it can help.

## Caveats

The biggest caveat is the overhead of off-CPU analysis, as described earlier in the overhead section, followed by getting stack traces to work, which I summarized in the earlier Prerequisites section. There is also scheduler latency and involuntary context switches to be aware of, which I'll summarize here, and wakeup stacks which I'll discuss in a later section.

### Scheduler Latency

Something that's missing from these stacks is if the off-CPU time includes time spent waiting on a CPU run queue. This time is known as scheduler latency, run queue latency, or dispatcher queue latency. If the CPUs are running at saturation, then any time a thread blocks, it may endure additional time waiting its turn on a CPU after being woken up. That time will be included in the off-CPU time.

You can use extra trace events to tease apart off-CPU time into time blocked vs scheduler latency, but in practice, CPU saturation is pretty easy to spot, so you are unlikely to be spending much time studying off-CPU time when you have a known CPU saturation issue to deal with.

### Involuntary Context Switching

If you see user-level stack traces that don't make sense – that show no reason to be blocking and going off-CPU – it could be due to involuntary context switching. This often happens when the CPUs are saturated, and the kernel CPU scheduler gives threads turns on CPU, then kicks them off when they reach their time slice. The threads can be kicked off anytime, such as in the middle of a CPU heavy code-path, and the resulting off-CPU stack trace makes no sense.

Here is an example stack from offcputime that is likely an involuntary context switch:

```
# /usr/share/bcc/tools/offcputime -p `pgrep -nx mysqld`
Tracing off-CPU time (us) of PID 29887 by user + kernel stack... Hit Ctrl-C to end.
[...]

    finish_task_switch
    __schedule
    schedule
    exit_to_usermode_loop
    prepare_exit_to_usermode
    swapgs_restore_regs_and_return_to_usermode
    Item_func::type() const
    JOIN::make_join_plan()
    JOIN::optimize()
    st_select_lex::optimize(THD*)
    handle_query(THD*, LEX*, Query_result*, unsigned long long, unsigned long long)
    [unknown]
    mysql_execute_command(THD*, bool)
    Prepared_statement::execute(String*, bool)
    Prepared_statement::execute_loop(String*, bool, unsigned char*, unsigned char*)
    mysqld_stmt_execute(THD*, unsigned long, unsigned long, unsigned char*, unsigned long)
    dispatch_command(THD*, COM_DATA const*, enum_server_command)
    do_command(THD*)
    handle_connection
    pfs_spawn_thread
    start_thread
    -                mysqld (30022)
        13

[...]
```



It's not clear (based on the function names) why this thread blocked in Item_func::type(). I suspect this is an involuntary context switch, as the server was CPU saturated.

A workaround with offcputime is to filter on the TASK_UNINTERRUPTIBLE state (2):

```
# /usr/share/bcc/tools/offcputime -p `pgrep -nx mysqld` --state 2
```



On Linux, involuntary context switches occur for state TASK_RUNNING (0), whereas the blocking events we're usually interested in are in TASK_INTERRUPTIBLE (1) or TASK_UNINTERRUPTIBLE (2), which offcputime can match on using --state. I used this feature in my [Linux Load Averages: Solving the Mystery](http://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html) post.



## Flame Graphs

[Flame Graphs](https://www.brendangregg.com/flamegraphs.html) are a visualization of profiled stack traces, and are very useful for quickly comprehending the hundreds of pages of stack trace output that can be generated by off-CPU analysis. Yichun Zhang first created off-CPU time flame graphs, using SystemTap.

The offcputime tool has a -f option for emitting stack traces in "folded format": semi-colon delimited on one line, followed by the metric. This is the format that my [FlameGraph](https://github.com/brendangregg/FlameGraph) software takes as input.

For example, creating an off-CPU flame graph for mysqld:

```
# /usr/share/bcc/tools/offcputime -df -p `pgrep -nx mysqld` 30 > out.stacks
[...copy out.stacks to your local system if desired...]
# git clone https://github.com/brendangregg/FlameGraph
# cd FlameGraph
# ./flamegraph.pl --color=io --title="Off-CPU Time Flame Graph" --countname=us < out.stacks > out.svg
```

Then open out.svg in a web browser. It looks like this ([SVG](https://www.brendangregg.com/FlameGraphs/off-mysqld1.svg), [PNG](https://www.brendangregg.com/FlameGraphs/off-mysqld1.png)):

<p align="center">
<img src="https://www.brendangregg.com/FlameGraphs/off-mysqld1.svg"/>
</p>

Much better: this shows all off-CPU stack traces, with stack depth on the y-axis, and the width corresponds to the total time in each stack. The left-to-right ordering has no meaning. There are delimiter frames "-" between the kernel and user stacks, which were inserted by offcputime's -d option.

You can click to zoom. For example, click on the "do_command(THD*)" frame on the right bottom, to zoom into the blocking paths that happened during a query. You might want to generate flame graphs which only show these paths, which can be as simple as grep, since the folded format is one line per stack:

```
# grep do_command < out.stacks | ./flamegraph.pl --color=io --title="Off-CPU Time Flame Graph" --countname=us > out.svg
```

The resulting flame graph ([SVG](https://www.brendangregg.com/FlameGraphs/off-mysqld2.svg), [PNG](https://www.brendangregg.com/FlameGraphs/off-mysqld2.png)): 

<p align="center">
<img src="https://www.brendangregg.com/FlameGraphs/off-mysqld2.svg"/>
</p>

That looks great.

For more on off-CPU flame graphs, see my [Off-CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html) page.



## Wakeups

> Now that you know how to do `off-CPU` tracing, and generate flame graphs, you're starting to really look at these flame graphs and interpret them. You may find that many off-CPU stacks show the blocking path, but not the full reason it was blocked. That reason and code path is with another thread, the one that called a wakeup on a blocked thread. This happens all the time.
>
> I cover this topic in my [Off-CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html) page, along with two tools: wakeuptime and offwaketime, to measure wakeup stacks and also to associate them with off-CPU stacks.
>

现在，您已经知道如何进行Off-CPU 跟踪并生成火焰图，您开始真正查看这些火焰图并解释它们。您可能会发现许多Off-CPU 堆栈显示阻塞路径，但不包括阻止路径的全部原因。原因是代码路径在另一个线程，即调用阻塞线程上的唤醒线程。这种情况经常发生。

我在Off-CPU Flame Graphs中介绍此主题，以及两种工具：wakeuptime and offwaketime，以测量唤醒堆栈，并将其与Off-CPU 堆栈关联。

## Other Operating Systems

- **Solaris**: DTrace can be used for off-cpu tracing. Here is my original page on this: [Solaris Off-CPU Analysis](https://www.brendangregg.com/Solaris/offcpuanalysis.html).
- **FreeBSD**: Off-CPU analysis can be performed using procstat -ka for kernel-stack sampling, and DTrace for user- and kernel-stack tracing. I've created a separate page for this: [FreeBSD Off-CPU Analysis](https://www.brendangregg.com/FreeBSD/offcpuanalysis.html).



## 起源

大约在2005年，我在探索了 `DTrace sched provider` 及其 `sched::off-cpu` 探测器的用法之后，开始使用这种方法。我将其称为 `off-CPU` 分析和 `off-CPU` 时间度量（不是一个完美的名称：2005年在阿德莱德教授 DTrace 课程时，一位Sun 工程师说我不应该将其称为 `off-CPU`，因为 CPU 没有**关闭**）。《Solaris动态跟踪指南》中有一些示例，用于测量某些特定情况和进程状态下从 `sched::off-cpu` 到 `sched::on-cpu` 的时间。我没有过滤进程状态，而是捕获所有 `off-CPU` 事件，并包含堆栈采样来解释原因。我认为这种方法显而易见，所以我怀疑我不是第一个这样做的人，但我似乎是一段时间以来唯一真正推广这种方法的人。2007 年的 [DTracing Off-CPU Time](http://www.brendangregg.com/blog/2007-07-29/dtracing-off-cpu-time.html) 以及后来的帖子和演讲中，都写了它。

## 小结

`Off-CPU` 分析是一种有效的方法，用于定位线程被阻塞（延迟）以等待其他事件的原因。通过跟踪**内核调度器切换线程上下文**的函数，以相同的方式分析所有类型的 `off-CPU` 延迟，而无需跟踪多个来源。要查看 `off-CPU` 事件的上下文以了解其发生的原因，可以检查用户和内核堆栈采样。

借助 CPU 和 `Off-CPU` 分析，可以全面了解线程在那里消耗时间。 这些是互补的技术。

有关 `off-CPU` 分析的更多信息，请参阅 [Off-CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html) 和 [Hot/Cold Flame Graphs](https://www.brendangregg.com/FlameGraphs/hotcoldflamegraphs.html) 中的可视化。

## Updates

My first post on off-CPU analysis was in 2007: [DTracing Off-CPU Time](http://www.brendangregg.com/blog/2007-07-29/dtracing-off-cpu-time.html).

Updates from 2012:

- I included off-CPU analysis as a part of a Stack Profile Method in my [USENIX LISA 2012](https://www.slideshare.net/brendangregg/lisa12-methodologies/121) talk. The Stack Profile Method is the technique of collecting both CPU and off-CPU stacks, to study all the time spent by threads.

Updates from 2013:

- Yichun Zhang created off-CPU flame graphs using SystemTap and gave the talk [Introduction to off CPU Time Flame Graphs (PDF)](http://agentzh.org/misc/slides/off-cpu-flame-graphs.pdf).
- I included off-CPU flame graphs in my USENIX LISA 2013 talk [Blazing Performance with Flame Graphs](http://www.brendangregg.com/blog/2017-04-23/usenix-lisa-2013-flame-graphs.html).

Updates from 2015:

- I posted [FreeBSD Off-CPU Flame Graphs](http://www.brendangregg.com/blog/2015-03-12/freebsd-offcpu-flame-graphs.html) to explore the procstat -ka off-CPU sampling approach.
- I posted [Linux perf_events Off-CPU Time Flame Graph](http://www.brendangregg.com/blog/2015-02-26/linux-perf-off-cpu-flame-graph.html) to show how these could be created with perf event logging – if all you had was perf (use eBPF instead).

Updates from 2016:

- I posted [Linux eBPF Off-CPU Flame Graph](http://www.brendangregg.com/blog/2016-01-20/ebpf-offcpu-flame-graph.html) to show the value of this and help make the case for stack traces in eBPF (I had to hack them in for this proof of concept).
- I posted [Linux Wakeup and Off-Wake Profiling](http://www.brendangregg.com/blog/2016-02-01/linux-wakeup-offwake-profiling.html) to show wakeup stack analysis.
- I posted [Who is waking the waker? (Linux chain graph prototype](http://www.brendangregg.com/blog/2016-02-05/ebpf-chaingraph-prototype.html) as a proof of concept of walking a chain of wakeups.
- I described the importance of off-CPU analysis at the start of my Facebook Performance@Scale talk: [Linux BPF Superpowers](https://www.facebook.com/atscaleevents/videos/1693888610884236/) ([slides](http://www.slideshare.net/brendangregg/linux-bpf-superpowers)).

Updates from 2017:

- I used a few off-CPU flame graphs in my [Linux Load Averages: Solving the Mystery](http://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html) post.
- I summarized off-CPU, wakeup, off-wake, and chain graphs in my USENIX ATC 2017 talk on Flame Graphs: [youtube](https://youtu.be/D53T1Ejig1Q?t=50m16s), [slides](https://www.slideshare.net/brendangregg/usenix-atc-2017-visualizing-performance-with-flame-graphs/54).