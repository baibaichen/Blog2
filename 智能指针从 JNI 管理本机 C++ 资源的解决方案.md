# 智能指针从 JNI 管理本机 C++ 资源的解决方案

## Introduction

In this article, I’ll propose a solution for managing native C++ resources from JNI using smart pointers.

While Smart Pointers can’t be useful from Java, because of the limits of the Java memory management, it may be required by the native library to maintain allocated resources through `shared_ptr` or `unique_ptr`, for example because classes derive from `std::enable_from_this`.

**Since there is a fixed pattern to maintain native objects in Java classes, a utility C++ class is proposed.**

## The problem of memory management when integrating Java and C++ code

Recently, I had to port a library I wrote for Linux to Android.

For instance, the library is aimed at implementing an OO interface to Bluetooth Low Energy service, using an USB dongle (BlueGiga BLED112), and avoiding the use of both Bluez and DBus.

Bluez’s Low Energy support was not ready for production code when we started this project, and I found the DBus interface unnecessarily complex for use with C/C++ applications. But anyway, there were many missing features that we needed, so we switched to some hardware solution, and one was the BlueGiga dongle.

I proposed my customer to open source the library, so perhaps one day we’ll release our solution.

The library was entirely developed in C++11 under Linux on ARM platform, using very small dependency except for boost, needed to have some feature like atomic and futures on ARM.

As any modern C++ program should, it makes large use of smart pointers as shared and weak pointers, so the memory management is entirely automatically handled by the smart pointer logic.

Then one day my customer asked me to develop a version of this library to be used on Android.

I had two options: since the dongle is managed through a serial port, I could rewrite the logic that implemented the read/write to the serial port, and the protocol, the parsing and constructing of each packet, all the classes modelling the Input and Output endpoints (i.e. the Low Energy Characteristics), and so on. I also had to write all the tests, because no library comes without a set of supporting code to demonstrate the many different use case scenarios.

Or, simply recompile the C++ library under Android and build a Java library that used the native library through jni code.

I would like to write about many problems I had with this task, and I can’t exclude, if I ever will find the time, to write here about.

But one of the most annoyng aspect of this task was the facts that Java and C++ (either “classic” and “modern”) have two completely incompatible memory management system.

---

For those who don’t catch the difference, the situation is this: C++ is very precise on objects lifecycle, either by letting the user to decide using the “classic” allocation/deallocation system through new/free calls, or by taking care of that with use of the smart pointers. When a smart pointer exits his scope, the pointed object is destroyed if there exists no other pointer that shares this object. So the object lifecycle is defined in a pretty predictabily way.

Java, on the other hand, isn’t so precise. Objects are created when they are instantiated, but they are destroyed whenever the JVM decides their time has come. No predictability here.

Every Java programmer knows that this pones a lot of problems even with the most common operations on common objects like files, sockets, and so on. If the object needs to be deinitialized before disposing, user must manually call a proper operation. Java provides a finalize() function that’s called when the system disposes the object, but it is up to the JVM, or more precisely to the Garbage Collector (GC) to decide when this happens.

This is the first aspect of the problem. You have a C++ library that’s designed to use smart pointers to manage the relations between the classes, you have a Java Library that uses it but requires the user to manage the allocation/deallocation of objects, and you have to glue them together.

Note also that in the native library, many objects are instantiated during the use of a feature, and some objects are owned by the user, so their lifecycle becomes somehow independent from the object that created it.

> 对于那些没有抓住区别的人来说，情况是这样的:c++在对象生命周期上非常精确，要么让用户通过new/free调用来决定使用“经典”的分配/释放系统，要么使用智能指针来处理这个问题。当智能指针退出其作用域时，如果没有其他指针共享该对象，则该指向对象将被销毁。所以对象生命周期是以一种非常可预测的方式定义的。 
>
> 另一方面，Java并不那么精确。对象是在实例化时创建的，但 JVM 一旦确定时机到了，就会销毁它们。这里没有可预测性。
>
> 每个 Java 程序员都知道，即使是对文件、套接字等常见对象的最常见操作，这也会带来很多问题。 如果对象需要在销毁前**取消初始化**，用户必须手动调用适当的操作。 Java 提供了一个 finalize() 函数，当系统销毁对象时调用该函数，但这取决于 JVM，或者更准确地说，取决于垃圾收集器 (GC) 来决定何时发生。
>
> 这是问题的第一个方面。 你有一个 C++ 库，使用智能指针来管理类之间的关系，你有一个使用它的 Java 库，需要用户管理对象分配/释放，必须将它们粘合在一起。
>
> 还要注意，在本机库中，许多对象是在使用其功能时实例化，有些对象由用户拥有，因此它们的生命周期在某种程度上独立于创建它的对象。

For example, suppose we have an adapter object that creates a protocol object when needed, and this object can create one or many other instances of the class characteristic. All of them are passed through smart pointers. **Adapter**, **Protocol** and **Characteristic** can have different lifecycles, though it has not much sense for a Characteristic to survive his Adapter object.

In C++ this poses not much problem: the objects are kept alive untl all the smart pointers are valid, so either the children objects are keeping alive the father, or their reference is invalid, if they use a weak pointer. It is a user responsability to select the proper pointer and the proper strategy.

---

In Java we have something to take care: the native object reference management, and the management of their lifecycle.

Usually, if you have a native pointer to keep in a Java object, you use a Java long type, that is a jlong in jni terms.

So the JNI code must also keep track of the object type, because if you allocate an object instance in jni, this object must be kept in a jlong Java field and it must also be retrieved and deleted at proper time.

Another issue is, object owning must be carefully managed: suppose you have a native class AN that have a relation to the class BN, and the classes AJ and BJ must own them, how you manage their lifecycle in a safe way? If AJ exits the scope before BJ, then AN must be disposed as well, but it must not dispose BN until BJ is ready to be disposed.

If you are using Smart Pointer, perhaps the life is easier, perhaps no. Anyway, there’s no such a thing like a smart pointer in JNI terms, you can keep a native pointer in a jlong variable, but std::shared_pointer is not a raw pointer, is an object with different internal fields.

The pattern on storing native pointers in java code is: allocate the pointer, cast it to jlong and store it in some long java field. To retrieve it, read the long java field, cast it back to the original pointer.

Additionally, when disposing the java object, you must retrieve the raw pointer from long java field, cast it back to the original type, delete it.

> 在 Java 中我们有一些事情需要注意：本机对象的引用以及它们生命周期的管理。
>
> 通常，如果您有一个要保存在 Java 对象中的本机指针，您可以使用 Java long 类型，即 jni 术语中的 `jlong`。
>
> 所以 JNI 代码还必须跟踪对象类型，因为如果你在 jni 中分配一个对象实例，这个对象必须保存在一个 jlong Java 字段中，并且还必须在适当的时候检索和删除它。
>
> ==另一个问题是，必须仔细管理对象的所有权：假设您有一个与类 BN 有关系的本机类 AN，并且类 AJ 和 BJ 必须拥有它们，您如何以安全的方式管理它们的生命周期？ 如果 AJ 在 BJ 之前退出作用域，那么 AN 也必须被释放，但是在 BJ 准备好被释放之前它不能释放 BN==。
>
> 如果您正在使用 Smart Pointer，也许生活会更轻松，也许不会。 无论如何，在 JNI 术语中没有像智能指针这样的东西，你可以在 jlong 变量中保留一个本地指针，但 `std::shared_pointer` 不是原始指针，是一个具有不同内部字段的对象。
>
> 在 java 代码中存储本机指针的模式是：分配指针，将其转换为 jlong 并将其存储在某个 long java 字段中。 要检索它，读取 long java 字段，将其转换回原始指针。
>
> 此外，在处理 java 对象时，必须从 long java 字段中检索原始指针，将其转换回原始类型，然后将其删除。

---

The following functions do exactly this:
```c++
#include <jni.h>

jfieldID inline getHandleField(JNIEnv *env, jobject obj)
{
    jclass c = env->GetObjectClass(obj);
    // J is the type signature for long:
    return env->GetFieldID(c, "nativeHandle", "J");
}

template <typename T>
T *getHandle(JNIEnv *env, jobject obj)
{
    jlong handle = env->GetLongField(obj, getHandleField(env, obj));
    return reinterpret_cast<T *>(handle);
}

template <typename T>
void setHandle(JNIEnv *env, jobject obj, T *t)
{
    jlong handle = reinterpret_cast<jlong>(t);
    env->SetLongField(obj, getHandleField(env, obj), handle);
}
```

The code should be self-explanatory. The `getHandleField()` function simply retrieve the `jfieldId` value from the java object passed as argument. The field has a fixed name, `nativeHandle` (an improvement is to make it codable).

`getHandle` and `setHandle` simply make the necessary cast. They are templatized so you can write

``` c++
auto ptr = getHandle(env,object);
```

and you have your raw-pointer-to-object in ptr.

But what for smart pointers? if your Object derives from `std::enable_from_this`, you must keep it in a smart_pointer, otherwise `shared_from_this()` will fail with a `bad_weak_ptr` exception.

So what you need is to allocate a smart pointer in the heap through a new. Or wrap it in a class, better if templatized:


```c++
#include <memory>
#include "handle.h"
#include "jnihelpers.h"

/** @brief a Wrapper for smart pointers to be used in JNI code
 *
 * **Usage**
 * Instantiation:
 * SmartPointerWrapper<Object> obj = new SmartPointerWrapper<Object>(arguments);
 * obj->instantiate(env,instance);
 *
 * Recovery:
 * std::shared_ptr<Object> obj = SmartPointerWrapper<Object>::object(env,instance);
 *
 * or
 *
 * SmartPointerWrapper<Object> wrapper = SmartPointerWrapper<Object>::get(env,instance);
 * std::shared_ptr<Object> obj = wrapper->get();
 *
 * Dispose:
 * SmartPointerWrapper<Object> wrapper = SmartPointerWrapper<Object>::get(env,instance);
 * delete wrapper;
 *
 * or simpler
 *
 * SmartPointerWrapper<Object>::dispose(env,instance);
 */
template <typename T>
class SmartPointerWrapper {
    std::shared_ptr<T> mObject;
public:
    template <typename ...ARGS>
    explicit SmartPointerWrapper(ARGS... a) {
        mObject = std::make_shared<T>(a...);
    }

    explicit SmartPointerWrapper (std::shared_ptr<T> obj) {
        mObject = obj;
    }

    virtual ~SmartPointerWrapper() noexcept = default;

    void instantiate (JNIEnv *env, jobject instance) {
        setHandle<SmartPointerWrapper>(env, instance, this);
    }

    jlong instance() const {
        return reinterpret_cast<jlong>(this);
    }

    std::shared_ptr<T> get() const {
        return mObject;
    }

    static std::shared_ptr<T> object(JNIEnv *env, jobject instance) {
        return get(env, instance)->get();
    }

    static SmartPointerWrapper<T> *get(JNIEnv *env, jobject instance) {
        return getHandle<SmartPointerWrapper<T>>(env, instance);
    }

    static void dispose(JNIEnv *env, jobject instance) {
        auto obj = get(env,instance);
        delete obj;
        setHandle<SmartPointerWrapper>(env, instance, nullptr);
    }
};
```

Here it is.

Use it this way: to instantiate, create the object and call instantiate(env,obj):

```c++
SmartPointerWrapper<Object> obj = new SmartPointerWrapper<Object>(arguments);
obj->instantiate(env,instance);
```

To recover the object smart pointer, use object():

```c++
SmartPointerWrapper<Object> wrapper = SmartPointerWrapper<Object>::get(env,instance);
std::shared_ptr<Object> obj = wrapper->get();
```

And to dispose/destroy:

```c++
SmartPointerWrapper<Object> wrapper = SmartPointerWrapper<Object>::get(env,instance);
delete wrapper;

// or

SmartPointerWrapper<Object>::dispose(env,instance);
```

Of course dispose must be called explicitly from java (do not use it from finalize()).

Happy Coding!