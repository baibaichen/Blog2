# 起底 C++ Range 令人惊讶的局限性！ 

> https://www.fluentcpp.com/2019/09/13/the-surprising-limitations-of-c-ranges-beyond-trivial-use-cases/

> 作者注：今天我们收到了一个来自Alex Astashyn 的客座帖子。Alex是美国国家生物技术信息中心的 Reference Sequenc （标准序列）资源的技术负责人。
>
> > 注：本文所表达的观点是该帖子作者的观点。而且，我自己也不能算是个 range 专家，所以有些与 range 有关的信息实际上可能是不正确的（如果你发现有任何严重错误，请在下面留下你的评论）。
>
> 在本文中，我将讨论我在C++ range上遇到的问题和局限性。我还将介绍我自己开发的库rangeless，它将所有我希望由 range 实现的功能提炼在一起，使得我能够处理更大范围的有趣的实际应用用例。

# 序言

和所有爱好面向函数的声明式无状态编程的开发者一样，我原以为 ranges 非常有前途。然而，在实践中使用它们的尝试，被证明是一个非常令人沮丧的经历。

我一直在尝试用 range 写出那些对我来说似乎很合理的代码，然而，编译器却不断地打印出一页页让我无法理解的错误消息。最后我意识到了我自己的错误。我原以为range和这样的UNIX管道一样：`cat file | grep ... | sed ... | sort | uniq -c | sort -nr | head -n10`，但事实并非如此……

# 示例

## 示例1：Intersperse(插入分隔符)

让我们尝试编写一个view，在输入元素之间插入一个分隔符。此功能由range-v3提供，因此我们可以比较一下这些方法的不同

```c++
// inputs:    [x1, x2, ... xn] 
// transform: [[x1, d], [x2, d], ... [xn, d]]
// flatten:   [ x1, d, x2, d, ... xn, d ]
// drop last: [ x1, d, x2, d, ... xn ]

auto intersperse_view = view::transform(
  [delim](auto inp){
    return std::array<decltype(inp), 2>{{ std::move(inp), delim }};
  }
) | view::join // also called concat or flatten in functional languages
  | view::drop_last(1); // drop trailing delim
```

上面  `transform | join` 的组合x是对流的一种常见操作，该操作将每个输入转换为一个输出序列，并对结果序列进行展平。

```c++
[x] -> (x -> [y]) -> [y]
```

有些语言对此有单独的抽象，例如 Elixir 语言中的 `flat_map` 或 LINQ 中的 `SelectMany`。基于[最小惊呀的原则](https://www.youtube.com/watch?v=5tg1ONG18H8)，看来上述办法应该奏效。（如果你还没看过这篇演讲，那说明我推荐的力度还不够）。

但是，上面的代码与 range-v3 一起无法编译通过。出什么事了？结果发现问题在于 view::join 不喜欢 subrange（子范围 - 返回的集合）是一个作为右值（rvalue）返回的容器这一事实。我想出了以下的技巧：（有时）用这些视图（view）的右值组成视图，所以让我们将容器返回值包装为一个视图！

```c++
       view::transform([delim](auto inp)
        {
            return view::generate_n([delim, inp, i = 0]() mutable
            {
                return (i++ == 0) ? inp : delim;
            }, 2);
        })
```

或者，概括地说，我们可以返回一个容器，例如向量，作为其他用例的视图：

```c++
        view::transform([](int x)
        {
            auto vec = ... ;
            return view::generate_n([i = 0, vec = std::move(vec)]() mutable
            {
                return std::move(vec[i++]);
            }, vec.size());
        })
      | view::join // now join composes with transform
```

这是不是很聪明的做法？也许是吧，但是必须想出一些巧妙的技巧来做一些基本的事情，这并不是一个好兆头。

事实证明，我不是第一个遇到此问题的人。range 库的实现者们提出了他们自己的变通方法。正如 Eric Niebler 在此处指出的那样，我的解决方案是**非法的**，因为通过在视图中捕获向量不再满足 O（1）复制复杂性的要求。

也就是说，如果我们看看在 view::generate 或 view::generate_n 后台发生的事，我们就会看到它们缓存了最后一个生成的值，因此让view :: generate 成生 std :: string 或 std :: vector， 或一种包含这些类型的类型，你就已经不满足库的要求了。

这个例子我们讲完了吗？差不多了。

接下来，我们讲讲最后的两行代码：

```c++
       ...
      | view::join
      | view::drop_last(1);
```

你可能会认为 `drop_last` 在内部会将 n 个元素的队列保留在循环缓冲区中，并在最后一个输入到达时简单地将其丢弃。然而，range-v3视图可能不会缓冲元素，因此 `view::drop_last` 必须在输入上施加 `SizedRange` 或 `ForwardRange` 约束，而 `view::join` 返回一个 `InputRange`（即使它接收到一个 `ForwardRange` 作为输入）。这不仅扼杀了组合，也扼杀了任何延迟计算的希望（你必须立刻将整个 `InputRange`（希望是有限的）转储到 `std::vector`，然后将其转换为一个 `ForwardRange` ）。

那么，我们将如何实现这一点呢？我们稍后再谈……

## 示例 2

下面是一个使用 rangeless 库实现的示例（这是 [Knuth-vs-McIlroy 挑战](https://leancrew.com/all-this/2011/12/more-shell-less-egg/)的一个稍作修改的版本，使其更加有趣）。

```c++
namespace fn = rangeless::fn;
using fn::operators::operator%;

//
// Top-5 most frequent words from stream chosen among the words of the same length.
//
auto my_isalnum = [](const int ch)
{
  return std::isalnum(ch) || ch == '_';
};
fn::from( // (1)
  std::istreambuf_iterator<char>(std::cin.rdbuf()),
  std::istreambuf_iterator<char>{ /* end */ })
  % fn::transform([](const char ch) // (2)
                  {
                    return std::tolower(uint8_t(ch));
                  })
  % fn::group_adjacent_by(my_isalnum) // (3)
  // (4) build word->count map
  % fn::foldl_d([&](std::map<std::string, size_t> out, const std::string& w)
                {
                  if(my_isalnum(w.front())) {
                    ++out[ w ];
                  }
                  return out; // NB: no copies of the map are made
                              // because it is passed back by move.
                })
  % fn::group_all_by([](const auto& kv) // (5) kv is (word, count)
                     {
                       return kv.first.size(); // by word-size
                     })
  % fn::transform( // (6)
  fn::take_top_n_by(5UL, fn::by::second{})) // by count
  % fn::concat() // (7) Note: concat is called _join_ in range-v3
  % fn::for_each([](const auto& kv)
                 {
                   std::cerr << kv.first << "\t" << kv.second << "\n";
                 });
```

正如你所看到的，这段代码在风格上与ranges非常相似，但是其幕后工作方式完全不同（稍后我们将进行讨论）。

尝试使用range-v3重写此代码时，我们会遇到以下问题：

- (3)处：这将不起作用，因为view::group_by需要一个ForwardRange或更强的约束。
- (4)处：如何使用ranges进行可组合的左折叠（filter/map/reduce习惯用法的三大支柱之一）？ranges::accumulate是一个可能的候选对象，但它不是“pipeable”，而且也不符合移动语义（面向数字）。
- (5)处：foldl_d返回一个满足ForwardRange要求的STD::MAP，但由于它是一个右值，因此不会与下游的group-by组合。Ranges中没有group_all_by，因此我们必须先将中间结果转储到左值（lvalue）中才能应用sort(排序)操作
- (6和7)处：transform，concat：这与我们在“intersperse”示例中已经看到的问题相同，在那个示例中，range-v3无法展平右值（rvalue）容器序列。

## 示例3：Transform-in-parallel（并行转换）

下面的函数取自 [aln_filter.cpp](https://github.com/ast-al/rangeless/blob/master/test/aln_filter.cpp) 示例。（顺便说一下，它展示了在适用的用例中数据流延时操作的有用性）。

`lazy_transform_in_parallel` 的目的是执行与普通 transform 相同的工作，不同之处在于，每次对 transform 函数的调用都与不超过指定数量的同时异步任务并行执行。与 c ++ 17 的并行化 `std：：transform` 不同的是，我们希望它可以和延时的 InputRange 一起工作。

```C++
static auto lazy_transform_in_parallel = [](auto fn,
                                           size_t max_queue_size = std::thread::hardware_concurrency())
{
    namespace fn = rangeless::fn;
    using fn::operators::operator%;
    assert(max_queue_size >= 1);
    return [max_queue_size, fn](auto inputs) // inputs can be an lazy InputRange
    {
        return std::move(inputs)
        //-------------------------------------------------------------------
        // Lazily yield std::async invocations of fn.
      % fn::transform([fn](auto inp)
        {
            return std::async(std::launch::async,
                [inp = std::move(inp), fn]() mutable // mutable because inp will be moved-from
                {
                    return fn(std::move(inp));
                });
        })
        //-------------------------------------------------------------------
        // Cap the incoming sequence of tasks with a seq of _max_queue_size_-1
        // dummy future<...>'s, such that all real tasks make it
        // from the other end of the sliding-window in the next stage.
      % fn::append(fn::seq([i = 1UL, max_queue_size]() mutable
        {
            using fn_out_t = decltype(fn(std::move(*inputs.begin())));
            return i++ < max_queue_size ? std::future<fn_out_t>() : fn::end_seq();
        }))
        //-------------------------------------------------------------------
        // Buffer executing async-tasks in a fixed-sized sliding window;
        // yield the result from the oldest (front) std::future.
      % fn::sliding_window(max_queue_size)
      % fn::transform([](auto view) // sliding_window yields a view into its queue
        {
            return view.begin()->get();
        });
    };
};
```

有人会认为这包含了所有可以用 ranges 实现的部分，但事实并非如此。明显的问题是 `view::sliding` 需要一个 `ForwardRange`。即使我们决定实现 sliding 的一个“非法”的缓存版本，仍有更多问题在代码中不可见，但会在运行时显现：

在 range-v3 中，view::transform 的正确用法取决于以下假设：

- 重新计算很便宜（这一点对在上例中的第一个 transform 中并不适用，因为它逐个接受和传递 input 输入，并启动一个异步任务）。
- 可以在同一个 input 上多次调用它（这对于第二个 transform 不起作用，因为对 `std::future::get` 的调用使它处于无效状态，因此只能被调用一次）。

如果 transform 函数类似于**加一**或**对一个整数取平方**，那么上面的这些假设可能很正确，但是如果 transform 函数需要查询数据库或生成一个进程以运行一个繁重的任务，那么这些假设会有点自以为是了。这个问题和 Jonathan在[**智能迭代器增加的一个可怕问题**](https://www.fluentcpp.com/2019/02/12/the-terrible-problem-of-incrementing-a-smart-iterator/)中描述的问题如出一辙。这种行为不是一个 bug，显然是[设计使然](https://github.com/ericniebler/range-v3/issues/1055) –– 这是我们无法很好地使用 range-v3 的另一个原因。在 rangeless 中，`fn::transform` 既不会对同一 `input` 上多次调用 `transform` 函数，也不会缓存结果。

注：rangeless 库中提供了 `transform_in_parallel`。比较 rangless （Ctrl+F pigz） 和 RaftLib 是如何实现并行 gzip 压缩的。

上面这一切的结论是什么呢？

# Ranges的复杂性

> 我们需要一种合理一致的语言，可以被“普通程序员”使用，他们的主要关注点是准时交付优秀的应用程序。
>
> -- Bjarne Stroustrup

Ranges简化了基本用例的代码，比如说，你可以编写 `action::sort(vec)` 来代替 `std::sort(vec.begin, vec.end)`。然而，除了最基本的用法以外，它会导致代码的复杂度呈指数级增长。举个例子，如何实现上述的 intersperse 适配器？

让我们先看看 Haskell 语言写的的示例，看看我们心目中的“简单”应该是什么样子的。

```haskell
intersperse ::  a -> [ a ] -> [ a ]
intersperse     _ [ ] = [   ]
intersperse     _ [ x ] = [ x ]
intersperse delim    (x:xs) = x : delim : intersperse delim xs
```

即使你一生中从未见过Haskell代码，你也可能知道上面的代码是如何工作的。

下面是使用 rangeless 来完成它的三种不同的方法。就像 Haskell 的签名一样，my_intersperse 接受delim 作为参数并返回一个一元可调用函数，该函数可以接受 Iterable 参数并返回一个产生元素的序列 - interspersing delim。

A)  作为一个 generator 函数使用：

```c++
auto my_intersperse = [](auto delim)
{
    return [delim = std::move(delim)](auto inputs)
    {
        return fn::seq([  delim,
                         inputs = std::move(inputs),
                             it = inputs.end(),
                        started = false,
                           flag = false]() mutable
        {
            if(!started) {
                started = true;
                it = inputs.begin();
            }
            return it == inputs.end() ? fn::end_seq()
                 :     (flag = !flag) ? std::move(*it++)
                 :                      delim;
        });
    };
};
```

B) 通过使用rangeless中的 `fn::adapt` 这个用来实现自定义适配器的工具：

```c++
auto my_intersperse = [](auto delim)
{
    return fn::adapt([delim, flag = false](auto gen) mutable
    {
        return           !gen ? fn::end_seq()
             : (flag = !flag) ? gen()
             :                  delim;
    });
};
```

C) 作为现有功能的组成部分（我们尝试用range-views实现但未能实现的功能）：

```c++
auto my_intersperse = [](auto delim)
{
    return [delim = std::move(delim)](auto inputs)
    {
        return std::move(inputs)
      % fn::transform([delim](auto inp)
        {
            return std::array<decltype(inp), 2>{{ std::move(inp), delim }};
        })
      % fn::concat()
      % fn::drop_last(); // drop trailing delim
    };
};
```

D) 我们也可以将 intersperse 作为[一个协程（coroutine）](https://coro.godbolt.org/z/3r_T0D)来实现，而无需借助于 `rangeless::fn`。

```c++
template<typename Xs, typename Delim>
static unique_generator<Delim> intersperse_gen(Xs xs, Delim delim)
{
    bool started = false;
    for (auto&& x : xs) {
        if(!started) {
            started = true;
        } else {
            co_yield delim;
        }
        co_yield std::move(x);
    }
};

auto my_intersperse = [](auto delim)
{
    return [delim](auto inps)
    {
        return intersperse_gen(std::move(inps), delim);
    };
};
```

上述所有的实现在代码复杂度方面都差不多。现在让我们看看 range-v3 实现的样子：[intersperse.hpp](https://github.com/ericniebler/range-v3/blob/master/include/range/v3/view/intersperse.hpp)。就我个人而言，这看起来非常复杂。如果你对它的复杂度印象还不够深刻的话，考虑一下作为一个协程来实现笛卡尔乘积的情形：

```c++
template<typename Xs, typename Ys>
auto cartesian_product_gen(Xs xs, Ys ys) 
  -> unique_generator<std::pair<typename Xs::value_type,
                                typename Ys::value_type>>
{
    for(const auto& x : xs)
        for(const auto& y : ys)
            co_yield std::make_pair(x, y);
}
```

我们把以上实现与 [range-v3](https://github.com/ericniebler/range-v3/blob/master/include/range/v3/view/cartesian_product.hpp) 的实现作一番比较。用 range-v3 编写视图应该很容易，但是，正如示例所示，在后现代 C++ 中被认为**容易**的标准已经提高到了普通人无法企及的高度。

应用程序代码中涉及 range 的情况并不简单。

如果我们比较一下日历格式化应用程序的 [Haskell](https://github.com/BartoszMilewski/Calendar/blob/master/Main.hs)，[Rust](https://play.rust-lang.org/?gist=1057364daeee4cff472a&version=nightly)，[rangeless](https://github.com/ast-al/rangeless/blob/gh-pages/test/calendar.cpp) 和 r[ange-v3](https://github.com/ericniebler/range-v3/blob/master/example/calendar.cpp) 的实现。我不知道你的情况如何，但最后一个实现（使用range-v3）并没有激发我去理解或编写这样的代码的热情。

注意，在 range-v3 的示例中，，开发者通过一 个std::vector 字段打破了在 `interleave_view` 本身的视图复制复杂度要求。

## Range views 的抽象泄漏

如果你回到上面基于range-v3库的intersperse和日历应用程序，并对其进行更详细的研究，你就会看到在视图的实现中，我们最终都是直接处理迭代器，实际上需要做非常多的事情。

除了在一个 range 上调用 sort 之外或某些类似的操作外，ranges 并不能避免让你直接处理迭代器。相反，它是**以额外的步骤处理迭代器**。

## 编译时间开销

Range-v3 因其编译时间而臭名昭著。在我的机器上，上述日历示例的编译时间超过20秒，而相应的rangeless实现的编译可以2.4秒内完成，其中1.8秒是为了include<gregorian.hpp>，这几乎相差了整整一个数量级！

编译时间已经变成了C++开发中每天面临的一个大问题，而range让它变得更糟！以我个人的情况为例，仅仅编译时间这一项就排除了在生产代码中使用range的任何可能性。

# Rangeless 库

对于rangeless库，我没有想要浪费时间做无用功，而是遵循函数式编程语言中的streaming库（如Haskell的Data.List，Elixir的Stream，F#的 Seq，以及和LINQ）的设计。

与range-v3库不同，rangeless库没有ranges、views或actions，只是通过一个一元可调用函数链将值从一个函数传递到下一个函数，其中的一个值是容器或序列（输入范围，有界或无界）。

有一点语法上的甜头：

```c++
operator % (Arg arg, Fn fn) -> decltype(fn(std::forward<Arg>(arg)))
auto x1 = std::move(arg) % f % g % h; // same as auto x1 = h(g(f(std::move(arg))));
```

这相当于 Haskell 语言中的**中缀运算符 &** 或 F#语言中的 **|> 运算符**。它允许我们以与数据流方向基本上一致的方式构造代码。这种方式对于一个单行的函数并没有什么影响，但是对于那些就地定义的多行 lambda 函数，就会很有帮助。

你可能想知道，为什么这里明确地使用 `operator %`，而不用 `>>` 或者 `|` 操作符呢？ C++的可重载二进制运算符的列表并不长，前者往往由于流而大量地重载，而管道运算符通常用于**智能标志**或**==链接==**，也称为无指针组合，如 range 中。我考虑过使用可重载的运算符 `operator->*` ，但最终还是决定使用运算 `operator %` ，因为考虑到上下文，它不太可能与整数取模运算混淆，而且还具有可以用于更改 LHS（运算符左边的操作数）状态的“%=”对应项，例如：

```c++
vec %= fn::where(.../*satisfies-condition-lambda*/);
```

这里的输入要么是一个序列，要么是一个容器，输出也是一样。例如，fn::sort需要所有元素来完成它的工作，所以它会将整个输入序列转储到std::vector中，对其进行排序，然后返回std::vector。

另一方面，一个fn::transform将按值获取的输入封装为一个序列，它将惰性地生成转换后的输入元素。从概念上讲，这类似于一个带有eager sort和lazy sed的UNIX管道。

与range-v3中不同的是，input-ranges（序列）在rangeless中是一等公民。我们在range-v3中看到的由于实参(argument)和形参(parameter)之间概念不匹配而导致的问题是不存在的（例如，在期望有ForwardRange的地方，但却收到了InputRange这样的问题）。只要值类型兼容，一切都是可组合的。

# 结束语

我尝试过用ranges来编写表达性的代码。我是唯一那个经常“错误地使用它”的人吗？

当我得知委员会在C++20标准中接纳了range时，我相当惊讶，大多数C++专家对此都很兴奋。看起来好象上面提到的这些问题（有局限的可用性、代码复杂性、漏洞百出的抽象和完全不合理的编译时间）对委员会成员没有任何影响一样。

我觉得这一点严重背离了率先开发这门语言的C++专家和那些想用更简单的方法来做复杂事情的普通程序员的初衷。在我看来，似乎所有人都对C++之父（Bjarne Stroustrup）在Remember the Vasa的发出的呼吁充耳不闻（当然，这是我个人的主观看法）。

https://www.reddit.com/r/cpp/comments/d3qkas/the_surprising_limitations_of_c_ranges_beyond/
