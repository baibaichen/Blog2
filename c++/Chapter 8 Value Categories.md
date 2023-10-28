# Chapter 8 Value Categories
This chapter introduces the formal terminology and rules for move semantics. We formally introduce value categories such as lvalue, rvalue, prvalue, and xvalue and discuss their role when binding references to objects. This allows us to also discuss details of the rule that move semantics is not automatically passed through, as well as a very subtle behavior of `decltype` when it is called for expressions.

This chapter is the most complicated chapter of the book. You will probably see facts and features that are tricky and for some people hard to believe. Come back to it later, whenever you read about value categories, binding references to objects, and `decltype` again.

## 8.1 Value Categories
To compile an expression or statement it does not only matter whether the involved types fit. For example, you cannot assign an `int` to an `int` when on the left-hand side of the assignment an int literal is used:

```c++
int i = 42;
i = 77; // OK
77 = i; // ERROR
```

For this reason, each expression in a C++ program has a **value category**. Besides the type, the value category is essential to decide what you can do with an expression.

However, value categories have changed over time in C++.

### 8.1.1 History of Value Categories
Historically (taken from Kernighan&Ritchie C, K&R C), we had only the value categories **lvalue** and **rvalue**. The terms came from what was allowed in an assignment:

- An **lvalue** could occur on the left-hand side of an assignment
- An **rvalue** could occur only on the right-hand side of an assignment

According to this definition, when you use an `int` object/variable you use an lvalue, but when you use an `int` literal you use an rvalue:

```c++
int x; // x is an lvalue when used in an expression

x = 42; // OK, because x is an lvalue and the type matches
42 = x; // ERROR: 42 is an rvalue and can be only on the right-hand side of an assignment
```

However, these categories were important not only for assignments. They were used generally to specify whether and where an expression can be used. For example:

```c++
int x; // x is an lvalue when used in an expression

int* p1 = &x; // OK: & is fine for lvalues (object has a specified location)
int* p2 = &42; // ERROR: & is not allowed for rvalues (object has no specified location)
```

However, things became more complicated with **ANSI-C** because an `x` declared as `const int` could not stand on the left-hand side of an assignment but could still be used in several other places where only an lvalue could be used:

```c++
const int c = 42; // Is c an lvalue or rvalue?

c = 42; // now an ERROR (so that c should no longer be an lvalue)
const int* p1 = &c; // still OK (so that c should still be an lvalue)
```

The decision in C was that c declared as const int is still an **lvalue** because most of the operations for lvalues can still be called for const objects of a specific type. The only thing you could not do anymore was to have a const object on the left-hand side of an assignment.

As a consequence, in ANSI-C, the meaning of the l changed to **locator value**. An **lvalue** is now an object that has a specified location in the program (so that you can take the address, for example). In the same way, an **rvalue** can now be considered just a **readable value**.

C++98 adopted these definitions of value categories. However, with the introduction of move semantics, the question arose as to which value category an object marked with std::move() should have, because objects of a class marked with std::move() should follow the following rules:

```c++
std::string s;
...
std::move(s) = "hello"; // OK (behaves like an lvalue)
auto ps = &std::move(s); // ERROR (behaves like an rvalue)
```

However, note that fundamental data types (FDTs) behave as follows:

```c++
int i;
...
std::move(i) = 42; // ERROR
auto pi = &std::move(i); // ERROR
```

With the exception of fundamental data types, an object marked with `std::move()` should still behave like an lvalue by allowing you to modify its value. On the other hand, there are restrictions such as that you should not be able to take the address.

A new category **xvalue** (“eXpiring value”) was therefore introduced to specify the rules for objects explicitly marked as **I no longer need the value here** (mainly objects marked with `std::move()`). However, most of the rules for former rvalues also apply to xvalues. Therefore, the former primary value category **rvalue** became a composite value category that now represents both new primary value categories **prvalue** (for everything that was an rvalue before) and **xvalue**. See http://wg21.link/n3055 for the paper proposing these changes.

### 8.1.2 Value Categories Since C++11
Since C++11, the value categories are as described in Figure 8.1.

> - [ ] Figure 8.1. Value categories since C++11

We have the following primary categories:

- lvalue (“locator value”)
- prvalue (“pure readable value”)
- xvalue (“eXpiring value”)

The composite categories are:

- glvalue (“generalized lvalue”) as a common term for “lvalue or xvalue”
- rvalue as a common term for “xvalue or prvalue”

#### Value Categories of Basic Expressions

Examples of lvalues are:

- An expression that is just the name of a variable, function, or data member (except a **plain value member** of an rvalue)
- An expression that is just a string literal (e.g., `"hello"`)
- The return value of a function if it is declared to return an lvalue reference (return type Type&)
- Any reference to a function, even when marked with std::move() (<u>see below</u>)
- The result of the built-in unary `*` operator (i.e., what dereferencing a raw pointer yields)

Examples of prvalues are:
- Expressions that consist of a built-in literal that is not a string literal (e.g., `42`, `true`, or `nullptr`)
- The return type of a function if it is declared to return by value (return type Type)
- The result of the built-in unary & operator (i.e., what taking the address of an expression yields)
- A lambda expression

Examples of xvalues are:
- The result of marking an object with std::move()
- A cast to an rvalue reference of an object type (not a function type)
- The returned value of a function if it is declared to return an rvalue reference (return type Type&&)
- A non-static value member of an rvalue (see below)

For example:

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
Roughly speaking, as a rule of thumb:

- All names used as expressions are lvalues.
- All string literals used as expression are lvalues.
- All non-string literals (`4.2`, `true`, or `nullptr`) are prvalues.
- All temporaries without a name (especially objects returned by value) are prvalues.
- All objects marked with `std::move()` and their value members are xvalues.

It is worth emphasizing that strictly speaking, glvalues, prvalues, and xvalues are terms for expressions and **not** for values (which means that these terms are misnomers). For example, a variable in itself is not an lvalue; only an expression denoting the variable is an lvalue:

```c++
int x = 3; // here, x is a variable, not an lvalue

int y = x; // here, x is an lvalue
```
In the first statement, 3 is a prvalue that initializes the variable (not the lvalue) x. In the second statement, x is an lvalue (its evaluation designates an object containing the value 3). The lvalue x is used as an rvalue, which is what initializes the variable y.

### 8.1.3 Value Categories Since C++17
C++17 has the same value categories but clarified the semantic meaning of value categories as described in Figure 8.2.

The key approach for explaining value categories now is that in general, we have two major kinds of expressions:

- **glvalues**: expressions for locations of long-living objects or functions
- **prvalues**: expressions for short-living values for initializations

An xvalue is then considered a special location, representing a (long-living) object whose resources/values are no longer needed.

> - [ ] Figure 8.2. Value categories since C++17

#### Passing Prvalues by Value
With this change, we can now pass around prvalues by value as unnamed initial values even if no valid copy and no valid move constructor is defined:

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

Before C++17, passing a prvalue such as the created and initialized return value of `createC()` around was not possible without either copy or move support. However, since C++17, we can pass prvalues around by value as long as we do not need an object with a location.

#### Materialization

C++17 then introduces a new term, called **materialization** (of an unnamed temporary), for the moment a prvalue becomes a temporary object. Thus, a **temporary materialization conversion** is a (usually implicit) prvalue-to-xvalue conversion.

Any time a prvalue is used where a glvalue (lvalue or xvalue) is expected, a temporary object is created and initialized with the prvalue (remember that prvalues are primarily “initializing values”) and the prvalue is replaced by an **xvalue** that designates the temporary object. Therefore, in the example above, strictly speaking, we have:

```c++
void f(const X& p); // accepts an expression of any value category but expects a glvalue

f(X{});             // creates a temporary prvalue and passes it materialized as an xvalue
```

Because `f()` in this example has a reference parameter, it expects a glvalue argument. However, the expression X{} is a prvalue. The “temporary materialization” rule therefore kicks in and the expression X{} is “converted” into an xvalue that designates a temporary object initialized with the default constructor.

Note that materialization does not mean that we create a new/different object. The lvalue reference `p` still binds to both an xvalue and a prvalue, although the latter now always involves a conversion to an xvalue.

## 8.2 Special Rules for Value Categories

We have special rules for the value category of functions and members that have an impact on move semantics.

### 8.2.1 Value Category of Functions
A special rule in the C++ standard states that all expressions that are references to functions are lvalues. For example:

```c++
void f(int) {
}

void(&fref1)(int) = f; // fref1 is an lvalue
void(&&fref2)(int) = f; // fref2 is also an lvalue

auto& ar = std::move(f); // OK: ar is lvalue of type void(&)(int)
```

In contrast to types of objects, we can bind a non-const lvalue reference to a function marked with `std::move()` because a function marked with `std::move()` is still an lvalue.

### 8.2.2 Value Category of Data Members

If you use data members of objects (e.g., when using members `first` and `second` of a std::pair<>), special rules apply.

In general, the value categories of data members are as follows:

- Data members of lvalues are lvalues.
- Reference and `static` data members of rvalues are lvalues.
- Plain data members of rvalues are xvalues.

This rule reflects that reference or `static` members are not really part of an object. If you no longer need the value of an object, this applies also to the plain data members of the object. However, the values of members that refer to somewhere else or are `static` might still be used by other objects.

For example:

```c++
std::pair<std::string, std::string&> foo(); // note: member second is reference

std::vector<std::string> coll;
...
coll.push_back(foo().first);                // moves because first is an xvalue here
coll.push_back(foo().second);               // copies because second is an lvalue here
```

You need `std::move()` to move the member second here:

```c++
coll.push_back(std::move(foo().second)); // moves
```

If you have an lvalue (an object with a name), you have two options to mark a member with std::move():

- `std::move(obj).member`
- `std::move(obj.member)`

Because `std::move()` means “**I no longer need this value here**” it looks like you should mark the obj if you no longer need the value of the object and mark member if you no longer need the value of the member. However, the situation is a bit more complicated.

#### `std::move()` for Plain Data Members

If the member is neither static nor a reference, by rule, std::move() always converts members to xvalues so that move semantics can be used.

Consider we have declared the following:

``` c++
std::vector<std::string> coll;
std::pair<std::string, std::string> sp;
```
The following code moves first the member first and then the member second into coll:

```c++
sp = ... ;
coll.push_back(std::move(sp.first)); // move string first into coll
coll.push_back(std::move(sp.second)); // move string second into coll
```

However, the following code has the same effect:

```c++
sp = ... ;
coll.push_back(std::move(sp).first); // move string first into coll
coll.push_back(std::move(sp).second); // move string second into coll
```

It looks a bit strange that we still use obj after marking it with `std::move()`, but in this case we know which part of the object may be moved so that we can still use a different part. Therefore, I would prefer to mark the member with `std::move()` when I, for example, have to implement a move constructor.

####  `std::move()` for Reference or `static` Members

If the members are references or static, different rules apply: A reference or static member of an rvalue is still an lvalue. Again, this rule reflects that the value of such a member is not really part of the object. Saying “I no longer need the value of the object” should not imply “I no longer need the value (of a member) that is not part of the object.”

Therefore, it makes a difference how you use `std::move()` if you have reference or static members:

Using `std::move()` for the **object** has no effect:

```c++
struct S {
  static std::string statString; // static member
  std::string& refString;        // reference member
};

S obj;
...
coll.push_back(std::move(obj).statString); // copies statString
coll.push_back(std::move(obj).refString); // copies refString
```

Using `std::move()` for the **members** has the usual effect:

```c++
struct S {
  static std::string statString;
  std::string& refString;
};

S obj;
...
coll.push_back(std::move(obj.statString); // moves statString
coll.push_back(std::move(obj.refString); // moves refString
```

Whether such a move is useful is a different question. Stealing the value of a static member or referenced member means that you modify a value outside the object you use. It might make sense, but it could also be surprising and dangerous. Usually, a type S should better protect access to theses members.

In generic code, you might not know whether members are static or references. Therefore, using the approach to mark the object with `std::move()` is less dangerous, even though it looks weird:

```c++
coll.push_back(std::move(obj).mem1); // move value, copy reference/static
coll.push_back(std::move(obj).mem2); // move value, copy reference/static
```

In the same way, `std::forward<>()`, [which we introduce later](), can be used to perfectly forward members of objects. See [basics/members.cpp](basics/members.cpp) for a complete example.

## 8.3 Impact of Value Categories When Binding References

Value categories play an important role when we bind eferences to objects. For example, in C++98/C++03, they define that you can assign or pass an rvalue (<u>a temporary object without a name</u> or an object marked with `std::move()`) to a `const` lvalue reference but not to a `non-const` lvalue eference:

```c++
std::string createString();            // forward declaration

const std::string& r1{createString()}; // OK

std::string& r2{createString()};       // ERROR
```

The typical error message printed by the compiler here is “cannot bind a non-const lvalue reference to an rvalue.”

You also get this error message with the call of foo2() here:

```c++
void foo1(const std::string&); // forward declaration
void foo2(std::string&); // forward declaration
foo1(std::string{"hello"}); // OK
foo2(std::string{"hello"}); // ERROR
```
### 8.3.1 Overload Resolution with Rvalue References

Let us see the exact rules when passing an object to a reference. Assume we have a `non-const` variable `v` and a `const` variable `c` of a `class X`:

```c++
class X {
  ...
};

X v{ ... };
const X c{ ... };
```

Table `Rules for binding references` lists the formal rules for binding references to passed arguments if we provide **all the reference overloads** of a function `f()`:

```c++
void f(const X&);  // read-only access
void f(X&);        // OUT parameter (usually long-living object)
void f(X&&);       // can steal value (object usually about to die)
void f(const X&&); // no clear semantic meaning
```

The numbers list the priority for overload resolution so that you can see which function is called when multiple overloads are provided. The smaller the number, the higher the priority (priority 1 means that this is tried first).

Note that you can only pass rvalues (prvalues, such as temporary objects without a name) or xvalues (objects marked with `std::move()`) to rvalue references. That is where their name comes from.

You can usually ignore the last column of the table because const rvalue references do not make much sense semantically, meaning that we get the following rules:	

> Table 8.1. Rules for binding references

| Call         | `f(X&)` | `f(const X&)` | `f(X&&)` | `f(const X&&)` |
| ------------ | ------- | ------------- | -------- | -------------- |
| `f(v)`       | 1       | 2             | no       | no             |
| `f(c)`       | no      | 1             | no       | no             |
| `f(X{})`     | no      | 3             | 1        | 2              |
| `f(move(v))` | no      | 3             | 1        | 2              |
| `f(move(c))` | no      | 2             | no       | 1              |

- A non-const lvalue reference takes only non-const lvalues.
- An rvalue reference takes only non-const rvalues.
- A const lvalue reference can take everything and serves as the fallback mechanism in case other overloads are not provided.

The following extract from the middle of the table is the rule for the fallback mechanism of move semantics:

| Call         | `f(const X&)` | `f(X&&)` |
| ------------ | ------------- | -------- |
| `f(X{})`     | 3             | 1        |
| `f(move(v))` | 3             | 1        |

If we pass an rvalue (temporary object or object marked with `std::move()`) to a function and there is no specific implementation for move semantics (declared by taking an rvalue reference), the usual copysemantics is used, taking the argument by `const&`.

Please note that we will [extend this table later]() when we introduce universal/forwarding references.

There we will also learn that sometimes, you can pass an lvalue to an rvalue reference (when a template parameter is used). Be aware that not every declaration with `&&` follows the same rules. The rules here apply if we have a type (or type alias) declared with `&&`.

### 8.3.2 Overloading by Reference and Value
We can declare functions by both reference and value parameters: For example:

```c++
void f(X);        // call-by-value
void f(const X&); // call-by-reference
void f(X&);
void f(X&&);
void f(const X&&);
```

In principle, declaring all these overloads is allowed. However, there is no specific priority between call-byvalue and call-by-reference. If you have a function declared to take an argument by value (which can take any argument of any value category), any matching declaration taking the argument by reference creates an ambiguity.

Therefore, you should usually only take an argument either by value or by reference (with as many reference overloads as you think are useful) but never both.

## 8.4 When Lvalues become Rvalues

As we have learned, when a function is declared with an rvalue reference parameter of a concrete type, you can only bind these parameters to rvalues. For example:

```c++
void rvFunc(std::string&&); // forward declaration

std::string s{ ... };
rvFunc(s);                  // ERROR: passing an lvalue to an rvalue reference
rvFunc(std::move(s));       // OK, passing an xvalue
```

However, note that sometimes, passing an lvalue seems to work. For example:

```c++
void rvFunc(std::string&&); // forward declaration

rvFunc("hello");            // OK, although "hello" is an lvalue
```

Remember that [string literals are lvalues]() when used as an expression. Therefore, passing them to an rvalue reference does not compile. However, there is a hidden operation involved, because the type of the argument (array of six constant characters) does not match the type of the parameter. We have an implicit type conversion, performed by the `string` constructor, which creates a temporary object that does not have a name.

Therefore, what we really call is the following:

```c++
void rvFunc(std::string&&);   // forward declaration

rvFunc(std::string{"hello"}); // OK, "hello" converted to a string is a prvalue
```

## 8.5 When Rvalues become Lvalues
Let us now look at the implementation of a function that declares the parameter as an rvalue reference:

```c++
void rvFunc(std::string&& str) {
...
}
```

As we have learned, we can only pass rvalues:

```c++
std::string s{ ... };
rvFunc(s);                    // ERROR: passing an lvalue to an rvalue reference
rvFunc(std::move(s));         // OK, passing an xvalue
rvFunc(std::string{"hello"}); // OK, passing a prvalue
```

However, when we use the parameter str inside the function, we are dealing with an object that has a name. This means that we use str as an lvalue. We can do only what we are allowed to do with an lvalue.

This means that we cannot directly call our own function recursively:

```c++
void rvFunc(std::string&& str) {
  rvFunc(str); // ERROR: passing an lvalue to an rvalue reference
}
```

We have to to mark `str` with `std::move()` again:

```c++
void rvFunc(std::string&& str) {
  rvFunc(std::move(str)); // OK, passing an xvalue
}
```

This is the formal specification of the rule that move semantics is not passed through that we have [already discussed](). Again, note that this is a feature, not a bug. If we passed move semantics through, we would not be able to use an object that was passed with move semantics twice, because the first time we use it it would lose its value. Alternatively, we would need a feature that temporarily disables move semantics here.

If we bind an rvalue reference parameter to an rvalue (prvalue or xvalue), the object is used as an lvalue, which we have to convert to an rvalue again to pass it to an rvalue reference.

Now, remember that `std::move()` is nothing but a `static_cast` to an rvalue reference. That is, what we program in a recursive call is just the following:

```c++
void rvFunc(std::string&& str) {
  rvFunc(static_cast<std::string&&>(str)); // OK, passing an xvalue
}
```

We cast the object str to its own type. So far, that would be a no-op. However, with the cast, we do something else: we change the value category. By rule, with a cast to an rvalue reference the lvalue becomes an xvalue and therefore allows us to pass the object to an rvalue reference.

This is nothing new: even before C++11, a parameter declared as an lvalue reference followed the rules of lvalues when being used. The key point is that a reference in a declaration specifies what can be passed to a function. For the behavior inside a function references are irrelevant.

Confusing? Well that is just how we define the rules of move semantics and value categories in the C++ standard. Take it as it is. Fortunately, compilers know these rules.

If there is one thing for you to learn here it is that move semantics is not passed through. If you pass an object with move semantics you have to mark it with std::move() again to forward its semantics to another function.

## 8.6 Checking Value Categories with `decltype`
Together with move semantics, C++11 introduced a new keyword decltype. The primary goal of this keyword is to get the exact type of a declared object. However, it can also be used to determine the value category of an expression.

### 8.6.1 Using `decltype` to Check the Type of Names

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

The expression `decltype(str)` always yields the type of `str`, which is `std::string&&`. We can use this type wherever we need this type in an expression. Type traits (type functions such as `std::is_same<>`) help us deal with these types.

For example, to declare a new object of the passed parameter type that is not a reference, we can declare:

```c++
void rvFunc(std::string&& str)
{
  std::remove_reference<decltype(str)>::type tmp;
  ...
}
```

`tmp` has type `std::string` in this function (which we could also explicitly declare, but if we make this a generic function for objects of type T, the code would still work).

### 8.6.2 Using `decltype` to Check the Value Category

So far, we have passed only names to `decltype` to ask for its type. However, you can also pass expressions (that are not just names) to `decltype`. In that case, `decltype` also yields the value category according to the following conventions:

- For a **prvalue** it just yields its value type: `type`
- For an **lvalue** it yields its type as an lvalue reference: `type&`
- For an **xvalue** it yields its type as an rvalue reference: `type&&`

For example:	

```c++
void rvFunc(std::string&& str)
{
   decltype(str + str) // yields std::string because s+s is a prvalue
   decltype(str[0])    // yields char& because the index operator yields an lvalue
  ...
}
```

This means that if you just pass a name placed inside parentheses, which is an expression and no longer just a name, `decltype` yields its type and its value category. The behavior is as follows:

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

Compare this with the [former implementation of this function not using additional parentheses](). Here, `decltype` of `(str)` yields `std::string&` because `str` is an lvalue of type `std::string`.

The fact that for decltype, it makes a difference when we put additional parentheses around a passed name, will also have significant consequences when we later discuss [`decltype(auto)`]().

#### Check for a Value Category Inside Code
In general, you can now check for a specific value category inside code as follows:

- `!std::is_reference_v<decltype((expr))>` checks whether expr is a prvalue.
- `std::is_lvalue_reference_v<decltype((expr))>` checks whether expr is an lvalue.
- `std::is_rvalue_reference_v<decltype((expr))>` checks whether expr is an xvalue.
- `!std::is_lvalue_reference_v<decltype((expr))>` checks whether expr is an rvalue.

Note again the additional parentheses used here to ensure that we use the value-category checking form of `decltype` even if we only pass a name as expr.

Before C++20, you have to skip the suffix `_v` and append `::value` instead.

## 8.7 Summary
- Any expression in a C++ program belongs to exactly one of these primary value categories:
  - **lvalue** (roughly, for a named object or a string literal)
  - **prvalue** (roughly, for an unnamed temporary object)
  - **xvalue** (roughly, for an object marked with std::move())
- Whether a call or operation in C++ is valid depends on both the type and the value category.
- Rvalue references of types can only bind to rvalues (prvalues or xvalues).
- Implicit operations might change the value category of a passed argument.
- **Passing an rvalue to an rvalue references binds it to an lvalue**.
- **Move semantics is not passed through**.
- Functions and references to functions are always lvalues.
- For rvalues (temporary objects or objects marked with std::move()), plain value members have move semantics but reference or `static` members have not.
- `decltype` can either check for the declared type of a passed name or for the type and the value category of a passed expression.