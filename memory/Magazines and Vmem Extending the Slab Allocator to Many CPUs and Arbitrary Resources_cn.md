# 弹匣（Magazines） 和虚拟内存（Vmem）：将 Slab 分配器扩展到多个 CPU 和任意资源

**摘要**

slab 分配器 [Bonwick94] 提供高效的对象缓存，但有两个明显的限制：它的全局锁定不能扩展到多 CPU，分配器不能管理内核内存以外的资源。为了提供可扩展性，我们引入了一种称为**弹匣层**的**每处理器缓存方案**，它为任意数量的 CPU 提供线性扩展。为了支持更通用的资源分配，我们引入了一个新的虚拟内存分配器 *vmem*，它充当 slab 分配器的通用后备存储。Vmem本身就是一个完整的通用资源分配器，提供几个重要的新服务；它似乎也是第一个可以在常量时间内满足任意大小分配的资源分配器。在 LADDIS 和 SPECweb99 等系统级基准测试中，弹匣和 vmem 的性能提升超过了50%。

我们将这些技术从内核移植到用户上下文，发现由此产生的 *libumem* 优于当前同类最佳的用户级内存分配器。libumem 还提供了更丰富的编程模型，可用于管理其他用户级资源。

## 1.简介

## 2. Slab 分配器回顾

### 2.1. 对象缓存
程序通常缓存它们经常使用的对象以提高性能如果程序频繁分配和释放 `foo` 结构，它可能会使用高度优化的 `foo_alloc()` 和 `foo_free()` 例程来**避免 malloc 的开销**通常的策略是将 `foo` 对象缓存在一个简单的空闲列表中，以便大多数分配和释放只需要少数指令如果 `foo` 对象在被释放之前自然地返回到部分初始化状态，则可以进一步优化，在这种情况下，`foo_alloc()` 可以假设空闲列表上的对象已经部分初始化。

我们将上述技术称为**对象缓存**。传统的 `malloc` 实现无法提供对象缓存，因为 `malloc`/`free` 接口无类型，因此 slab 分配器引入了一个显式对象缓存编程模型，该模型具有创建和销毁对象缓存的接口，并且 从中分配和释放对象（见图 2.1）。
```c
// Figure 2.1: Slab Allocator Interface Summary
kmem_cache_t *kmem_cache_create(
    char *name,                    /* descriptive name for this cache */
    size_t size,                   /* size of the objects it manages */
    size_t align,                  /* minimum object alignment */ 
    int (*constructor)(void *obj, void *private, int kmflag),
    void (*destructor)(void *obj, void *private),
    void (*reclaim)(void *private), /* memory reclaim callback */
    void *private,                  /* argument to the above callbacks */
    vmem_t *vmp,                    /* vmem source for slab creation */
    int cflags);                    /* cache creation flags */

/** Creates a cache of objects, each of size size, aligned on an align boundary. name identifies the cache for statistics and debugging. constructor and destructor convert plain memory into objects and back again; constructor may fail if it needs to allocate memory but can’t. reclaim is a callback issued by the allocator when system−wide resources are running low (see §5.2). private is a parameter passed to the constructor, destructor and reclaim callbacks to support parameterized caches (e.g. a separate packet cache for each instance of a SCSI HBA driver). vmp is the *vmem source* that provides memory to create slabs (see §4 and §5.1). cflags indicates special cache properties. kmem_cache_create() returns an opaque pointer to the object cache (a.k.a. *kmem cache*).*/

void kmem_cache_destroy(kmem_cache_t *cp);
/*Destroys the cache and releases all associated resources. All allocated objects must have been freed.*/

void *kmem_cache_alloc(kmem_cache_t *cp, int kmflag);
/*Gets an object from the cache. The object will be in its constructed state. kmflag is either KM_SLEEP or KM_NOSLEEP, indicating whether it’s acceptable to wait for memory if none is currently available.*/

void kmem_cache_free(kmem_cache_t *cp, void *obj);
/*Returns an object to the cache. The object must be in its constructed state.*/
```
分配器和它的客户端合作维护对象部分初始化（或**构造的**）状态。**分配器保证对象在分配时处于这种状态；客户端保证在释放时它将处于这种状态**。因此，我们可以多次分配和释放一个对象，而不必每次都销毁和重新初始化它的锁、条件变量、引用计数和其他不变状态。

### 2.2. Slabs
**slab** 是一页或多页虚拟连续的内存，分为大小相等的块，引用计数指示当前分配了多少块为了创建新对象，分配器创建一个 slab，将 *constructor* 应用于每个块，并将生成的对象添加到缓存中如果系统内存不足，分配器可以通过将 *destructor* 应用于每个对象并将内存返回给 VM 系统来回收任何引用计数为零的 slab一旦填充了缓存，分配和释放就会非常快：它们只是将对象移入或移出空闲列表并更新其 slab 引用计数。

## 3. 弹匣（Magazines）

>“在 slab 算法中添加 per-CPU 的缓存**将提供一个优秀的分配器**。”
>
> Uresh Vahalia， *UNIX内部结构：新前沿*

原始 slab 分配器的最大限制是它缺乏多处理器可扩展性。要分配对象，分配器必须获取保护缓存 slab 列表的锁，从而串行化所有分配。为了允许所有 CPU 并行分配，我们需要某种形式的 per-CPU 缓存。

我们的基本方法是为每个 CPU 提供一个 M 元素的对象缓存，称为弹匣（**magazine**），类似于自动武器。在 CPU 需要**重新加载**之前，每个 CPU 的弹匣可以满足 M 个分配——也就是说，将其空弹匣换成满弹匣。CPU 在从其弹匣中分配时不访问任何全局数据，因此我们可以通过增加弹匣大小 (M) 来任意增加可扩展性。

在本节中，我们将介绍弹匣层是如何工作的，以及它在实践中的表现。图 3（下图）说明了关键概念。

![](./magazine/f3.png)

### 3.1 概述

**[弹匣](https://www.zhihu.com/question/57084396)**是一个 M 元素的数组，包含指向对象^1^的指针，其计数为当前数组中**轮数**（有效指针）的数量。从概念上讲，**弹匣**就像一个堆栈。要从**弹匣**中分配一个对象，我们弹出它的顶部元素：

> ^1^我们使用对象指针数组，而不是在空闲列表中将对象链接在一起，原因有二：首先，空闲列表链接会覆盖对象的构造状态； 其次，我们计划使用 slab 分配器来管理任意资源，因此我们不能假设我们正在管理的对象由可写内存支持。

```
obj = magazine[--rounds];
```
要将一个对象释放到弹匣中，我们将它推到顶部:

```
magazine[rounds++] = obj;
```

我们使用弹匣为每个对象缓存提供一个小的每 CPU 对象供应。每个 CPU 都有自己**加载的弹匣**，因此事务（分配和释放）可以在所有 CPU 上并行进行。

有趣的问题是，当我们想要分配一个对象时，加载的弹匣是空的（或者当我们想要释放一个对象时，弹匣是满的）该怎么办。我们不能直接进入 slab 层，因为长时间的分配每次都会在 CPU 层中<u>==丢失==</u>，破坏可扩展性。因此，每个对象缓存都保存一个全局弹匣库，即**仓库**（depot），以补充其 CPU 层。我们将 CPU 和 depot 层统称为**弹匣层**。

对于 M 轮弹匣，我们直觉上预计 CPU 层的未命中率最多为 1/M，但实际上，两次分配紧接着两次释放的紧密循环可能会导致抖动，**无论 M** 如何，一半的事务都会访问全局锁定的仓库，如下图 3.1a 所示。

![](./magazine/f31a.png)

我们通过在 CPU 层中保留**先前加载的弹匣**来解决这个问题，如（上一页）图 3 所示。如果加载的弹匣不能满足事务，但前一个弹匣可以，我们将**加载的**与**前一个**交换，然后重试。如果两个弹匣都不能满足事务，<u>我们将 **previous** 返回到仓库，将 **loaded** 移动为到 **previous**，然后从仓库加载新弹匣</u>。

关键的观察是，加载新弹匣的唯一原因是用空的替换满的弹匣，或反之，所以我们知道每次重新加载后，CPU 要么有一个满的**已加载的弹匣**和**上一个空的弹匣**，或反之。所以在 CPU 必须再次访问存仓库之前，基于本地弹匣，CPU 可以满足至少 M 次分配**和**至少 M 次完全释放。无论工作负载如何，因此 CPU 层最坏情况下的未命中率以 1/M 为界。

在具有高分配率的短期对象的常见情况下，该方案有两个性能优势。首先，同一个 CPU 上平衡的 **alloc/free pair** 几乎都可以由加载的弹匣来满足； 因此我们可以预期实际未命中率甚至低于 1/M。其次，弹匣**后进先出**的性质意味着我们倾向于一遍又一遍地重复使用相同的对象。这在硬件中是有利的，因为 CPU 已经拥有最近修改的内存的**缓存线**。

图 3.1b（下一页）用伪代码总结了弹匣的总体算法。图 3.1c 显示了热路径的实际代码（即击中装载的弹匣），以说明需要做的工作有多么少。

> **图3.1b：弹匣算法**通过弹匣层的分配和释放路径几乎完全对称，如下所示。唯一的不对称性是释放路径负责用空弹匣填充仓库，如§3.3所述。
>
> ```
> Alloc:
> if (the CPU's loaded magazine isn't empty)
>   pop the top object and return it;
> 
> if (the CPU's previous magazine is full)
>   exchange loaded with previous,
>   goto Alloc;
> 
> if (the depot has any full magazines)
>   return previous to depot,
>   move loaded to previous,
>   load the full magazine,
>   goto Alloc;
> 
> 
> 
> allocate an object from the slab layer,
>   apply its constructor, and return it;
> ```
>
> ```c
> Free:
> if (the CPU's loaded magazine isn't full)
> push the object on top and return;
> 
> if (the CPU's previous magazine is empty)
> exchange loaded with previous,
> goto Free;
> 
> if (the depot has any empty magazines)
> return previous to depot,
> move loaded to previous,
> load the empty magazine,
> goto Free;
> 
> if (an empty magazine can be allocated)
> put it in the depot and goto Free;
> 
> apply the object's destructor
> and return it to the slab layer
> ```
>
> **Figure 3.1c: The Hot Path in the Magazine Layer**
>
> ``` c++
> void *
> kmem_cache_alloc(kmem_cache_t *cp, int kmflag)
> {
>  kmem_cpu_cache_t *ccp = &cp->cache_cpu[CPU->cpu_id];
> 
>  mutex_enter(&ccp->cc_lock);
>  if (ccp->cc_rounds > 0) {
>      kmem_magazine_t *mp = ccp->cc_loaded;
>      void *obj = mp->mag_round[--ccp->cc_rounds];
>      mutex_exit(&ccp->cc_lock);
>      return (obj);
>  }
>  //...
> }
> /*-------------------------------------*/
> void
> kmem_cache_free(kmem_cache_t *cp, void *obj)
> {
>  kmem_cpu_cache_t *ccp = &cp->cache_cpu[CPU->cpu_id];
> 
>  mutex_enter(&ccp->cc_lock);
>  if (ccp->cc_rounds < ccp->cc_magsize) {
>      kmem_magazine_t *mp = ccp->cc_loaded;
>      mp->mag_round[ccp->cc_rounds++] = obj;
>      mutex_exit(&ccp->cc_lock);
>      return;
>  }
>  //...    
> }
> ```

### 3.2. 对象构建

原始的 slab 分配器在创建 slab 时应用构造函数。对于构造函数分配额外内存的对象，这可能是一种浪费。举一个极端的例子，假设一个 8 字节对象的构造函数为其附加了一个 1K 的缓冲区。假设 8K 页，一个 slab 将包含大约 1000 个对象，这些对象在构建后将消耗 1MB 的内存。如果这些对象中只有少数被分配，那么这 1MB 中的大部分都将被浪费。

我们通过将对象构造移至弹匣层并在 slab 层中仅保留原始缓冲区来解决此问题。现在，当一个缓冲区从 slab 层移动到弹匣层时，它变成一个对象（应用了它的构造函数），而当它从弹匣层向下移动回 slab  层时，则会成为一个原始缓冲区（应用了析构函数）。

### 3.3. 填充弹匣层
我们已经描述了弹匣层在填充后如何工作，但它是如何**填充**弹匣呢？

这里有两个截然不同的问题：我们必须分配对象，我们必须分配弹匣来容纳它们。

- **对象分配**。在分配路径中，如果仓库没有满的弹匣，我们从 slab 层分配一个对象并构造它。
- **弹匣分配**。在空闲路径中，如果仓库没有空弹匣，我们分配一个。

我们从不显式地分配完整的弹匣，因为这不是必需的：空弹匣最终会被免费填充，因此创建空弹匣，并让完整的弹匣作为正常分配/释放调用的副作用出现就足够了。

就像其他事情一样，我们从对象缓存中分配弹匣本身（即指针数组）； 不需要特殊的弹匣分配器^2^。

> ^2^请注意，如果我们在分配路径中分配了完整的弹匣，当我们第一次尝试为其中一个弹匣缓存分配弹匣时，这将导致无限递归。在空闲路径中分配空弹匣不存在这样的问题。

### 3.4. 动态调整弹匣大小

到目前为止，我们已经讨论了 M-元素的弹匣，但没有具体说明 M 是如何确定的。我们已经观察到，通过增加 M，我们可以使 CPU 层的未命中率尽可能低，但使 M 大于必要值会浪费内存。因此，我们寻求提供线性可伸缩性的最小 M 值。

我们没有选择一些**神奇的价值**，而是动态调整**弹匣层**。我们以较小的 M 值启动每个对象缓存，并观察仓库锁的争用率。我们通过在仓库锁上使用非阻塞的 `trylock` 原语来做到这一点； 如果失败，我们使用普通的**阻塞锁原语**并增加一个争用计数。如果争用率超过固定阈值，我们会增加缓存的弹匣大小。<u>我们强制执行最大弹匣大小，以确保此反馈循环不会失控</u>，但实际上该算法在所有设备上，从台式机到 64-CPU 的 Starfires，都表现得非常好。该算法通常在加载几分钟后稳定，具有合理的弹匣尺寸和小于每秒一次的仓库锁定争用率。

### 3.5. 保护每个 CPU 状态

对象缓存的 CPU 层包含每个 CPU 的状态，必须按 CPU 分别锁定或禁用中断来保护。我们选择按 CPU 分别锁定有几个原因：

- **编程模型**。某些操作，例如更改缓存的弹匣大小，需要分配器修改每个 CPU 的状态。如果 CPU 层受锁保护，这就很简单了。

- **实时**。禁用中断会增加调度延迟（因为它会禁用抢占），这在像 Solaris [Khanna92] 这样的实时操作系统中是不可接受的。

- **性能**。在大多数现代处理器上，获取无竞争锁比修改处理器中断级别的成本更低。

### 3.6. 硬件缓存效果

即使是 ==CPU 独立的算法==，如果遇到**错误共享**（当多个 CPU 修改逻辑上不相关的数据，而这些数据恰好位于同一条物理缓存线上时，就会争用缓存线所有权），则它们也无法扩展。我们小心地填充和对齐弹匣层每个 CPU 的数据结构，以便每个都有自己的缓存行。我们发现这样做对于现代硬件上的线性可伸缩性相当**关键**。

分配器还可以通过将小于缓存行的对象分配给多个 CPU [Berger00] 来**诱导**错误共享。但是，我们在实践中并没有发现这是一个问题，因为大多数内核数据结构都比缓存线大。

### 3.7. 使用仓库作为工作集

当系统处于稳定状态时，分配和释放必须大致平衡（因为内存使用大致恒定）。内存消耗在固定时间段内的变化定义了一种工作集的形式[Denning68]；具体来说，它定义了仓库手头必须有多少弹匣，==以保持分配器主要在其高性能弹匣层之外工作==。例如，如果仓库**<u>完整</u>**的弹匣列表，给定时间段内在 37 到 47 个弹匣之间变化，则工作集为 10 个弹匣； 其他 37 个符合回收条件。

仓库持续跟踪其已满和空弹匣列表的工作集大小，但除非内存不足，否则不会实际释放多余的弹匣。
### 3.8. 微基准性能

**==MT-hot==** 内存分配器的两个关键指标是延迟和**可扩展性**。**延迟**的测量是在紧密循环内，每对分配/释放的平均时间。我们通过在 333MHz 16-CPU Starfire 上运行延迟测试的多个实例来测量可扩展性。

延迟测试表明，**由于热路径非常简单**（见图 3.1c），弹匣层甚至提高了单个 CPU 的性能（每个分配/空闲对 356ns，而原始 slab 分配器为 743ns），实际上，因为锁定成本强加了 186ns 的下限，延迟几乎没有进一步改善的空间。

随着线程数量的增加，弹匣层表现出完美的线性缩放，如下图所示。在没有弹匣层的情况下，由于越来越病态的锁争用，增加线程，吞吐量实际上**更低**。有 16 个线程（所有 16 个 CPU 都忙）弹匣层提供比单个 CPU 高 16 倍的吞吐量（比原始分配器高 340 倍的吞吐量），，延迟同样为 356ns。
![](./magazine/f38.png)

### 3.9. 系统层性能

我们在有和没有弹匣层的情况下运行了几个系统级基准测试，以评估弹匣层的有效性^3^。使用弹匣时，系统一致更快，在（如网络 I/O这类）分配器密集型工作负载方面改进最大。

> ^3^ 不幸的是，我们无法与其他内核内存分配器进行直接比较，因为 Solaris 内核广泛使用了对象缓存接口，这在其他分配器中根本不可用。然而，我们将在第 6 节中提供与同类最佳用户级分配器的直接比较。

#### 3.9.1 SPECweb99
我们在 8 CPU E4500 上运行了行业标准 SPECweb99 Web 服务器基准测试 [SPEC01]。弹匣层的性能超过**两倍**，同时连接从 995 增加到 2037。收益如此巨大，因为每个网络数据包都来自分配器。

#### 3.9.2 TPC-C
我们在 8-CPU E6000 上运行行业标准 TPC-C 数据库基准测试 [TPC01]。弹匣提高了 7% 的性能。这里的增益比 SPECweb99 小得多，因为 TPC-C 对内核内存分配器的要求不是很高。

##### 3.9.3 Kenbus
我们在 24-CPU E6000 上运行了 Kenbus，它是目前正在开发的 SPEC SMT（**S**ystem **M**ulti**−T**asking）基准测试 [SPEC01] 的前身。弹匣层将峰值吞吐量提高了 13%，并提高了系统在负载增加时**维持**峰值吞吐量的能力。在最大测试负载（6000 个用户）下，弹匣层将系统吞吐量提高了 23%。
![](./magazine/f393.png)

### 3.10. 总结
弹匣层提供高效的对象缓存，具有非常低的延迟和线性扩展到任意数量的CPU。我们在 slab 分配器的上下文中讨论了弹匣层，但实际上算法是完全通用的。弹匣层可以添加到**任何内存分配器**以使其可扩展。

## 4. Vmem

slab 分配器依赖于两个底层系统服系统服务来创建 slab：**虚拟地址分配器**提供内核虚拟地址，**VM 例程**为这些地址分配物理页面，并建立虚拟到物理的转换。

令人难以置信的是，我们发现我们最大的系统的可扩展性受到旧虚拟地址分配器的限制。随着时间的推移，它往往会严重地碎片化地址空间，其延迟与碎片数量成线性关系，而且整个过程都是单线程的。

虚拟地址分配只是更普遍的**资源分配**问题的一个例子。就我们的目的而言，**资源**是指可以用一组整数描述的任何东西。例如，虚拟地址是 64 位整数的子集； 进程 ID 是整数 [0, 30000] 的子集； [**次要设备号**](https://zhuanlan.zhihu.com/p/446439925)是 32 位整数的子集。

资源分配（基于上面描述的意义）是每个操作系统都必须解决的一个基本问题，但令人惊讶的是，在文献中却没有。对于内存分配器 40 年的研究似乎从未应用于资源分配器。Linux、所有 BSD 内核和 Solaris 7 或更早版本的资源分配器都使用线性时间算法。

在本节中，我们描述了一个新的通用资源分配器，**vmem**，它提供有保证的常量时间性能和低碎片。Vmem 似乎是第一个可以做到这一点的资源分配器。

### 4.1. 背景

几乎所有版本的 Unix 都有一个名为 `rmalloc()` [Vahalia96] 的**资源映射分配器**。资源映射可以是任何整数集，但它通常是地址范围，如 [0xe0000000, 0xf0000000)。接口很简单：`rmalloc(map, size)` 从 `map` 中分配指定大小的**段**，然后 `rmfree(map, size, addr)` 将其返回。

Linux 的 **resource allocator** 和 BSD 的 **extent allocator** 提供大致相同的服务。这**三者**在设计和实现上都存在严重缺陷：

- **线性时间性能**。所有三个分配器都维护一个**空闲段**列表，按地址顺序排序，以便分配器可以检测何时可以**合并**：如果段 [a, b) 和 [b, c) 都是空闲的，则可以将它们合并为一个空闲段 [a, c) 以减少碎片。分配代码执行线性搜索，以找到足够大的段以满足分配。释放代码使用插入排序（也是一种线性算法）将段返回到空闲段列表。一旦资源变得碎片化，分配或释放一个段可能需要几毫秒。

- **实现曝露**。资源分配器需要数据结构来保存有关其空闲段的信息。以不同的方式下，这三个分配器都使这**成为您的问题**：

  - `rmalloc()` 要求资源映射的创建者在创建映射创建时，指定空闲段的最大可能数量。如果映射变得更加碎片化，分配器会丢弃 `rmfree()` 中的资源，因为它无处可放（！）。

  - Linux 将负担放在它的**客户**上，为每个分配提供一个**段结构**，以保存分配器的内部数据（！）。

  - BSD 动态分配段结构，但这样做会产生一种尴尬的失败模式：如果 `extent_free()` 无法分配段结构，则会失败。与一个不让你归还东西的分配器打交道是很困难的。

我们得出结论，**是时候抛弃石器**，用现代技术来解决这个问题了。

### 4.2. 目标

我们认为一个好的资源分配器应该具备以下特性：

- 一个强大的接口，可以清晰地表达最常见的资源分配问题。
- 常数时间性能，**与请求大小和碎片程度无关**。
- 线性可扩展，可线性扩展到任意数量的 CPU。
- 低碎片，即使操作系统全速运行**多年**。

我们将从讨论接口注意事项开始，然后深入到实现细节。

### 4.3. 接口说明

vmem 接口做三件基本的事情：创建和销毁描述资源的 **arenas**；分配和释放资源；以及<u>允许 **arenas** 动态地**导入**新资源</u>。本节描述关键概念及其背后的基本原理。图 4.3（下一页）提供了完整的 vmem 接口规范。

#### 4.3.1 创建 Arenas

==我们首先需要是能够定义一个资源集合==，==或称为 **arena**==。==<u>**Arena** 只是一组整数</u>==。Vmem arena 通常表示虚拟内存地址（因此得名 *vmem*），但实际上，它们可以表示任何整数资源，从虚拟地址到次要设备号再到进程 ID。

Arena 中的整数通常可以描述为单个连续范围或 **span**，例如 [100, 500)，因此我们将此**初始范围**指定给 `vmem_create()`。对于不连续的资源，我们可以使用 `vmem_add()` 一次一个 **span** 将 arena 拼凑在一起。

- **例子**。要创建一个 arena 来表示范围 [100, 500) 中的整数，我们可以这样：

   `foo = vmem_create(“foo”, 100, 400, ...);`

   （注意：100 是开始，400 是大小）。如果我们希望 `foo` 也代表整数 [600, 800)，我们可以使用 `vmem_add()` 添加范围 [600, 800)：
  
   `vmem_add(foo, 600, 200, VM_SLEEP);`

`vmem_create()` 指定 arena 的**主要分配单位**，或称为 **quantum**，通常为 1（对于进程 ID 等单个整数）或 `PAGESIZE`（对于虚拟地址）。Vmem 将所有大小四舍五入为  **quantum** 倍数，并保证  **quantum** 对齐分配。

#### 4.3.2 资源分配和释放

分配和释放资源的主要接口很简单：`vmem_alloc(vmp, size, vmflag)` 从 `vmp` 指向的 arena 中分配**一段大小为 size 的字节**，然后 `vmem_free(vmp, addr, size)` 将其返回。

我们还提供了一个 `vmem_xalloc()` 接口，可以指定常见的**分配约束**：**对齐**、**相位**（想对对齐地址的偏移量）、**地址范围**和**边界交叉限制**（例如**不要跨越页面边界**）。`vmem_xalloc()` 对于内核 DMA 代码之类的东西很有用，它使用相位和对齐约束分配内核虚拟地址，**以确保正确的缓存着色**。

- **例子**。要分配一个 20 字节的段，其地址距 64 字节边界 8 字节，并且位于 [200, 300) 范围内，我们可以：

  `addr = vmem_xalloc(foo, 20, 64, 8, 0, 200, 300, VM_SLEEP);`

  在此示例中，addr 将为 262：它距 64 字节边界 8 个字节（262 mod 64 = 8），段 [262, 282) 位于 [200, 300) 内。

每个 `vmem_[x]alloc()` 都可以通过其 `vmflag` 参数指定三种**分配策略**之一：

- **VM_BESTFIT**。指示 vmem 使用能够满足分配的最小空闲段。该策略倾向于最大限度地减少非常小的、宝贵资源的碎片化。
- **VM_INSTANTFIT**。指示 vmem 在保证常量时间内提供最接近的 best-fit。这是默认的分配策略。
- **VM_NEXTFIT**。指示 vmem 使用先前分配的空闲段之后的下一个空闲段。这对于进程 ID 之类的东西很有用，我们希望在重用它们之前循环遍历所有 ID。

我们还提供了一个 ==arena 范围的分配策略==，称为 **quantum  缓存**。这里的想法是，大多数分配只针对几个 **quanta** （例如，从堆上分配一到两页或分配一个次要设备号），因此我们按 **quantum** 的倍数使用高性能缓存，最高可达 `qcache_max`，在 `vmem_create()` 中指定。我们显式指定缓存阈值，以便每个 arena  都可以为其管理的资源请求适当的缓存量。Quantum 缓存为最常见的分配大小提供**完美匹配**、极低的延迟和线性可扩展性（§4.4.4）。

#### 4.3.3 从另一个 Arena 导入

Vmem 允许一个 arena  从另一个 Arena **导入**它的资源。`vmem_create()` 指定**源 arena**，以及分配和释放该源的函数。Arena 根据需要导入新的 span，并在所有段都被释放后归还它们。

导入的强大之处在于导入函数的**副作用**，最好通过示例来理解。在 Solaris 中，函数 `segkmem_alloc()` 调用 `vmem_alloc()` 以获取虚拟地址，然后为其分配物理页面。因此，我们可以通过简单地使用 `segkmem_alloc()` 和 `segkmem_free()` 从虚拟地址的 **arena** 导入，来创建映射页面的 **arena**。附录 A 说明了如何使用 vmem 的导入机制基于简单的构造来创建复杂的资源。

```c
/* Figure 4.3: Vmem Interface Summary */
vmem_t *vmem_create(
    char *name,                              /* descriptive name */
    void *base,                              /* start of initial span */
    size_t size,                             /* size of initial span */
    size_t quantum,                          /* unit of currency */
    void *(*afunc)(vmem_t *, size_t, int),   /* import alloc function */ 
    void (*ffunc)(vmem_t *, void *, size_t), /* import free function */ 
    vmem_t *source,                          /* import source arena */
    size_t qcache_max,                       /* maximum size to cache */
    int vmflag);                             /* VM_SLEEP or VM_NOSLEEP */
/** 创建一个名为 name 的 vmem arena，其初始范围为 [base, base + size)。arena的基础分配单位是 quantum，所以 vmem_alloc() 保证了 quantum 对齐。arena 可以通过在 source 上调用 afunc 来导入新的 span，并且可以通过在 source 上调用 ffunc 来返回这些 span。小分配很常见，因此 arena 为每个整数倍的 quantum 提供高性能缓存，直到 qcache_max。vmflag 是 VM_SLEEP 或 VM_NOSLEEP 取决于调用者是否愿意等待内存来创建 arena。vmem_create() 返回一个指向 arena 的不透明指针。*/

void vmem_destroy(vmem_t *vmp);
/** 销毁 vmp 指向的 arena.*/

void *vmem_alloc(vmem_t *vmp, size_t size, int vmflag);
/** 从 vmp 分配 size 字节。成功返回分配的地址，失败返回 NULL。仅当 vmflag 指定 VM_NOSLEEP 且当前没有可用资源时，vmem_alloc() 才会失败。vmflag 还可以指定分配策略（VM_BESTFIT、VM_INSTANTFIT 或 VM_NEXTFIT），如 §4.3.2 中所述。如果没有指定策略，则默认为 VM_INSTANTFIT，它保证在常量时间内提供了一个很好的最佳匹配近似。*/

void vmem_free(vmem_t *vmp, void *addr, size_t size);
/** Frees size bytes at addr to arena vmp.*/

void *vmem_xalloc(vmem_t *vmp, size_t size, size_t align, size_t phase, 
                  size_t nocross, void *minaddr, void *maxaddr, int vmflag);
/** Allocates size bytes at offset phase from an align boundary such that the resulting segment [addr, addr + size) is a subset of [minaddr, maxaddr) that does not straddle a nocross− aligned boundary. vmflag is as above. One performance caveat: if either minaddr or maxaddr is non−NULL, vmem may not be able to satisfy the allocation in constant time. If allocations within a given [minaddr, maxaddr) range are common it is more efficient to declare that range to be its own arena and use unconstrained allocations on the new arena.*/
void vmem_xfree(vmem_t *vmp, void *addr, size_t size);
/** Frees size bytes at addr, where addr was a constrained allocation. vmem_xfree() must be used if the original allocation was a vmem_xalloc() because both routines bypass the quantum caches.*/

void *vmem_add(vmem_t *vmp, void *addr, size_t size, int vmflag);
/** Adds the span [addr, addr + size) to arena vmp. Returns addr on success, NULL on failure. vmem_add() will fail only if vmflag is VM_NOSLEEP and no resources are currently available.*/
```
### 4.4. Vmem 实现
在本节中，我们将描述 vmem 的实际工作原理。图 4.4 展示了 arena 的整体结构。

#### 4.4.1 跟踪段
> “显然，很少有研究人员意识到 Knuth 发明边界标签的全部意义。”
>
> Paul R. Wilson et. al. in [Wilson95]

`malloc()` 的大多数实现都会为每个缓冲区预留少量空间，用于为分配器保存信息。这些**边界标签**由 Knuth 于 1962 年发明 [Knuth73]，解决了两个主要问题：

- 使 `free()` 可以轻松确定缓冲区的大小，因为 `malloc()` 可以将大小存储在边界标签中。
- 使合并变得简单。边界标签按地址顺序将所有段链接在一起，因此 `free()` 可以简单地查看两个方向，如果其中一个邻居是空闲的，则合并。

不幸的是，资源分配器不能使用传统的边界标签，因为它们管理的资源可能不是内存（因此可能无法保存信息）。在 vmem 中，我们通过使用**外部边界标签**来解决这个问题。对于 arena 中的每个**段**，我们分配一个边界标签来管理它，如下图 4.4 所示。（有关我们如何分配边界标签本身的说明，请参阅附录 A。）我们很快就会看到外部边界标签可以实现常量时间性能。

<p align="center">
<B>Figure 4.4: Vmem Arena 的结构</B> vmem_alloc() 的分配基于 size 分配：小的分配路由到 quantum 缓存，大的分配路由到段列表。在这个图中我们描绘了一个 1 页的 quantum 和 5 页 qcache_max 的 arena 。请注意，严格来说，<B>段列表</B>是表示<B>段的边界标签列表</B>（下面的<B>BT</B>）。已分配段的边界标签（白色）也链接到已分配段哈希表中，空闲段的边界标签（灰色）链接到大小隔离的空闲列表（未显示）中。<br>
<img src="./magazine/f44.png"/>
</p>


#### 4.4.2 分配和释放段

每个 arena  都有一个**段列表**，按地址顺序链接其所有段，如图 4.4 所示。每个段要么属于空闲列表，要么属于已分配段的哈希链，如下所述。（Arena  的段列表还包括 **span 标记**以跟踪 span 边界，因此我们可以容易判断何时可以将导入的 span 返回到其 source。）

我们将所有空闲段保存在空闲列表的二次幂上；也就是说，`freelist[n]` 包含大小在 [2^n^, 2^n+1^) 范围内的所有空闲段。为了分配一个段，我们在适当的空闲列表中搜索一个足够大的段来满足分配。这种方法被称为**分离拟合**，实际上近似于**最佳拟合**，因为所选空闲列表上的**任何段**都是**好的拟合** [Wilson95]。（实际上，使用二次幂空闲列表，**分离拟合**必然在**完美拟合**的 2 倍以内。）最佳拟合的近似值很有吸引力，因为它们在实践中对各种工作负载表现出较低的碎片化 [Johnstone97]。

选择空闲段的算法取决于 `vmem_alloc()` 标志中指定的分配策略，如下所示； 在所有情况下，假设分配大小位于 [2^n^, 2^n+1^) 范围内：

- **VM_BESTFIT**。在 `freelist[n]` 上搜索满足分配的最小段。

- **VM_INSTANTFIT**。如果大小恰好为 2^n^，则取 `freelist[n]` 上的第一个段。否则，取 `freelist[n+1]` 上的第一个段。此空闲列表上的任何段都必须足够大以满足分配，因此我们获得了常量时间性能并具有相当好的拟合^4^。

- **VM_NEXTFIT**。完全忽略空闲列表，在 arena 上搜索先前分配的空闲段之后的下一个空闲段。

> ^4^我们喜欢 **instant−fit**，因为它保证了常量的时间性能，在实践中提供了低碎片化，并且实现简单。还有许多其他技术可以在合理（例如对数）时间内选择合适的空闲段，例如将所有空闲段保存在大小排序树中； 参见 [Wilson95] 的全面调查。这些技术中的任何一种都可以用于 vmem 实现。

一旦我们选择了一个段，我们就会将它从它的空闲列表中删除。如果段不完全匹配，我们拆分段，为剩余部分创建**边界标签**，并将其放在适当的空闲列表中。然后，将新分配的段的边界标签添加到哈希表中，以便 `vmem_free()` 可以快速找到它。

`vmem_free()` 很简单：它在已分配段的哈希表中查找段的边界标签，将其从哈希表中删除，尝试将该段与其邻居合并，并将其放入适当的空闲列表中。所有操作都是常量时间。请注意，哈希查找还提供了一种廉价而有效的**完整性检查**：释放的地址必须在哈希表中，并且释放的大小必须与段大小匹配。这有助于捕获诸如重复释放之类的错误。

上述算法的关键特征是，其性能独立于事务大小**和 **arena  碎片。Vmem 似乎是第一个可以在常量时间内，保证**分配和释放**任何大小的**的资源分配器**。

#### 4.4.3 锁定策略

为简单起见，我们使用全局锁保护每个 arena 的段列表、空闲列表和哈希表。我们依赖于大分配相对较少的事实，并允许 arena  的 quantum 缓存为所有常见分配大小提供线性可扩展性。这种策略在实践中非常有效，如 §4.5 中的性能数据和附录 B 中大型 Solaris 8 服务器的分配统计数据所示。

#### 4.4.4 quantum 缓存

Slab 分配器可以为任何 vmem arena（§5.1）提供对象缓存，因此 vmem 的 quantum 缓存实际上按对象缓存实现。对于 arena  quantum 的每个**小**整数倍，我们创建一个对象缓存来服务该大小的请求。`vmem_alloc()` 和 `vmem_free()` 只是将每个小请求 `(size <= qcache_max)` 转换为适当缓存上的 `kmem_cache_alloc()` 或 `kmem_cache_free()`，如图 4.4 所示。因为它基于对象缓存，所以 quantum 缓存为最常见的分配大小提供了非常低的延迟和线性可扩展性。

- **例子**。假设 arena   如图 4.4 所示。3 页分配将按如下方式进行：`vmem_alloc(foo, 3 * PAGESIZE)` 将调用 `kmem_cache_alloc(foo->vm_qcache[2])`。在大多数情况下，缓存的弹匣层会满足分配，我们就可以完成了。如果缓存需要创建一个新的 slab，它会调用 `vmem_alloc(foo, 16 * PAGESIZE)`，这将从 arena 的段列表中得到满足。然后 slab 分配器将其 16 页的 slab 分成五个 3 页的对象，并使用其中之一来满足原始分配。

当我们创建一个 arena 的 quantum 缓存时，我们将一个标志传递给 `kmem_cache_create()`，即 `KMC_QCACHE`，它指示 slab 分配器使用特定的 slab 大小：`3 * qcache_max` 之上的下一个 2 次幂。我们出于三个原因使用这个特定值：(1) slab 大小**必须**大于 qcache_max 以防止无限递归； (2) 幸运的是，这个 slab 大小提供了近乎完美的 slab 包装（例如，五个 3 页对象填充了 16 页 slab 的 15/16）； (3) 我们将在下面看到，对所有 quantum  缓存使用通用的 slab 大小有助于减少整体 arena 碎片化。

#### 4.4.5 碎片
>“浪费是一件可怕的事情。”−匿名者

碎片化是指资源分解成无法使用的小的、不连续的片段。要了解这是如何发生的，想象从 1GB 的资源一次分配一个字节，然后只释放偶数地址的字节。竞技场将有 500MB 空闲空间，但它甚至不能满足 2 字节的分配。

我们观察到，<u>正是不同分配大小和不同段生命周期的**组合**导致持久碎片</u>。如果所有分配的大小都相同，那么任何释放的段显然都可以满足另一个相同大小的分配。**如果所有分配都是暂时的，则碎片也是暂时的**。

我们无法控制段的生命周期，但 quantum 缓存提供了对分配大小的一些控制：即，所有quantum 缓存具有相同的 slab 大小，因此来自 arena 段列表的大多数分配都发生在 slab 大小的块中。

乍一看，我们所做的一切似乎只是在转移问题：段列表不会碎片化太多，但现在 quantum 缓存 **自身** 可能会以部分使用的 slab 的形式出现碎片。关键区别在于 quantum 缓存中的空闲对象**大小已知是有用的**，而段列表可以在敌对工作负载下分解为**无用**片段。此外，先前分配可以很好地预测未来分配 [Weinstock88]，因此空闲对象很可能会再次使用。

不可能**证明**这有用 ^5^，但它似乎在实践中运作良好。自从引入 vmem 以来，我们从未收到过严重碎片的报告（我们有很多关于旧资源映射分配器的此类报告），而 Solaris 系统通常会持续运行**多年**。

> ^5^事实上，已经证明“没有可靠的算法来确保高效的内存使用，**而且也不可能**。” [Wilson95]

### 4.5. 性能

#### 4.5.1 微基准性能

我们已经声明 `vmem_alloc()` 和 `vmem_free()` 是常量时间操作，与 arena 碎片无关，而 `rmalloc()` 和 `rmfree()` 是线性时间。我们将**分配**/**释放**延迟作为碎片的函数来测量，验证这一点。

> f4.5.1

`rmalloc()` 在碎片化非常低的情况下具有轻微的性能优势，因为该算法非常简单。零碎片**没有 quantum 缓存**时，vmem的延迟为 1560ns，而 `rmalloc()` 为 715ns。quantum 缓存将 vmem 的延迟减少到仅 482ns，因此对于进入 quantum 缓存的分配（常见情况）vmem 比 `rmalloc()` 更快，即使在碎片非常低的情况下也是如此。

#### 4.5.2 系统层性能

Vmem 的低延迟和线性缩放纠正了 `rmalloc()` 下内核虚拟地址分配性能的严重问题，从而显着提高了系统层性能。

- **LADDIS **。Veritas 报告称，使用新的虚拟内存分配器 [Taylor99]，LADDIS 峰值吞吐量提高了 50%。

- **Web服务**。在 Softway 的 Share II 调度程序下运行 2700 台 Netscape 服务器的大型 Starfire 系统上，vmem 将系统时间从 60% 减少到 10%，大约是系统容量的两倍 [Swain98]。

- **I/O 带宽**。64-CPU Starfire 上的内部 I/O 基准测试对旧的 `rmalloc()` 锁产生了如此激烈的争用，以至于系统基本上无用。由于 `rmalloc()` 线性搜索日益碎片化的内核堆的线性搜索，占用的时间非常长，从而加剧了争用。lockstat(1M)（一种测量内核锁争用的 Solaris 实用程序）显示线程平均旋转 48 **毫秒** 以获取 `rmalloc()` 锁，从而将 I/O 带宽限制为每个 CPU 每秒只有 1000/48 = 21 个I/O操作。使用 vmem，问题完全消失，性能提高了**几个数量级**。

### 4.6. 总结

vmem 接口支持简单和高度受限的分配，其**导入**机制可以从简单的组件构建复杂的资源。该接口非常通用，自从引入 vmem 以来，我们已经能够在 Solaris 中消除 30 多个特殊用途的分配器。

vmem 实现已经被证明是非常快速和可扩展，在系统级基准测试上提高了 50% 或更多的性能。在实践中，它也被证明对碎片化非常有效。

Vmem 的 **instant−fit 策略**和**外部边界标签**似乎是新概念。无论分配的大小是多少或者 arean 碎片如何，都能保证常量的时间性能。

Vmem 的**quantum 缓存**为最常见的分配提供非常低的延迟和线性可扩展性。他们还为 arean 的分段列表提供了特别友好的工作负载，这有助于减少 arean 的整体碎片化。

## 5. 核心 Slab 配器增强功能

第 3 节和第 4 节描述了弹匣和 vmem 层，**这是 slab 层之上和之下的两项新技术**。在本节中，我们将描述两个与 vmem 相关的对 slab 分配器本身的增强。

### 5.1. 任何资源的对象缓存

最初的 slab 分配器使用 `rmalloc()` 为其 slab 获取内核堆地址，并调用 VM 系统为这些地址分配物理页面。

每个对象缓存现在都使用 vmem arena 作为其 slab 供应商。slab 分配器简单地调用 `vmem_alloc()` 和 `vmem_free()` 来创建和销毁 slab。它对其管理的资源的性质不做任何假设，因此它可以为**任何** arena^6^ 提供对象缓存。此功能使 vmem 的高性能*quantum 缓存*成为可能（§4.4.4）。

> ^6^对于由不是内存 vmem arenas 支持的缓存，调用者必须为 `kmem_cache_create()` 指定标志 `KMC_NOTOUCH`，**这样分配器就不会尝试使用空闲缓冲区来保存其内部状态**。

### 5.2. 回收回调

为了提高性能，内核会缓存并非严格需要的内容。例如，DNLC（目录名称查找缓存）提高了路径名解析性能，但大多数 DNLC 条目在任何给定时刻都没有实际使用。如果当系统内存不足时可以通知 DNLC，它可以释放一些条目以减轻内存压力。

我们通过允许客户端为 `kmem_cache_create()` 指定一个**回收回调**来支持这一点。当缓存的 vmem arena 资源不足时，分配器调用此函数。回调纯粹是建议性的；它实际做什么完全取决于客户。典型的操作可能是归还一部分对象，或者释放在最后 N 秒内未访问的所有对象。

此功能允许像 DNLC、inode 缓存和 NFS_READDIR 缓存这样的客户端或多或少不受限制地增长，直到系统内存不足，此时他们被要求开始返回一些。

未来可能的一种增强是向回收回调中添加一个参数，以指示所需的字节数或**绝望程度**。我们还没有这样做，因为简单的回调政策，如“每次被调用时返还 10%”，在实践中已被证明是完全足够的。

## 6. 用户层内存分配：libumem 库

将弹匣、slab 和 vmem 技术移植到用户级别相对简单。我们创建了一个库，*libumem*，它提供所有相同的服务。在本节中，我们将讨论出现的少数移植问题，并将 libumem 的性能与其他用户级内存分配器进行比较。在撰写本文时，libumem 仍处于试验阶段。

### 6.1. 移植问题

分配代码（弹匣、slab 和 vmem）基本上没有变化；挑战是为它所依赖的内核功能找到用户层的替代品，并适应用户层库代码的限制和接口要求。

- **CPU ID**。内核使用 CPU ID（只需几条指令即可确定）来索引缓存的 cache_cpu[] 数组。线程库中没有对应的CPU ID； 我们需要自己实现一个^7^。对于原型，我们只是对线程 ID 进行哈希处理，它在 libthread 中很容易获取。
- **内存压力**。在内核中，当系统范围内的空闲内存不足时，VM 系统调用 `kmem_reap()`。在用户领域中没有类似的概念。在 libumem 中，每当我们访问仓库时，我们都会检查仓库的工作集大小，并将任何多余的部分返回给 slab 层。
- **支持 malloc(3C) 和 free(3C)**。为了实现 `malloc()` 和 `free()`，我们创建了一组大约 30 个固定大小的对象缓存来处理中小型 `malloc()` 请求。我们使用 `malloc()` 的 `size` 参数作为表的索引，以找到最近的缓存，例如 `malloc(350)` 进入 `umem_alloc_384` 缓存。对于更大的分配，我们直接使用 VM 系统，即 sbrk(2) 或 mmap(2)。我们为每个缓冲区添加一个 8 字节的边界标记，以便我们可以在 `free()` 中确定其大小。
- **初始化**。与启动成本相比，初始化内核内存分配器的成本微不足道，但与 `exec(2)` 的成本相比，初始化 libumem 的成本并非完全微不足道，主要是因为 libumem 必须创建 30 个支持 `malloc`/`free` 的标准缓存。因此，我们惰性地（按需）创建这些缓存。

> ^7^我们的策略是让内核和线程库合作，这样每当内核将一个线程分派到不同的 CPU 时，它都会将新的 CPU ID 存储在用户层的线程结构中。

### 6.2. 性能
对用户级内存分配器的完整分析超出了本文的范围，因此我们只将 libumem 与最强的竞争者进行了比较：

- Hoard 分配器 [Berger00]，它似乎是当前可扩展用户级内存分配器中的最佳品种；
- ptmalloc [Gloger01]，一种在 GNU C 库中广泛使用的多线程 malloc；
- Solaris mtmalloc 库。

我们还对 Solaris C 库的 malloc [Sleator85] 进行了基准测试，以建立单线程基线。

在我们的测量过程中，我们发现 Solaris mtmalloc 库存在几个严重的可伸缩性问题。mtmalloc 为每个 CPU 创建二次幂的空闲列表，最大到 64K ，但是它选择空闲列表的算法只是循环；因此它的工作负载是分散的，而不是 CPU 本地化。此外，循环索引本身是一个全局变量，因此所有 CPU 的频繁递增会导致对其高速缓存行的严重争用。我们还发现，如§3.6所述，mtmalloc 的每CPU数据结构没有适当填充并与缓存线边界对齐，以防止错误共享。

我们修复了 mtmalloc 以像在 libumem 中一样通过线程 ID 哈希值来选择每个 CPU 空闲列表，并填充和对齐其每个 CPU 的数据结构。这些变化极大地提高了 mtmalloc 的可扩展性，使其与 Hoard 和 libumem 竞争。

我们使用 §3.8 中描述的方法在 10-CPU E4000 上测量了分配器的可扩展性。图 6.2 显示了 libc 的 malloc 和原始的 mtmalloc 随着线程数量的增加表现得很糟糕。ptmalloc 提供了高达 8 个 CPU 的良好可扩展性，但似乎无法扩展到 8 个以上。相比之下，libumem、Hoard 和固定的 mtmalloc 都显示线性缩放。只有斜率不同，libumem 最快。

> Figure 6.2

## 7. 结论

从我们使用 slab 分配器的经验中得到的持久教训是，创建出色的核心服务至关重要。**乍一看可能很奇怪，但核心服务往往是最被忽视的**。

处理特定性能问题（例如 Web 服务器性能）的人们通常专注于特定目标，例如更好的 SPECweb99 数字。**如果数据分析表明核心系统服务是前五个问题之一，我们假设的 SPECweb99 性能团队更有可能找到一种快速而肮脏的方法来避免该服务，而不是偏离他们的主要任务，并重新设计有问题的子系统**。这就是我们在 vmem 出现之前最终得到 30 多个专用分配器的原因。

这种快速而肮脏的解决方案虽然在当时足够了，但并没有推动操作系统技术的发展。恰恰相反：它们使系统更复杂，更难维护，并留下一堆最终必须处理的定时炸弹。例如，我们的 30 个专用分配器都没有像弹匣层这样的东西；因此，它们中的每一个有可扩展性问题等待解决。（事实上，有些人已经不再等待了。）

1994 年之前，Solaris 内核工程师避免使用内存分配器，因为众所周知它很慢。现在，相比之下，我们的工程师积极寻找使用分配器的方法，因为它以快速和可扩展着称。他们还知道分配器提供了广泛的统计信息和调试支持，这使得他们所做的事情更加容易。	

我们目前使用分配器来管理普通内核内存、虚拟内存、DMA、次要设备号、System V 信号量、线程堆栈和任务 ID。更多创造性的用途目前正在开发中，包括使用分配器来管理工作线程池——这个想法是**仓库**工作集提供了一种有效的算法来管理线程池的大小。在不久的将来，libumem 会将所有这些技术带到用户层应用程序和库中。

我们已经证明弹匣和 vmem 在现实世界的系统级基准测试中的性能提高了 50% 或更多。但同样重要的是，我们通过投资许多其他项目团队构建的核心系统服务（资源分配）来获得这些收益。投资核心服务对于维护和发展快速、可靠的操作系统至关重要。

## 致谢

## References

Magazines and vmem are part of Solaris 8. The source is available for free download at [www.sun.com](http://www.sun.com/).

For general background, [Wilson95] provides an extensive survey of memory allocation techniques. In addition, the references in [Berger00], [Bonwick94], and [Wilson95] list dozens of excellent papers on memory allocation.

**[Berger00]** Emery D. Berger, Kathryn S. McKinley, Robert D. Blumofe, Paul R. Wilson. *Hoard: A Scalable Memory Allocator for Multithreaded Applications*. ASPLOS−IX, Cambridge, MA, November 2000. Available at [http://www.hoard.org.](http://www.hoard.org/)

**[BIRD01]** BIRD Programmer’s Documentation. Available at [http://bird.network.cz.](http://bird.network.cz/)

**[Bonwick94]** Jeff Bonwick. *The Slab Allocator: An Object−Caching Kernel Memory Allocator*. Summer 1994 Usenix Conference, pp. 87−98. Available at [http://www.usenix.org.](http://www.usenix.org/)

**[Bovet00]** Daniel P. Bovet and Marco Cesati.

*Understanding the Linux Kernel*. Prentice Hall, 2000.

**[Denning68]** Peter J. Denning. *The Working Set Model for Program Behaviour*. CACM 11(5), 1968, pp. 323−333.

**[FreeBSD01]** The FreeBSD source code. Available at [http://www.freebsd.org.](http://www.freebsd.org/)

**[Gloger01]** Source code and documentation for ptmalloc are available on Wolfram Gloger’s home page at [http://www.malloc.de.](http://www.malloc.de/)

**[Johnstone97]** Mark S. Johnstone and Paul R. Wilson. *The Memory Fragmentation Problem: Solved?* ISMM’98 Proceedings of the ACM SIGPLAN International Symposium on Memory Management, pp. 26−36. Available at ftp://ftp.dcs.gla.ac.uk/pub/drastic/gc/wilson.ps.

**[Khanna92]** Sandeep Khanna, Michael Sebree and John Zolnowski. *Realtime Scheduling in SunOS 5.0*. Winter 1992 USENIX Conference.

**[Knuth73]** Donald Knuth. *The Art of Computer Programming: Fundamental Algorithms*. Addison Wesley, 1973.

**[Linux01]** The Linux source code. Available at [http://www.linux.org.](http://www.linux.org/)

**[Mauro00]** Jim Mauro and Richard McDougall. *Solaris Internals: Core Kernel Architecture*. Prentice Hall, 2000.

**[McKenney93]** Paul E. McKenney and Jack Slingwine. *Efficient Kernel Memory Allocation on Shared−Memory Multiprocessors*. Proceedings of the Winter 1993 Usenix Conference, pp. 295−305. Available at [http://www.usenix.org.](http://www.usenix.org/)

**[Nemesis01]** The Nemesis source code. Available at [http://nemesis.sourceforge.net.](http://nemesis.sourceforge.net/)

**[NetBSD01]** The NetBSD source code. Available at [http://www.netbsd.org.](http://www.netbsd.org/)

**[OpenBSD01]** The OpenBSD source code. Available at [http://www.openbsd.org.](http://www.openbsd.org/)

**[Perl01]** The Perl source code. Available at [http://www.perl.org.](http://www.perl.org/)

**[Shapiro01]** Jonathan Shapiro, personal communi− cation. Information on the EROS operating system is available at http://www.eros−os.org.

**[Sleator85]** D. D. Sleator and R. E. Tarjan. *Self− Adjusting Binary Trees*. JACM 1985.

**[SPEC01]** Standard Performance Evaluation Corporation. Available at [http://www.spec.org.](http://www.spec.org/)

**[Swain98]** Peter Swain, Softway. Personal communication.

**[Taylor99]** Randy Taylor, Veritas Software. Personal communication.

**[TPC01]** Transaction Processing Council. Available at [http://www.tpc.org.](http://www.tpc.org/)

**[Vahalia96]** Uresh Vahalia. *UNIX Internals: The New Frontiers*. Prentice Hall, 1996.

**[Weinstock88]** Charles B. Weinstock and William A. Wulf. *QuickFit: An Efficient Algorithm for Heap Storage Allocation*. ACM SIGPLAN Notices, v.23, no. 10, pp. 141−144 (1988).

**[Wilson95]** Paul R. Wilson, Mark S. Johnstone, Michael Neely, David Boles. *Dynamic Storage Allocation: A Survey and Critical Review.* Proceedings of the International Workshop on Memory Management, September 1995. Available at [http://citeseer.nj.nec.com/wilson95dynamic.html](http://citeseer.nj.nec.com/wilson95dynamic.html).

## 作者信息

## 附录 A：组成 Vmem Arenas 和对象缓存

在本附录中，我们描述了从系统启动到创建复杂对象缓存的所有关键步骤。

在编译时，我们静态地声明了一些 vmem arena 结构和边界标签，以帮助我们完成引导。在引导期间，我们创建的第一个 arena 是原始 heap_arena，它定义了用于内核堆的内核虚拟地址范围：
```c
heap_arena =  vmem_create(
    "heap",
    kernelheap, heapsize, /* base and size of kernel heap */
    PAGESIZE,             /* unit of currency is one page */
    NULL, NULL, NULL,  /* nothing to import from -- heap is primordial */ 
    0,                    /* no quantum caching needed */
    VM_SLEEP);            /* OK to wait for memory to create arena */
```
看到我们处于启动早期，`vmem_create()`使用静态声明的某个 arena 来表示堆，并使用静态声明的边界标签来表示堆的初始范围。一旦我们有了 `heap_arena`，我们就可以动态地创建新的边界标签。为简单起见，我们总是一次分配一整页边界标签：我们选择一页的堆，映射它，将其划分为边界标签，使用其中一个边界标签来表示我们刚刚分配的堆页面，并将其余的放在竞技场的空闲边界标签列表中。

接下来，我们创建 `kmem_va_arena` 作为 `heap_arena` 的子集，以提供最多 8 页的虚拟地址缓存（通过 quantum 缓存）。正如我们在 §4.4.5 中看到的，quantum 缓存提高了性能并有助于最小化堆碎片。`kmem_va_arena` 使用 `vmem_alloc()` 和 `vmem_free()` 从 `heap_arena` 导入：
```c
kmem_va_arena = vmem_create(
    "kmem_va",
    NULL, 0,      /* no initial span; we import everything */
    PAGESIZE,     /* unit of currency is one page */
    vmem_alloc,   /* import allocation function */
    vmem_free,    /* import free function */
    heap_arena,   /* import vmem source */
    8 * PAGESIZE, /* quantum caching for up to 8 pages */
    VM_SLEEP);    /* OK to wait for memory to create arena */
```

最后，我们创建 `kmem_default_arena`，这是大多数对象缓存的后备存储它的导入函数 `segkmem_alloc()` 调用 `vmem_alloc()` 来获取虚拟地址，然后为它们分配物理页面：

```c
kmem_default_arena = vmem_create(
    "kmem_default",
    NULL, 0,       /* no initial span; we import everything */
    PAGESIZE,      /* unit of currency is one page */
    segkmem_alloc, /* import allocation function */
    segkmem_free,  /* import free function */
    kmem_va_arena, /* import vmem source */
    0,             /* no quantum caching needed */
    VM_SLEEP);     /* OK to wait for memory to create arena */
```

此时我们有一个简单的页级分配器：要获得三页映射内核堆，我们可以直接调用 `vmem_alloc(kmem_default_arena, 3 * PAGESIZE, VM_SLEEP)`事实上，这正是 slab 分配器为新 slab 获取内存的方式最后，内核的各种子系统创建它们的对象缓存例如，UFS 文件系统创建它的 inode 缓存：
```c
inode_cache = kmem_cache_create(
    "ufs_inode_cache",
    sizeof (struct inode),       /* object size */
    0,                           /* use allocator's default alignment */ 
    ufs_inode_cache_constructor, /* inode constructor */ 
    ufs_inode_cache_destructor,  /* inode destructor */
    ufs_inode_cache_reclaim,     /* inode reclaim */
    NULL,                        /* argument to above funcs */
    NULL,                        /* implies kmem_default_arena */
    0);                          /* no special flags */
```