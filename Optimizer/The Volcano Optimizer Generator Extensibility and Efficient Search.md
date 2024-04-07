# The Volcano Optimizer Generator: Extensibility and Efficient Search

[TOC]

## 摘要（Abstract）

> Emerging database application domains demand not only new functionality but also high performance. <u>To satisfy these two requirements, the Volcano project provides efficient, extensible tools for query and request processing, particularly for object-oriented and scientific database systems</u>. One of these tools is a new **optimizer generator**. Data model, logical algebra, physical algebra, and optimization rules are translated by the optimizer generator into optimizer source code. Compared with our earlier *EXODUS* optimizer generator prototype, the search engine is more extensible and powerful; it provides effective support for <u>non-trivial</u> cost models and for physical properties such as sort order. <u>At the same time, it is much more efficient as it combines dynamic programming, which until now had been used only for relational **select-project-join** optimization, with goal-directed search and branch-and-bound pruning.</u> Compared with other rule-based optimization systems, it provides **complete data model independence** and more natural extensibility.

新兴的数据库应用领域不仅需要新功能，还需要高性能。为了满足这两个需求，Volcano 为查询和请求处理，尤其是面向对象的科学数据库系统，提供了高效，可扩展的工具。其中一个工具是新的**优化器生成器**。优化器生成器将数据模型、逻辑代数、物理代数和优化规则转换为优化器源代码。与早期的 *EXODUS* 优化器生成器原型相比，搜索引擎有更好的扩展性和更强的功能。它有效地支持了**复杂的成本模型**和**物理属性**，如排序顺序。<u>同时，它将动态规划与目标导向搜索、分支和边界剪枝相结合，从而提高了效率，动态规划到目前为止只用于关系**选择-投影-关联**优化</u>。与其他基于规则的优化系统相比，它提供了**完全独立的数据模型**和更自然的可扩展性。

## 简介（Introduction）

> While **extensibility** is an important goal and requirement for many current database research projects and system prototypes, performance must not be sacrificed for two reasons. **First**, data volumes stored in database systems continue to grow, in many application domains far beyond the capabilities of most existing database systems. Second, in order to overcome acceptance problems in emerging database application areas such as scientific computation, database systems must achieve at least the Same performance as the file systems currently in use. Additional software layers for database management must be <u>counterbalanced</u> by database performance advantages normally not used in these application areas. Optimization and parallelization are prime candidates to provide these performance advantages, and tools and techniques for optimization and parallelization are crucial for the wider use of extensible database technology. 
>
> For a number of research projects, namely the Volcano extensible, parallel query processor [4], the REVELATION OODBMS project [[11]]() and optimization and parallelization in scientific databases [20] as well as to assist research efforts by other researchers, we have built a new extensible query optimization system. Our earlier experience with the EXODUS optimizer generator had been inconclusive; while it had proven the feasibility and validity of the optimizer generator <u>paradigm</u>, it was difficult to con struct efficient, production-quality optimizers. Therefore, we designed a new **optimizer generator**, requiring several important improvements over the EXODUS prototype. **First**, this new optimizer generator had to be usable both in the Volcano project with the existing query execution software as well as in other projects as a stand-alone tool. **Second**, the new system had to be more efficient, both in optimization time and in memory consumption for the search. **Third**, it had to provide effective, efficient, and extensible support for physical properties such as sort order and compression status. **Fourth**, it had to permit use of heuristics and data model semantics to guide the search and to prune futile parts of the search space. **Finally**, it had to support flexible cost models that permit generating dynamic plans for incompletely specified queries.
>
> In this paper, we describe the Volcano Optimizer Generator, which will soon fulfill all the requirements above. Section 2 introduces the main concepts of the Volcano optimizer generator and enumerates facilities for tailoring a new optimizer. Section 3 discusses the optimizer search strategy in detail. Functionality, extensibility, and search efficiency of the EXODUS and Volcano optimizer generators are compared in Section 4. In Section 5, we describe and compare other research into extensible query optimization. We offer our conclusions from this research in Section 6.
>

**可扩展性**是当前许多数据库研究项目和系统原型的重要目标和要求，但不能因此牺牲性能，有两个原因。**首先**，数据库系统中存储的数据量持续增长，在许多应用程序域中，远远超出了大多数现有数据库系统的功能。**其次**，为了克服新兴数据库应用程序领域（如科学计算）中的验收问题，数据库系统和当前使用的文件系统的性能至少相同。应用程序区域通常没有用到数据库性能优势，但必须用数据库性能优势来平衡数据库管理的其他软件层。优化和并行化是提供这些性能优势的主要候选方法，而优化和并行化的工具和技术对于可扩展数据库技术的广泛使用至关重要。

我们为许多研究项目，即 Volcano 可扩展并行查询处理器[4]，REVELATION OODBMS 项目[11]，科学数据库的优化和并行化[20]，以及为了协助其他研究人员的研究工作，**建立了一个新的可扩展查询优化系统**。我们对 EXODUS 优化器生成器的早期经验尚无定论。尽管已经证明了优化器生成器<u>范例</u>的可行性和有效性，但很难构建有效的、生产质量的优化器。 因此，我们设计了一种新的**优化器生成器**，需要对 EXODUS 原型进行几项重要的改进。**第一**，这个新的优化器生成器既可以在 Volcano 项目中使用（基于现有查询执行软件），也可以在其他项目中作为独立工具使用。**第二**，无论是优化时间还是搜索的内存消耗，新系统必须更高效。**第三**，它必须为物理属性（如排序顺序和压缩状态）提供有效、高效和可扩展的支持。**第四**，它必须允许使用启发式和数据模型语义来指导搜索，并裁剪搜索空间中无用的部分。**最后**，它必须支持灵活的成本模型，允许为不完全指定的查询生成动态计划。

我们在本文描述了 Volcano 优化生成器，它将很快满足上述所有要求。第2节介绍了Volcano优化器生成器的主要概念，并列举了定制新优化器的工具。第3节详细讨论了优化器搜索策略。第4节比较 EXODUS 和 Volcano 优化器生成器的功能、可扩展性和搜索效率。在第5节中，我们描述并比较可扩展查询优化的其他研究。我们在第6节中给出本研究的结论。

>  什么是优化器生成器（Optimizer Generator）？

## 2. Volcano 优化器生成器外部视图（The Outside View of the Volcano Optimizer Generator）

> In this section, we describe the Volcano optimizer generator as seen by the person who is implementing a database system and its query optimizer. The focus is the wide array of facilities given to the optimizer implementor, i.e., modularity and extensibility of the Volcano optimizer generator design. After considering the design principles of the Volcano optimizer generator, we discuss generator input and operation. Section 3 discusses the search strategy used by optimizers generated with the Volcano optimizer generator.
>
> Figure 1 shows the optimizer generator <u>paradigm</u>. When the DBMS software is being built, a model specification is translated into optimizer source code, which is then compiled and linked with the other DBMS software such as the query execution engine. Some of this software is written by the optimizer implementor, e.g., cost functions. After a data model description has been translated into source code for the optimizer, the generated code is compiled and linked with the search engine that is part of the Volcano optimization software. When the DBMS is operational and a query is entered, the query is passed to the optimizer, which generates an optimized plan for it. We call the person who specifies the data model and implements the DBMS software the "**optimizer implementor**." The person who poses queries to be optimized and executed by the database system is called the **DBMS user**.
>

本节描述实现数据库系统和查询优化器开发者所<u>看到</u>的 **Volcano 优化器生成器**。重点是为优化器实现者提供的大量工具，即 Volcano 优化器生成器设计的模块化和可扩展性。讨论了 Volcano 优化器生成器的设计原理之后，讨论生成器的输入和操作。第3节讨论 Volcano 优化器生成器生成的优化器所使用的搜索策略。

> TODO: 图一

图1显示了优化器生成器<u>范例</u>。构建 DBMS 软件时，将<u>模型规范</u>转换为优化器源代码，然后编译并链接进其他 DBMS 软件（如查询执行引擎）。优化器的实现者编写软件中的某些部分，如成本函数。**将数据模型描述转换为优化程序的源代码后，编译生成的代码，并与 Volcano 优化软件的搜索引擎链接**。运行 DBMS 并输入查询，将查询传递给优化器，优化器生成优化的查询计划。我们将指定数据模型并实现 DBMS 软件的人称为**优化器实现者**。提出要由数据库系统优化和执行查询的人称为**DBMS用户**。

### 2.1.  设计原则（Design Principles）

> There are five fundamental design decisions embodied in the system, which contribute to the extensibility and search efficiency of optimizers designed and implemented with the Volcano optimizer generator. We explain and justify these decisions in turn.
>
> **First**, while query processing in relational systems has always been based on the relational algebra, it is becoming increasingly clear that query processing in extensible and object-oriented systems will also be based on algebraic techniques, i.e., by defining algebra operators, algebraic equivalence laws, and suitable implementation algorithms. Several object-oriented algebras have recently been proposed, e.g. [16-18] among many others. Their common thread is that algebra operators **consume** one or more bulk types (e.g., a set, bag, array, time series, or list) and **produce** another one suitable as input into the next operator. The execution engines for these systems are also based on algebra operators, i.e., algorithms consuming and producing **<u>bulk types</u>**. However, the set of operators and the set of algorithms are different, and selecting the most efficient algorithms is one of the central tasks of query optimization. Therefore, the Volcano optimizer generator uses two algebras, called the logical and the physical algebras, and generates optimizers that map an expression of the logical algebra (a query) into an expression of the physical algebra (a query evaluation plan consisting of algorithms). <u>To do so, it uses transformations within the logical algebra and cost-based mapping of logical operators to algorithms</u>.
>
> **Second**, rules have been identified as a general concept to specify knowledge about pattems in a concise and modular fashion, and knowledge of algebraic laws as required for equivalence transformations in query optimization can easily be expressed using patterns and rules. Thus, most extensible query optimization systems use rules, including the Volcano optimizer generator. Furthermore, the focus on independent rules ensures modularity. In our design, rules are translated independently from one another and are combined only by the search engine when optimizing a query. Considering that query optimization is one of the conceptually most complex components of any database system, modularization is an advantage in itself both for initial construction of an optimizer and for its maintenance.
>
> **Third**, the choices that the query optimizer can make to map a query into an optimal equivalent query evaluation plan are represented as **algebraic equivalences** in the Volcano optimizer generator's input. Other systems use multiple intermediate levels when transforming a query into a plan. For example, the cost-based optimizer component of the extensible relational Starburst database system uses an "expansion grammar" with multiple levels of "nonterminals" such as commutative binary join, noncommutative binary join, etc. [lo]. We felt that multiple intermediate levels and the need to re-design them for a new or extended algebra confuse issues of equivalence, i.e., defining the choices open to the optimizer, and of search method, i.e., the order in which the optimizer considers possible query evaluation plans. Just as navigational query languages are less user-friendly than nonnavigational ones, an extensible query optimization system that requires control information from the database implementor is less convenient than one that does not. Therefore, optimizer choices are represented in the Volcano optimizer generator's input file as algebraic equivalences, and the optimizer generator's search engine applies them in a suitable manner. However, for database implementors who wish to exert control over the search, e.g., who wish to specify search and pruning heuristics, there will be optional facilities to do so.
>
> The **fourth** fundamental design decision concerns rule interpretation vs. compilation. In general, interpretation can be made more flexible (in particular the rule set can be augmented at run-time), while compiled rule sets typically execute faster. Since query optimization is very CPUintensive, we decided on rule compilation similar to the EXODUS optimizer generator. Moreover, we believe that extending a query processing system and its optimizer is so complex and time-consuming that it can never be done quickly, making the strongest argument for an interpreter pointless. In order to gain additional flexibility with compiled rule sets, it may be useful to parameterize the rules and their conditions, e.g., to conml the thoroughness of the search, and to observe and exploit repeated sequences of rule applications. In general, the issue of flexibility in the search engine and the choice between interpretation vs. compilation are orthogonal.
>
> **Finally**, the search engine used by optimizers generated with the Volcano optimizer generator is based on dynamic programming. We will discuss the use of dynamic programming in Section 3.

系统包含了五个基本设计决策，帮助 Volcano 优化器生成器设计和实现优化器，提升优化器的可扩展性和搜索效率。下面依次解释并证明这些设计决策。

**第一**，尽管关系系统中的查询处理始终基于关系代数，但越来越明确的是，可扩展和面向对象系统中的查询处理**也将基于关系代数**，即通过定义**代数运算符**、**代数等价律**和**合适的实现算法**。最近提出了一些面向对象代数，如[16-18]等。它们的共同点是代数运算符**消费**一个或多个大容量类型（例如，集合、包、数组、时间序列或列表），并**生产**下一个运算符的合法输入。这些系统的执行引擎也基于代数运算符，即消费和生产**<u>大量类型</u>**的算法。 但是，<u>==运算符集合==</u>和<u>==算法集合==</u>不同，选择最高效的算法是查询优化的中心任务之一。因此，Volcano 优化器生成器使用两种代数，分别称为**<u>逻辑代数</u>**和**<u>物理代数</u>**，生成的优化器将逻辑代数表达式（查询语句）转换为物理代数表达式（由算法组成的查询执行计划）。因此，使用<u>关系代数进行逻辑转换</u>，<u>基于成本将逻辑运算符转换为物理算法</u>。

**第二**，规则被定义为一个通用的概念，以简洁、模块化的方式描述模式，**可以很容易地用模式和规则**来表示**查询优化中等价转换所需的代数法则**。因此，大多数可扩展的查询优化系统都使用规则，包括 Volcano 优化器生成器。此外，规则的独立性确保了模块化。在我们的设计中，规则相互独立地转换，并且在优化查询时仅由搜索引擎组合。考虑到查询优化是任何数据库系统理论上最复杂的组件之一，模块化本身对于优化器的初始构建和维护都是一个优势。

==**第三**，查询优化器将查询转换为最佳等价查询执行计划的选择，在 Volcano 优化器生成器的输入中表示为**代数等价**。其他系统在将查询转换为执行计划时，使用多个中间层。例如，可扩展关系型数据库系统 Starburst 基于成本的优化器组件使用一种“扩展语法”，它具有多层“非终结符”，如交换二进制关联、非交换二进制关联等[10]。我们认为多个中间层，以及为新的或扩展的代数重新设计它们的需求，混淆了等价性问题，即定义向优化器开放的选择，以及搜索方法问题，即优化器考虑可能的查询执行计划的顺序。正如导航式查询语言，比非导航式查询语言不方便用户一样；需要来自数据库实现者控制信息的可扩展查询优化系统，也比不需要控制信息的查询优化系统不方便。因此，优化器选择在 Volcano 优化器生成器的输入文件中表示为代数等价，并且优化器生成器的搜索引擎以适当的方式使用它们。但对于希望对搜索施加控制的数据库实现者，例如，希望指定搜索和使用启发式裁剪的数据库实现者，要有可选的工具来执行此操作。==

**第四**个基本设计决策涉及解释和编译规则。解释通常更灵活（特别是运行时可以增加规则集），而编译通常执行得更快。由于查询优化耗费大量CPU时间，决定使用规则编译，类似 EXODUS 优化器生成器。而且，我们认为扩展查询处理系统及其优化器是如此复杂且耗时，以至于无法快速完成，这使得解释器的最强论据毫无意义。为了利用编译的规则集获得额外的灵活性，对规则及其条件进行参数化可能很有用，例如，控制搜索的彻底性，观察和利用规则应用的重复序列。一般来说，搜索引擎的灵活性与解释和编译之间的选择是正交的。

**最后**，使用 Volcano 优化生成器生成的优化器使用的搜索引擎基于动态规划。将在第3节讨论动态规划的使用。

### 2.2. 优化器生成器的输入和优化器操作（Optimizer Generator Input and Optimizer Operation）

> Since one major design goal of the Volcano optimizer generator was to minimize the assumptions about the data model to be implemented, the optimizer generator only provides a framework into which an optimizer implementor can integrate data model specific operations and functions. In this section, we discuss the components that the optimizer implementor defines when implementing a new database query optimizer. The actual user queries and execution plans are input and output of the generated optimizer, as shown in Figure 1. All other components discussed in this section are specified by the optimizer implementor before optimizer generation in the form of equivalence rules and support functions, compiled and linked during optimizer generation, and then used by the generated optimizer when optimizing queries. We discuss parts of the operation of generated optimizers here, but leave it to the section on search to draw all the pieces together.
>
> The user queries to be optimized by a generated optimizer are specified as an algebra expression (tree) of logical operators. The translation from a user interface into a logical algebra expression must be performed by the parser and is not discussed here. The set of logical operators is declared in the model specification and compiled into the optimizer during generation. Operators can have zero or more inputs; the number of inputs is not restricted. The output of the optimizer is a plan, which is an expression over the algebra of algorithms. ==The set of algorithms, their capabilities and their costs represents the data formats and physical storage structures used by the database system for permanent and temporary data==.
>
> Optimization consists of mapping a logical algebra expression into the optimal equivalent physical algebra expression. In other words, a generated optimizer reorders operators and selects implementation algorithms. The algebraic rules of expression equivalence, e.g., commutativity or associativity, are specified using transformation rules. The possible mappings of operators to algorithms are specified using implementation rules. It is important that the rule language allow for complex mappings. For example, a join followed by a projection (without duplicate removal) should be implemented in a single procedure; therefore, it is possible to map multiple logical operators to a single physical operator. Beyond simple pattern matching of operators and algorithms, additional conditions may be specified with both kinds of rules. This is done by attaching condition code to a rule, which will be invoke after a pattern match has succeeded.
>
> **The results of expressions are described using properties**, similar to the concepts of properties in the EXODUS optimizer generator and the Starburst optimizer. Logical properties can be derived from the logical algebra expression and include schema, expected size, etc., while physical properties depend on algorithms, e.g., sort order, partitioning, etc. When optimizing a many-sorted algebra, the logical properties also include the type (or sort) of an intermediate result, which can be inspected by a rule's condition code to ensure that rules are only applied to expressions of the correct type. Logical properties are attached to equivalence classes - sets of equivalent logical expressions and plans - whereas physical properties are attached to specific plans and algorithm choices.
>
> The set of physical properties is summarized for each intermediate result in a physical property vector, which is defined by the optimizer implementor and treated as an abstract data type by the Volcano optimizer generator and its search engine. In other words, the types and semantics of physical properties can be designed by the optimizer implementor.
>
> There are some operators in the physical algebra that do not correspond to any operator in the logical algebra, for example sorting and decompression. The purpose of these operators is not to perform any logical data manipulation but to enforce physical properties in their outputs that are required for subsequent query processing algorithms. We call these operators enforcers; they are comparable to the "glue" Operators in Starburst. It is possible for an enforcer to ensure two properties, or to enforce one but destroy another.
>
> Each optimization goal (and subgoal) is a pair of a logical expression and a physical property vector. In order to decide whether or not an algorithm or enforcer can be used to execute the root node of a logical expression, a generated optimizer matches the implementation rule, executes the condition code associated with the rule, and then invokes an applicability function that determines whether or not the algorithm or enforcer can deliver the logical expression with physical properties that satisfy the physical property vector. The applicability functions also determine the physical property vectors that the algorithm's inputs must satisfy. For example, when optimizing a join expression whose result should be sorted on the join attribute, hybrid hash join does not qualify while merge-join qualifies with the requirement that its inputs be sorted. The sort enforcer also passes the test, and the requirements for its input do not include sort order. When the input to the sort is optimized, hybrid hash join qualifies. There is also a provision to ensure that algorithms do not qualify redundantly, e.g., merge-join must not be considered as input to the sort in this example.
>
> After the optimizer decides to explore using an algorithm or enforcer, it invokes the algorithm's cost function to estimate its cost. Cost is an abstract datu type for the optimizer generator; therefore, the optimizer implementor can choose cost to be a number (e.g., estimated elapsed time), a record (e.g., estimated CPU time and I/O count), or any other type. Cost arithmetic and comparisons are performed by invoking functions associated with the abstract data type "cost."
>
> For each logical and physical algebra expression, logical and physical properties are derived using property functions. There must be one property function for each logical operator, algorithm, and enforcer. The logical properties are determined based on the logical expression, before any optimization is performed, by the property functions associated with the logical operators. For example, the schema of an intermediate result can be determined independently of which one of many equivalent algebra expressions creates it. The logical property functions also encapsulate selectivity estimation. On the other hand, physical properties such as sort order can only be determined after an execution plan has been chosen. As one of many consistency checks, generated optimizers verify that the physical properties of a chosen plan really do satisfy the physical property vector given as part of the optimization goal.
>
> To summarize this section, the optimizer implementor provides (1) a set of logical operators, (2) algebraic transformation rules, possibly with condition code, (3) a set of algorithms and enforcers, (4) implementation rules, possibly with condition code, (5) an ADT "cost" with functions for basic arithmetic and comparison, (6) an ADT "logical properties," (7) an ADT "physical property vector" including comparisons functions (equality and cover), (8) an applicability function for each algorithm and enforcer, (9) a cost function for each algorithm and enforcer, (10) a property function for each operator, algorithm, and enforcer. This might seem to be a lot of code; however, all this functionality is required to construct a database query optimizer with or without an optimizer generator. Considering that query optimizers are typically one of the most intricate modules of a database management systems and that the optimizer generator prescribes a clean modularization for these necessary optimizer components, the effort of building a new database query optimizer using the Volcano optimizer generator should be significantly less than designing and implementing a new optimizer from scratch. This is particularly true since the optimizer implementor using the Volcano optimizer generator does not need to design and implement a new search algorithm.
>

由于 Volcano 优化器生成器的一个主要设计目标是最小化对要实现的数据模型的假设，因此优化器生成器只提供了一个框架，优化器实现者可以将特定于数据模型的操作和功能集成到该框架中。我们将在本节中讨论，在实现新的数据库查询优化器时，**优化器实现者**需要定义的组件。如图 1 所示，实际的用户查询和执行计划是生成的优化器的输入和输出。本节讨论的所有其他组件，在优化器生成之前由优化器实现者以等价规则和支持函数的形式指定；在优化器生成期间编译和链接；然后在优化查询时，由生成的优化器使用。我们在这里讨论生成的优化器的部分操作，但将其留在搜索部分以将所有部分组合在一起。

用户查询被生成的优化器优化，并被指定为逻辑运算符的代数表达式树。从用户接口到逻辑代数表达式的转换必须由解析器执行，不在这讨论。 逻辑运算符集在**模型规范**中声明，并在生成期间编译到优化器中。运算符可以有零个或多个输入；输入的数目不受限制。优化器的输出是一个计划，**是算法的一个代数表达式**。算法集及其能力和成本代表数据格式和物理存储结构，数据库系统利用它们存储永久和临时数据。

**优化包括将逻辑代数表达式映射到最佳等价物理代数表达式**。换句话说，生成的优化器对运算符进行重新排序并选择实现算法。使用**==变换规则==**来表达等价的代数规则，如可交换性或结合性。使用**==实现规则==**表达运算符到算法的转换。规则语言允许复杂的映射很重要。例如，一个关联后跟一个投影（没有删除重复项）应该在一个过程中实现；因此，会将多个逻辑运算符映射到一个物理运算符。除了算子和算法的简单模式匹配外，两类规则还可以指定附加条件。通过将条件附加到这两类规则，在模式匹配成功后测试这些附加条件来完成。

**表达式的结果用属性描述**，这里的属性类似于 EXODUS 优化器生成器和 Starburst 优化器中的属性概念。逻辑属性可以从逻辑代数表达式推导出来，包括 Schema，预期大小等，而物理属性取决于算法，例如排序顺序，分区等。优化多次排序的代数时，逻辑属性还包括中间结果的类型（或排序），可以由规则的条件代码检查，以确保规则仅应用于正确类型的表达式。逻辑属性附加到等价类（等价逻辑表达式和计划的集合），而物理属性附加到特定计划和选择的算法上。

中间结果的物理属性保存在物理属性数组中，物理属性数组由优化器实现者定义，Volcano 优化器生成器及其搜索引擎将其视为**抽象数据类型**。换句话说，物理属性的类型和语义可以由优化器实现者设计。

物理代数中有一些运算符与逻辑代数中的任何运算符都不对应，例如排序和解压缩。这些运算符的目的不是执行任何逻辑数据操作，而是在其输出中强制执行后续查询处理算法所需的物理属性。我们称这些运算符为强制执行器；它们与 Starburst 中的“胶水”运算符类似。强制执行器可以确保两个属性，或者强制执行一个但销毁另一个属性。

**==每个优化目标（和子目标）是一对逻辑表达式和一个物理属性数组（向量）==**。为了决定是否可以使用算法或强制执行器来执行逻辑表达式的根节点，生成的优化器匹配**实现规则**，执行与该规则关联的条件代码，然后调用一个**适用性函数**，该函数确定算法或实现程序**交付**的逻辑表达式的物理性质是否满足物理属性数组。适用性函数还确定算法输入必须满足的物理属性数组。例如，当优化关联表达式时，其结果应在关联属性上排序，混合哈希关联不符合条件，而归并关联符合其输入进行排序的要求。排序执行器也通过了测试，其它不要求输入有序。当优化排序的输入时，混合哈希 Join 就可以了。还有一个规定可以确保算法不会过多地限定，例如，在本例中，不得将 merge-join 视为排序的输入。

在优化器决定使用算法或强制执行器进行探索之后，它调用**算法的成本函数**来估计其成本。成本是优化器生成器的抽象数据类型。因此，优化器实现者可选择成本的类型为数字（例如，估计的运行时间），记录（例如，估计的CPU时间和I/O计数）或其他任何类型。计算和比较成本是通过调用与抽象 “cost” 数据类型相关联的函数来执行。

对于每个逻辑和物理代数表达式，使用属性函数导出逻辑和物理属性。每个逻辑运算符、算法和执行器必须有一个属性函数。在执行任何优化之前，通过与逻辑运算符关联的属性函数，基于逻辑表达式确定逻辑属性。例如，中间结果的 schema 可以由创建它的等价代数表达式各自独立确定。逻辑属性函数还封装了选择性估计。另一方面，物理属性（如排序顺序）只能在选择了执行计划之后才能确定。作为众多一致性检查之一，生成的优化器验证**所选计划的物理属性**，是否确实满足作为优化目标一部分给定的物理属性数组（向量）。

总结本节，优化器实现程序提供（1）一组逻辑运算符，（2）代数转换规则，可能有条件代码，（3）一组算法和强制执行器，（4）实现规则，可能有条件代码，（5）ADT“成本”，有基本算术和比较功能，（6）ADT“逻辑属性”，（7）ADT“物理属性数组（向量）”，包括比较函数（等式和覆盖），（8）每个算法和实施者的适用性函数，（9）每个算法和实施者的成本函数，（10）每个运算符、算法和实施者的属性函数。这看起来有很多代码；但是用不用优化器生成器，都需要所有这些功能来构造数据库查询优化器。考虑到查询优化器通常是数据库管理系统中最复杂的模块之一，并且优化器生成器为这些必要的优化器组件规定了干净的模块化，使用 Volcano 优化器生成器构建新的数据库查询优化器的工作量应该大大小于从头开始设计和实现一个新的优化器，尤其是不需要设计和实现新的搜索算法。

##  3. 搜索引擎（The Search Engine）

> Since the general paradigm of database query optimization is to create alternative (equivalent) query evaluation plans and then to choose among the many possible plans, the search engine and its algorithm are central components of any query optimizer. Instead of forcing each database and optimizer implementor to implement an entirely newsearch engine and algorithm, the Volcano optimizer generator provides a search engine to be used in all created optimizers. This search engine is linked automatically with the pattern matching and rule application code generated from the data model description.
>
> Since our experience with the EXODUS optimizer generator indicated that it is easy to waste a lot of search effort in extensible query optimization, we designed the search algorithm for the Volcano optimizer generator to use dynamic programming and to be very goal-oriented, i.e., ==driven by needs rather than by possibilities==.
>
> Dynamic programming has been used before in database query optimization, in particular in the System R optimizer [15] and in Starburst's cost-based optimizer [8, 10], but only for relational select-project-join queries. The search strategy designed with the Volcano optimizer generator extends dynamic programming from relational join optimization to general algebraic query and request optimization and combines it with a top-down, goal-oriented control strategy for algebras in which the number of possible plans exceeds practical limits of pre-computation. ==Our dynamic programming approach derives equivalent expressions and plans only for those partial queries that are considered as parts of larger subqueries (and the entire query), not all equivalent expressions and plans that are feasible or seem interesting by their sort order [15]==. Thus, the exploration and optimization of subqueries and their alternative plans is tightly directed and very goal-oriented. In a way, while the search engines of the EXODUS optimizer generator as well as of the System R and Starburst relational systems use f**orward chaining** (in the sense in which this term is used in AI), the Volcano search algorithm uses backward chaining, because it explores only those subqueries and plans that truly participate in a larger expression. We call our search algorithms *directed dynam'c programming*.
>
> Dynamic programming is used in optimizers created with the Volcano optimizer generator by retaining a large set of partial optimization results and using these earlier results in later optimization decisions. Currently, this set of partial optimization results is reinitialized for each query being optimized. In other words, earlier partial optimization results are used during the optimization of only a single query. We are considering research into <u>==longer-lived partial results==</u> in the future.
>
> Algebraic transformation systems always include the possibility of deriving the same expression in several different ways. In order to prevent redundant optimization effort by detecting redundant (i.e., multiple equivalent) derivations of the same logical expressions and plans during optimization, expression and plans are captured in a hash table of expressions and equivalence classes. An equivalence class represents two collections, one of equivalent logical and one of physical expressions (plans).The logical algebra expressions are used for efficient and complete exploration of the search space, and plans are used for a fast choice of a suitable input plan that satisfies physical property requirements. For each combination of physical properties for which an equivalence class has already been optimized, e.g., unsorted, sorted on A, and sorted on B, the best plan found is kept.
>
> Figure 2 shows an outline of the search algorithm used by the Volcano optimizer generator. The original invocation of the `FindBestPlan` procedure indicates the logical expression passed to the optimizer as the query to be optimized, physical properties as requested by the user (for example, sort order as in the ORDER BY clause of SQL), and a cost limit. This limit is typically infinity for a user query, but the user interface may permit users to set their own limits to "catch" unreasonable queries, e.g., ones using a Cartesian product due to a missing join predicate.
>
> > - [x] Figure 2
>
> The `FindBestPlan` procedure is broken into two parts. **First**, if a plan for the expression satisfying the physical property vector can be found in the hash table, either the plan and its cost or a failure indication are returned depending on whether or not the found plan satisfies the given cost limit. If the expression cannot be found in the hash table, or if the expression has been optimized before but not for the presently required physical properties, actual optimization is begun.
>
> There are three sets of possible "moves" the optimizer can explore at any point. First, the expression can be transformed using a transformation rule. Second, there might be some algorithms that can deliver the logical expression with the desired physical properties, e.g., hybrid hash join for unsorted output and merge-join for join output sorted on the join attribute. Third, an **enforcer** might be useful to permit additional algorithm choices, e.g., a sort operator to permit using hybrid hash join even if the final output is to be sorted.
>
> After all possible moves have been generated and assessed, the most promising moves are pursued. Currently, with only exhaustive search implemented, all moves are pursued. In the future, a subset of the moves will be selected, determined and ordered by another function provided by the optimizer implementor. Pursuing all moves or only a selected few is a major heuristic placed into the hands of the optimizer implementor. In the extreme case, an optimizer implementor can choose to transform a logical expression without any algorithm selection and cost analysis, which covers the optimizations that in Starburst are separated into the query rewrite level. The difference between Starburst's two-level and Volcano's approach is that this separation is mandatory in Starburst while Volcano will leave it as a choice to be made by the optimizer implementor.
>
> > pursue：继续探讨(或追究、从事);
>
> **The cost limit** is used to improve the search algorithm using branch-and-bound pruning. Once a complete plan is known for a logical expression (the user query or some part of it) and a physical property vector, no other plan or partial plan with higher cost can be part of the optimal query evaluation plan. Therefore, it is important (for optimization speed, not for correctness) that a relatively good plan be found fast, even if the optimizer uses exhaustive search. Furthermore, cost limits are passed down in the optimization of subexpressions, and tight upper bounds also speed their optimization.
>
> **If a move to be pursued is a transformation, the new expression is formed and optimized using** `FindBestPlan`. In order to detect the case that two (or more) rules are inverses of each other, the current expression and physical property vector is marked as "in progress." If a newly formed expression already exists in the hash table and is marked as "in progress," it is ignored because its optimal plan will be considered when it is finished.
>
> Often a new equivalence class is created during a transformation. Consider the associativity rule in Figure 3. The expressions rooted at A and B are equivalent and therefore belong into the same class. However, expression C is not equivalent to any expression in the left expression and requires a new equivalence class. In this case, a new equivalence class is created and optimized as required for cost analysis and optimization of expression B.
>
> > TODO：图 3
>
> **If a move to be pursued is the exploration of a normal query processing algorithm such as merge-join**, its cost is calculated by the algorithm's cost function. The algorithm's <u>applicability function</u> determines the physical property vectors for the algorithms inputs, and their costs and optimal plans are found by invoking FindBestPlan for the inputs.
>
> For some binary operators, the actual physical properties of the inputs are not as important as the consistency of physical properties among the inputs. For example, for a sort-based implementation of intersection, i.e., an algorithm very similar to merge-join, any sort order of the two inputs will suffice as long as the two inputs are sorted in the same way. Similarly, for a parallel join, any partitioning of join inputs across multiple processing nodes is acceptable if both inputs are partitioned using compatible partitioning rules. For these cases, the search engine permits the optimizer implementor to specify a number of physical property vectors to be tried. For example, for the intersection of two inputs R and S with attributes A, B, and C where R is sorted on (A,B,C) and S is sorted on (B,A,C), both these sort orders can be specified by the optimizer implementor and will be optimized by the generated optimizer, while other possible sort orders, e.g., (C,B,A), will be ignored.
>
> **If the move to be pursued is the use of an enforcer such as sort**, its cost is estimated by a cost function provided by the optimizer implementor and the original logical expression is optimized using `FindBestPlan` with a suitably modified (i.e., relaxed) physical property vector. In many respects, enforcers are dealt with exactly like algorithms, which is not surprising considering that both are operators of the physical algebra. During optimization with the modified physical property vector, algorithms that already applied before relaxing the physical properties must not be explored again. For example, if a join result is required sorted on the join column, merge-join (an algorithm) and sort (an enforcer) will apply. When optimizing the sort input, i.e., the join expression without the sort requirement, **hybrid hash join** should apply but **merge-join** should not. To ensure this, FindBestPlan uses an additional parameter, not shown in Figure 2, called the excluding physical property vector that is used only when inputs to enforcers are optimized. In the example, the excluding physical property vector would contain the sort condition, and since merge-join is able to satisfy the excluding properties, it would not be considered a suitable algorithm for the sort input.
>
> > `Sort <= hash join` vs `Merge-join <=  sort`
>
> At the end of (or actually already during) the optimization procedure `FindBestPlan`, newly derived interesting facts are captured in the hash table. **"Interesting" is defined with respect to possible future use**, which includes both plans optimal for given physical properties as well as failures that can save future optimization effort for a logical expression and a physical property vector with the same or even lower cost limits.
>
> In summary, the search algorithm employed by optimizers created with the Volcano optimizer generator uses dynamic programming by storing all optimal sub-plans as well as optimization failures until a query is completely optimized. Without any **a-priori assumptions** about the algebras themselves, it is designed to map an expressions over the logical algebra into the optimal equivalent expressions over the physical algebra. Since it is very goal oriented through the use of physical properties and **<u>derives only those expressions and plans that truly participate in promising larger plans</u>**, the algorithm is more efficient than previous approaches to using dynamic programming in database query optimization.

由于数据库查询优化的一般范式是创建可选的（等价的）查询执行计划，然后在众多可能的计划中进行选择，因此搜索引擎及其算法是任何查询优化器的核心组件。Volcano 优化器生成器提供了一个搜索引擎，可供所有创建的优化器使用，而不是强制每个数据库和优化器实现者实现全新的搜索引擎和算法。从数据模型描述生成的<u>模式匹配和规则应用代码</u>和搜索引擎自动链接。

使用 EXODUS 优化器生成器的经验表明，在可扩展查询优化中很容易浪费大量的搜索工作，因此我们为 Volcano 优化器生成器设计了一个使用动态规划的搜索算法，且**非常面向目标**，==即由需求，而非可能性驱动==。

动态规划之前已经用于数据库查询优化，尤其是 System R 优化器[15]和 Starburst 基于成本的优化器[8，10]，但仅用于关系的 select-project-join 查询。Volcano 优化器生成器设计的搜索策略将动态规划从**关系的 Join 优化**扩展到一般代数查询和请求优化，并将其与自顶向下、面向目标的代数控制策略相结合，在这些代数中，可能的计划数量超过了预计算的实际限值。==我们的动态规划方法仅针对部分查询产生等价的表达式和计划，这些部分查询被视为较大子查询（和整个查询）的一部分，而不是根据排序顺序，所有可行或看起来有趣的等价表达式和计划[15]==。因此，子查询及其替代计划的探索和优化有着紧密的方向性，并且非常面向目标。在某种程度上，虽然 EXODUS 优化器生成器以及 System R 和 Starburst 的搜索引擎使用**前向链接**（AI 中使用该术语的意义），但 Volcano 搜索算法仍使用**后向链接**，因为它仅搜索真正参与更大表达式的那些子查询和计划。我们称这种搜索算法为**定向动态规划**。

> 什么是 forward chaining 和 backward chaining

Volcano 优化器生成器创建的优化器使用动态规划，保留大量的部分优化结果，并在后续的优化决策中使用它们。当前，针对每个要优化的查询，都将重新初始化局部优化结果。换句话说，仅在单个查询的优化过程中使用了较早的部分优化结果。 我们正在考虑将来对<u>==寿命更长的部分结果==</u>进行研究。

代数变换系统总是包含以几种不同方式推导（优化）同一表达式的可能性。为了防止冗余的优化工作，优化过程中需要检测是否多次优化（即多个等价）相同的逻辑表达式和计划，因此在哈希表中保存等价的表达式和计划。等价分类表示两个集合，一个是等价逻辑表达式，一个是物理表达式（计划）。逻辑代数表达式用于对搜索空间进行高效、完整地探索，<u>==而计划则用于快速选择满足物理属性要求的输入计划==</u>。对于已经优化了的等价物理属性的每种组合（例如，未排序，在 A 上排序和在 B 上排序），将保留找到的最佳计划。

```C
/*图 2 搜索算法概述*/
FindBestPlan (LogExpr, PhysProp, Limit)
  if the pair LogExpr and PhysProp is in the look-up table
    if the cost in the look-up table < Limit
      return Plan and Cost
    else    
      return failure                           // 优化失败的计划，执行成本高于期望成本
  /* else: optimization required */
  create the set of possible "moves" from
    applicable transformations                 // 转换表达式
    algorithms that give the required PhysProp // 提供所需物理属性的算法
    enforcers for required PhysProp            // 所需物理属性的执行器
  order the set of moves by promise            // 根据可行性排序
  for the most promising moves
    if the move uses a transformation
      apply the transformation creating NewLogExpr
      call FindBestPlan (NewLogExpr, PhysProp, Limit)
    else if the move uses an algorithm
      TotalCost := cost of the algorithm
      for each input I while Totalcost <= Limit
        determine required physical properties PP for I
        Cost = FindBestPlan (I, PP, Limit Totalcost)
        add Cost to Totalcost
    else /* move uses an enforcer */
      Totalcost := cost of the enforcer
      modify PhysProp for enforced property
      call FindBestPlan for LogExpr with new Physhop
  /* maintain the look-up table of explored facts */
  if LogExpr is not in the look-up table
    insert LogExpr into the look-up table
  insert PhysProp and best plan found into look-up table
  return best Plan and Cos
```
图 2 概述 Volcano 优化器生成器使用的搜索算法。调用 `FindBestPlan` 时（注意 `FindBestPlan` 是递归调用）需要传入：逻辑表达式（优化器要优化的查询），用户需要的物理属性（例如，SQL ORDER BY 子句中的排序顺序）和成本限制。对于用户查询，通常没有成本限制，但是用户接口允许用户设置自己的限制来“捕获”不合理的查询，例如，由于缺少连接谓词而使用笛卡尔积的查询。

`FindBestPlan` 分为两部分。**首先**，如果可以为表达式在哈希表中找到满足物理属性数组的计划，则根据找到的计划是否满足给定的成本限制，返回找到的计划及其成本，或者查找失败的指示。如果在哈希表中找不到表达式，或者如果该表达式之前已优化，但不是针对当前所需的物理属性，则开始实际优化。

优化器可以随时探索三组可能的“动作”。 第一，使用转换规则来转换表达式。第二，有一些算法可以传递具有所需物理属性的逻辑表达式，例如，**混合哈希连接**用于<u>未排序</u>输出，**归并连接**用于<u>根据 Join 属性排序</u>的输出。第三，**强制执行器**有助于选择其他算法，例如，即使最终输出需要有序，那么使用排序运算符，就可以选择**混合哈希联接**。

在生成并评估所有可能的动作之后，将**<u>继续探测</u>**最有希望的动作。目前只实现了穷举搜索，会继续探测所有的动作。未来，优化器实现者将提供另一个函数，用于选择、确定和排序这些动作的子集。由优化器实现者决定是否继续探测所有动作，或仅选择少数动作进行探测。极端情况下，优化器实现者可以选择转换逻辑表达式，而无需任何算法选择和成本分析，这在 Starburst 中被分离到查询重写层优化。Starburst 的两级方法和 Volcano 方法的区别在于：Starburst 是强制分离，而 Volcano 把它留给优化器实现者去选择。

使用分支定界裁剪的搜索算法使用**成本限制**提高其性能。如果已知<u>某个逻辑表达式（用户查询或其中的某一部分）和物理属性数组</u>的完整计划，那么成本更高的计划或者部分（子）计划不能成为最佳查询执行计划的一部分。因此，即使优化器使用穷举搜索，尽快找到一个相对好的计划也很重要（对于优化速度，而不是正确性）。此外，优化子表达式时，也传递成本限制，严格的上限亦加快了它们的优化速度。

**如果继续探索的动作是转换，则使用** `FindBestPlan` **来形成并优化新的表达式**。为了检测两个（或多个）规则互逆的情况，将当前表达式和物理属性数组标记为“进行中”。如果新形成的表达式已经存在于哈希表中并被标记为“进行中”，则将其忽略，因为完成时会考虑其最佳计划。

转换通常会创建新的等价表达式。考虑图 3 中的结合规则。以 A 和 B 为根的表达式是等价的，因此属于同一类。但是，左侧没有一个表达式和表达式 C 等价，因此需要一个新的等价分类。这种情况下，会创建一个新的等价类，并根据需要进行优化，以进行成本分析和优化表达式 B。

> TODO：图 3

**如果继续探索的行动是探索常规查询处理算法（例如归并连接）**，则由算法的成本函数来计算其成本。 算法的<u>适用性函数</u>确定算法输入的物理属性数组，调用 `FindBestPlan` 找到算法输入（算法输入也是逻辑计划）的成本和最佳计划。

对于某些二元运算符，输入的实际物理属性不如输入之间物理属性的一致性重要。例如，基于排序的交集实现，一种与归并连接非常相似的算法，两个输入只要以相同的方式排序，任意排序顺序都可以。类似，对于并行 Join，如果两个输入的分区规则兼容，那么跨多个处理节点的 Join 输入的任意分区都可以接受。对于这些情况，搜索引擎允许优化器实现者指定要尝试的多个物理属性数组。例如，计算两个输入 R 和 S 在属性 A、B 和 C 上的交集，其中 R 按（A、B、C）排序，S 按（B、A、C）排序，这两个排序顺序都可以由优化器实现者指定，并由生成的优化器优化，而其他可能的排序顺序，例如（C、B、A）将被忽略。

**如果继续探索的行动是使用排序之类的强制执行器**，则由优化器实现者提供的成本函数估算其成本，并使用 `FindBestPlan` 和经过适当修改（即放松）的物理属性数组优化原始逻辑表达式。在很多方面，强制执行器的处理方式与算法完全相同，考虑到两者都是物理代数的运算符，这并不奇怪。在使用修改后的物理属性数组进行优化的过程中，不用再探索放松物理属性之前已经应用的算法。例如，如果需要对 Join 列上的连接结果进行排序，则将应用归并连接（算法）和排序（强制执行器）。当优化排序的输入时，即连接表达式没有排序的要求，应使用**混合哈希连接**，不应使用**归并连接**。为确保这一点，`FindBestPlan` 使用了一个未在图 2 中显示的附加参数，称为排除物理属性数组，该参数仅在优化强制执行器的输入时使用。在本例中，排除物理属性数组将包含排序条件，由于归并连接满足排除属性，因此，不是用于排序输入的合适算法。

`FindBestPlan` 结束时（或实际上在此过程中），哈希表保存了新推导出的**有趣事实**。**“有趣”是针对将来可能使用而定义**，它既包括针对给定物理属性的最佳计划，也包括优化失败的计划，当未来优化具有相同或更低成本限制的逻辑表达式和物理属性数组时，可节省工作。 

总之，由 Volcano 优化器生成器创建的优化器，其搜索算法使用动态规划，将存储所有最佳和优化失败的子计划，直到完全优化完查询为止。它不需要对代数本身进行任何**先验假设**，而是将逻辑代数上的表达式映射到物理代数上的最优等价表达式。由于该算法是一种目标导向的方法，通过物理属性的使用，**<u>只得到那些真正有希望参与到更大计划的表达式和计划</u>**，因此比以往数据库查询优化中使用动态规划的方法更有效。

## 4. Comparison with the EXODUS Optimizer Generator