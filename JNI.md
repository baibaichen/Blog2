# Chapter 2: Design Overview

本章重点介绍 JNI 中的主要设计问题。 本节中的大多数设计问题都与本机方法有关。 调用 API 的设计在第 5 章：**调用 API** 中介绍。

本章涵盖以下主题：

- [JNI Interface Functions and Pointers](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#jni_interface_functions_and_pointers)
- Compiling, Loading and Linking Native Methods
  - [Resolving Native Method Names](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#resolving_native_method_names)
  - [Native Method Arguments](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#native_method_arguments)
- Referencing Java Objects
  - [Global and Local References](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#global_and_local_references)
  - [Implementing Local References](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#implementing_local_references)
- Accessing Java Objects
  - [Accessing Primitive Arrays](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#accessing_primitive_arrays)
  - [Accessing Fields and Methods](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#accessing_fields_and_methods)
- Java Exceptions
  - [Exceptions and Error Codes](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#exceptions_and_error_codes)
  - [Asynchronous Exceptions](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#asynchronous_exceptions)
  - [Exception Handling](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html#exception_handling)

## JNI Interface Functions and Pointers

本机代码通过调用 JNI 函数来访问 Java VM 功能。 JNI 函数可通过接口指针使用。 接口指针是指向指针的指针。 这个指针指向一个指针数组，每个指针指向一个接口函数。 每个接口函数都位于数组内的预定义偏移量处。 下图“接口指针”说明了接口指针的组织。

![Interface pointer](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/images/designa.gif)

JNI 接口的组织方式类似于 C++ 虚函数表或 COM 接口。 使用接口表而不是硬连线函数条目的优点是 JNI 名称空间与本机代码分离。 一个虚拟机可以很容易地提供多个版本的 JNI 函数表。 例如，VM 可能支持两个 JNI 函数表：

## Referencing Java Objects

原始类型，例如整数、字符等，在 Java 和本机代码之间进行复制。另一方面，任意 Java 对象都是通过引用传递的。VM 必须跟踪已传递给本机代码的所有对象，以便这些对象不会被垃圾收集器释放。反过来，本机代码必须有办法通知 VM 它不再需要这些对象。此外，垃圾收集器必须能够移动本地代码引用的对象。

### Global and Local References

JNI 将本地代码使用的对象引用分为两类：**局部引用**和**全局引用**。局部引用在本机方法调用期间有效，<u>并在本机方法返回后自动释放</u>。全局引用在显式释放之前一直有效。

**对象作为局部引用传递给本机方法**。JNI 函数返回的所有 Java 对象都是局部引用。JNI 允许程序员从局部引用创建全局引用。接受 Java 对象的 JNI 函数同时支持全局和局部引用。本机方法可以将本地或全局引用作为其结果返回给 VM。

在大多数情况下，程序员应该依靠 VM 在本机方法返回后释放所有局部引用。**然而，有时程序员应该显式释放一个局部引用**。例如，考虑以下情况：

- 本机方法访问大型 Java 对象，从而创建对 Java 对象的局部引用。然后，本机方法在返回给调用者之前执行额外的计算。对大型 Java 对象的局部引用将阻止对象被垃圾收集，即使该对象不再用于计算的其余部分。
- 本机方法会创建大量的局部引用，然而不会在同一时间使用所有的局部引用。由于 VM 需要一定量的空间来跟踪局部引用，因此创建过多的局部引用可能会导致系统内存不足。例如，本机方法循环遍历大量对象，以局部引用的形式取得其中的元素，并在每次迭代时操作其中的一个元素。每次迭代后，程序员不再需要对数组元素的局部引用。

JNI 允许程序员在本机方法中的任何位置手动删除局部引用。为确保程序员可以手动释放局部引用，JNI 函数不允许创建额外的局部引用，除非将局部引用作为结果返回。

局部引用仅在创建它们的线程中有效。本机代码不能将局部引用从一个线程传递到另一个线程。

### Implementing Local References

为了实现局部引用，Java VM 为每次调用本机方法时创建一个注册表。注册表将不可移动的局部引用映射为 Java 对象，并防止对象被垃圾清理。传递给本机方法的所有 Java 对象（包括那些作为 JNI 函数调用结果返回的对象）都会自动添加到注册表中。注册表在本机方法返回后被删除，从而可以垃圾清理所有条目。

有多种实现注册表的方法，例如使用表、链表或哈希表。尽管可以使用引用计数来避免注册表中的重复条目，但 JNI 实现没有义务检测和去除重复条目。

请注意，通过保守地扫描本机堆栈，无法忠实地实现局部引用。本机代码可以将局部引用存储到全局或堆数据结构中。

## Accessing Java Objects

JNI 提供了一组丰富的全局和局部引用访问器函数。这意味着无论 VM 在内部如何表示 Java 对象，都可以使用相同的本机方法实现。这就是为什么 JNI 可以被各种各样的 VM 实现所支持的一个关键原因。

通过不透明引用使用访问器函数的开销高于直接访问 C 数据结构的开销。我们相信，在大多数情况下，Java 程序员使用本机方法来执行重要的任务，这些任务掩盖了该接口的开销。

### Accessing Primitive Arrays

**对于包含许多基本数据类型（例如整数数组和字符串）的大型 Java 对象，这种开销是不可接受的。 考虑用于执行向量和矩阵计算的本机方法，遍历 Java 数组并使用函数调用检索每个元素的效率非常低**。

一种解决方案引入了“固定”的概念，以便本机方法可以要求 VM 固定数组的内容。 本机方法然后接收指向元素的直接指针。 然而，这种方法有两个含义：

- 垃圾收集器必须支持固定。

- VM 必须在内存中连续布置基本数组。 虽然这是大多数原始数组的最自然实现，但布尔数组的实现方式有打包和拆包两种。 因此，依赖布尔数组确切布局的本机代码将不可移植。

我们采用了一种折衷方案来克服上述两个问题。

首先，我们提供了一组函数，将 Java 数组的某段数组元素复制到本机内存缓冲区。 如果本机方法只需要访问大型数组中的少量元素，则使用这些函数。

其次，程序员可以使用另一组函数来检索固定版本的数组元素。 请记住，这些功能可能需要 Java VM 执行存储分配和复制。 这些函数是否实际上复制数组取决于VM实现，如下所示：

- 如果垃圾收集器支持固定，并且数组的布局与本机方法所期望的相同，则不需要复制。
- 否则，将数组复制到一个不可移动的内存块（例如，在 C 堆中）并执行必要的格式转换。 返回指向副本的指针。

最后，该接口提供了一些函数来通知 VM 本机代码不再需要访问数组元素。调用这些函数时，系统要么解除数组固定，要么将原始数组与其不可移动的副本进行协调并释放该副本。

我们的方法提供了灵活性。 垃圾收集器算法可以为每个给定数组做出关于复制或固定的单独决定。 例如，垃圾收集器可能会复制小对象，但固定较大的对象。

JNI 实现必须确保在多个线程中运行的本机方法可以同时访问同一个数组。 例如，JNI 可以为每个固定数组保留一个内部计数器，这样一个线程就不会解除另一个线程也固定的数组。**注意，JNI 不需要为本机方法的排他访问锁定基本类型数组**。从不同线程同时更新 Java 数组会导致不确定的结果。

### Accessing Fields and Methods

JNI 允许本机代码访问字段并调用 Java 对象的方法。 JNI 通过它们的符号名称和类型签名来识别方法和字段。 这个过程分两步，首先，将基于名称和签名定位字段或方法的开销独立出来。例如调用类 `cls` 中的方法 `f`，本机代码首先获取一个**方法 ID**，如下：

```java
jmethodID mid = env->GetMethodID(cls, “f”, “(ILjava/lang/String;)D”);
```

这样，本地代码就可以重复使用**方法 ID**，而不会有方法查找的开销，如下所示：

```java
jdouble result = env->CallDoubleMethod(obj, mid, 10, str);
```

字段或方法 ID 不会阻止 VM 卸载该 ID 对应的类。 卸载类后，方法或字段 ID 将失效。 因此，如果本机代码打算长时间使用方法或字段 ID，必须确保：

- 保持对底层类的实时引用，或者
- 重新计算方法或字段 ID

JNI 不对字段 ID 和方法 ID 的内部实现方式施加任何限制。

## Reporting Programming Errors

# Chapter 3: JNI Types and Data Structures
