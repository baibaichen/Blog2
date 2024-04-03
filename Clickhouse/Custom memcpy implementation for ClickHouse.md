# Custom memcpy implementation for ClickHouse.
 It has the following benefits over using glibc's implementation:

 1. Avoiding dependency on specific version of glibc's symbol, like `memcpy@@GLIBC_2.14` for portability.
 2. Avoiding indirect call via PLT due to shared linking, that can be less efficient.
 3. **It's possible to include this header and call `inline_memcpy` directly for better inlining or ==interprocedural== analysis.**
 4. Better results on our performance tests on current CPUs: up to 25% on some queries and up to 0.7%..1% in average across all queries.

 Writing our own memcpy is extremely difficult for the following reasons:
 1. The optimal variant depends on the specific CPU model.
 2. The optimal variant depends on the distribution of size arguments.
 3. It depends on the number of threads copying data concurrently.
 4. It also depends on how the calling code is using the copied data and how the different memcpy calls are related to each other.

Due to vast range of scenarios it makes proper testing especially difficult. When writing our own memcpy there is a risk to overoptimize it on non-representative microbenchmarks while making real-world use cases actually worse. Most of the benchmarks for memcpy on the internet are wrong.

Let's look at the details:

**For small size**, the order of branches in code is important. There are variants with specific order of branches (like here or in glibc) or with jump table (in asm code see example from [Cosmopolitan libc](https://github.com/jart/cosmopolitan/blob/de09bec215675e9b0beb722df89c6f794da74f3f/libc/nexgen32e/memcpy.S#L61)) or with [Duff device in C](https://github.com/skywind3000/FastMemcpy/). It's also important how to copy uneven sizes. Almost every implementation, including this, is using two overlapping movs. It is important to disable `-ftree-loop-distribute-patterns` when compiling memcpy implementation, otherwise the compiler can replace internal loops to a call to memcpy that will lead to infinite recursion.

 **For larger sizes** it's important to choose the instructions used:

1. SSE or AVX or AVX-512;
2. rep movsb;

Performance will depend on the size threshold, on the CPU model, on the "erms" flag ("Enhansed Rep MovS" - it indicates that performance of "rep movsb" is decent for large sizes). see [Enhanced REP MOVSB for memcpy](https://stackoverflow.com/questions/43343231/enhanced-rep-movsb-for-memcpy).

Using AVX-512 can be bad due to throttling.  Using AVX can be bad if most code is using SSE due to switching penalty (it also depends on the usage of "vzeroupper" instruction). But in some cases AVX gives a win.

It also depends on how many times the loop will be unrolled. We are unrolling the loop 8 times (by the number of available registers), but it not always the best.

It also depends on the usage of aligned or unaligned loads/stores. We are using unaligned loads and aligned stores.

 It also depends on the usage of prefetch instructions. It makes sense on some Intel CPUs but can slow down performance on AMD. Setting up correct offset for prefetching is non-obvious.

Non-temporary (cache bypassing) stores can be used for very large sizes (more than a half of L3 cache). But the exact threshold is unclear - when doing memcpy from multiple threads the optimal threshold can be lower, because L3 cache is shared (and L2 cache is partially shared).

Very large size of memcpy typically indicates suboptimal (not cache friendly) algorithms in code or unrealistic scenarios, so we don't pay attention to using non-temporary stores.

On recent Intel CPUs, the presence of "erms" makes "rep movsb" the most beneficial, even comparing to non-temporary aligned unrolled stores even with the most wide registers.

memcpy can be written in asm, C or C++. The latter can also use inline asm. The asm implementation can be better to make sure that compiler won't make the code worse, to ensure the order of branches, the code layout, the usage of all required registers. But if it is located in separate translation unit, inlining will not be possible (inline asm can be used to overcome this limitation). Sometimes C or C++ code can be further optimized by compiler. For example, clang is capable replacing SSE intrinsics to AVX code if -mavx is used. Please note that compiler can replace plain code to memcpy and vice versa.
 - memcpy with compile-time known small size is replaced to simple instructions without a call to memcpy; it is controlled by `-fbuiltin-memcpy` and can be manually ensured by calling `__builtin_memcpy`. This is often used to implement unaligned load/store without undefined behaviour in C++.
 - a loop with copying bytes can be recognized and replaced by a call to memcpy; it is controlled by `-ftree-loop-distribute-patterns`.
 - also note that a loop with copying bytes can be unrolled, peeled and vectorized that will give you inline code somewhat similar to a decent implementation of memcpy.

This description is up to date as of Mar 2021. How to test the memcpy implementation for performance:

 1. Test on real production workload.
 2. For synthetic test, see utils/memcpy-bench, but make sure you will do the best to exhaust the wide range of scenarios.

> TODO: 
>
> - [ ] Add self-tuning memcpy with bayesian bandits algorithm for large sizes.  See https://habr.com/en/company/yandex/blog/457612/