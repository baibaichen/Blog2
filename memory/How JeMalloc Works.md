# How JeMalloc Works

## Introduction

A memory allocator needs to suit hardware(multi-processor + cache line) and use memory efficiently(fast + less fragment).

By default, JeMalloc uses Thread-Specific-Data and mutiple arenas for every CPU for reducing lock contention.

For handling cache line related things, JeMalloc relies on multiple arenas and allows applications to pad the allocations.

JeMalloc allocates different size memory from different memory blocks(slab/extent) which can reduce fragmentation and locate memory quickly.

This article will introduce how JeMalloc 5.2.1[1] allocates and deallocates memory. And for simplicity, I will focus on small memory allocation and will not cover all details.

---

> Traditionally, allocators have used sbrk(2) to obtain memory, which is suboptimal for several reasons, including race conditions, increased fragmentation, and artificial limitations on maximum usable memory. If sbrk(2) is supported by the operating system, this allocator uses both mmap(2) and sbrk(2), in that order of preference; otherwise only mmap(2) is used.
>
> This allocator uses multiple arenas in order to reduce lock contention for threaded programs on multi-processor systems. This works well with regard to threading scalability, but incurs some costs. There is a small fixed per-arena overhead, and additionally, arenas manage memory completely independently of each other, which means a small fixed increase in overall memory fragmentation. These overheads are not generally an issue, given the number of arenas normally used. Note that using substantially more arenas than the default is not likely to improve performance, mainly due to reduced cache performance. However, it may make sense to reduce the number of arenas if an application does not make much use of the allocation functions.
>
> In addition to multiple arenas, this allocator supports thread-specific caching, in order to make it possible to completely avoid synchronization for most allocation requests. Such caching allows very fast allocation in the common case, but it increases memory usage and fragmentation, since a bounded number of objects can remain allocated in each thread cache.
>
> Memory is conceptually broken into extents. Extents are always aligned to multiples of the page size. This alignment makes it possible to find metadata for user objects quickly. User objects are broken into two categories according to size: small and large. Contiguous small objects comprise a slab, which resides within a single extent, whereas large objects each have their own extents backing them.
>
> Small objects are managed in groups by slabs. Each slab maintains a bitmap to track which regions are in use. Allocation requests that are no more than half the quantum (8 or 16, depending on architecture) are rounded up to the nearest power of two that is at least `sizeof(double)`. All other object size classes are multiples of the quantum, spaced such that there are four size classes for each doubling in size, which limits internal fragmentation to approximately 20% for all but the smallest size classes. Small size classes are smaller than four times the page size, and large size classes extend from four times the page size up to the largest size class that does not exceed `PTRDIFF_MAX`.
>
> Allocations are packed tightly together, which can be an issue for multi-threaded applications. If you need to assure that allocations do not suffer from cacheline sharing, round your allocation requests up to the nearest multiple of the cacheline size, or specify cacheline alignment when allocating.
>
> The realloc(), rallocx(), and xallocx() functions may resize allocations without moving them under limited circumstances. Unlike the *allocx() API, the standard API does not officially round up the usable size of an allocation to the nearest size class, so technically it is necessary to call realloc() to grow e.g. a 9-byte allocation to 16 bytes, or shrink a 16-byte allocation to 9 bytes. Growth and shrinkage trivially succeeds in place as long as the pre-size and post-size both round up to the same size class. No other API guarantees are made regarding in-place resizing, but the current implementation also tries to resize large allocations in place, as long as the pre-size and post-size are both large. For shrinkage to succeed, the extent allocator must support splitting (see arena.<i>.extent_hooks). Growth only succeeds if the trailing memory is currently available, and the extent allocator supports merging.
>
> Assuming 4 KiB pages and a 16-byte quantum on a 64-bit system, the size classes in each category are as shown in Table 1

传统上，分配器使用 sbrk(2) 来获取内存，这不是最优的，原因有几个，包括竞争条件、增加的碎片和对最大可用内存的人为限制。如果操作系统支持 sbrk(2)，则此分配器按优先顺序同时使用 mmap(2) 和 sbrk(2)； 否则只使用 mmap(2)。

此分配器使用多个 **arena** 以减少多处理器系统上线程程序的锁争用。这在线程可伸缩性方面效果很好，但会产生一些成本。每个 **arena** 有一个小的固定开销，此外，各个 **arena** <u>管理的内存彼此完全独立</u>，这意味着内存碎片整体上有一个小的固定增加。考虑到通常使用的 **arena** 数量，这些开销通常不是问题。请注意，使用比默认更多的 **arena** 不太可能提高性能，**主要是因为缓存性能降低**。但是，如果应用程序不经常使用分配函数，那么减少 **arena** 的数量可能有意义。

除了多 **arena** 之外，这个分配器还支持线程特定的缓存，以便完全避免大多数分配请求的同步。这种缓存在常见情况下允许非常快速的分配，但它会增加内存使用和碎片，因为有限数量的对象可以保留在每个线程缓存中。

内存在概念上被分解为多个 **extent**。**Extent** 总是与页面大小的倍数对齐。这种对齐使得快速查找用户对象的元数据成为可能。用户对象根据大小分为两类：小型和大型。连续的小对象组成一个 slab，它驻留在一个 **extent** 内，而每个大对象都有自己的 **extent** 支持它们。

**小对象由 slab 分组管理**。每个 slab 都维护一个位图，用于跟踪正在使用的 region。==不超过 quantum 一半（8 或 16，取决于体系结构）的分配请求被四舍五入到最接近的 2 次幂，至少为 `sizeof(double)`。所有其他对象大小类都是 quantum  的倍数，间隔使得 size 每增加一倍就有四个 size 类，这将内部碎片限制为大约 20%，除了最小的 **size class**。小的 **size class** 小于页面大小的四倍，大的 **size class** 从页面大小的四倍扩展到不超过 `PTRDIFF_MAX` 的最大 **size class**==。

**分配紧密地打包在一起，这对于多线程应用程序来说可能是个问题**。如果您需要确保分配不会受到高速缓存行共享的影响，请将您的分配请求四舍五入到最接近的高速缓存行大小的倍数，或者在分配时指定高速缓存行对齐。

`realloc()`、`rallocx()` 和 `xallocx()` 函数可以在有限的情况下调整分配大小而不移动它们。与 `*allocx()` API 不同，标准 API 并未正式将分配的可用大小四舍五入到最接近的 **size class**，因此从技术上讲，有必要调用 `realloc()` 来增长，例如 9 字节分配到 16 字节，或将 16 字节分配缩小到 9 字节。只要 pre-size 和 post-size 都四舍五入到相同的 size class，增长和收缩就很容易成功。没有关于就地调整大小的其他 API 保证，但当前的实现也尝试就地调整大型分配的大小，只要 pre-size 和 post-size 都很大。要成功收缩，extent 分配器必须支持拆分（参见 `arena.<i>.extent_hooks`）。仅当尾随内存当前可用，且 extent 分配器支持合并，增长才会成功。

假设在 64 位系统上有 4 KiB 页面和 16 字节 quantum ，则每个类别中的大小类别如表 1 所示

> quantum => 最小分配单元？


## Big Picture -- The Hierarchy

> We can image the memory managed in 3 levels: `tcache`, `arena`, and OS. It works like CPU cache -- memory will be allocated from a higher level, if the higher level doesn't have available memory, memory will be allocated from the next level and fill in the higher level, now the memory can be allocated.

我们可以将内存管理分为 3 层：`tcache`、`Arena` 和 OS。它的工作原理类似于 CPU 缓存——内存从更高层分配，如果更高层没有可用内存，内存将从下一级分配并填充更高级别，现在可以分配内存。

<img width="1110" alt="Screen Shot 2022-09-25 at 11 31 51" src="https://user-images.githubusercontent.com/3775525/192127017-c6653401-c4ec-40d7-874b-97432bee0a80.png">

> `tcache` has many cache_bins, `cache_bin`'s `avail` field will point to regions -- `region` is a unit of memory and will be returned when an application calls `malloc`.
>
> `arena` has many extents/slabs, a slab will have many regions for small memory. When there is no available memory in a `cache_bin`, the `cache_bin` will try to get memory from `extent/slab.bin` through the current `arena`. If the arena doesn't have an available extent/slab too, JeMalloc will try to allocate memory from OS.

`tcache` 有很多 **cache_bin**，`cache_bin` 的 avail 字段会指向 regions -- `region` 是一个内存单元，当应用程序调用 `malloc` 时会返回。

`arena` 有许多 extent/slab，一个 slab 将有许多用于小内存的区域。当 `cache_bin` 中没有可用内存时，`cache_bin` 将尝试通过当前 `arena` 从 `extent/slab.bin` 中获取内存。如果 arena 也没有可用的 extent/slab，JeMalloc 将尝试从 OS 分配内存。

<img width="1040" alt="Screen Shot 2022-09-25 at 11 44 50" src="https://user-images.githubusercontent.com/3775525/192127352-a8cf98ae-45ff-47b9-9ba6-1f2242d0ea92.png">

Now let's see how JeMalloc's every component works.

## Small Memory Allocation

### TCache

<img width="285" alt="Screen Shot 2022-09-26 at 08 36 28" src="https://user-images.githubusercontent.com/3775525/192173979-ff30eaf8-00ea-4478-81b5-41565128c8e7.png">

When an application allocates memory, JeMalloc will try to find available memory from `tcache`, `tcache` is thread-specific data, as the data is owned by a thread, we do not need to lock it when we use it. The thread-specific data is get by `pthread_setspecific` and set by `pthread_getspecific`.

Relate data structures are `tsd`, `tcache` and `cache_bin`. `tsd` is used for fast access `tcache` and others. `tcache` has many `cache_bin`, different `cache_bin` is used for allocating different size memory.

For example, `tcache.bins_small[0]` is used for allocating 0 ~ 8 bytes memory,  `tcache.bins_small[1]` is for 9 ~ 16 bytes, the calculation is in `sz_size2index_compute`.

After finding the right `cache_bin` through size, we can find the available memory address through `cache_bin.avail`, it contains the same size memory(JeMalloc calls this region) addresses, the code is in `cache_bin_alloc_easy`.

If the `cache_bin` doesn't have available memory, JeMalloc needs to get memory from the next level -- arena, fill the `cache_bin`, and allocate the memory again. Simplified code as below:

``` c
JEMALLOC_ALWAYS_INLINE void *
tcache_alloc_small(tsd_t *tsd, arena_t *arena, tcache_t *tcache,
                   size_t size, szind_t binind, bool zero, bool slow_path) {
    // ...
    bin = tcache_small_bin_get(tcache, binind);
    ret = cache_bin_alloc_easy(bin, &tcache_success);
    assert(tcache_success == (ret != NULL));
    if (unlikely(!tcache_success)) {
        bool tcache_hard_success;
        arena = arena_choose(tsd, arena);

        ret = tcache_alloc_small_hard(tsd_tsdn(tsd), arena, tcache,
                                      bin, binind, &tcache_hard_success);
    }
    // ...

    return ret;
}
```

### Arena

<img width="651" alt="Screen Shot 2022-09-26 at 08 37 57" src="https://user-images.githubusercontent.com/3775525/192174072-2803a3e0-6e47-4679-9d8b-ffc1329dc07a.png">

> `arena` is used for managing `extent`, `extent` is a unit of memory, it may contain multiple OS pages. `extent` is allocated from or deallocated to OS through OS provides system call such as `mmap`, relates code is in `src/pages.c`. And small size `extent` is called `slab` in JeMalloc.
>
> Likes `tcache`, `arena` has many `bin` which is used for managing different size memory for the application. `bin` has a `slab` pointer( `bin.slabcur`) and a collections of non-full slab/extent(`bin.slabs_nonfull`).
>
> When JeMalloc trying to find available memory in a `bin`, JeMalloc will try `bin.slabcur` first, if fails it will try to get a `slab` in `bin.slabs_nonfull` and assign it to the `bin.slabcur`.
>
> And if `bin.slabs_nonfull` has no available extent/slab too, JeMalloc will try to find the memory in `arena`'s extents(the order is `extents_dirty` -> `extents_muzzy` -> `extents_retained` -> `extent_avail`, `extents_dirty`, `extents_muzzy` and `extents_retained` are used for purging, will cover in other sections). If all those do not have available extents, JeMalloc will allocate memory from the OS.

`arena`用于管理`extent`，`extent`是一个内存单元，它可能包含多个操作系统页面。`extent`通过操作系统提供的系统调用如`mmap`从操作系统分配或释放给操作系统，相关代码在`src/pages.c`中。而小尺寸的 extent 在 JeMalloc 中称为 slab。

和 `tcache` 一样，`arena` 有许多 `bin`，用于管理应用程序的不同大小的内存。`bin` 有一个 `slab` 指针 (`bin.slabcur`) 和一组非完整的 slab/extent(`bin.slabs_nonfull`)。

当 JeMalloc 试图在 `bin` 中寻找可用内存时，JeMalloc 将首先尝试 `bin.slabcur`，如果失败，它将尝试在 `bin.slabs_nonfull` 中获取一个 `slab` 并将其分配给 `bin.slabcur` .

## Purging
When an application frees memory, JeMalloc needs to determine how to return the memory. JeMalloc will return memory to `tcache` first. When `tcache` is full, JeMalloc will return free memory to `extent`, and arena will handle how and when returning the unused extents to the system.

### Application -> `tcache` -> extent
When an application frees a small memory, the trace will be `je_free` -> `ifree` -> `idalloctm` -> `tcache_dalloc_small`.

In `tcache_dalloc_small`, the deallocation relates code is:

```c
JEMALLOC_ALWAYS_INLINE void
tcache_dalloc_small(tsd_t *tsd, tcache_t *tcache, void *ptr, szind_t binind,
                    bool slow_path) {
    // ...
    if (unlikely(!cache_bin_dalloc_easy(bin, bin_info, ptr))) {
        tcache_bin_flush_small(tsd, tcache, bin, binind,
                               (bin_info->ncached_max >> 1));
        bool ret = cache_bin_dalloc_easy(bin, bin_info, ptr);
        assert(ret);
    }
    // ...
}
```

`cache_bin_dalloc_easy` will retun memory to current `cache_bin`. If `cache_bin` is full (`bin->ncached == bin_info->ncached_max`), JeMalloc will call `tcache_bin_flush_small`.

In `tcache_bin_flush_small`, it will return half(`bin_info->ncached_max >> 1` in tcache_dalloc_small) to extent, `arena_dalloc_bin_locked_impl` will do this work:


```c
static void
arena_dalloc_bin_locked_impl(tsdn_t *tsdn, arena_t *arena, bin_t *bin,
                             szind_t binind, extent_t *slab, void *ptr, bool junked) {
    // ...
    if (nfree == bin_info->nregs) {
        arena_dissociate_bin_slab(arena, slab, bin);
        arena_dalloc_bin_slab(tsdn, arena, slab, bin);
    } else if (nfree == 1 && slab != bin->slabcur) {
        arena_bin_slabs_full_remove(arena, bin, slab);
        arena_bin_lower_slab(tsdn, arena, slab, bin);
    }
    // ...
}
```

If `nfree == bin_info->nregs`, it means slab is empty, so need to call `arena_dissociate_bin_slab` and then `arena_dalloc_bin_slab`. `arena_dalloc_bin_slab` will append the free slab(extent) to current `arena->extents_dirty` by calling `arena_extents_dirty_dalloc`.


## extent -> system

JeMalloc is a user level memory allocator, we need to consider other applications' memory usage in the current system, so JeMalloc needs to return free memory back when necessary. And after an arena returns free memory to the system, other arenas can use it too.

For returning memory to system, we need to call a system call and in the system call, the system needs to zero the memory and mark the memory as unused. If we return too much memory at one step, it may hurt performance.

And when an `extent` is free, the application may use it in a very short time. For such a case, we'd better not return to the system too quickly.

JeMalloc uses "decay" to handle those things. We already know free slab(extent) is appended to `arena->extents_dirty` by `arena_extents_dirty_dalloc`. Extents in `arena->extents_dirty` will be moved to `arena->extents_muzzy` and the extents in `arena->extents_muzzy` will be returned to the system.

Let's see how the "decay" works and then see how the extents are returned from `arena->extents_dirty` to `arena->extents_muzzy`, and then returned to the system.

### Decay
JeMalloc uses a `ticker` to count down how many times an arena allocated/deallocated memory. And when the `ticker` reaches 0, it will trigger `arena_decay` which will calculate how long passed since the last time and call `arena_decay` to  do purging work when needed.

The ticker is initialized by `ticker_init(&arenas_tdata[i].decay_ticker, DECAY_NTICKS_PER_UPDATE);` in `arena_tdata_get_hard`, the value of `DECAY_NTICKS_PER_UPDATE` is 1000.

`arena_decay_ticks` is used for handling tick related thing and it will be called when memory is allocated or deallocated, such as by `arena_malloc_small`.

For `arena_decay_ticks`, it will call `ticker_ticks(decay_ticker, nticks)` for updating the count. After subtract `nticks` (`ticker->tick -= nticks`), if the `ticker->tick` is less than 0, JeMalloc will reset it to 0 and return true. Then `arena_decay` will be called.

``` c
JEMALLOC_ALWAYS_INLINE void
arena_decay_ticks(tsdn_t *tsdn, arena_t *arena, unsigned nticks) {
    // ...
    if (unlikely(ticker_ticks(decay_ticker, nticks))) {
        arena_decay(tsdn, arena, false, false);
    }
}
```

After we know how the `arena_decay` is trigged, let's see how `arena_decay` works.

For high level, JeMalloc wants to return memory back smoothly, it means when JeMalloc find n unused pages, instead of returning the n pages in one time, it will return them in serval seconds(default dirty decay is 10 seconds and stored in `DIRTY_DECAY_MS_DEFAULT`) and in several steps(default is 200 and it is in `SMOOTHSTEP_NSTEPS`.)

In `struct arena_decay`, `backlog` is used for recording how many unused dirty pages were generated during each of the past SMOOTHSTEP_NSTEPS decay epochs. `nunpurged` is used for recording the number of unpurged pages at beginning of current epoch.

The current epoch `backlog` is calculated by `current_npages - decay->nunpurged` and `backlog` saves the number in reverse order, so the current epoch number is stored in the last index, see `arena_decay_backlog_update_last`.

And when epochs passed, JeMalloc will move the backlog forward by `memmove(decay->backlog, &decay->backlog[nadvance_z], (SMOOTHSTEP_NSTEPS - nadvance_z) * sizeof(size_t));`, and as time may pass more than one epoch, needs  set uncalculated backlog to 0 by `memset(&decay->backlog[SMOOTHSTEP_NSTEPS - nadvance_z], 0, (nadvance_z-1) * sizeof(size_t));`,  all those are in `arena_decay_backlog_update`.

JeMalloc uses `Smoothstep`[2] function to calculate how many pages need to remain. For example, when x = 1, y = 1, that means no pages need to be purged, and when x = 0, y = 0, that means all the pages need to be purged.

![220px-Smoothstep_and_Smootherstep svg](https://user-images.githubusercontent.com/3775525/193720890-e69d2517-2560-4f76-a2f7-1d2067805dfd.png)


For avoiding calculation, JeMalloc generates those values by `smoothstep.sh`, and the value is encoded by binary fixed point representation and then they are stored in `h_steps`.

`arena_decay_backlog_npages_limit` is used for calculating how many pages need to remain.

``` c
static size_t
arena_decay_backlog_npages_limit(const arena_decay_t *decay) {
    // ...
    /*
     * For each element of decay_backlog, multiply by the corresponding
     * fixed-point smoothstep decay factor.  Sum the products, then divide
     * to round down to the nearest whole number of pages.
     */
    sum = 0;
    for (i = 0; i < SMOOTHSTEP_NSTEPS; i++) {
        sum += decay->backlog[i] * h_steps[i];
    }
    npages_limit_backlog = (size_t)(sum >> SMOOTHSTEP_BFP);

    return npages_limit_backlog;
}

```

### dirty -> muzzy and muzzy -> system

Now let's see how the extents are moved from `dirt` to` muzzy` and how `muzzy` returns them to the system.

`arena_decay` will handle dirty and muzzy extents by calling `arena_decay_dirty` and `arena_decay_muzzy`. `arena_maybe_decay` will do the decay job for `arena_decay_dirty` and `arena_decay_muzzy`.

In `arena_maybe_decay`, if `decay->time_ms` is 0, will call `arena_decay_to_limit` and the `limit` params is 0, that means deallocate all free extents.

And if `decay->time_ms` is not zero, will handle epoch advance related things, calculate limit by `arena_decay_backlog_npages_limit(decay)` and use the limit to call `arena_decay_to_limit`.

`arena_decay_stashed` will do purging work for `arena_decay_to_limit`. 

In `arena_decay_stashed`, it will check ‘extents' state, if the state is `extent_state_dirty`, it will add the extents to `arena->extents_muzzy`, and if the state is `extent_state_muzzy`, the extent will return to system by `extent_dalloc_wrapper`.

Default dirty decay time 10 seconds(`DIRTY_DECAY_MS_DEFAULT`) and default muzzy decay time is 0(MUZZY_DECAY_MS_DEFAULT).

## Others

Memory allocation is important for application performance, there are many different implementation[3][4][5][6] or designed for special purpose[7][8].

JeMalloc provides per CPU arena but this feature has been disabled by default.

TCMalloc uses per-thread mode first and it doesn't work well when an application has a large thread count. Then TCMalloc migrated to the per-CPU approach[8].

Slab allocator[5] is used for kernel object caching which has specific consideration about cache line usage. JeMalloc relies on multiple arenas and allows applications to pad the memory[3].

The cache line will be helpfull in some cases but not all cases. CPHash[9] does some comparison about this, CPHash is a hash table which designed for reducing cache missing. In its benchamrk, when the hash table's memory usage is bigger than L3 cache, the performance wil drop and is limitted by DRAM.

Erlang VM creates one thread for every CPU which is used for scheduling Erlang processes, so it's easier to do per-CPU related things. And Erlang has different allocators for different usages, such as `ets_alloc` for in-memory key-value storage, `temp_alloc` for temporary allocations, and it can specify different fit algorithms for different allocators[6].

MICA[7] is in-memory key-value storage. In its cache mode, memory management is very interesting. It organizes its memory as a fix-sized circular log, and key-value items will be appended to the tail of the log. When the circular log is full, items will be evicted from the head. So no need for garbage collection and defragmentation.

LAMA is designed for solving slab calcification[11], this problem may occur in the default Memcached server, Memcached allocates different size memory from the different slabs. The memory allocator needs to consider how to evict item(s) when no free memory. LAMA is designed for distributing memory to different slabs dynamically based on the access pattern for reducing the miss rate.

## Summary
In this article, instead of describing the detail such as each structure's fields or how its extent rtree works, I focus on introducing the relationship between different structures and how those structures work together for allocating and deallocating memory. Hope it is helpful for people who want to understand how JeMalloc works.


## References
1. JeMalloc
   https://github.com/jemalloc/jemalloc/releases/tag/5.2.0
2. Smoothstep
   https://en.wikipedia.org/wiki/Smoothstep
3. A Scable Concurrent malloc(3) Implementation for FreeBSD
4. TCMalloc
   https://github.com/google/tcmalloc
5. The Slab Allocator: An Object-Caching Kernel Memory Allocator
6. Erlang memory allocator
   https://github.com/erlang/otp/blob//OTP-25.1.1/erts/emulator/beam/erl_alloc.c
7. MICA: A Holistic Approach to Fast In-Memory Key-Value Storage
8. TCMalloc : Thread-Caching Malloc
   https://google.github.io/tcmalloc/design.html
9. CPHash: A Cache-Partitioned Hash Table
10. LAMA: Optimized Locality-aware Memory Allocation for Key-value Cache
11. Caching with twemcache.
    https://blog.twitter.com/2012/caching-with-twemcache

```
haha
and the edata_t is the metadata representation structure for a given page, all the way from the page allocators down to the slab management stuff
"slab" in the sense of "region of memory dedicated to objects of a particular size" (sometimes called magazine)
and so, when the system has a 64k page size
we naturally inherit 64k slab sizes
so if you're allocating (say) 256 byte objects out of a given slab, then for a slab to get reused with 4k pages, 16 slots have to be unused, but with 64k pages 256 slots have to be unused
which ends up being less likely
so it hurts fragmentation
arguably what you should do in that situation is break up a 64k page into 16 4k new-thing-thats-in-between-a-page-and-a-slab
but we just haven't done that
```

haha
and the edata_t is the metadata representation structure for a given page, all the way from the page allocators down to the slab management stuff
"slab" in the sense of "region of memory dedicated to objects of a particular size" (sometimes called magazine)
and so, when the system has a 64k page size
we naturally inherit 64k slab sizes
so if you're allocating (say) 256 byte objects out of a given slab, then for a slab to get reused with 4k pages, 16 slots have to be unused, but with 64k pages 256 slots have to be unused
which ends up being less likely
so it hurts fragmentation
arguably what you should do in that situation is break up a 64k page into 16 4k new-thing-thats-in-between-a-page-and-a-slab
but we just haven't done that