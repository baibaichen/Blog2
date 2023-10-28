# 现代C++模板元编程杂谈

> https://www.zhihu.com/people/mo-fa-xiao-wan-xiong-40/posts

**前言**

本人研究方向是数值计算（会另外开一个系列讲讲数值计算），固然会对计算性能与代码框架的稳定性与统一性有着极高的要求。对于计算性能展开讲会过于冗余而且其主要取决于算法本身以及并行方法。本系列文章旨在学习与探究不同框架设计或者架构（会在静态多态，即本系列主题模板元编程进行主要的描述）对于计算性能的影响，也能起到督促自己扩展技能的作用，若能帮助正在看此博文的你，我的荣幸。

# 引子

正如 C++之父所言，C++立国精神**零开销抽象**。对于此言，我认为有四重理解，

1. 对于开销而言存在两类开销：内存开销以及运行时间开销。

2. 对于抽象而言存在两类抽象：动态抽象与静态抽象。

以下将以一个小例子讲解传统的内存开销，运行时间开销以及动态多态。

## 2.1 内存开销浅析

```C++
class Base
{
	inline void SaySomeThing()
	{
		std::cout << "I am base class" << std::endl;
	}
};

class Sub
{
	double data{ 0.0 };
};

int main()
{
	Base base;
	std::cout << "Size of Base = " << sizeof(base) << std::endl;
	Sub sub;
	std::cout << "Size of Sub = " << sizeof(sub) << std::endl;
}

Size of Base = 1
Size of Sub = 8
```

如上代码所示：首先对于空类（不包括有虚函数的类）由于要在内存中记录其位置即占位符，在C++中空类占一个字节。Sub类不包含空类时，所占内存大小为八个字节。

```c++
class Base
{
	inline void SaySomeThing()
	{
		std::cout << "I am base class" << std::endl;
	}
};

class Sub
{
	Base base;  // 组合
	double data{ 0.0 };
};

int main()
{
	Base base;
	std::cout << "Size of Base = " << sizeof(base) << std::endl;
	Sub sub;
	std::cout << "Size of Sub = " << sizeof(sub) << std::endl;

}

Size of Base = 1
Size of Sub = 16
```

如上代码所示：当Sub类组合Base类时，Sub类对象的内存大小变为了16字节，其原因为：C++中的内存对齐机制，即为4，8的倍数机制，1+8变成了8+8，在此不再赘述。

那么如何优化这种内存布局呢？传统C++设计原则上，组合要优于继承，但是对于库开发者或者大型框架开发者而言，内存空间是极为重要的（分毫必争），对于上述所言例子，如果想使Sub的内存布局尽量小，还能拥有Base的访问即使用权限，那么在此是继承优于组合的。如下代码所示，Sub所占内存重新变回了8字节，因为其本身有了占位，公有继承的父类Base不再需要1字节的占位。到此简单的内存开销分析结束，读者可以记住此类范式，在今后的学习中会有很多此类模块在稍大设计中的缩影。在极致追求性能与通用的标准库STL中也极为常见。

```c++
class Base
{
	inline void SaySomeThing()
	{
		std::cout << "I am base class" << std::endl;
	}
};

class Sub
	:
	public Base
{
	double data{ 0.0 };
};
Size of Base = 1
Size of Sub = 8
```

## 2.2 运行时间开销浅析

在此章节中主要谈一下除去算法外的时间开销，即运行期达到多态效果的计算开销。代码如下

```c++
class Base
{
public:
	virtual void SaySomeThing()
	{
		std::cout << "I am base class" << std::endl;
	}
	virtual ~Base() = default;
};

class Sub
	:
	public Base
{
public:
	double data{ 0.0 };
	virtual void SaySomeThing()override
	{
		std::cout << "I am Sub class" << std::endl;
	}
};

int main()
{
	Base* base = new Sub;
	base->SaySomeThing();
	delete base;
}

/*
I am Sub class
*/
```

结果输出是Sub，在此简单介绍下多态机制。即子类向上转型成为父类（指针或引用），调用虚函数时，会重新计算虚表位置，从而取得子类重写的虚函数地址，进而调用。此中之意：在进行计算时，每调用一次虚函数，都会计算一次虚表位置。此称为运行时开销，此类多态即为传统的动态多态。这类运行时开销，是否可接受亦取决于整体算法本身，但私以为，有开销，总不是那么好的事情。

> 本章结语
>
> 传统的抽象思维核心：动态多态机制，对于运行时开销是不可避免的，大部分情况下内存开销也难以避免，对于高性能计算是一种甜蜜的负担。下一章将会以一个小的案例（设计模式）由动态多态过渡到静态多态，从而正式开始我们的模板元编程之旅。
>
> Let's play some C plus plus!

# 静态多态VS动态多态

> 引言
>
> 在此系列的第一篇文章提到用一个设计模式来了解动态多态与静态多态区别，话不多说，let's start!

## 背景需求

假设我们正在完成一项任务（Task），完成项目的策略（Strategy）需由客户指定。那么如何隔离此类变化？使得代码结构是底层稳定，高层变化呢？

## 动态多态

若使用**动态多态方法**，其实这是一个非常经典的设计模式：**策略模式**，如代码所示

```c++
class Strategy
{
public:
	virtual void DoTask() = 0;
	virtual ~Strategy() = default;
};

class Method1
	:
	public Strategy
{
public:
	virtual void DoTask()override
	{
		std::cout << "This is Method1" << std::endl;
	}
};

class Method2
	:
	public Strategy
{
public:
	virtual void DoTask()override
	{
		std::cout << "This is Method2" << std::endl;
	}
};

enum class MethodType
{
	Method1,
	Method2
};

class Task
{
public:
	Strategy* method = nullptr;
	void Set_Strategy(MethodType s_tp)
	{
		if (s_tp==MethodType::Method1)
		{
			method = new Method1;
		} 
		else
		{
			method = new Method2;
		}
	}
	void DoTask()
	{
		method->DoTask();
	}
	~Task()
	{
		delete method;
		method = nullptr;
	}
};

int main()
{
	Task task;
	task.Set_Strategy(MethodType::Method1);
	task.DoTask();
}

This is Method1
```

所有的策略方法如Method1与Method2都继承自抽象基类Strategy，并重写虚函数:void DoTask()。在Task类中，我们放一根抽象基类Strategy指针（目的是留出子类向上转型的接口），从内存安全的角度来看，此处应用智能指针（But,I am lazy）懒狗的我自己写了析构。在Set_Strategy()函数中，我们根据用户指定的不同方法，创建不同类型的子类并向上转型成Strategy父类。这时，Task类中的DoTask（）会调用Strategy中的DoTask()，此处是多态的调用，真正的做到了无论再多多少策略，此处都是稳定不变的，即：method->DoTask().

## 静态多态（奇异递归模板CRTP）

对于动态多态而言，他的缺点是什么？在系列（一）中提到，首先其在运行时会多一次运行时的开销，计算虚表地址。其次在Task类中，实实在在的存了一个内存占8字节的指针。两大开销一点也不符合咱们的立国精神“零开销抽象”嘛。那么在此欢迎我们的CRTP同志，代码如下。

```c++
template<typename Method>
class Strategy
{
public:
	void DoTask()
	{
		static_cast<Method*>(this)->DoTask();
	}
};

class Method1
	:
	public Strategy<Method1>
{
public:
	void DoTask()
	{
		std::cout << "This is Method1" << std::endl;
	}
};

class Method2
	:
	public Strategy<Method2>
{
public:
	void DoTask()
	{
		std::cout << "This is Method2" << std::endl;
	}
};

int main()
{
	Strategy<Method1> method;
	std::cout << "size of method = " << sizeof(method) << std::endl;
	method.DoTask();
}

size of method = 1
This is Method1
```

对于基类Strategy,模板参数为Method，在DoTask（）函数中，将this指针转型成了Method*指针，从而调用的DoTask函数就是Method中的Dotask()函数。此处是绝对稳定的，也不用工厂方法去创建子类，只需在main函数中指定模板参数即可。对于具体子类方法的实现，继承其Strategy<本类>即可，原因是让Strategy在转型时是可以成功转型，而不发生截断。值得注意的是，这里子类的DoTask不是虚函数，这里给他起名叫阿猫阿狗也行，只需要在Strategy中用到即可，聪明的你一定会发现CRTP有一个优点已经体现出来了，没有虚函数！我们无需在运行时去计算虚表，满足零运行时额外开销。再看，第二点。我们生成的Strategy实体对象，并没有继承什么，它只是转型了一次，所以其所占内存仍是1字节。第二个优点！零额外内存开销。这是完全符合了我们的立国精神。

## 结语

在此节中我们比较了静态多态的独特优点，这种设计范式，我相信会越来越多的应用到更多的领域。不过，更杠一点

![img](https://pic4.zhimg.com/80/v2-f693b9b9a55aabec28586f7968947b2f_720w.webp)

也是留给各位小伙伴们的一些思考，也欢迎找我交流。如果我在另一个类中还想在此类的函数中调用 `Strategy` 中的 `DoTask`。这时我们还能零开销吗？如果可以，方法是什么。（剧透：在下一个文章中，我将把白嫖进行到底！）

**世间皆苦，我选C++！**

# 从图灵完备看元编程

前言

首先填上一篇文章留下来的问题，<u>==如何做到，在另一个类中指定方法，且是零开销的==</u>。让我们先来看一个初级版本。代码如下

```c++
template<typename Method>
class Strategy
{
public:
	void DoTask()
	{
		static_cast<Method*>(this)->DoTask();
	}
};

class Method1
	:
	public Strategy<Method1>
{
public:
	void DoTask()
	{
		std::cout << "This is Method1" << std::endl;
	}
};

class Method2
	:
	public Strategy<Method2>
{
public:
	void DoTask()
	{
		std::cout << "This is Method2" << std::endl;
	}
};

template<typename Method>
class Task
{
public:
	double data{ 0.0 };
public:
	Strategy<Method> method;
public:
	void DoTask()
	{
		method.DoTask();
	}
};

int main()
{
	Task<Method1> task;
	task.DoTask();
	std::cout << "size of task = " << sizeof(task) << std::endl;
}

This is Method1
size of task = 16
```

仍然是运用 CRTP（奇异递归模板），我们可以做到在类外指定方法，并且无运行时开销，但是我们生成的 task 对象仍具有16字节内存占用，原因在第一篇文章已提到是因为内存对齐机制。那么我们可从第一篇文章获得启发，我们可以去继承这个 Method 模板参数，那么此时 Method 成为了我们 Task 类的父类，无需再在内存中占位。可达到零开销，同时我们也无需使用奇异递归模板方法，只需在外部指定需要的Method类即可。在 `DoTask` 函数中使用父类的方法即可。如代码所示

```c++
class Method1
{
public:
	void DoTask()
	{
		std::cout << "This is Method1" << std::endl;
	}
};

class Method2
{
public:
	void DoTask()
	{
		std::cout << "This is Method2" << std::endl;
	}
};

template<typename Method>
class Task : public Method
{
public:
	double data{ 0.0 };
public:
	void DoTask()
	{
		Method::DoTask();
	}
};

int main()
{
	Task<Method1> task;
	task.DoTask();
	std::cout << "size of task = " << sizeof(task) << std::endl;
}

This is Method1
size of task = 8
```

==外部调用接口没有变化，且对于代码而言，可以少写父类以及继承关系，并且如果想要增加方法只需要添加方法 class 即可，最重要的是，真正做到了零开销抽象。好了，那么到此我们上一篇文章的悬念结束！==

## 元编程概念

何谓图灵完备，简单来讲就是拥有：顺序，分支选择以及循环或者递归结构的逻辑即可称为图灵完备。常见的Python，C++，C等语言均具有图灵完备性质。那么为何我们要讲C++模板元编程呢。以下观点仅代表个人看法，也欢迎有不同意见交流，大家互相进步。

C++的元编程发现是一个意外（这个有趣的故事之后会讲），正如标题所讲，C++模板元编程。C++所具有的元编程是基于模板技术的，通过模板的系列计算，可以完成顺序，分支选择以及循环的逻辑在编译期进行计算。那么对于其理解，个人认为C++元编程，是寄生于C++语言的另一种语言。不过他也是可以完美融入C++的，毕竟他诞生于C++语言。同理，只要其它编程语言如Python等，也具有在编译期的图灵完备性质，它们也可以拥有一套元编程语言。

### 顺序结构

```c++
template<typename T>
struct reference
{
	using Reference = T&;
};

template<typename T>
struct Rvalue_reference
{
	using Reference = T&&;
};

int main()
{
	int a = 1;
	reference<int>::Reference b = a;
	b = 2;
	std::cout <<"a = " <<a << std::endl;
}

a = 2
```

顺序结构顾名思义，顺着写就行，第一个元函数 `reference` 返回一个引用类型（可能看着别扭，之后的系列文章我会细讲）第二个元函数 `Rvalue_reference` 返回一个右值引用类型。在 `main` 函数中，也测试通过。下一节会继续讲如何通过元编程实现分支与递归结构。

### 分支语句

需求：在编译期判断所给的类型是否为整数，如果是整数类型，元函数返回ture，反之返回false。代码如下

```c++
template<typename Value_Type>
struct is_integer
{
	constexpr static bool value = false;
};

template<>
struct is_integer<int>
{
	constexpr static bool value = true;
};

int main()
{
	std::cout << is_integer<int>::value << std::endl;
	std::cout << is_integer<double>::value << std::endl;
}

输出：
1
0
```

从原理出发：首先我们声明一个类模板，默认的返回值是false (可能小伙伴们看这个会觉得别扭，别急我在下一篇文章中会详细解释，咱们默认把它当作返回值吧)。然后写出特化模板，特化类型为int，此时返回true。那么当我们在调用端，实例化模板时，编译器会去匹配这个模板参数。如果是int，编译器会按照我们写的特化int型模板进行匹配，并返回true。如果是其他的类型，则会匹配未特化的模板返回false。好了，都看见我说了那么多如果了，if else这种选择分支语句咱们也讲清楚了。其实编译期计算就是一种不停的匹配模板参数的过程。

### 循环语句

需求：编译期来求一下给定正整数的阶乘吧（一种典型的递归）。代码如下

```c++
template<int N>
struct Stair
{
	constexpr static int value = N * Stair<N - 1>::value;
};

template<>
struct Stair<1>
{
	constexpr static int value = 1;
};

int main()
{
	std::cout << Stair<3>::value << std::endl;
	std::cout << Stair<4>::value << std::endl;
	std::cout << Stair<5>::value << std::endl;
}

输出：
6
24
120
```

从原理出发：首先，我们给定一个整数做为类模板参数，在模板类中返回值value定义为N*Stair<N-1>::value，那么此时当我们实例化一个类模板时，他就会接着去计算对应<N-1>这个模板中的value的值，欸，你看这不就开始递归了吗，其实也是编译器一直在匹配<N-1>这个模板，就如我们熟知的for循环，总要有一个终止条件吧。这个时候我们的特化模板<1>登场了：到我这value=1，终止递归。（小tips：其实不用打印编译期计算完成，有的IDE鼠标放在value旁边就可以看值啦）至此递归语句结束。

**下一节，我们将深入系统的了解模板，元数据等概念，See you!**

# 元数据与元函数(上)

> 前言
>
> 从现在开始我们将详细介绍模板元编程的基础构件—模板，以及模板元编程的基本范式：元数据，元函数，元函数的输入输出概念


## 模板

何谓模板，可能大家比较习惯的有两类：函数模板与类模板。其实模板一共有四类：<u>变量模板</u>，函数模板，类模板，**==别名模板==**，以及概念（C++20新特性）。如下代码所示

```c++
//variable template
template<typename T>
T value;

//function template
template<typename T>
void func() {};

//class template
template<typename T>
class Kevin{};

//alias template
template<typename T>
using value_type = T;

//Concept
template<typename T>
concept is_ture = true;
```

值得注意的是，前三种模板：变量模板，函数模板与类模板需要声明，因为他们可能会在运行期产生实体，而后两种不需要，其实咱们可以简单理解为，他们取了一个别名，并不生成实体（但是作用是很大的）。

讲完了模板有关变量，我们来看看模板参数，一共分三类：

1. 非模板类型形参：整型（int，char，std::size_t）等，枚举型enum，指针与引用类型，浮点数类型以及字面量。如代码所示

```c++
template<int N> struct Kevin{};

template<char N>struct Kevin{};

template<std::size_t N>struct Kevin {};

enum MyEnum
{
	Kevin,
	Linda
};

template<MyEnum>struct Kevin{};
template<double* value>struct Kevin{};
template<double& value>struct Kevin{};
```

2. 类型模板形参，如代码所示

```c++
template<typename T>struct Kevin{};
```

3. 模板模板形参，即这个形参也是一个模板，如代码所示

```c++
template<template<typename T> typename Tmp>struct Kevin{};
```

值得注意的是第三类模板参数只能匹配类模板，如

```c++
template<typename T>struct Linda{};
template<template<typename T> typename Tmp>struct Kevin{};

Kevin<double> Liu;//Error,must be the template class
Kevin<Linda> Liu;//OK!
Kevin<Linda<int>>//Eorror,Linda<int> is not template class after we use int！
```

同时，一个模板可以拥有多个形参，也可以直接使用可变长参数列表如

```c++
template<typename Geo, typename T>struct Kevin{};
template<typename...Arg>struct MultiKevin{};
int main()
{
	Kevin<int, double> kevin{};
	MultiKevin<int, int, int, double> multikevin{};
}
```

> **有了模板类型基础下一节我们将展开讲解模板的强大运算能力**

## 模板实例化

模板实例化是指由我们编写的泛化的模板，在编译期生成的具体实例的变量，函数，类型等。在模板实例化时，模板类型由实参指定。模板实例化又分为：**显式实例化**与**隐式实例化**。隐式实例化是我们最经常用到的，且最常见于函数模板，显式实例化常见于类模板。如代码所示

```c++
template<typename DOTA2>
struct PSGLGD{};

template<typename DOTA2>
void OG(DOTA2 name) {};

int main()
{
	PSGLGD<char> Ame;
	OG(2);
}
```

可以看到，我们以char这个实参，显示指定了类模板PSGLGD。OG这个函数由整型（编译器根据函数实参推导了模板实参）实参指定。

## 模板特化

模板特化顾名思义，是指泛型模板参数被特殊指定后，模板有特殊的实现。泛化的模板（未经特化）称为主模板，特化的模板叫特化模板（我好像在说废话）。其中，类模板既可以全特化也可以偏特化，函数模板只能全特化。在模板实例化时，编译器会根据最匹配的特化模板进行匹配，如果没有则采用主模板。如代码所示

```c++
class PSGLGD{};
class OG{};

template<typename Winner,typename Loser>
struct TI10
{};

template<typename Winner>
struct TI10<Winner,OG>
{};

template<>
struct TI10<PSGLGD,OG>
{};
```

首先声明两个类PSGLGD与OG，类模板TI10拥有两个模板形参，Winner与Loser。第一个struct为泛化版本的类模板TI10，第二个Struct为偏特化版本的类模板TI10，其中将Loser这个模板形参特化为OG。第三个Struct为全特化版本类模板，将Winner指定为PSGLGD，将Loser指定为OG。

```c++
template<typename T1,typename T2>
void DoSomeThing(T1 t1, T2 t2) {};

template<>
void DoSomeThing<int, int>(int t1, int t2) {};
```

对于函数模板而言，只能全特化。言简意赅，如上代码所示。

> 结语
>
> 在本节中，我们讨论了模板实例化与特化机制，下一节我们将展开讲解这些机制如何运用达到元编程中。

# SFINAE(替换失败不是错误)

前言

首先，我们重新认识下C++函数重载机制。理解编译器在函数重载背后的行为，对我们理解SFINAE有很重要的帮助。

机制：

1 将所有同名函数放入一个集合中

2 根据函数声明，剔除一些不合适的函数

3 在剩余的集合中根据参数，挑选一个最适合的参数，如果没有或无法决定哪一个最合适就报错

4 再完成挑选后，会继续做一步检查，看是否是已经delete的函数

什么叫做匹配，其实就是实参与形参匹配，优先级最高的就是实参与形参的完全匹配，其次是，一些隐式转换如const等，最低优先级别的是可变参数...（因为其几乎能匹配所有参数类型）

SFINAE机制

SFINAE（Substitution Failure Is Not An Error）替换失败不是错误。SFINAE的需求场景之一模板特化的局限性，如代码所示

```c++
struct Kevin
{
	using size_type = unsigned int;
};

template<typename T,int N>
std::size_t Len(T(&)[N])
{
	return N;
}

template<typename T>
typename T::size_type Len(const T& t)
{
	return t.size();
}

unsigned int Len(...)
{
	return 0;
}

int main()
{
	std::cout << Len(Kevin()) << std::endl;
}
```

我们定义了三个重载函数以及自定义类，Kevin类中有一个类型为size_type，按照之前我们的理解，main函数调用到的Len函数应该匹配到最后的可变参数函数即参数列表为（...）。但编译器报错，Kevin中没有size成员，说明编译器为我们匹配到了第二个重载函数，没有发生替换。

这是为什么？因为替换原理就是：编译器会根据实参类型对函数声明做替换（注意此处与函数体无关），如果替换完成后发现得到的函数声明是没有意义的，那么编译器会忽略不计，也就是前言中提到的从候选函数集合中删除。并且不报错！此处就是SFINAE!替换失败不是错误。

那么刚刚编译器为我们选择了第二个函数重载，并不是我们想要的结果那么，我们如何让编译器针对这个函数重载发生替换失败但不是错误呢，很简单，只要对函数声明进行一些操作即可！注意一定是函数声明，因为编译器只会针对函数声明进行实参匹配与替换。如代码所示

```c++
struct Kevin
{
	using size_type = unsigned int;
};

template<typename T,int N>
std::size_t Len(T(&)[N])
{
	return N;
}

template<typename T>
decltype(T().size(),typename T::size_type()) Len(const T& t)
{
	return t.size();
}

unsigned int Len(...)
{
	return 0;
}

int main()
{
	std::cout << Len(Kevin()) << std::endl;
}

输出
0
```

输出0，说明第二个函数替换失败，使用decltype()表达式进行类型计算，编译器会在函数声明时候就会发现，我们的Kevin类并没有size这个成员，于是编译器发生替换失败，转到了第三个重载函数中。

以上就是番外篇,SFINAE！

# 元数据与元函数(下)

> 前言
>
> 有了前面一些章节的铺垫现在，我们正式介绍模板元编程中过的基本元素：元数据与元函数。
>

## 元数据

何谓数据，大家广泛接受的概念可能是，C++的一些内置数据类型的值，更广一点，一切数据结构的值，这里也包括我们创建的类对象等。但是，更高层面上，或者更广义的来说，类型也是可以被我们看做数据的，元编程嘛做的就是编译期间的一系列计算，包括类型，所以，元数据包含一切数据类型，包括编译时的常量如constexpr以及我们更广义上的类型。举个例子，代码如下

```c++
template<typename T>
struct Kevin{};

int a = 3;
double b = 3.0;
Kevin<double> LHY;
```

值对象如：a,b,LHY。是元数据，同时类模板Kevin也是元数据。

## 元函数

有了前面的铺垫，元函数的概念就非常简单了。平时我们所理解的函数都是输入/不输入变量，返回/不返回值。那么我们只要把这个值代入我们的元数据概念，那么元函数也就清晰了，输入/不输入元数据，返回/不返回元数据。代码如下

```c++
template<typename T,typename U>
struct Is_Same
{
	constexpr static bool value = false;
};

template<typename T>
struct Is_Same<T, T>
{
	constexpr static bool value = true;
};
```

输入两个类型T，U。如果T与U相同那么返回bool值true。这里相当于用模板特化，完成了类似于运行期if-else的分支语句。

# 从 `enable_if` 及 `concept` 看模板技术的变化

> 前言
>
> 在上回文章中，我们已经结束了元编程的所有基本概念，已经拥有了编译期的所有运算能力，那么这次，我们审视一下之前的SFINAE（替换失败不是错误），从SFINAE的演进，看C++模板技术的演化方向以及C++未来的目标。

## `enable_if` 技术

在这里我们直接看C++中的内置enable_if元函数

```c++
// STRUCT TEMPLATE enable_if
template <bool _Test, class _Ty = void>
struct enable_if {}; // no member "type" when !_Test

template <class _Ty>
struct enable_if<true, _Ty> { // type is _Ty for _Test
    using type = _Ty;
};
```

这里的enable_if函数：一个主模板，由非类型形参bool值与模板类型形参_Ty组成，其中第二个模板形参指定为默认形参void。主模版不返回任何值。特化模板中，将bool值特化为true，返回类型_Ty。有了这些结构分析，那么我们很清楚enable_if想要做的事情是什么：在满足指定条件（即true）时，返回我们指定的模板形参Ty_。否则不返回任何值。

## 重新审视 SFINAE

```c++
template<typename T>
decltype(T().size(),typename T::size_type()) Len(const T& t)
{
	return t.size();
}
```

在之前的代码中，我们为了使这个Len函数发生替换失败，针对了T类型中没有的算法进行了调用，这是非常不通用甚至笨拙的，那么enable_if就可以派上大用场了。

```c++
template<typename T,typename T2= std::enable_if<!std::is_same_v<Kevin,T>,T>::type>
auto Len(const T& t)
{
	return t.size();
}
```

在这里，如果我们的类型和Kevin一样，那么我们希望编译器对这个函数声明进行替换失败，那么我们就利用了enable_if如果接收bool值为false的情况下不返回任何类型，这样相当于typename T2=空，编译器识别这种错误，自动发生替换失败且不报错！这样看是不是比我们之前根据类的具体算法要简单很多了呢。

## C++20的约束与概念

随着C++20的到来，越来越多的重磅炸弹随之抛出，概念与约束，个人来看是最能体现C++未来演进方向的，即让泛型编程称为程序员日常中必不可少的一环，或者说在大量面向对象的技术浪潮下，让泛型编程有立足之地，或者说面向概念编程，毕竟泛型编程，更容易实现零开销抽象的立国精神。那么，在这里简单介绍下概念与约束。

```c++
template<typename T>
concept Cando = requires(T a)
{
	T::size();
};
```

在上述代码中我们定义了一个概念Cando，定义了一个约束：即T类型中必须有size（）函数。那么概括而言：Cando是一个概念，他是拥有size（）这个函数的所有类型的一个抽象。他是任意的泛型的一个子集。那么有了这个概念，我们可以进一步简化我们的SFINAE，甚至可以说在未来99%的泛型编程中，enable_if这类元函数，将会成为过去。

```c++
template<Cando T>
auto Len(const T& t)
{
	return t.size();
}
```

当编译器识别到，如果实际类型，不匹配我们的概念，则自动发生替换，多么简洁优雅。

# 深入元计算之可变模板

> 前言
>
> 在之前的文章中，我们介绍了所有的元编程基础以及相关的应用，今天我们将从稍微进阶的案例中深入理解可变参模板及其常用计算。

## 可变参模板的递归

什么是可变参模板呢，顾名思义，我们可以指定任意多的模板形参，其代码如下所示

```c++
template<typename...T> struct TList;
TList<double, Kevin, int> mylist;
```

...T就是一个可变模板的声明，在如上代码中，我们给了一个可变参模板类的声明与实例化。他其实可以看作一个编译期的容器，只不过容器里装的是元数据中的：类型。

我们想对这个可变参模板做一些递归拆分或者计算，那么我们就有必要把这个变参模板拆分，如代码所示

```c++
emplate<typename...T> struct TList;

template<typename T>
struct TList<T>
{
	using Head = T;
	using Tail = NullParameter;
};

template<typename T1,typename...TE>
struct TList<T1, TE...> :TList<TE...>
{
	using Head = T1;
	using Tail = TList<TE...>;
};
```

第二个特化模板，其实可以这样理解，本来是可变参模板形参的声明，但变成了一个单一的具体模板形参，这也是一种特化。我们分别把其拆成了头部Head=T，与尾部Tail=NullParameter。对于第三个特化模板，我们将可变参模板形参特化为T1与TE...，即一个单一具体模板形参与剩余的可变参模板形参，在这里Head=T1,Tail=TList<TE...>。那么我们其中的Tail也可以继续往后拆分，直到终止条件，即特化满足我们的第二类模板特化。有了这样的思想，我介绍一下一个好玩的小工具。

## 可变参模板的ID化

对于一个可变参模板，如果我们想知道：我们指定的类型在这个变参模板序列中处于什么位置，即类似于我们运行期的字典：我想要通过一个值知道这个索引是多少，只不过这个值变成了我们编译期的元数据。也许你会想，一定会很麻烦吧，那么请看好代码！

```c++
template <typename TFindTag, size_t N, typename TCurTag, typename...TTags>
struct Tag2ID_
{
	constexpr static size_t value = Tag2ID_<TFindTag, N + 1, TTags...>::value;
};

template <typename TFindTag, size_t N, typename...TTags>
struct Tag2ID_<TFindTag, N, TFindTag, TTags...>
{
	constexpr static size_t value = N;
};

template <typename TFindTag, typename...TTags>
constexpr size_t Tag2ID = Tag2ID_<TFindTag, 0, TTags...>::value;
```

短短几十行代码，让我们来看他的工作原理吧。首先我们定义了一个Tag2ID_的元函数（类模板），模板形参为，我们想要找的类型 TFindTag，正整数N，现在查找到的类型TCurTag，以及剩下的可变参序列包。其中返回一个正整数value，他又会等于其中Tag2ID_<TFindTag, N + 1, TTags...>中的正整数。其实这里是很重要的，他规定了一个递归意义：如果类模板匹配到我这个主模板上了，那么我的value将会等于一个新构造类模板中的value,这个新构造的类模板中的可变参模板是丢弃了TCurTag的，也就是说主模板中的逻辑是TCurTag不符合我们的TFindingTag那么此时就会继续递归。

那么此时，我们必须有一个递归终止条件，是什么呢？很简单即当TCurTag=TFindingTag时，我们递归结束，并且这个时候value=N。

至此这个工具完备。