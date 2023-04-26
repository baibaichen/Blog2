# 可见性

**Note:** the text on this page was almost entirely written by Niall Douglas, the original author of the patch, and placed on [nedprod.com](http://www.nedprod.com/). This copy in the GCC wiki has some corrections that may not be present on Niall's site.

[写 Linux 动态库的最佳实践](https://www.jianshu.com/p/143a059224aa)

[A compiler option, a hidden visibility, and a weak symbol walk into a bar](https://developers.redhat.com/articles/2021/10/27/compiler-option-hidden-visibility-and-weak-symbol-walk-bar)

## 为什么新的C++可见性支持如此有用？

简而言之，它隐藏了大多数以前（并且不必要地）公开的 ELF 符号。这意味着：

- **大大缩短了 DSO（动态共享对象）的加载时间**。例如，经过测试的一个巨大的基于 C++ 模板的库（TnFOX Boost.Python 绑定库）现在加载时间为 8 秒，而不是超过 6 分钟！
- **让优化器产生更好的代码**。PLT 间接寻址可以完全避免（例如在 PIC 代码中，必须通过全局偏移表查找函数调用或变量访问），从而大大避免现代处理器上的流水线停顿，从而产生更快的代码。此外，当大多数符号在本地绑定时，它们可以通过整个 DSO 安全地完全省略（删除）。这为内联提供了更大的自由度，它不再需要为了**以防万一**保留一个入口点。
- **将 DSO 的大小减少 5-20%**。ELF 的导出符号表格式非常占用空间，给出完整的错位符号名称，模板使用量大时平均约为 1000 字节。C++ 模板会产生大量符号，典型的 C++ 库可以轻松超过 30,000 个符号，大约 5-6Mb！ 因此，如果您剪掉 60-80% 的不必要符号，您的 DSO 可以变小好多 MB！
- **符号冲突的可能性大大降低**。两个库在内部使用相同符号表示不同事物的旧祸在这个补丁中终于过去了。哈利路亚！

虽然上面引用的库是一个极端案例，但新的可见性支持将导出的符号表从 > 200,000 个符号减少到不到 18,000 个。二进制大小也减少了大约 21Mb！

有些人可能会建议 GNU 链接器版本脚本也能做到这一点。也许对于 C 程序来说这是真的，但对于 C++ 来说它不可能是真的——除非你费力地指定每个公开的符号（以及它的复杂的错位名称），否则你必须使用通配符，这往往会让很多虚假符号 通过。如果您决定更改类或函数的名称，则必须更新链接描述文件。在上面的库中，作者无法使用版本脚本获取低于 40,000 个符号的符号表。此外，使用链接器版本脚本不允许 GCC 更好地优化代码。

### Windows 兼容性

对于在 Windows 和 POSIX 上开发过任何大型便携式应用程序的人来说，您都会感到沮丧，因为 GCC 的非 Windows 构建不提供与 `__declspec(dllexport)` 等效的功能，即将C/C++接口标记为共享库的功能。==沮丧是因为良好的 DSO 接口设计与良好的类设计或正确地不透明内部数据结构对于健康的编码同样重要==。

虽然 Windows DLL 和 ELF DSO 的语义不同，但几乎所有基于 Windows 的代码都使用宏来在编译时选择是使用`dllimport` 还是 `dllexport`。这个机制可以很容易地通过这个补丁重用，因此添加对任何已经能够编译为 Windows DLL 的支持实际上只需五分钟的操作。

注意：Windows 和此 GCC 功能之间的语义不同 - 例如，`__declspec(dllexport) void (*foo)(void)` 和 `void (__declspec(dllexport) *foo)(void)` 的意思是完全不同事情，而这会生成一条警告，说明无法将属性应用于 GCC 上的非类型。

### 还是不相信？

关于良好 DSO 设计主题的进一步阅读是 Ulrich Drepper（GNU glibc 的主要维护者）的 [这篇文章](http://people.redhat.com/drepper/dsohowto.pdf)。

## 如何使用新的 C++ 可见性支持

在你的头文件中，无论你想在当前 DSO 之外公开一个接口或 API，将 `__attribute__ ((visibility ("default"))))` 放在你希望公开的结构、类和函数声明中（如果你将它 定义为一个宏会更容易）。您不需要在定义中指定它。然后，修改您的 make 系统，编译每个源文件时将 `-fvisibility=hidden` 传递给 GCC。如果您跨共享对象边界抛出异常，请参阅下面的 **C++ 异常问题* 部分。在输出的 DSO 上使用 `nm -C -D` 来比较前后的差异，看看它有什么不同。

一些语法示例：

```c++
#if defined _WIN32 || defined __CYGWIN__
  #ifdef BUILDING_DLL
    #ifdef __GNUC__
      #define DLL_PUBLIC __attribute__ ((dllexport))
    #else
      #define DLL_PUBLIC __declspec(dllexport) // Note: actually gcc seems to also supports this syntax.
    #endif
  #else
    #ifdef __GNUC__
      #define DLL_PUBLIC __attribute__ ((dllimport))
    #else
      #define DLL_PUBLIC __declspec(dllimport) // Note: actually gcc seems to also supports this syntax.
    #endif
  #endif
  #define DLL_LOCAL
#else
  #if __GNUC__ >= 4
    #define DLL_PUBLIC __attribute__ ((visibility ("default")))
    #define DLL_LOCAL  __attribute__ ((visibility ("hidden")))
  #else
    #define DLL_PUBLIC
    #define DLL_LOCAL
  #endif
#endif

extern "C" DLL_PUBLIC void function(int a);
class DLL_PUBLIC SomeClass
{
   int c;
   DLL_LOCAL void privateMethod();  // Only for use within this DSO
public:
   Person(int _c) : c(_c) { }
   static void foo(int a);
};
```

这也有助于生成更优化的代码：当您声明在当前编译单元之外定义的内容时，GCC 在编译结束之前，无法知道该符号是驻留在当前编译单元 DSO 的内部还是外部，因此，GCC 必须假设最坏的情况，并通过 GOT（全局偏移表）路由所有内容，这会在代码空间，以及**动态链接器**执行额外（昂贵）的重定位方面带来开销。要告诉 GCC 在当前 DSO 中定义了一个类、结构、函数或变量，您必须在其头文件声明中手动指定隐藏可见性（使用上面的示例，您使用 `DLLLOCAL` 声明此类内容）。这会让 GCC 生成最佳代码。

但这当然很麻烦：这就是添加 `-fvisibility`的原因。使用 `-fvisibility=hidden`，告诉 GCC 每个未明确标记可见性属性的声明都隐藏可见性。就像上面的例子一样，即使对于标记为可见的类（从 DSO 导出），您可能仍然想要将**私有成员**标记为隐藏，以便在调用它们时（在 DSO 内部）生成最佳代码。

为了帮助您转换旧代码以使用新系统，GCC 现在还支持 `#pragma GCC visibility` 命令：

```c++
extern void foo(int);
#pragma GCC visibility push(hidden)
extern void someprivatefunct(int);
#pragma GCC visibility pop
```

`#pragma GCC visibility` 比 `-fvisibility` 强； 它也会影响外部声明。`-fvisibility` 只影响定义，因此现有代码可以通过最小的更改重新编译。C 比 C++ 更是如此； C++ 接口倾向于使用受 `-fvisibility` 影响的类。

最后，还有一个新的命令行开关：`-fvisibility-inlines-hidden`。这会导致所有内联类成员函数都具有隐藏的可见性，从而导致导出符号表大小和二进制大小显着减少，尽管不如使用 `-fvisibility=hidden` 那么多。但是，`-fvisibility-inlines-hidden` 可以在不更改源代码的情况下使用，除非您需要为内联覆盖它，其中地址身份对于函数本身或任何函数本地静态数据都很重要。

## C++异常的问题（请阅读！）

<u>在引发异常的二进制文件之外的二进制文件中捕获用户定义的类型</u>需要类型信息查找。**回去再读一遍上一句话**。当异常开始神秘地发生故障时，原因就是这个！

就像函数和变量一样，在多个共享对象之间抛出的类型是公共接口，必须具有默认可见性。显而易见，第一步是将所有跨共享对象边界抛出的类型始终标记为默认可见性。您必须这样做，因为即使（例如）异常类型的实现代码位于 DLL A 中，当 DLL B 抛出该类型的实例时，DLL C 中的捕获处理程序也会在 DLL B 中查找类型信息。

然而这不是故事的全部 —— 它变得更难了。默认情况下符号缺省可见，如果链接器只遇到一个可见性是隐藏的定义（只有一个），将永久隐藏 `typeinfo` 符号（记住 C++ 标准的 ODR ，一处定义规则）。这适用于所有符号，但更有可能影响 `typeinfo`； 对于没有 `vtable` 的类，是在每个使用 EH 类的 object 文件中按需定义`typeinfo`。并且是 Weak 定义，因此在链接时将定义合并为一个副本。

这样的结果是，如果你忘记了你的预处理器只在一个 object  文件中定义，或者如果在任何时候一个可抛出的类型没有明确声明为公共的，`-fvisibility=hidden` 将导致它在该目标文件中被标记为隐藏 ，它以默认可见性覆盖所有其他定义，并导致类型信息在输出的二进制文件中消失（然后该类型的任何抛出将导致捕获它的二进制文件调用 terminate() ）。您的二进制文件将完美链接并且看起来可以正常工作，即使它们不能正常工作。

虽然对此发出警告会很好，但有很多合理的理由让可抛出的类型远离公众视野。在将整个程序优化添加到 GCC 之前，编译器无法知道在本地捕获了哪些抛出。

其他[模糊链接](https://mentorembedded.github.io/cxx-abi/abi.html#vague)实体（例如类模板的静态数据成员）也会出现同样的问题。如果类具有隐藏的可见性，则数据成员可以在多个 DSO 中实例化并分别引用，造成严重破坏。

这个问题也出现在用作 `dynamic_cast` 操作数的类中。确保导出所有这样的类。

## Step-by-step guide

下面的说明是如何为您的库添加**全面支持**，以最大程度地减少二进制大小、加载时间和链接时间来生成最高质量的代码。所有新代码都应该从一开始就有这种支持！ 花几天时间来完全实现它是值得的，尤其是在速度关键的库中——这是一次一次性的时间投资，只会带来永远更好的结果。但您也可以在更短的时间内为您的库添加**基本支持**，不过不建议这样做。

- 在您的**主头文件**（或将在任何地方包含的特定头文件）中放置以下代码行中的内容。此代码取自上述 TnFOX 库：

```C++
// Generic helper definitions for shared library support
#if defined _WIN32 || defined __CYGWIN__
  #define FOX_HELPER_DLL_IMPORT __declspec(dllimport)
  #define FOX_HELPER_DLL_EXPORT __declspec(dllexport)
  #define FOX_HELPER_DLL_LOCAL
#else
  #if __GNUC__ >= 4
    #define FOX_HELPER_DLL_IMPORT __attribute__ ((visibility ("default")))
    #define FOX_HELPER_DLL_EXPORT __attribute__ ((visibility ("default")))
    #define FOX_HELPER_DLL_LOCAL  __attribute__ ((visibility ("hidden")))
  #else
    #define FOX_HELPER_DLL_IMPORT
    #define FOX_HELPER_DLL_EXPORT
    #define FOX_HELPER_DLL_LOCAL
  #endif
#endif

// Now we use the generic helper definitions above to define FOX_API and FOX_LOCAL.
// FOX_API is used for the public API symbols. It either DLL imports or DLL exports (or does nothing for static build)
// FOX_LOCAL is used for non-api symbols.

#ifdef FOX_DLL // defined if FOX is compiled as a DLL
  #ifdef FOX_DLL_EXPORTS // defined if we are building the FOX DLL (instead of using it)
    #define FOX_API FOX_HELPER_DLL_EXPORT
  #else
    #define FOX_API FOX_HELPER_DLL_IMPORT
  #endif // FOX_DLL_EXPORTS
  #define FOX_LOCAL FOX_HELPER_DLL_LOCAL
#else // FOX_DLL is not defined: this means FOX is a static lib.
  #define FX_API
  #define FOX_LOCAL
#endif // FOX_DLL
```

显然，您可能希望用适合您的库的前缀替换 `FOX`，对于还支持 Win32 的项目，您会发现上面的很多内容很熟悉（您可以重用大部分 Win32 宏机制来支持 GCC）。解释：

- 如果定义了 `_WIN32`（在为 Windows 构建时是自动的，即使对于 64 位系统也是如此）：

  - 如果定义了 `FOX_DLL_EXPORTS`，则正在构建库，并且应导出符号。因此，您将在构建 FOX DLL 的构建系统中定义 `FOX_DLL_EXPORTS`。默认情况下，在所有 IDE 项目中，以 `_EXPORTS` 结尾的内容 MSVC 定义（同 CMake 默认，参见 [CMake Wiki BuildingWinDLL](http://www.cmake.org/Wiki/BuildingWinDLL)）。

  - 如果 `FOX_DLL_EXPORTS` 未定义（使用库的客户端就是这种情况），我们将导入库，因此应该导入符号。

- 如果未定义 `_WIN32`（使用 GCC 构建 Unix 时就是这种情况）：

  - 如果 `__GNUC__ >= 4` 为真，则表示编译器是 GCC 4.0 或更高版本，因此支持新功能。

  - 对于库中的每个**非模板化非静态函数**定义（头文件和源文件），决定它是公开使用还是内部使用：

    - 如果它是公开使用的，像这样用 `FOX_API` 标记：`extern FOX_API PublicFunc()`

    - 如果只在内部使用，用 `FOX_LOCAL` 标记如下： `extern FOX_LOCAL PublicFunc()`，<u>请记住，静态函数不需要分界，也不需要任何模板化的东西</u>。

  - 对于库中的每个**非模板类定义**（头文件和源文件），确定它是公开使用还是内部使用：

    - 如果它是公开使用的，则用 `FOX_API` 标记如下：`class FOX_API PublicClass`

    - 如果仅供内部使用，则用 `FOX_LOCAL` 标记如下： `class FOX_LOCAL PublicClass`

      导出类中不属于接口的单个成员函数，特别是那些私有的，不被**友元代码**使用的成员函数，应该单独标记为 `FOX_LOCAL`。

  - 在您的构建系统（Makefile 等）中，您可能希望将 `-fvisibility=hidden` 和 `-fvisibility-inlines-hidden` 选项添加到每个 GCC 调用的命令行参数中。记住之后要彻底测试你的库，包括所有异常都正确地遍历共享对象边界。

如果您想查看之前和之后的结果，请使用命令 `nm -C -D <library>.so`，它以分解形式列出所有导出的符号。
