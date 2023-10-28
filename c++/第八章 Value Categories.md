# 第八章 Value Categories

本章介绍移动语义的正式术语和规则。我们正式介绍左值、右值、纯右值和将亡值等**值类别**，并讨论它们在将<u>引用</u>绑定到对象时的作用。这使我们还可以讨论<u>不自动传递</u>移动语义的规则的细节，以及为表达式调用 `decltype` 时非常微妙的行为。

本章是全书最复杂的一章。您可能会看到一些令人难以相信的棘手事实和特征。稍后，每当您阅读有关值类别、将引用绑定到对象和 `decltype` 的内容时，请再回来看看它。

## 8.1 值类别

要编译表达式或语句，不仅关系到所涉及的类型是否适合。例如，当赋值的左边使用 `int` 字面量时，你不能将 `int` 分配给 `int`：

```c++
int i = 42;
i = 77; // OK
77 = i; // ERROR
```

因此，C++ 程序中的每个表达式都有一个**值类别**。除了类型之外，值类别对于决定你可以用表达式做什么必不可少。

但是，C++ 中的值类别随时间发生了变化。

### 8.1.1 值类别的历史

历史上（取自 Kernighan&Ritchie C、K&R C），`值类别`只有 **lvalue** 和 **rvalue**。这些术语来自于赋值中允许的操作：

- **左值**可以出现在赋值的左边
- **右值**只能出现在赋值的右边

根据这个定义，当你使用 `int 对象/变量`时，你使用的是左值，但是当你使用 `int 字面量`时，你使用的是右值：

```c++
int x; // x is an lvalue when used in an expression
x = 42; // OK, because x is an lvalue and the type matches
42 = x; // ERROR: 42 is an rvalue and can be only on the right-hand side of an assignment
```

然而，这些类别不仅对赋值很重要。它们通常用于指定是否以及在何处可以使用表达式。例如：

```c++
int x;        // x is an lvalue when used in an expression
int* p1 = &x; // OK: & is fine for lvalues (object has a specified location)
int* p2 = &42;// ERROR: & is not allowed for rvalues (object has no specified location)
```

然而，使用 **ANSI-C** 时事情变得更加复杂，因为声明为 `const int` 的 `x` 不能位于赋值的左侧，但仍可以在其他几个只能使用左值的地方使用：

```c++
const int c = 42;  // Is c an lvalue or rvalue?
c = 42;            // now an ERROR (so that c should no longer be an lvalue)
const int* p1 = &c;// still OK (so that c should still be an lvalue)
```

C 中的决定是声明为 `const int` 的 `c` 仍然是一个**左值**，因为左值的大部分操作仍然可以为特定类型的 `const` 对象调用。你唯一不能再做的就是在赋值的左侧有一个 `const` 对象。

因此，在 ANSI-C 中，`l` 的含义更改为**有地址的值**。**左值**现在是程序中具有指定位置的对象（例如，这样您就可以获取地址）。同样，一个**右值**现在可以被认为只是一个**可读的值**。

C++98 采用了这些值类别的定义。然而，随着移动语义的引入，问题出现了，以 `std::move()` 标记的对象应该具有哪个值类别，因为以 `std::move()` 标记的类的对象应遵循以下规则：

```c++
std::string s;
...
std::move(s) = "hello"; // OK (behaves like an lvalue)
auto ps = &std::move(s); // ERROR (behaves like an rvalue)
```

但是，请注意基本数据类型 (FDT) 的行为如下：

```c++
int i;
...
std::move(i) = 42; // ERROR
auto pi = &std::move(i); // ERROR
```

除了基本数据类型之外，标有 `std::move()` 的对象应该仍然表现得像一个左值，允许您修改它的值。另一方面，也有不能取得地址等限制。

因此引入了一个新的类别 **xvalue**（将亡值），用于为显式标记为**我不再需要这里的值**（主要是用 `std::move()` 标记的对象）指定规则。但是，以前的右值的大多数规则也适用于 xvalues。因此，以前的主要值类别 **rvalue** 变成了一个复合值类别，现在代表新的基础值类别 **prvalue**（对于之前是右值的所有内容）和 **xvalue**。有关提出这些更改的论文，请参阅 http://wg21.link/n3055。

### 8.1.2 自 C++11 以来的值类别

从 C++11 开始，值类别如图 8.1 所示。

> - [ ] Figure 8.1.

我们有以下主要类别：

- lvalue（可定位的值）

- prvalue （纯读的值）

- xvalue（将亡值）


复合类别有：

- glvalue（广义左值）作为 lvalue 或 xvalue 的通用术语
- rvalue 作为 xvalue 或 prvalue 的通用术语

#### 基本表达式的值类别
lvalues 的示例有：

- 变量、函数或数据成员名称的表达式（rvalue 的**纯值成员**除外）
- 字符串常量表达式（例如 `“hello”`）
- 函数的返回值（如果声明返回**左值引用**）（返回类型为 `Type&`）
- 对函数的任何引用，即使标有 `std::move()` （<u>见下文</u>）
- 内置一元 `*` 运算符的结果（即，对原始指针**解引用**产生的结果）

prvalue 的例子有：

- 由内置的非字符串常量组成的表达式（例如 `42`、`true` 或 `nullptr`）
- 函数的返回类型（如果声明为按值返回）（返回类型为 `Type`）
- 内置一元 `&` 运算符的结果（即，获取表达式的地址会产生什么）
- lambda 表达式

xvalue 的例子有:

- 使用 `std::move()` 标记对象的结果
- 转换为对象类型（不是函数类型）的右值引用
- 函数的返回值（如果声明返回右值引用）（返回类型 `Type&&`）
- 右值的**非静态值成员**（见下文）

例如：

```c++
class X {
};

X v;
const X c;

f(v); // passes a modifiable lvalue
f(c); // passes a non-modifiable lvalue
f(X()); // passes a prvalue (old syntax of creating a temporary)
f(X{}); // passes a prvalue (new syntax of creating a temporary)
f(std::move(v)); // passes an xvalue
```

粗略地说，作为经验法则：

- 所有用作表达式的名称都是 lvalue。
- 用作表达式的所有字符串常量都是 lvalue。
- 所有非字符串常量（`4.2`、`true` 或 `nullptr`）都是 prvalue。
- 所有没有名称的临时对象（**特别是按值返回的对象**）都是 prvalue。
- 所有带有 `std::move()` 标记的对象及其值成员都是 xvalues。

值得强调的是，严格来说 glvalue、prvalue 和 xvalue 是表达式的术语，而**不是**值的术语（这意味着这些术语用词不当）。例如，**变量本身不是左值**； **只有表示变量的表达式才是左值**：

```c++
int x = 3; // here, x is a variable, not an lvalue
int y = x; // here, x is an lvalue
```

在第一个语句中，3 是初始化变量 `x` 的 prvalue，这里 `x` 不是左值。在第二个语句中，`x` 是 lvalue（它的求值指定一个包含值3的对象）。lvalue x 按 rvalue 使用，用于初始化变量 `y`。

### 8.1.3 自 C++17 以来的值类别

C++17 具有相同的值类别，但澄清了值类别的语义，如图 8.2 所示。

现在解释值类别的关键方法是，一般来说，我们有两种主要的表达方式：

- **glvalues**：长期存在的对象或函数的**位置表达式**
- **prvalues**：用于初始化、短期存在的<u>值**表达式**</u>

<u>然后 xvalue 被视为特殊位置</u>，表示不再需要（长期存在的）对象的**资源或值**。

> - [ ] Figure 8.2. 

#### 按值传递 prvalue

通过此更改，即使没有定义有效的复制构造函数和有效的移动构造函数，现在也可以按值将 prvalue 作为**==未命名的初始值==**传递：


```c++
class C {
public:
  C( ... );
  C(const C&) = delete; // this class is neither copyable ...
  C(C&&) = delete;      // ... nor movable
};

C createC() {
  return C{ ... };      // Always creates a conceptual temporary prior to C++17.
}                       // In C++17, no temporary object is created at this point.


void takeC(C val) {
...
}

auto n = createC(); // OK since C++17 (error prior to C++17)

takeC(createC());   // OK since C++17 (error prior to C++17)
```

在 C++17 之前，如果没有复制或移动支持，则无法传递纯右值，例如 `createC()` 创建和初始化的返回值。然而，从 C++17 开始，只要我们不需要带有位置的对象，我们就可以按值传递纯右值。

#### 物化

然后，C++17 引入了一个新术语，称为**物化**（未命名临时对象），此时 prvalue 成为临时对象。因此，**临时物化转换**是（通常是隐式的）prvalue 到 xvalue 的转换。

每当需要 glvalue（lvalue 或 xvalue）时使用 prvalue，就会创建一个临时对象并使用 prvalue 初始化（请记住，prvalue 主要是**初始化值**），然后 prvalue 将被替换为 **xvalue** 指定的临时对象。因此在上面的例子中，严格来说，我们有:

```c++
void f(const X& p); // accepts an expression of any value category but expects a glvalue

f(X{});             // creates a temporary prvalue and passes it materialized as an xvalue
```

因为本例中的 `f()` 有一个引用参数，所以它需要一个 glvalue 参数。然而，表达式 `X{}` 是 prvalue。因此，**临时物化**规则生效，表达式 `X{}` 被**转换**为 xvalue，该 xvalue 指定一个用默认构造函数初始化的临时对象。

注意，物化并不意味着我们创建一个新的/不同的对象。lvalue 引用`p`仍然绑定到 xvalue 和 prvalue，尽管后者现在总是涉及到 xvalue 的转换。

## 8.2 值类别的特殊规则

对于影响移动语义的<u>函数和成员的</u>**值类别**，有特殊规则。

### 8.2.1 函数的值类别
C++ 标准中的一条特殊规则规定，所有引用函数的表达式都是左值。例如：

```c++
void f(int) {
}

void(&fref1)(int) = f; // fref1 is an lvalue
void(&&fref2)(int) = f; // fref2 is also an lvalue

auto& ar = std::move(f); // OK: ar is lvalue of type void(&)(int)
```
与对象的类型相反，可以将**非常量 lvalue 引用**绑定到标有 `std::move()` 的函数，因为标有 `std::move()` 的函数仍然是左值。

## 8.3 绑定引用时值类别的影响
当我们将引用绑定到对象时，值类别发挥着重要作用。例如在 C++98/C++03 中，它们定义了可以将右值（<u>没有名称的临时对象</u>或标有 `std::move()` 的对象)赋值或传递给`const` lvalue 引用，但不能将其赋值或传递给 `non-const` lvalue 引用：

```c++
std::string createString();            // forward declaration
const std::string& r1{createString()}; // OK
std::string& r2{createString()};       // ERROR
```
编译器打印的典型错误消息是 “cannot bind a non-const lvalue reference to an rvalue”。在此处调用 `foo2()` 时还会收到此错误消息：

```c++
void foo1(const std::string&); // forward declaration
void foo2(std::string&); // forward declaration
foo1(std::string{"hello"}); // OK
foo2(std::string{"hello"}); // ERROR
```
### 8.3.1右值引用的重载解析

**让我们看看将对象传递给引用时的确切规则**。假设我们有一个 `non-const` 变量 `v` 和一个`class X` 的 `const` 变量 `c`:

```c++
class X {
  ...
};

X v{ ... };
const X c{ ... };
```
如果我们提供了函数`f()`的所有引用重载，**绑定引用的规则**的表列出了将引用绑定到传递参数的正式规则：

```c++
void f(const X&);  // read-only access
void f(X&);        // OUT parameter (usually long-living object)
void f(X&&);       // can steal value (object usually about to die)
void f(const X&&); // no clear semantic meaning
```

这些数字列出了重载解析的优先级，以便您可以看到在提供多个重载时调用了哪个函数。数字越小，优先级越高（优先级1表示首先尝试）。

请注意，您只能将 rvalue（prvalue，例如没有名称的临时对象）或 xvalue（用`std::move()`标记的对象）传递给**右值引用**。这就是它们名字的由来。

您通常可以忽略表的最后一列，因为 **const 右值引用**在语义上没有多大意义，这意味着我们得到以下规则：

> Table 8.1. Rules for binding references

| Call         | `f(X&)` | `f(const X&)` | `f(X&&)` | `f(const X&&)` |
| ------------ | ------- | ------------- | -------- | -------------- |
| `f(v)`       | 1       | 2             | no       | no             |
| `f(c)`       | no      | 1             | no       | no             |
| `f(X{})`     | no      | 3             | 1        | 2              |
| `f(move(v))` | no      | 3             | 1        | 2              |
| `f(move(c))` | no      | 2             | no       | 1              |

- **非常量的左值引用**只接收**非常量的左值**。
- **右值引用**只接受**非常量右值**。
- const 左值引用可以接受所有内容，并在未提供其他重载的情况下充当 **fallback 机制**。

下面从表格中间摘录的内容，是**移动语义 **<u>fallback 机制</u>的规则：

| Call         | `f(const X&)` | `f(X&&)` |
| ------------ | ------------- | -------- |
| `f(X{})`     | 3             | 1        |
| `f(move(v))` | 3             | 1        |

如果我们将右值（临时对象或标有 `std::move()` 的对象）传递给函数，并且没有移动语义的具体实现（声明为**接收右值引用**），那么就会使用通常的复制语义，使用`const&`作为参数。

请注意，当我们引入**万能引用**和**<u>转发引用</u>**时，我们将[扩展此表]()。

在那里我们还将了解到，有时您可以将左值传递给右值引用（当使用模板参数时）。请注意，并不是每个使用 `&&` 的声明都遵循相同的规则。如果我们使用 `&&` 声明类型（或类型别名），则适用于此规则。

### 8.3.2 通过引用和值重载
我们可以通过引用参数和值参数来声明函数，例如：

```c++
void f(X);        // call-by-value
void f(const X&); // call-by-reference
void f(X&);
void f(X&&);
void f(const X&&);
```
原则上，声明所有这些重载都是允许的。但是，按值调用和按引用调用之间没有特定的优先级。如果有一个函数声明为按值接受参数（可以接受任何值类别的任何参数），那么任何以引用方式接受参数的重载声明都会产生歧义。

因此，您通常应该只通过值或引用来接受实参（尽可能多的使用**引用重载**），但绝不能同时采用两者。

## 8.4 当左值变成右值时

如前所述，当使用具体类型的右值引用参数声明函数时，你只能将这些参数绑定到右值。例如：

```c++
void rvFunc(std::string&&); // forward declaration

std::string s{ ... };
rvFunc(s);                  // ERROR: passing an lvalue to an rvalue reference
rvFunc(std::move(s));       // OK, passing an xvalue
```
但是请注意，有时传递左值似乎有效。例如：

```c++
void rvFunc(std::string&&); // forward declaration

rvFunc("hello");            // OK, although "hello" is an lvalue
```
请记住，当用作表达式时，[字符串常量是左值]()。因此，将它们传递给右值引用无法编译。然而，这里涉及到一个隐藏的操作，因为参数的类型（六个常量字符的数组）与参数的类型不匹配。我们有一个隐式类型转换，由 `string` 的构造函数执行，它创建一个没有名称的临时对象。

因此，我们真正调用的是以下代码：

```c++
void rvFunc(std::string&&);   // forward declaration

rvFunc(std::string{"hello"}); // OK, "hello" converted to a string is a prvalue
```
## 8.5 当右值变成左值时
现在，让我们看一下将形参声明为右值引用的函数的实现：

```c++
void rvFunc(std::string&& str) {
...
}
```
正如我们所知，我们只能传递右值：
```c++
std::string s{ ... };
rvFunc(s);                    // ERROR: passing an lvalue to an rvalue reference
rvFunc(std::move(s));         // OK, passing an xvalue
rvFunc(std::string{"hello"}); // OK, passing a prvalue
```
但是，当我们在函数内使用参数 `str` 时，我们正在处理一个具有名称的对象。这意味着我们使用 `str` 作为左值。我们只能用做**左值允许做**的事情。

**这意味着我们不能直接递归调用我们自己的函数**：
```c++
void rvFunc(std::string&& str) {
  rvFunc(str); // ERROR: passing an lvalue to an rvalue reference
}
```
我们必须再次用 `std::move()` 标记 `str`：

```c++
void rvFunc(std::string&& str) {
  rvFunc(std::move(str)); // OK, passing an xvalue
}
```
这是我们[已经讨论过]()的移动语义的正式规则：移动语义不传递。请注意这是一个功能，而不是一个 bug。如果我们传递移动语义，**我们将无法使用两次传递了移动语义的对象**，因为我们第一次使用它时，它将失去它的值。或者，我们需要一个功能暂时禁用移动语义。

如果我们将**右值引用参数绑定到右值**（prvalue 或 xvalue），则该对象将用作左值，我们必须再次将其转换为右值才能将其传递给右值引用。

现在，请记住 `std::move()` 只是一个右值引用的 `static_cast`。也就是说，我们在递归调用中编写的程序如下所示：

```c++
void rvFunc(std::string&& str) {
  rvFunc(static_cast<std::string&&>(str)); // OK, passing an xvalue
}
```
我们将对象 str 强制转换为它自己的类型。到目前为止，这是一个空操作。但是，强制转换还可以做其他事情：**改变值的类别**。==按照规则，通过强制转换为右值引用，左值将变为 xvalue，因此允许我们将对象传递给右值引用==。

这并不是什么新鲜事：即使<u>在 C++11 之前</u>，声明为左值引用的形参在使用时也遵循左值规则。关键是声明中的引用指定了可以传递给函数的内容。对于函数内部的行为，引用是无关紧要的。

令人困惑？ 这就是我们在 C++ 标准中定义移动语义和值类别的规则的方式。接受现实吧。幸运的是，编译器知道这些规则。

如果这里有一件事需要你学习，那就是不传递移动语义。如果传递具有移动语义的对象，则必须再次使用 `std::move()` 标记它，以将其语义转发到另一个函数。

## 8.6 使用 `decltype` 检查值类别

与移动语义一起，C++11 引入了新的关键字 `decltype`。 该关键字的主要目的是获取已声明对象的确切类型。 但是，它也可用于确定表达式的**值类别**。

### 8.6.1 使用 `decltype` 检查名称的 `Type`

```c++
void rvFunc(std::string&& str)
{
  std::cout << std::is_same<decltype(str), std::string>::value;    // false
  std::cout << std::is_same<decltype(str), std::string&>::value;   // false
  std::cout << std::is_same<decltype(str), std::string&&>::value;  // true
  std::cout << std::is_reference<decltype(str)>::value;            // true
  std::cout << std::is_lvalue_reference<decltype(str)>::value;     // false
  std::cout << std::is_rvalue_reference<decltype(str)>::value;     // true
}
```

表达式 `decltype(str)` 总是返回 `str` 的类型，即 `std::string&&`。我们可以在表达式中需要这种类型的地方使用这种类型。类型 traits（像 `std::is_same<>` 这样的类型函数）帮助我们处理这些类型。

例如，要使用传递的**形参类型**不是**引用**声明新对象，可以：
```c++
void rvFunc(std::string&& str)
{
  std::remove_reference<decltype(str)>::type tmp;
  ...
}
```
这个函数中，`tmp `的类型是 `std::string`（也可以显式地声明，但如果我们将它声明为类型为 T 的泛型函数，代码仍然可以工作）。

### 8.6.2 使用 `decltype` 检查值类别

到目前为止，我们只将名称传递给 `decltype` 来询问其类型。 但是，您也可以将表达式（不仅仅是名称）传递给 `decltype`。 在这种情况下，`decltype` 还会根据以下约定生成值类别：

- 对于 **prvalue**，它只产生它的值类型：`type`
- 对于 **lvalue**，它生成其类型作为左值引用：`type&`
- 对于 **xvalue**，它生成其类型作为右值引用：`type&&`

例如：

```c++
void rvFunc(std::string&& str)
{
   decltype(str + str) // yields std::string because s+s is a prvalue
   decltype(str[0])    // yields char& because the index operator yields an lvalue
  ...
}
```

这意味着如果您只传递一个放在括号内的名称（它是一个表达式而不再只是一个名称），`decltype` 将生成它的类型和值类别。 行为如下：

```c++
void rvFunc(std::string&& str)
{
  std::cout << std::is_same<decltype((str)), std::string>::value;   // false
  std::cout << std::is_same<decltype((str)), std::string&>::value;  // true
  std::cout << std::is_same<decltype((str)), std::string&&>::value; // false
  std::cout << std::is_reference<decltype((str))>::value;           // true
  std::cout << std::is_lvalue_reference<decltype((str))>::value;   // true
  std::cout << std::is_rvalue_reference<decltype((str))>::value;   // false
}
```
将此与[该函数先前不使用括号的实现]()进行比较。 这里，`(str)`  的  `decltype`  产生 `std::string&`，**因为  `str`  是  `std::string`  类型的左值**。

事实上，对于 `decltype`，当我们在传递的名称周围添加额外的括号时，会产生不同的结果，当我们稍后讨论 [`decltype(auto)`]() 时，也会产生重要的影响。

#### 检查代码内的值类别
一般来说，您现在可以检查代码中的特定值类别，如下所示：

- `!std::is_reference_v<decltype((expr))>` 检查 expr 是否是 **prvalue**。
- `std::is_lvalue_reference_v<decltype((expr))>` 检查 expr 是否是 **lvalue**。
- `std::is_rvalue_reference_v<decltype((expr))>` 检查 expr 是否是 **xvalue**。
- `!std::is_lvalue_reference_v<decltype((expr))>` 检查 expr 是否是 **rvalue**。

再次注意这里使用的附加括号，以确保我们使用 `decltype` 的值类别检查形式，即使我们只将名称作为 expr 传递。

在 C++20 之前，您必须省略后缀 `_v` 并附加 `::value`。


## 8.7 总结
- C++ 程序中的任何**表达式**都属于以下主要值类别之一：
   - **lvalue**（粗略地说，对于命名对象或字符串文字）
   - **prvalue**（粗略地说，对于未命名的临时对象）
   - **xvalue** （粗略地说，对于标有 std::move() 的对象）
- C++ 中的调用或操作是否有效取决于类型和值类别。
- 类型的 Rvalue 引用只能绑定到右值（prvalues  或 xvalues）。
- 隐式操作可能会更改传递参数的值类别。
- **将 rvalue  传递给 rvalue 引用会将其绑定到左值**。
- **移动语义不被传递**。
- 函数和函数引用始终是 lvalue。
- 对于rvalues （临时对象或用 `std::move()` 标记的对象），普通值成员具有移动语义，但引用或**静态成员**则没有。
- `decltype` 可以检查传递名称的声明类型或传递表达式的类型和值类别。