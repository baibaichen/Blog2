# Assembling a query optimizer with Apache Calcite

> **Abstract** Apache Calcite is a dynamic data management framework with SQL parser, optimizer, executor, and JDBC driver.
>
> Many examples of Apache Calcite usage demonstrate the end-to-end execution of queries using JDBC driver, some built-in optimization rules, and the `Enumerable` executor. Our customers often have their own execution engines and JDBC drivers. So how to use Apache Calcite for query optimization only, without its JDBC driver and `Enumerable` executor?
>
> In this tutorial, we create a simple query optimizer using internal Apache Calcite classes.

**摘要** Apache Calcite 是一个动态数据管理框架，带有 SQL 解析器、优化器、执行器和 JDBC 驱动程序。许多 Apache Calcite 使用示例演示了使用 JDBC 驱动程序、一些内置优化规则和 `Enumerable` 执行器的端到端查询执行。我们的客户通常拥有自己的执行引擎和 JDBC 驱动程序。在不适用 JDBC 驱动和 `Enumerable` 执行引擎的情况下，如何只使用 Apache Calcite 进行查询优化？

在本教程中，我们使用内部 Apache Calcite 类创建一个简单的查询优化器。

## Schema

> First, we need to define the schema. We start with a custom table implementation. To create a table, you should extend Apache Calcite's `AbstractTable`. We pass two pieces of information to our table:
>
> 1. Field names and types that we will use to construct the row type of the table (required for expression type derivation).
> 2. An optional `Statistic` object that provides helpful information for query planner: row count, collations, unique table keys, etc.
>
> Our statistic class exposes only row count information.

首先，我们需要定义 **schema**。我们从自定义表开始，要创建表，应该扩展 Apache Calcite 的`AbstractTable`。 我们向表传递两条信息:

1. 用于构造表的 **Row** 类型的字段名和类型（表达式类型推导所需）。
2. 一个可选的 `Statistic` 对象，为查询优化器提供有用的信息：行数、排序规则、唯一的表键等。

我们的统计类只公开行数信息。

```java
public class SimpleTableStatistic implements Statistic {
    private final long rowCount;
    public SimpleTableStatistic(long rowCount) {
        this.rowCount = rowCount;
    }
    @Override
    public Double getRowCount() {
        return (double) rowCount;
    }
    // Other methods no-op
}
```

> We pass **column names** and **types** to our <u>table class</u> to construct the row type, which Apache Calcite uses to derive data types of expressions.

我们将**列名**和**类型**传递给<u>表类</u>以构造 Row 类型，Apache Calcite 使用它来推导表达式的数据类型。

```java
public class SimpleTable extends AbstractTable {

    private final String tableName;
    private final List<String> fieldNames;
    private final List<SqlTypeName> fieldTypes;
    private final SimpleTableStatistic statistic;

    private RelDataType rowType;

    private SimpleTable(
        String tableName, 
        List<String> fieldNames,       // 列名
        List<SqlTypeName> fieldTypes,  // 字段类型 
        SimpleTableStatistic statistic // 统计信息
    ) {
        this.tableName = tableName;
        this.fieldNames = fieldNames;
        this.fieldTypes = fieldTypes;
        this.statistic = statistic;
    }
    
    @Override
    public RelDataType getRowType(RelDataTypeFactory typeFactory) {
        if (rowType == null) {
            List<RelDataTypeField> fields = new ArrayList<>(fieldNames.size());
            for (int i = 0; i < fieldNames.size(); i++) {
                RelDataType fieldType = typeFactory.createSqlType(fieldTypes.get(i));
                RelDataTypeField field = 
                  new RelDataTypeFieldImpl(fieldNames.get(i), i, fieldType);
                fields.add(field);
            }
            rowType = new RelRecordType(StructKind.PEEK_FIELDS, fields, false);
        }

        return rowType;
    }

    @Override
    public Statistic getStatistic() {
        return statistic;
    }
}
```

> Our table also implements Apache Calcite's `ScannableTable` interface. We do this only for demonstration purposes because we will use a certain `Enumerable` optimization rule in our example that will fail without this interface. You do not need to implement this interface if you are not going to use the Apache Calcite `Enumerable` execution backend.

我们的表还实现了 Apache Calcite 的 `ScannableTable` 接口。 我们这样做只是为了演示目的，因为我们将在我们的示例中使用某个 `Enumerable` 优化规则，如果没有这个接口就会失败。 如果您不打算使用 Apache Calcite `Enumerable` 执行后端，则不需要实现此接口。

```java
public class SimpleTable extends AbstractTable implements ScannableTable {
    ...
    @Override
    public Enumerable<Object[]> scan(DataContext root) {
        throw new UnsupportedOperationException("Not implemented");
    }
    ...
}
```

> Finally, we extend Apache Calcite's `AbstractSchema` class to define our own schema. We pass a map from a table name to a table. Apache Calcite uses this map to resolve tables during semantic validation.

最后，我们扩展 Apache Calcite 的 `AbstractSchema` 类来定义我们自己的 **schema**。我们传递一个表名到表的 `Map`。Apache Calcite 在语义验证期间使用此映射来解析表。

```java
public class SimpleSchema extends AbstractSchema {

    private final String schemaName;
    private final Map<String, Table> tableMap;

    private SimpleSchema(String schemaName, Map<String, Table> tableMap) {
        this.schemaName = schemaName;
        this.tableMap = tableMap;
    }

    @Override
    public Map<String, Table> getTableMap() {
        return tableMap;
    }
}
```

> We are ready to start the optimization.

我们准备开始优化。

## Optimizer

> The optimization process consists of the following phases:
>
> 1. Syntax analysis that produces an abstract syntax tree (AST) from a query string.
> 2. Semantic analysis of an AST.
> 3. Conversion of an AST to a relational tree.
> 4. Optimization of a relational tree.
>

优化过程包括以下阶段：

1. 语法分析：从查询字符串生成抽象语法树 (AST) 。
2. 语义分析：分析 AST  的语义。
3. AST  转换为关系树。
3. 优化关系树。

### Configuration

> Many Apache Calcite classes that we use for query optimization require configuration. However, there is no common configuration class in Apache Calcite that could be used by all objects. For this reason, we store the common configuration in a single object and then copy configuration values into other objects when needed.
>
> In this specific example, we instruct Apache Calcite on how to process object identifiers: do not change identifier casing, use case-sensitive name resolution.

许多用于查询优化的 Apache Calcite 类都需要配置。但是，Apache Calcite 中没有可供所有对象使用的通用配置类。因此，我们将公共配置存在单个对象中，然后在需要时将配置值复制到其他对象中。

在这个特定示例中，我们指导 Apache Calcite 如何处理对象标识符：不要更改标识符大小写，使用区分大小写的名称解析。

```java
Properties configProperties = new Properties();

configProperties.put(CalciteConnectionProperty.CASE_SENSITIVE.camelName(), Boolean.TRUE.toString());
configProperties.put(CalciteConnectionProperty.UNQUOTED_CASING.camelName(), Casing.UNCHANGED.toString());
configProperties.put(CalciteConnectionProperty.QUOTED_CASING.camelName(), Casing.UNCHANGED.toString());

CalciteConnectionConfig config = new CalciteConnectionConfigImpl(configProperties);
```

### Syntax Analysis

> First of all, we should parse the query string. The result of parsing is an abstract syntax tree, with every node being a subclass of `SqlNode`.
>
> We pass a part of our common configuration to the parser configuration, then instantiate `SqlParser`, and finally perform the parsing. If you have a custom SQL syntax, you may pass a custom parser factory class to the configuration.

首先，我们应该解析查询字符串。 解析的结果是一个抽象的语法树，每个节点都是 `SqlNode` 的子类。

我们将一部分我们常用的配置传递给解析器配置，然后实例化 `SqlParser`，最后进行解析。 如果您有自定义 SQL 语法，则可以将自定义解析器工厂类传递给配置。

```java
public SqlNode parse(String sql) throws Exception {
    SqlParser.ConfigBuilder parserConfig = SqlParser.configBuilder();
    parserConfig.setCaseSensitive(config.caseSensitive());
    parserConfig.setUnquotedCasing(config.unquotedCasing());
    parserConfig.setQuotedCasing(config.quotedCasing());
    parserConfig.setConformance(config.conformance());

    SqlParser parser = SqlParser.create(sql, parserConfig.build());

    return parser.parseStmt();
}
```

### Semantic Analysis

> The goal of semantic analysis is to ensure that the produced abstract syntax tree is valid. Semantic analysis includes the resolution of object and function identifiers, data types inference, checking the correctness of certain SQL constructs (e.g., a group key in the `GROUP BY` statement).
>
> The validation is performed by the `SqlValidatorImpl` class, one of the most [complex](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/sql/validate/SqlValidatorImpl.java) classes in Apache Calcite. This class requires several supporting objects. First, we create an instance of `RelDataTypeFactory`, which provides SQL type definitions. We use the built-in type factory, but you may also provide your custom implementation if need.

语义分析的目标是确保生成的抽象语法树是有效的。 语义分析包括对象和函数标识符的解析、数据类型推断、检查某些 SQL 构造（例如，`GROUP BY` 语句中的分组键）的正确性。

验证由 `SqlValidatorImpl` 类执行，这是 Apache Calcite 中最[复杂](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite /sql/validate/SqlValidatorImpl.java)的类之一，它需要几个支持对象。**==首先==**，我们创建一个 `RelDataTypeFactory` 的实例，它提供 SQL 类型定义。 我们使用内置类型工厂，但如果需要，您也可以提供自定义实现。

```Java
RelDataTypeFactory typeFactory = new JavaTypeFactoryImpl();
```

> Then, we create a `Prepare.CatalogReader` object that provides access to database objects. This is where our previously defined schema comes into play. Catalog reader consumes our common configuration object to have an object name resolution mechanics consistent with the one we used during parsing.

然后，我们创建一个 `Prepare.CatalogReader` 对象来提供对数据库对象的访问。 这就是我们之前定义的 Schema 发挥作用的地方。 `CatalogReader` 使用通用的配置对象，以获得与 <u>SQL Parse 期间</u>使用的对象名称解析机制一致的对象名称解析机制。

```java
SimpleSchema schema = ... // Create our custom schema

CalciteSchema rootSchema = CalciteSchema.createRootSchema(false, false);
rootSchema.add(schema.getSchemaName(), schema);

Prepare.CatalogReader catalogReader = new CalciteCatalogReader(
    rootSchema,
    Collections.singletonList(schema.getSchemaName()),
    typeFactory,
    config
);
```

> Then, we define a `SqlOperatorTable`, the library of SQL functions and operators. We use the built-in library. You may also provide your implementation with custom functions.

然后，我们定义了一个 `SqlOperatorTable`，SQL 函数和操作符库，这里使用内置库。还可以自定义实现以提供自定义函数。

```java
SqlOperatorTable operatorTable = ChainedSqlOperatorTable.of(
    SqlStdOperatorTable.instance()
);
```

> We created all the required supporting objects. Now we instantiate the built-in `SqlValidatorImpl`. As usual, you may extend it if you need a custom validation behavior (such as custom error messages).

我们创建了所有必需的支持对象。 现在我们实例化内置了 `SqlValidatorImpl`。 像往常一样，如果您需要自定义验证行为（例如自定义错误消息），可以扩展它。

```java
SqlValidator.Config validatorConfig = SqlValidator.Config.DEFAULT
    .withLenientOperatorLookup(config.lenientOperatorLookup())
    .withSqlConformance(config.conformance())
    .withDefaultNullCollation(config.defaultNullCollation())
    .withIdentifierExpansion(true);

SqlValidator validator = SqlValidatorUtil.newValidator(
    operatorTable, 
    catalogReader, 
    typeFactory,
    validatorConfig
);
```

> Finally, we perform validation. Keep the validator instance because we will need it for AST conversion to a relational tree.

最后，我们执行验证。保留验证器实例，因为我们需要它将 AST 转换为关系树。

```java
SqlNode sqlNode = parse(sqlString);
SqlNode validatedSqlNode = validator.validate(node);
```

### Conversion to a Relational Tree

> AST is not convenient for query optimization because the semantics of its nodes is too complicated. It is much more convenient to perform query optimization on a tree of relational operators, defined by the `RelNode` subclasses, such as `Scan`, `Project`, `Filter`, `Join`, etc. We use `SqlToRelConverter`, another [monstrous class](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/sql2rel/SqlToRelConverter.java) of Apache Calcite, to convert the original AST into a relational tree.
>
> Interestingly, to create a converter, we must create an instance of a cost-based planner `VolcanoPlanner` first. This is one of Apache Calcite's abstraction leaks.
>
> To create the `VolcanoPlanner`, we again pass the common configuration and the `RelOptCostFactory` that the planner will use to calculate costs. In a production-grade optimizer, you are likely to define a custom cost factory, because the built-in factories [take in count](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/volcano/VolcanoCost.java#L100) only cardinality of relations, which is often insufficient for proper cost estimation.
>
> You should also specify which physical operator properties the `VolcanoPlanner` should track. Every property has a descriptor that extends Apache Calcite's `RelTraitDef` class. In our example, we register only the `ConventionTraitDef`, which defines the execution backend for a relational node.

AST 不便于查询优化，因为其节点的语义太复杂。在关系运算符树上执行查询优化要方便得多，这些运算符由 `RelNode` 子类定义，例如 `Scan`、`Project`、`Filter`、`Join` 等。我们使用 `SqlToRelConverter`， Apache Calcite 的另一个 [怪异](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/sql2rel/SqlToRelConverter.java)，用于将原始 的AST 转化为关系树。

有趣的是，要创建**转换器**，我们必须先创建一个基于成本的规划器 `VolcanoPlanner` 的实例。这是 Apache Calcite 的抽象泄漏之一。

为了创建 `VolcanoPlanner`，我们再次传递通用配置和 `RelOptCostFactory` （优化器将用于计算成本）。在生产级优化器中，您可能会定义一个自定义的 **cost factory**，因为内置工厂只[计算](https://github.com/apache/calcite/blob/branch-1.24/core/src /main/java/org/apache/calcite/plan/volcano/VolcanoCost.java#L100)关系的基数，这通常不足以进行正确的成本估算。 

您还应该指定 `VolcanoPlanner` 应该跟踪哪些物理操作符属性。每个属性都有一个扩展 Apache Calcite 的 `RelTraitDef` 类的描述符。在我们的例子中，我们只注册了 `ConventionTraitDef`，它定义了关系节点的执行后端。


```java
VolcanoPlanner planner = new VolcanoPlanner(
    RelOptCostImpl.FACTORY, 
    Contexts.of(config)
);

planner.addRelTraitDef(ConventionTraitDef.INSTANCE);
```

> We then create a `RelOptCluster`, a common context object used during conversion and optimization.

然后我们创建一个 `RelOptCluster`，一个在转换和优化过程中使用的通用上下文对象。

```java
RelOptCluster cluster = RelOptCluster.create(
    planner, 
    new RexBuilder(typeFactory)
);
```

> We can create the converter now. Here we set a couple of configuration properties for a subquery unnesting, which is out of this post's scope.

我们现在可以创建转换器。 在这里，我们为消除子查询设置了几个配置属性，这超出了本文的范围。

```java
SqlToRelConverter.Config converterConfig = SqlToRelConverter.configBuilder()
    .withTrimUnusedFields(true)
    .withExpand(false) 
    .build();

SqlToRelConverter converter = new SqlToRelConverter(
    null,
    validator,
    catalogReader,
    cluster,
    StandardConvertletTable.INSTANCE,
    converterConfig
);
```

> Once we have the converter, we can create the relational tree.

一旦我们有了转换器，我们就可以创建关系树。

```java
public RelNode convert(SqlNode validatedSqlNode) {
    RelRoot root = converter.convertQuery(validatedSqlNode, false, true);

    return root.rel;
}
```

> During the conversion, Apache Calcite produces a tree of [logical](https://github.com/apache/calcite/tree/branch-1.24/core/src/main/java/org/apache/calcite/rel/logical) relational operators, are abstract and do not target any specific execution backend. For this reason, logical operators always have the convention trait set to `Convention.NONE`. It is expected that you will convert them into **physical** operators during the optimization. Physical operators have a specific convention different from `Convention.NONE`.

在转换过程中，Apache Calcite 生成[逻辑关系运算符树](https://github.com/apache/calcite/tree/branch-1.24/core/src/main/java/org/apache/calcite/rel/logical)，是抽象的并且不针对任何特定的执行后端。因此，逻辑运算符总是将调用约定特征设置为 `Convention.NONE`，优化期间将它们转换为**物理**操作符。物理操作符有一个不同于 `Convention.NONE` 的调用约定。

### Optimization

> Optimization is a process of conversion of a relation tree to another relational tree. You may do rule-based optimization with heuristic or cost-based planners, `HepPlanner` and `VolcanoPlanner` respectively. You may also do any manual rewrite of the tree without rule. Apache Calcite comes with several powerful rewriting tools, such as `RelDecorrelator` and `RelFieldTrimmer`.
>
> Typically, to optimize a relational tree, you will perform multiple optimization passes using rule-based optimizers and manual rewrites. Take a look at the [default optimization program](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/tools/Programs.java#L250-L283) used by Apache Calcite JDBC driver or [multi-phase query optimization](https://github.com/apache/flink/blob/release-1.12/flink-table/flink-table-planner-blink/src/main/scala/org/apache/flink/table/planner/plan/optimize/program/FlinkBatchProgram.scala#L45) in Apache Flink.
>
> In our example, we will use `VolcanoPlanner` to perform cost-based optimization. We already instantiated the `VolcanoPlanner` before. Our inputs are a relational tree to optimize, a set of optimization rules, and traits that the optimized tree's parent node must satisfy.
>

优化是将一棵关系树转换成另一棵关系树。可以分别使用启发式或基于成本的优化器 `HepPlanner` 和 `VolcanoPlanner` 进行基于规则的优化。也可以在没有规则的情况下手动重写树。 Apache Calcite 附带了几个强大的重写工具，例如 `RelDecorrelator` 和 `RelFieldTrimmer`。

通常，要优化关系树，您将使用基于规则的优化器和手动重写来执行多轮优化。看看 Apache Calcite JDBC 驱动使用的[默认优化程序](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/tools/Programs.java#L250-L283)或 Apache Flink 中的[多阶段查询优化](https://github.com/apache/flink/blob/release-1.12/flink-table/flink-table-planner-blink/src/main/scala/org/apache/flink/table/planner/plan/optimize/program/FlinkBatchProgram.scala#L45)。

我们的例子使用 `VolcanoPlanner` 来执行基于成本的优化。之前已经实例化了 `VolcanoPlanner`。我们的**输入**是要优化的关系树、一组优化规则以及优化树的父节点必须满足的特征。

```java
public RelNode optimize(
    RelOptPlanner planner,
    RelNode node, 
    RelTraitSet requiredTraitSet, 
    RuleSet rules
) {
    Program program = Programs.of(RuleSets.ofList(rules));

    return program.run(
        planner,
        node,
        requiredTraitSet,
        Collections.emptyList(),
        Collections.emptyList()
    );
}
```

## Example

> In this example, we will optimize the TPC-H query №6. The full source code is available [here](https://github.com/querifylabs/querifylabs-blog/tree/main/01-simple-query-optimizer). Run the `OptimizerTest` to see it in action.

在本例中，我们将优化 TPC-H 查询 №6。 完整源代码可在 [此处](https://github.com/querifylabs/querifylabs-blog/tree/main/01-simple-query-optimizer) 获得。 运行 `OptimizerTest` 以查看它的运行情况。

```sql
SELECT
    SUM(l.l_extendedprice * l.l_discount) AS revenue
FROM
    lineitem
WHERE
    l.l_shipdate >= ?
    AND l.l_shipdate < ?
    AND l.l_discount between (? - 0.01) AND (? + 0.01)
    AND l.l_quantity < ?
```

> We define the `Optimizer` class that encapsulates the created configuration, `SqlValidator`, `SqlToRelConverter` and `VolcanoPlanner`.

我们定义了`Optimizer` 类，它封装了创建的配置、`SqlValidator`、`SqlToRelConverter` 和 `VolcanoPlanner`。

```java
public class Optimizer {
    private final CalciteConnectionConfig config;
    private final SqlValidator validator;
    private final SqlToRelConverter converter;
    private final VolcanoPlanner planner;
    
    public Optimizer(SimpleSchema schema) {
        // Create supporting objects as explained above
        ... 
    }
}
```

> Next, we create the schema with the `lineitem` table.

接下来，我们使用 `lineitem` 表创建 Schema。

```java
SimpleTable lineitem = SimpleTable.newBuilder("lineitem")
    .addField("l_quantity", SqlTypeName.DECIMAL)
    .addField("l_extendedprice", SqlTypeName.DECIMAL)
    .addField("l_discount", SqlTypeName.DECIMAL)
    .addField("l_shipdate", SqlTypeName.DATE)
    .withRowCount(60_000L)
    .build();

SimpleSchema schema = SimpleSchema.newBuilder("tpch").addTable(lineitem).build();

Optimizer optimizer = Optimizer.create(schema);
```

> Now we use our optimizer to parse, validate, and convert the query.

现在我们使用优化器来解析、验证和转换查询。

```java
SqlNode sqlTree = optimizer.parse(sql);
SqlNode validatedSqlTree = optimizer.validate(sqlTree);
RelNode relTree = optimizer.convert(validatedSqlTree);
```

> The produced logical tree looks like this.

生成的逻辑树看起来像这样。

```
LogicalAggregate(group=[{}], revenue=[SUM($0)]): rowcount = 1.0, cumulative cost = 63751.137500047684
  LogicalProject($f0=[*($1, $2)]): rowcount = 1875.0, cumulative cost = 63750.0
    LogicalFilter(condition=[AND(>=($3, ?0), <($3, ?1), >=($2, -(?2, 0.01)), <=($2, +(?3, 0.01)), <($0, ?4))]): rowcount = 1875.0, cumulative cost = 61875.0
      LogicalTableScan(table=[[tpch, lineitem]]): rowcount = 60000.0, cumulative cost = 60000.0
```

> Finally, we optimize the relational tree and convert it into the `Enumerable` convention. We use logical rules that convert and merge `LogicalProject` and `LogicalFilter` into compound `LogicalCalc`, and physical rules that convert logical nodes into `Enumerable` nodes.

最后，我们优化关系树并将其转换为 `Enumerable` 约定。我们使用逻辑规则将 `LogicalProject` 和 `LogicalFilter` 转换并合并为复合 `LogicalCalc`，以及物理规则将逻辑节点转换为  `Enumerable`  节点。

```java
RuleSet rules = RuleSets.ofList(
    CoreRules.FILTER_TO_CALC,
    CoreRules.PROJECT_TO_CALC,
    CoreRules.FILTER_CALC_MERGE,
    CoreRules.PROJECT_CALC_MERGE,
    EnumerableRules.ENUMERABLE_TABLE_SCAN_RULE,
    EnumerableRules.ENUMERABLE_PROJECT_RULE,
    EnumerableRules.ENUMERABLE_FILTER_RULE,
    EnumerableRules.ENUMERABLE_CALC_RULE,
    EnumerableRules.ENUMERABLE_AGGREGATE_RULE
);

RelNode optimizerRelTree = optimizer.optimize(
    relTree,
    relTree.getTraitSet().plus(EnumerableConvention.INSTANCE),
    rules
);
```

> The produced physical tree looks like this. Notice that all nodes are `Enumerable`, and that `Project` and `Filter` nodes have been replaced with `Calc`.

生成的物理树看起来像这样。 请注意，所有节点都是 `Enumerable`，并且 `Project` 和 `Filter` 节点已被替换为 `Calc`。

```
EnumerableAggregate(group=[{}], revenue=[SUM($0)]): rowcount = 187.5, cumulative cost = 62088.2812589407
  EnumerableCalc(expr#0..3=[{inputs}], expr#4=[*($t1, $t2)], expr#5=[?0], expr#6=[>=($t3, $t5)], expr#7=[?1], expr#8=[<($t3, $t7)], expr#9=[?2], expr#10=[0.01:DECIMAL(3, 2)], expr#11=[-($t9, $t10)], expr#12=[>=($t2, $t11)], expr#13=[?3], expr#14=[+($t13, $t10)], expr#15=[<=($t2, $t14)], expr#16=[?4], expr#17=[<($t0, $t16)], expr#18=[AND($t6, $t8, $t12, $t15, $t17)], $f0=[$t4], $condition=[$t18]): rowcount = 1875.0, cumulative cost = 61875.0
    EnumerableTableScan(table=[[tpch, lineitem]]): rowcount = 60000.0, cumulative cost = 60000.0
```

## Summary

> Apache Calcite is a flexible framework for query optimization. In this blog post, we demonstrated how to optimize SQL queries with Apache Calcite parser, validator, converter, and rule-based optimizer. In future posts, we will dig into individual components of Apache Calcite. Stay tuned!
>
> We are always ready to help you with your SQL query optimizer design. Just [let us know](https://www.querifylabs.com/#contact-form).

Apache Calcite 是一个灵活的查询优化框架。 在这篇博文中，我们演示了如何使用 Apache Calcite 解析器、验证器、转换器和基于规则的优化器优化 SQL 查询。 在以后的文章中，我们将深入研究 Apache Calcite 的各个组件。 敬请关注！

我们随时准备帮助您进行 SQL 查询优化器设计。

# Custom traits in Apache Calcite

>
> **Abstract** Physical properties are an essential part of the optimization process that allows you to explore more alternative plans.
>
> Apache Calcite comes with **convention** and **collation (sort order) properties**. Many query engines require custom properties. For example, distributed and heterogeneous engines that we often see in our daily practice need to carefully plan the movement of data between machines and devices, which requires a custom property to describe data location.
>
> In this blog post, we will explore how to define, register and enforce a custom property, also known as *trait*, with Apache Calcite cost-based optimizer.

**摘要** 物理特性是优化过程的重要组成部分，可让您探索更多替代计划。

Apache Calcite 带有**约定**和**排序规则（排序顺序）属性**。 许多查询引擎需要自定义属性。比如我们日常实践中经常看到的==分布式异构引擎==，需要仔细规划机器和设备之间的数据移动，这就需要自定义属性来描述数据位置。

在本篇博文中，我们将探讨如何使用 Apache Calcite 基于成本的优化器来定义、注册和强制执行**自定义属性**，也称为 *trait*。

## Physical Properties

> We start our journey by looking at the example of common physical property - sort order.
>
> Query optimizers work with relational operators, such as `Scan`, `Project`, `Filter`, and `Join`. During the optimization, an operator may require it's input to satisfy a specific condition. To check whether the condition is satisfied, operators may expose **physical properties** - plain values associated with an operator. Operators may compare the desired and actual properties of their inputs and enforce the desired property by injecting a special **enforcer** operator on top of the input.
>
> Consider the join operator `t1 JOIN t2 ON t1.a = t2.b`. We could use a merge join if both inputs are sorted on their join attributes, `t1.a` and `t2.b`, respectively. We may define the collation property for every operator, describing the sort order of produced rows:
>
> ```
> Join[t1.a=t2.b]
>   Input[t1]      [SORTED by a]
>   Input[t2]      [NOT SORTED]
> ```
>
> The merge join operator may enforce the sorting on `t1.a` and `t2.b` on its inputs. Since the first input is already sorted on `t1.a`, it remains unchanged. The second input is not sorted, so the enforcer `Sort` operator is injected, making a merge join possible:
>
> ```
> MergeJoin[t1.a=t2.b]  
>   Input[t1]           [SORTED by t1.a]
>   Sort[t2.a]          [SORTED by t2.b]
>     Input[t2]         [NOT SORTED]
> ```

我们从一个常见物理属性的例子 —— 排序顺序 —— 开始我们的旅程。

查询优化器使用关系运算符，如 `Scan`、`Project`、`Filter` 和 `Join`。在优化过程中，运算符可能要求满足特定条件的输入。要检查输入是否满足条件，运算符可以暴露其**物理属性**  - 与运算符相关联的普通值。运算符可以比较其输入的期望属性和实际属性，并通过在输入之上注入一个特殊的 **enforcer** 运算符来强制需要的属性。

考虑连接操作符 `t1 join t2 ON t1.a = t2.b`。如果两个输入分别按其 `join` 属性 `t1.a` 和 `t2.b` 排序，我们可以使用合并连接。可以为每个操作符定义 `collation` 属性，描述生成行的排序顺序:

```
Join[t1.a=t2.b]
  Input[t1]      [SORTED by a]
  Input[t2]      [NOT SORTED]
```

merge join 运算符可以对其输入的 `t1.a` 和 `t2.b` 强制排序。由于第一个输入已经在 `t1.a` 上排序，所以保持不变。第二个输入未排序，因此注入了**强制执行器** `Sort` 运算符，使 merge join  成为可能：

```
MergeJoin[t1.a=t2.b]  
  Input[t1]           [SORTED by t1.a]
  Sort[t2.a]          [SORTED by t2.b]
    Input[t2]         [NOT SORTED]
```

## Apache Calcite API

> In Apache Calcite, properties are defined by the `RelTrait` and `RelTraitDef` classes. `RelTrait` is a concrete value of the property. `RelTraitDef` is a property definition, which describes the property name, expected Java class of the property, the default value of the property, and how to enforce the property. Property definitions are registered in the planner via the `RelOptPlanner.addRelTraitDef` method. The planner will ensure that every operator has a specific value for every registered property definition, whether the default or not.
>
> All properties of a node are organized in an immutable data structure `RelTraitSet`. This class has convenient methods to add and update properties with copying semantics. You may access the properties of a concrete operator using the `RelOptNode.getTraitSet` method.
>
> To enforce a specific property on the operator during planning, you should do the following from within the rule:
>
> 1. Get the current properties of a node using `RelOptNode.getTraitSet` method.
> 2. Create a new instance of `RelTraitSet` with updated properties.
> 3. Enforce the properties by calling the `RelOptRule.convert` method.
>
> Finally, before invoking the planner program, you may define the desired properties of the root operator of the optimized relational tree. After the optimization, the planner will either return the operator that satisfies these properties or throw an exception.
>
> Internally, the Apache Calcite enforces properties by adding a special `AbstractConverter` operator with the desired traits on top of the target operator.
>
> ```
> AbstractConverter [SORTED by a]
>   Input[t2]       [NOT SORTED]
> ```
>
> To transform the `AbstractConverter` into a real enforcer node, such as `Sort`, you should add the built-in `ExpandConversionRule` rule to your optimization program. This rule will attempt to expand the `AbstractConverter` into a sequence of enforcers to satisfy the desired traits consulting to the trait definitions that we already discussed. We have only one unsatisfied property in our example, so the converter expands into a single `Sort` operator.
>
>
> ```
> Sort[t2.a]        [SORTED by a]
>   Input[t2]       [NOT SORTED]
> ```
>
> You may use your custom expansion rule if needed. See Apache Flink [custom rule](https://github.com/apache/flink/blob/release-1.12/flink-table/flink-table-planner-blink/src/main/scala/org/apache/flink/table/planner/plan/rules/physical/FlinkExpandConversionRule.scala) as an example.


Apache Calcite 用 `RelTrait` 和 `RelTraitDef` 定义**属性**。`RelTrait` 是具体的属性值。`RelTraitDef` 是属性定义，描述了属性名称、属性的 Java 类、属性的默认值以及如何强制执行该属性。通过 `RelOptPlanner.addRelTraitDef` 方法在 planner 中注册属性定义。planner 确保每个运算符对于每个注册的属性定义都有一个特定的值，要么是某个值，要么是默认值。

节点的所有属性都组织在一个不可变的数据结构 `RelTraitSet` 中。这个类有便利的方法，使用复制语义添加和更新属性。可以使用 `RelOptNode.getTraitSet` 方法访问具体运算符的属性。

要在优化期间对运算符强制执行特定属性，应该在 `rule` 中执行以下操作：

1. 使用 `RelOptNode.getTraitSet` 方法获取节点的当前属性。
2. 用修改后的属性创建一个新的 `RelTraitSet` 实例。
3. 通过调用 `RelOptRule.convert` 方法来强制执行属性。

最后，在调用 planner 之前，可以定义<u>关系树的根运算符</u>在优化后所需的属性。优化后，优化器要么返回满足这些属性的运算符，要么抛出异常。

Apache Calcite 内部通过在目标运算符之上添加 `AbstractConverter` 运算符，并带上所需的 **trait** 来强制执行属性。

```
AbstractConverter [SORTED by a]
  Input[t2]       [NOT SORTED]
```

要将 `AbstractConverter` 转换为真正的执行器节点，例如 `Sort`，要将内置的 `ExpandConversionRule` 规则添加到优化器中。此规则尝试将 `AbstractConverter` 扩展为一系列执行器，以满足我们已经讨论过的 trait 定义所要求的 trait 。在我们的示例中，只有一个未满足的属性，因此转换器展开为一个 `Sort` 运算符。

```
Sort[t2.a]        [SORTED by a]
  Input[t2]       [NOT SORTED]
```

如果需要，可以自定义扩展规则。参见 Apache Flink[自定义规则](https://github.com/apache/flink/blob/release-1.12/flink-table/flink-table-planner-blink/src/main/scala/org/apache/flink/ table/planner/plan/rules/physical/FlinkExpandConversionRule.scala)的例子。

## Custom Property

> As we understand the purpose of properties and which Apache Calcite API to use, we will define, register, and enforce our custom property.
>
> Consider that we have a distributed database, where every relational operator might be distributed between nodes in one of two ways:
>
> 1. `PARTITIONED` - relation is partitioned between nodes. Every tuple (row) resides on one of the nodes. An example is a typical distributed data structure.
> 2. `SINGLETON` - relation is located on a single node. An example is a cursor that delivers the final result to the user application.
>
> In our example, we would like to ensure that the top operator always has a `SINGLETON` distribution, simulating the results' delivery to a single node.

随着我们了解**属性**的用途以及要使用的 Apache Calcite API，我们将定义、注册和**强制执行**我们的自定义属性。

假设有一个分布式数据库，其中每个关系运算符可能有以下两种方式之一分布在节点之间：

1. `PARTITIONED` - **relation** 在节点之间进行分区。每个元组（行）都驻留在其中一个节点上。分布式数据结构就是一个典型的例子。
2. `SINGLETON` - **relation** 位于单个节点上。一个例子是向用户应用程序交付最终结果的<u>游标</u>。

在我们的示例中，我们希望确保顶层运算符始终具有 `SINGLETON` 分布，模拟将结果交付到单个节点。

### Enforcer

>First, we define the enforcer operator. To ensure the `SINGLETON` distribution, we need to move from all nodes to a single node. In distributed databases, data movement operators are often called `Exchange`. The minimal requirement for a custom operator in Apache Calcite is to define the constructor and the `copy` method.

首先，定义强制执行器操作符。 为了确保 `SINGLETON` 分布，我们需要从所有节点移动到单个节点。 在分布式数据库中，数据移动操作符通常被称为 `Exchange`。 Apache Calcite 中自定义运算符的最低要求是定义构造函数和 `copy` 方法。

```java
public class ExchangeRel extends SingleRel {
    public RedistributeRel( // ExchangeRel??
        RelOptCluster cluster,
        RelTraitSet traits,
        RelNode input
    ) {
        super(cluster, traits, input);
    }

    @Override
    public RelNode copy(RelTraitSet traitSet, List<RelNode> inputs) {
        return new ExchangeRel(getCluster(), traitSet, inputs.get(0));
    }
}
```

### Trait

> Next, we define our custom trait and trait definition. Our implementation must adhere to the following rules:
>
> 1. The trait must refer to a common trait definition instance in the method `getTraitDef`.
> 2. The trait must override the `satisfies` method to define whether the current trait satisfies the target trait. If not, the enforcer will be used.
> 3. The trait definition must declare the expected Java class of the trait in the `getTraitClass` method.
> 4. The trait definition must declare the default value of the trait in the `getDefault` method.
> 5. The trait definition must implement the method `convert`, which Apache Calcite will invoke to create the enforcer if the current trait doesn't satisfy the desired trait. If there is no valid conversion between traits, `null` should be returned.
>
> Below is the source code of our trait. We define two concrete values, `PARTITIONED` and `SINGLETON`. We also define the special value `ANY`, which we use as the default. We say that both `PARTITIONED` and `SINGLETON` satisfy `ANY` but `PARTITIONED` and `SINGLETON` do not satisfy each other.

接下来，定义自定义的 **trait** 和 **trait definition**。实现必须遵守以下规则：

1. **trait** 必须在方法 `getTraitDef` 中引用一个公共的 **trait definition** 实例。
2. **trait** 必须实现 `satisfies` 方法来定义当前 **trait** 是否满足目标 **trait**。如果没有，则使用强制执行器。
3. **trait definition** 必须在 `getTraitClass` 方法中声明 **trait** 预期的 Java 类。
4. **trait definition** 必须在 `getDefault` 方法中声明 **trait** 的默认值。
5. **trait definition** 必须实现 `convert` 方法，如果当前 **trait** 不满足所需的 **trait**，Apache Calcite 将调用该方法来创建强制执行器。如果 **trait** 之间没有有效的转换，则应返回 `null`。

下面是我们 **trait** 的源代码。我们定义了两个具体的值，`PARTITIONED` 和 `SINGLETON`。我们还定义了特殊值 `ANY`，我们将其用作默认值。我们说 `PARTITIONED` 和 `SINGLETON` 都满足 `ANY`，但 `PARTITIONED` 和 `SINGLETON` 彼此不满足。

```java
public class Distribution implements RelTrait {

    public static final Distribution ANY = new Distribution(Type.ANY);
    public static final Distribution PARTITIONED = new Distribution(Type.PARTITIONED);
    public static final Distribution SINGLETON = new Distribution(Type.SINGLETON);

    private final Type type;

    private Distribution(Type type) {
        this.type = type;
    }

    @Override
    public RelTraitDef getTraitDef() {
        return DistributionTraitDef.INSTANCE; //
    }

    @Override
    public boolean satisfies(RelTrait toTrait) {
        Distribution toTrait0 = (Distribution) toTrait;

        if (toTrait0.type == Type.ANY) {
            return true;
        }

        return this.type.equals(toTrait0.type);
    }

    enum Type {
        ANY,
        PARTITIONED,
        SINGLETON
    }
}
```

> Our trait definition defines the `convert` function, which injects the `ExchangeRel` enforcer if the current property doesn't satisfy the target one.

我们的 **trait definition** 定义了 `convert` 函数，如果当前属性不满足目标属性，它会注入 `ExchangeRel` 强制执行器。

```java
public class DistributionTraitDef extends RelTraitDef<Distribution> {

    public static DistributionTraitDef INSTANCE = new DistributionTraitDef();

    private DistributionTraitDef() {
        // No-op.
    }

    @Override
    public Class<Distribution> getTraitClass() {
        return Distribution.class;
    }

    @Override
    public String getSimpleName() {
        return "DISTRIBUTION";
    }

    @Override
    public RelNode convert(
        RelOptPlanner planner,
        RelNode rel,
        Distribution toTrait,
        boolean allowInfiniteCostConverters
    ) {
        Distribution fromTrait = 
          rel.getTraitSet().getTrait(DistributionTraitDef.INSTANCE);

        if (fromTrait.satisfies(toTrait)) {
            return rel;
        }

        return new ExchangeRel(
            rel.getCluster(),
            rel.getTraitSet().plus(toTrait),
            rel
        );
    }

    @Override
    public boolean canConvert(
        RelOptPlanner planner,
        Distribution fromTrait,
        Distribution toTrait
    ) {
        return true;
    }

    @Override
    public Distribution getDefault() {
        return Distribution.ANY;
    }
}
```

> You would likely have more distribution types, dedicated distribution columns, and different exchange types in production implementations. You may refer to Apache Flink as an example of a real [distribution trait](https://github.com/apache/flink/blob/release-1.12/flink-table/flink-table-planner-blink/src/main/scala/org/apache/flink/table/planner/plan/trait/FlinkRelDistribution.scala#L63).

在生产实现中，您可能会有更多的分布类型、专用的分布列以及不同的交换类型。可以将 Apache Flink 作为真实  [distribution trait](https://github.com/apache/flink/blob/release-1.12/flink-table/flink-table-planner-blink/src/main/scala/org/apache/flink/table/planner/plan/trait/FlinkRelDistribution.scala#L63) 的示例。

### Putting It All Together

> Let's see the new trait in action. The complete source code is available [here](https://github.com/querifylabs/querifylabs-blog/tree/main/02-custom-calcite-trait).
>
> First, we create a schema with a couple of tables - one with `PARTITIONED` distribution and another with `SINGLETON` distribution. We use custom table and schema implementation, similar to the ones we used in the previous [blog post](https://www.querifylabs.com/blog/assembling-a-query-optimizer-with-apache-calcite).

让我们看看新 **trait** 的作用。完整的源代码[这里](https://github.com/querifylabs/querifylabs-blog/tree/main/02-custom-calcite-trait)。

首先，我们创建一个包含几个表的模式——一个表使用 `PARTITIONED` 分布，另一个表使用 `SINGLETON` 分布。我们使用自定义表和 schema，类似于我们在上一篇[博客文章](https://www.querifylabs.com/blog/assembling-a-query-optimizer-with-apache-calcite)中使用的实现。

```java
// Table with PARTITIONED distribution.
Table table1 = Table.newBuilder("table1", Distribution.PARTITIONED)
  .addField("field", SqlTypeName.DECIMAL).build();

// Table with SINGLETON distribution.
Table table2 = Table.newBuilder("table2", Distribution.SINGLETON)
  .addField("field", SqlTypeName.DECIMAL).build();

Schema schema = Schema.newBuilder("schema").addTable(table1).addTable(table2).build();
```

> Then we create a planner instance and register our custom trait definition in it.

然后我们创建一个 planner 实例，并在其中注册我们自定义的 **trait definition** 。

```java
VolcanoPlanner planner = new VolcanoPlanner();

planner.addRelTraitDef(ConventionTraitDef.INSTANCE);
planner.addRelTraitDef(DistributionTraitDef.INSTANCE);
```

> Finally, we create a table scan operator for each of our tables and enforce the `SINGLETON` distribution. Notice that we use the aforementioned `ExpandConversionRule` in our optimization program. Otherwise, the enforcement will not work.

最后，为每个表创建一个表扫描运算符，并强制执行 `SINGLETON` 分布。注意，我们在优化器中使用了前面提到的 `ExpandConversionRule`。 否则，强制执行不起作用。

```java
// Use the built-in rule that will expand abstract converters.
RuleSet rules = RuleSets.ofList(AbstractConverter.ExpandConversionRule.INSTANCE);

// Prepare the desired traits with the SINGLETON distribution.
RelTraitSet desiredTraits = node.getTraitSet().plus(Distribution.SINGLETON);
        
// Use the planner to enforce the desired traits
RelNode optimizedNode = Programs.of(rules).run(
    planner,
    node,
    desiredTraits,
    Collections.emptyList(),
    Collections.emptyList()
);
```

> Now we run the [TraitTest](https://github.com/querifylabs/querifylabs-blog/commit/1bb7d1c8942e7df00916d20de0e51f2a1965ac23#diff-5c30c410d3e7db69b7b8375de2802b3c04f94799dc4b30239fba532001d8eea4) from the sample project to see this in action. For the `PARTITIONED` table, the planner has added the `ExchangeRel` to enforce the `SINGLETON` distribution.

现在我们运行示例项目中的 [TraitTest](https://github.com/querifylabs/querifylabs-blog/commit/1bb7d1c8942e7df00916d20de0e51f2a1965ac23#diff-5c30c410d3e7db69b7b8375de2802b3c04f94799dc4b30239fba532001d8eea4) 以查看其实际效果。 对于`PARTITIONED` 表，规划器添加了`ExchangeRel` 来强制执行`SINGLETON` 分布。

```
BEFORE:
2:LogicalTableScan(table=[[schema, partitioned]])

AFTER:
7:ExchangeRel
  2:LogicalTableScan(table=[[schema, partitioned]])
```

> But the table with the `SINGLETON` distribution remains unchanged because it already has the desired distribution.

但是具有 `SINGLETON` 分布的表保持不变，因为它已经具有所需的分布。

```
BEFORE:
0:LogicalTableScan(table=[[schema, singleton]])

AFTER:
0:LogicalTableScan(table=[[schema, singleton]])
```

> Congratulations! Our custom property is ready.

恭喜！ 我们的自定义属性已准备就绪。

## Summary

> Physical properties are an important concept in query optimization that allows you to explore more alternative plans.
>
> In this blog post, we demonstrated how to define the custom physical property in Apache Calcite. We created a custom `RelTraitDef` and `RelTrait` classes, registered them in the planner, and used the custom operator to enforce the desired value of the property.
>
> However, we omitted one crucial question - how to **propagate** properties between operators? It turns out, Apache Calcite cannot do this well, and you will have to make a tough decision choosing between several non-ideal solutions. We will discuss property propagation in detail in future posts. Stay tuned!
>
> We are always ready to help you with your SQL query optimizer design. Just [let us know](https://www.querifylabs.com/#contact-form).

物理属性是查询优化中的一个重要概念，它允许您探索更多的备选计划。在这篇博文中，我们演示了如何在 Apache Calcite 中定义自定义物理属性。 我们创建了一个自定义的 `RelTraitDef` 和 `RelTrait` 类，在优化器中注册它们，并使用自定义运算符来强制执行所需的属性值。

然而，我们忽略了一个关键问题 —— 如何在运算符之间**传播**属性？事实证明，Apache Calcite 不能很好地做到这一点，您将不得不在几个非理想的解决方案之间做出艰难的决定。我们将在以后的文章中详细讨论属性传播。 敬请关注！

我们随时准备帮助您进行 SQL 查询优化器设计。 只需[让我们知道](https://www.querifylabs.com/#contact-form)。

# Inside Presto Optimizer

> **Abstract** Presto is an open-source distributed SQL query engine for big data. Presto provides a connector API to interact with different data sources, including RDBMSs, NoSQL products, Hadoop, and stream processing systems. Created by Facebook, Presto received wide adoption by the open-source world ([Presto](https://github.com/prestodb), [Trino](https://github.com/trinodb)) and commercial companies (e.g., [Ahana](https://ahana.io/), [Qubole](https://www.qubole.com/)).
>
> Presto comes with a sophisticated query optimizer that applies various rewrites to the query plan. In this blog post series, we investigate the internals of Presto optimizer. In the first part, we discuss the optimizer interface and the design of the rule-based optimizer.
>
> Please refer to the [original paper](https://research.fb.com/publications/presto-sql-on-everything/) by Facebook to get a better understanding of Presto's capabilities and design.
>
> We will use the Presto Foundation fork [version 0.245](https://github.com/prestodb/presto/tree/release-0.245) for this blog post.

**摘要** Presto 是一个开源的大数据分布式 SQL 查询引擎。 Presto 提供了一个连接器 API 来与不同的数据源交互，包括 RDBMS、NoSQL 产品、Hadoop 和流处理系统。 Presto 由 Facebook 创建，被开源世界（[Presto](https://github.com/prestodb)、[Trino](https://github.com/trinodb)）和商业公司广泛采用（[Ahana](https://ahana.io/)、[Qubole](https://www.qubole.com/))。

Presto 带有一个复杂的查询优化器，可以将各种重写应用于查询计划。在本博文系列中，我们研究了 Presto 优化器的内部结构。在第一部分，我们讨论优化器接口和基于规则的优化器的设计。

请参阅 Facebook 的[原始论文](https://research.fb.com/publications/presto-sql-on-everything/) 以更好地了解 Presto 的功能和设计。我们将在这篇博文中使用 Presto 基金会版本 [0.245](https://github.com/prestodb/presto/tree/release-0.245)

## Relational Tree

Presto optimizer works with relational operators. Similarly to other SQL optimizers, such as [Apache Calcite](https://www.querifylabs.com/blog/assembling-a-query-optimizer-with-apache-calcite), Presto performs syntax and semantic analysis of the original SQL string and then produces the logical relational tree:

1. The ANTLR-based [parser](https://github.com/prestodb/presto/blob/release-0.245/presto-parser/src/main/antlr4/com/facebook/presto/sql/parser/SqlBase.g4) converts the original query string into an abstract syntax tree (AST)
2. The [analyzer](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/analyzer/Analyzer.java#L77) performs the semantic validation of the AST.
3. The [converter](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/RelationPlanner.java) creates the logical relational tree from the AST.

Every node in the tree represents a relational operation and implements a common [PlanNode](https://github.com/prestodb/presto/blob/release-0.245/presto-spi/src/main/java/com/facebook/presto/spi/plan/PlanNode.java) interface, which exposes a unique node's ID, node's inputs, and node's output. The interface also allows traversing the tree with a visitor pattern, used extensively during the optimization. Examples of relational operations: [TableScanNode](https://github.com/prestodb/presto/blob/release-0.245/presto-spi/src/main/java/com/facebook/presto/spi/plan/TableScanNode.java), [ProjectNode](https://github.com/prestodb/presto/blob/release-0.245/presto-spi/src/main/java/com/facebook/presto/spi/plan/ProjectNode.java), [FilterNode](https://github.com/prestodb/presto/blob/release-0.245/presto-spi/src/main/java/com/facebook/presto/spi/plan/FilterNode.java), [AggregationNode](https://github.com/prestodb/presto/blob/release-0.245/presto-spi/src/main/java/com/facebook/presto/spi/plan/AggregationNode.java), [JoinNode.](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/plan/JoinNode.java)

Consider the following query:

```SQL
SELECT 
    orderstatus, 
    SUM(totalprice) 
FROM orders 
GROUP BY orderstatus
```

The associated query plan might look like this:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/607d33d2b04e03f8aad679dd_plan-example.png)

## Optimizer Interface

When the logical plan is ready, we can start applying optimizations to it. In Presto, there is the general [PlanOptimizer](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/optimizations/PlanOptimizer.java) interface that every optimization phase implements. The interface accepts one relational tree and produces another.

```Java
public interface PlanOptimizer
{
    PlanNode optimize(
        PlanNode plan,
        Session session,
        TypeProvider types,
        PlanVariableAllocator variableAllocator,
        PlanNodeIdAllocator idAllocator,
        WarningCollector warningCollector
    );
}
```

The optimization program builder [PlanOptimizers](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/PlanOptimizers.java#L212) creates a list of optimizers that are invoked sequentially on the relational tree. Optimization problems often split into several phases to keep logical and computational complexity under control. In Presto, there are more than 70 optimization phases that every relational tree will pass through.

The majority of optimization phases use the rule-based optimizer that we will discuss further. Other phases rely on custom optimizers that make no use rules but apply a custom transformation logic. For example, the [PredicatePushDown](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/optimizations/PredicatePushDown.java) optimizer moves filters down in the relational tree, and [PruneUnreferencedOutputs](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/optimizations/PruneUnreferencedOutputs.java) removes unused fields that could be generated during the AST conversion or the previous optimization phases. We will discuss the most important custom optimizers in the second part of this blog post series.

Presto may also [reoptimize](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/PlanOptimizers.java#L620) the query plan in runtime. The details of this process are out of the scope of this blog post.

## Rule-Based Optimizer

Presto uses the rule-based [IterativeOptimizer](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java) for the majority of optimization phases. In rule-based optimization, you provide the relational tree and a set of pluggable optimization rules. A **rule** is a self-contained code that defines the relational tree **pattern** it should be applied to and the **transformation** logic. The optimizer then applies the rules to the relational tree using some algorithm. The main advantage of rule-based optimizers is **extensibility**. Instead of having a monolithic optimization algorithm, you split the optimizer into smaller self-contained rules. To extend the optimizer, you create a new rule that doesn't affect the rest of the optimizer code. Please refer to our [blog post](https://www.querifylabs.com/blog/rule-based-query-optimization) to get more details about rule-based optimization.

Rule-based optimizers could be either cost-based or heuristic. In [cost-based optimizers](https://www.querifylabs.com/blog/what-is-cost-based-optimization), a particular transformation is chosen based on the estimated cost assigned to a plan. Heuristic optimizers don't use costs and could produce arbitrary bad plans in the worst case. Presto relies on a rule-based **heuristic** optimization, although some specific rules use costs internally to pick a single transformation from multiple alternatives. An example is the [ReorderJoins](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/rule/ReorderJoins.java#L102) rule that selects a single join order with the least cost from multiple alternatives.

We now describe the most important parts of the Presto rule-based optimizer: the `Memo` class, rule matching, and the search algorithm.

### MEMO

> MEMO is a data structure used primarily in cost-based optimizers to encode multiple alternative plans efficiently. The main advantage of MEMO is that multiple alternative plans could be encoded in a very compact form. We discuss the design of MEMO in one of our [blog posts](https://www.querifylabs.com/blog/memoization-in-cost-based-optimizers).
>
> Presto also uses a MEMO-like data structure. There is the [Memo](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Memo.java) class that stores groups. The optimizer [initializes](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L89) the `Memo`, which populates groups via a recursive traversal of the relational tree. However, every group in `Memo` may have only [one operator](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Memo.java#L254). That is, Presto doesn't store multiple equivalent operators in a group. Instead, as we will see below, Presto unconditionally replaces the current operator with the transformed operator. Therefore, the `Memo` class in Presto is not a MEMO data structure in a classical sense because it doesn't track equivalent operators. In Presto, you may think of the group as a convenient wrapper over an operator, used mostly to track operators' reachability during the optimization process.

MEMO 是一种数据结构，主要用于基于成本的优化器，以有效地编码多个替代计划。 MEMO 的主要优点是以非常紧凑的形式对多个备选计划进行编码。 我们在其中一篇 [博客文章](https://www.querifylabs.com/blog/memoization-in-cost-based-optimizers) 中讨论了 MEMO 的设计。

Presto 还使用类似 MEMO 的数据结构。有一个存储**组**的 [`Memo`](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Memo.java) 类。优化器[初始化](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L89) `Memo`，它通过关系树的递归遍历填充**组**。但是，`Memo` 中的每个组可能只有一个 [运算符](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Memo.java#L254)。也就是说，Presto 不会在一个组中存储多个等价的运算符。相反，正如我们将在下面看到的，Presto 无条件地用转换后的**运算符**替换当前**运算符**。因此，Presto 中的`Memo` 类不是经典意义上的 MEMO 数据结构，因为它不跟踪等价操作符。在 Presto 中，您可能会将**组**视为**运算符**的方便包装器，主要用于在优化过程中跟踪运算符的==可达性==。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/607d35a463c67eb5fef29ffd_memo.png)

### Rule Matching

To optimize the relational tree, you should provide the optimizer with one or more rules. Every rule in Presto implements the [Rule](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Rule.java) interface.

First, the interface defines the [pattern](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Rule.java#L35), which may target an arbitrary part of the tree. It could be a single operator (filter in the [PruneFilterColumns](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/rule/PruneFilterColumns.java#L37) rule), multiple operators (filter on top of the filter in the [MergeFilters](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/rule/MergeFilters.java#L34) rule), an operator with a predicate (join pattern in the [ReorderJoins](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/rule/ReorderJoins.java#L114) rule), or anything else.

Second, the interface defines the [transformation logic](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Rule.java#L42). The result of the transformation could be either a new operator that replaces the previous one or no-op if the rule failed to apply the transformation for whatever reason.

### Search Algorithm

Now, as we understand the Presto rule-based optimizer's core concepts, let's take a look at the search algorithm.

1. The `Memo` class is [initialized](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L89) with the original relational tree, as we discussed above.
2. For every `Memo` group, starting with the root, the method [exploreGroup ](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L102)is invoked. We look for rules that [match](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L133) the current operator and fire them. If a rule produces an alternative operator, it [replaces](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L144) the original operator unconditionally. The process continues until there are no more available transformations for the current operator. Then we optimize operators' inputs. If an alternative input is found, it may open up more optimizations for the parent operator, so we [reoptimize](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L108) the parent. Presto relies on timeouts to terminate the optimization process if some rules continuously replace each other's results. Think of `b JOIN a`, that replaces `a JOIN b`, that replaces `b JOIN a`, etc. You may run the [TestIterativeOptimizer](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/test/java/com/facebook/presto/sql/planner/iterative/TestIterativeOptimizer.java) test to see this behavior in action.
3. In the end, we [extract](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/IterativeOptimizer.java#L99) the final plan from `Memo`.

This is it. The search algorithm is very simple and straightforward.

The main drawback is that the optimizer is heuristic and cannot consider multiple alternative plans concurrently. That is, at every point in time, Presto has only one plan that it may transform further. In the [original paper](https://research.fb.com/publications/presto-sql-on-everything/) from 2019, Facebook engineers mentioned that they explore an option to add a cost-based optimizer:

> We are in the process of enhancing the optimizer to perform a more comprehensive exploration of the search space using a cost-based evaluation of plans based on the techniques introduced by the Cascades framework.

There is also a [document](https://github.com/prestodb/presto/wiki/New-Optimizer) dated back to 2017 with some design ideas around cost-based optimization.

## Summary

> In this blog post, we explored the design of the Presto optimizer. The optimization process is split into multiple sequential phases. Every phase accepts a relational tree and produces another relational tree. Most phases use a rule-based heuristic optimizer, while some rules rely on custom logic without rules. There were some thoughts to add the cost-based optimizer to Presto, but it hasn't happened yet.
>
> In the second part of this series, ==we will explore the <u>concrete optimization rules</u> and <u>custom phases of Presto's query optimization</u>==. Stay tuned!

在这篇博文中，我们探讨了 Presto 优化器的设计。 优化过程分为多个连续阶段。 每个阶段都接受一个关系树并生成另一个关系树。 大多数阶段使用基于规则的启发式优化器，而一些规则依赖于没有规则的自定义逻辑。曾经有想法将基于成本的优化器添加到 Presto，但仍未实现。

在本系列的第二部分，==我们将探讨<u>具体的优化规则</u>和 Presto <u>查询优化的自定义阶段</u>==。 敬请关注！

# Rule-based Query Optimization

The goal of the query optimizer is to find the query execution plan that computes the requested result efficiently. In this blog post, we discuss rule-based optimization - a common pattern to explore equivalent plans used by modern optimizers. Then we explore the implementation of several state-of-the-art rule-based optimizers. Then we analyze the rule-based optimization in Apache Calcite, Presto, and CockroachDB.

## Transformations

A query optimizer must explore the space equivalent execution plans and pick the optimal one. Intuitively, plan B is **equivalent** to plan A if it produces the same result for all possible inputs.

To generate the equivalent execution plans, we may apply one or more **transformations** to the original plan. A transformation accepts one plan and produces zero, one, or more equivalent plans. As a query engine developer, you may implement hundreds of different transformations to generate a sufficient number of equivalent plans.

Some transformations operate on bigger parts of the plan or even the whole plan. For example, an implementation of the join order selection with dynamic programming may enumerate all joins in the plan, generate alternative join sequences, and pick the best one.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60963ba5eb259ef7ebab78e4_blog04-dp.png)

Other transformations could be relatively isolated. Consider the transformation that pushes the filter operator past the aggregate operator. It works on an isolated part of the tree and doesn't require a global context.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60963bb7dc99fc0d65d4ebbf_blog04-filter-push.png)

## Rules

Every optimizer follows some algorithm that decides when to apply particular transformations and how to process the newly created equivalent plans. As the number of transformations grows, it becomes not very convenient to hold them in a monolithic routine. Imagine a large if-else block of code that decides how to apply a hundred transformations to several dozens of relational operators.

To facilitate your engine's evolution, you may want to abstract out some of your transformations behind a common interface. For every transformation, you may define a pattern that defines whether we can apply the transformation to the given part of the plan. A pair of pattern and transformation is called a **rule**.

The rule abstraction allows you to split the optimization logic into pluggable parts that evolve independently of each other, significantly simplifying the development of the optimizer. The optimizer that uses rules to generate the equivalent plans is called a **rule-based optimizer**.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60963bc8dc99fc4d98d4ec35_blog04-rules.png)

Notice that the rules are, first of all, a pattern that helps you decompose the optimizer's codebase. The usage of rules doesn't force you to follow a specific optimization procedure, such as Volcano/Cascades. It doesn't prevent you from using particular optimization techniques, like dynamic programming for join enumeration. It doesn't require you to choose between heuristic or cost-based approaches. However, the isolated nature of rules may complicate some parts of your engine, such as join planning.

## Examples

Now, as we understand the idea behind the rule-based optimization, let's look at several real-world examples: Apache Calcite, Presto, and CockroachDB.

### Apache Calcite

[Apache Calcite](https://calcite.apache.org/) is a dynamic data management framework. At its core, Apache Calcite has two rule-based optimizers and a library of transformation rules.

The [HepPlanner](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/hep/HepPlanner.java) is a heuristic optimizer that applies rules one by one until no more transformations are possible.

The [VolcanoPlanner](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/volcano/VolcanoPlanner.java) is a cost-based optimizer that generates multiple equivalent plans, put them into the MEMO data structure, and uses costs to choose the best one. The `VolcanoPlanner` may fire rules in an arbitrary order or work in a recently introduced Cascades-like [top-down](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/volcano/VolcanoPlanner.java#L256) style.

The [rule interface](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/RelOptRule.java#L41) accepts the pattern and requires you to implement the `onMatch(context)` method. This method doesn't return the new relational tree as one might expect. Instead, it returns `void` but provides the ability to register new transformations in the context, which allows you to emit multiple equivalent trees from a single rule call. Apache Calcite comes with an extensive [library](https://github.com/apache/calcite/tree/branch-1.24/core/src/main/java/org/apache/calcite/rel/rules) of built-in rules and allows you to add your own rules.

```Java
class CustomRule extends RelOptRule {
    new CustomRule() {
        super(pattern_for_the_rule);
    }
    
    void onMatch(RelOptRuleCall call) {
        RelNode equivalentNode = ...;
        
        // Register the new equivalent node in MEMO
        call.transformTo(equivalentNode);
    }
}
```

In Apache Calcite, you may define one or more optimization stages. Every stage may use its own set of rules and optimizer. Many products based on Apache Calcite use multiple stages to minimize the optimization time at the cost of the possibility of producing a not optimal plan. See our previous [blog post](https://www.querifylabs.com/blog/assembling-a-query-optimizer-with-apache-calcite) for more details on how to create a query optimizer with Apache Calcite.

Let's take a look at a couple of rules for join planning. To explore all bushy join trees, you may use [JoinCommuteRule](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/rel/rules/JoinCommuteRule.java) and [JoinAssociateRule](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/rel/rules/JoinAssociateRule.java). These rules are relatively simple and work on individual joins. The problem is that they may trigger duplicate derivations, as explained in this [paper](https://dl.acm.org/doi/10.14778/2732977.2732997).

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60963bdab571206fb3c6b90a_blog04-commute-associate.png)

Alternatively, Apache Calcite may use a set of rules that convert multiple joins into a single [n-way join](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/rel/rules/MultiJoin.java) and then apply a heuristic algorithm to produce a single optimized join order from the n-way join. This is an example of the rule, that works on a large part of the tree, rather than individual operators. You may use a similar approach to implement the rule to do the join planning with dynamic programming.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60963be3ec20c2754457d5d0_blog04-calcite-multijoin.png)

The Apache Calcite example demonstrates that the rule-based optimization could be used with both heuristic and cost-based exploration strategies, as well as for complex join planning.

### Presto

[Presto](https://prestodb.io/) is a distributed query engine for big data. Like Apache Calcite, it uses rules to perform transformations. However, Presto doesn't have a cost-based search algorithm and relies only on heuristics when transitioning between optimization steps. See our [previous blog](https://www.querifylabs.com/blog/the-architecture-of-presto-optimizer-part-1) for more details on Presto query optimizer.

As Presto cannot explore multiple equivalent plans at once, it has a simpler [rule interface](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Rule.java) that produces no more than one new equivalent tree.

```Java
interface Rule {
    Pattern getPattern();
    Result apply(T node, ...);
}
```

Presto also has several rules that use costs internally to explore multiple alternatives in a rule call scope. An example is a (relatively) recently introduced [ReorderJoins](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/rule/ReorderJoins.java#L93) rule. Similar to the above-mentioned Apache Calcite's n-way join rules, the `ReorderJoins` rule first converts a sequence of joins into a single n-way join. Then the rule enumerates equivalent joins orders and picks the one with the least cost (unlike Apache Calcite's [LoptOptimizerJoinRule](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/rel/rules/LoptOptimizeJoinRule.java), which uses heuristics).

The `ReorderJoins` rule is of particular interest because it demonstrates how we may use rule-based optimization to combine heuristic and cost-based search strategies in the same optimizer.

### CockroachDB

CockroachDB is a cloud-native SQL database for modern cloud applications. It has a rule-based Cascades-style query [optimizer](https://www.cockroachlabs.com/blog/building-cost-based-sql-optimizer/).

Unlike Apache Calcite and Presto, Cockroach doesn't have a common rule interface. Instead, it uses a custom DSL to define the rule's pattern and transformation logic. The code [generator](https://github.com/cockroachdb/cockroach/tree/release-20.2/pkg/sql/opt/optgen) analyzes the DSL files and produces a monolithic optimization routine. The code generation may allow for a faster optimizer's code because it avoids virtual calls when calling rules.

Below is an [example](https://github.com/cockroachdb/cockroach/blob/release-20.2/pkg/sql/opt/xform/rules/groupby.opt#L110) of a rule definition that attempts to generate a streaming aggregate. Notice that you do not need to write the whole rule logic using DSL only. Instead, you may reference utility methods written in Go (which is CockroachDB primary language) from within the rule to minimize the amount of DSL-specific code.

```
[GenerateStreamingGroupBy, Explore]
(GroupBy | DistinctOn | EnsureDistinctOn | UpsertDistinctOn
        | EnsureUpsertDistinctOn
    $input:*
    $aggs:*
    $private:* & (IsCanonicalGroupBy $private)
)
=>
(GenerateStreamingGroupBy (OpName) $input $aggs $private)
```

There are two rule types in CockroachDB. The [normalization rules](https://github.com/cockroachdb/cockroach/tree/release-20.2/pkg/sql/opt/norm/rules) convert relational operators into canonical forms before being inserted into a MEMO, simplifying the subsequent optimization. An example is a [NormalizeNestedAnds](https://github.com/cockroachdb/cockroach/blob/release-20.2/pkg/sql/opt/norm/rules/bool.opt#L6) rule that normalizes `AND` expressions into a left-deep tree. The normalization is performed via a sequential invocation of normalization rules. The second category is [exploration rules](https://github.com/cockroachdb/cockroach/tree/release-20.2/pkg/sql/opt/xform/rules), which generate multiple equivalent plans. The exploration rules are invoked using the cost-based Cascades-like top-down optimization strategy with memoization.

CockroachDB has a [ReorderJoins](https://github.com/cockroachdb/cockroach/blob/release-20.2/pkg/sql/opt/xform/rules/join.opt#L11) rule to do the join planning. The rule uses a variation of the dynamic programming algorithm described in this [paper](https://dl.acm.org/doi/10.1145/2463676.2465314) to enumerate the valid join orders and add them to MEMO.

Thus, CockroachDB uses rule-based optimization for heuristic normalization, cost-based exploration, and join planning with dynamic programming.

## Summary

Rule-based query optimization is a very flexible pattern that you may use when designing a query optimizer. It allows you to split the complicated transformation logic into self-contained parts, reducing the optimizer's complexity.

The rule-based optimization doesn't limit you in how exactly to optimize your plans, be it bottom-up dynamic programming or top-down Cascades-style exploration, cost-based or heuristic optimization, or anything else.

In future posts, we will discuss the difference between logical and physical optimization. Stay tuned!

# Memoization in Cost-based Optimizers

> ==Query optimization is an expensive process that needs to explore multiple alternative ways to execute the query==. The query optimization problem is [NP-hard](https://core.ac.uk/download/pdf/21271492.pdf), and the number of possible plans grows exponentially with the query's complexity. For example, a typical [TPC-H](http://www.tpc.org/tpch/) query may have up to several thousand possible join orders, 2-3 algorithms per join, a couple of access methods per table, some filter/aggregate pushdown alternatives, etc. Combined, this could quickly explode the search space to millions of alternative plans.
>
> This blog post will discuss **memoization** - an important technique that allows cost-based optimizers to consider billions of alternative plans in a reasonable time.

==查询优化需要探索**多种替代方法**来执行查询，过程昂贵==，是一个 [NP-hard](https://core.ac.uk/download/pdf/21271492.pdf) 问题，可能的计划数量随着查询的复杂性呈指数增长。例如，一个典型的 [TPC-H](http://www.tpc.org/tpch/) 查询可能有多达数千个的 `Join` 顺序，每个 `Join` 有 2-3 个算法，每个表有几个访问方法，以及还可以下推过滤器/聚合。结合起来，可能会迅速将搜索空间扩展到数百万个备选计划。

本文讨论 一种重要的技术 **memoization** ——允许**基于成本的优化器**在合理的时间内考虑数十亿个替代计划。

## The Naïve Approach

> Consider that we are designing a rule-based optimizer. We want to apply a rule to a relational operator tree and produce another tree. If we insert a new operator in the middle of the tree, we need to update the parent to point to the new operator. Once we've changed the parent, we may need to change the parent of the parent, etc. <u>If your operators are immutable by design or used by other parts of the program, you may need to copy large parts of the tree to create a new plan</u>.

假设我们正在设计一个基于规则的优化器。我们想将规则应用于关系运算符树，并生成另一棵树。如果我们在树的中间插入一个新的运算符，我们需要更新父级运算符以指向新的运算符。一旦我们改变了**父级**运算符，我们可能需要改变**父级**的**父级**。==如果你的运算符在设计上是不可变的，或者被程序的其他部分使用，可能需要复制树的大部分来创建一个 新计划==。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/6065b4d9ce4c7f60b6b80638_memo-01.png)

>  This approach is wasteful because you need to propagate changes to parents over and over again.

这种方法很浪费，因为您需要一遍又一遍地将更改传播给父级。

## Indirection

> We may solve the problem with change propagation by applying an additional layer of indirection. Let us introduce a new surrogate operator that will store a **reference** to a child operator. Before starting the optimization, we may traverse the initial relational tree and create copy of operators, where all concrete inputs are replaced with references.
>
> When applying a transformation, we may only change a reference without updating other parts of the tree. When the optimization is over, we remove the references and reconstruct the final tree.

我们可以通过应用额外的间接层来解决变更传播的问题。 我们引入一个新的代理运算符，它将存储对子运算符的**引用**。 在开始优化之前，我们可以遍历初始关系树并创建算子的副本，其中所有具体输入都被替换为引用。

应用转换时，我们可能只更改引用而不更新树的其他部分。 优化结束后，我们删除引用并重建最终树。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/6065b1551fda64a7d2555d8b_memo-02.png)

> You may find a similar design in many production-grade heuristic optimizers. In our previous [blog post](https://www.querifylabs.com/blog/the-architecture-of-presto-optimizer-part-1) about **Presto**, <u>==we discussed==</u> the [Memo](https://github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Memo.java) class that manages such references. In **Apache Calcite**, the heuristic optimizer [HepPlanner](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/hep/HepPlanner.java) models node references through the class [HepRelVertex](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/hep/HepRelVertex.java).
>
> We realized how references might help us minimize change propagation overhead. But in a cost-based optimization, we need to consider multiple alternative plans at the same time. We need to go deeper.
>

您可能会在许多生产级启发式优化器中找到类似的设计。在之前关于 **Presto** 的[博客文章](https://www.querifylabs.com/blog/the-architecture-of-presto-optimizer-part-1)中，<u>==我们讨论了==</u>管理这样引用的 [`Memo`](https: //github.com/prestodb/presto/blob/release-0.245/presto-main/src/main/java/com/facebook/presto/sql/planner/iterative/Memo.java) 类。在 **Apache Calcite** 中，启发式优化器 [`HepPlanner`](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/hep /HepPlanner.java) 通过类 [`HepRelVertex`](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/hep/HepRelVertex.java) 对节点引用建模。

我们认识到引用可以帮助我们<u>最小化变更传播</u>的开销。但在基于成本的优化器中，需要同时考虑多个备选方案，要深入研究。

## MEMO

> In cost-based optimization, we need to generate multiple equivalent operators, link them together, and find the cheapest path to the root.
>
> Two relational operators are **equivalent** if they generate the same result set on every legal database instance. How can we encode equivalent operators efficiently? Let's extend our references to point to multiple operators! We will refer to such a surrogate node as a **group**, which is a collection of equivalent operators.
>
> We start the optimization by creating equivalence groups for existing operators and replacing concrete inputs with relevant groups. At this point, the process is similar to our previous approach with references.
>
> When a rule is applied to operator **A**, and a new equivalent operator **B** is produced, we add **B** to **A**'s equivalence group. The collection of groups that we consider during optimization is called **MEMO**. The process of maintaining a MEMO is called **memoization**.

在基于成本的优化中，我们需要生成多个等效的算子，将它们链接在一起，并找到最便宜的根路径。

如果两个关系运算符在每个合法数据库实例上生成相同的结果集，则它们是**等价的**。我们如何有效地编码等价运算符？将引用扩展为指向多个运算符！我们将这样的代理节点称为 **group**，它是等价运算符的集合。

我们通过为现有算子创建等价组并用相关组替换具体输入来开始优化。在这一点上，该过程类似于我们之前的引用方法。

当规则应用于算子**A**，并产生一个新的等价算子**B**时，我们将**B**添加到**A**的等价群。 我们在优化过程中考虑的组集合称为 **MEMO**。 维护 MEMO 的过程称为 **memoization**。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/6065be2f874bac04397aca27_memo-03.png)

> MEMO is a variation of the [AND/OR graph](https://anilshanbhag.in/static/papers/rsgraph_vldb14.pdf). Operators are AND-nodes representing the subgoals of the query (e.g., applying a filter). Groups are OR-nodes, representing the alternative subgoals that could be used to achieve the parent goal (e.g., do a table scan or an index scan).
>
> When <u>==all interesting operators==</u> are generated, the MEMO is said to be explored. We now need to extract the **cheapest plan** from it, which is the ultimate goal of cost-based optimization. To do this, we first assign costs to individual operators via the cost function. Then we traverse the graph bottom-up and select the cheapest operator from each group (often referred to as "winner"), combining costs of individual operators with costs of their inputs.
>
> Practical optimizers often maintain groups' winners up-to-date during the optimization to allow for search space **pruning**, which we will discuss in future blog posts.

MEMO是[AND/OR图](https://anilshanbhag.in/static/papers/rsgraph_vldb14.pdf)的变体。运算符表示查询子节点的 `AND` 节点（例如，过滤器）。组是 OR 节点，代表可用于实现父节点的替代子节点（例如，进行表扫描或索引扫描）。

当所有<u>==感兴趣的运算符==</u>都生成后，就表示对 MEMO 进行了探索。我们现在需要从中提取**成本最优的计划**，这是基于成本的优化的最终目标。为此，我们首先通过代价函数将代价分配给各个操作符。然后，我们自底向上遍历图表，并从每组中选择最优的运算符(通常称为**赢家**)，将单个操作符的成本与它们的输入成本结合起来。

通常，优化器在优化过程中**总是**保持组的==最新获胜者==，以便**修剪**搜索空间，我们将在以后的博客文章中讨论。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/6065ce8aa449b40540d1253a_memo-04.png)

> When the root group's cheapest operator is resolved, we construct the final plan through a top-down traverse across every group's cheapest operators.

当 root group 成本最低的运算符被解析时，我们通过**自顶向下**遍历每个组成本最低的运算符来构造最终的执行计划。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/6065ce9ae0bc9c1de43ee87c_memo-05.png)

> Memoization is very efficient because it allows for the **deduplication** of nodes, eliminating unnecessary work. Consider a query that has five joins. The total number of unique join orders for such a query is 30240. If we decide to create a new plan for every join order, we would need to instantiate 30240 * 5 = 151200 join operators. With memoization, you only need 602 join operators to encode the same search space - a dramatic improvement!
>
> The memoization idea is simple. Practical implementations of MEMO are much more involved. You need to design operator equivalence carefully, decide how to do the deduplication, manage the operator's physical properties (such as sort order), track already executed optimization rules, etc. We will cover some of these topics in future blog posts.

Memoization 非常有效，它允许节点**删除重复数据**，从而消除不必要的工作。考虑一个有五个连接的查询。 此类查询的唯一的连接顺序总数为 30240。如果我们决定为每个连接顺序创建一个新计划，我们将需要实例化 `30240 * 5 = 151200` 个连接运算符。 通过 Memoization，只需要 602 个**连接运算符**，即可对相同的搜索空间进行编码 - 一个巨大的改进！

Memoization 的想法很简单。MEMO 的实际实现要复杂得多。您需要仔细设计运算符的等价性，决定如何进行重复数据删除，管理运算符的物理属性（例如排序顺序），跟踪已使用的优化规则等。我们将在以后的博客文章中介绍其中的一些主题。

## Summary

> Memoization is an efficient technique that allows you to encode the large search space in a very compact form and eliminate duplicate work. MEMO data structure routinely backs modern cost-based rule-based optimizers.
>
> In future posts, we will discuss the design of MEMO in practical cost-based optimizers. Stay tuned!

Memoization 是一种有效的技术，它允许您以非常紧凑的形式对较大的搜索空间进行编码，并消除重复工作。MEMO 数据结构通常支持现代基于成本的规则优化器。

在以后的文章中，我们将讨论实用的基于成本的优化器中的 MEMO 设计。敬请期待！

# What is Cost-based Optimization?

In our previous blog posts ([1](https://www.querifylabs.com/blog/rule-based-query-optimization), [2](https://www.querifylabs.com/blog/memoization-in-cost-based-optimizers)), we explored how query optimizers may consider different equivalent plans to find the best execution path. But what does it mean for the plan to be the "best" in the first place? In this blog post, we will discuss what a plan cost is and how it can be used to drive optimizer decisions.

## Example

Consider the following query:

```SQL
SELECT * FROM fact 
WHERE event_date BETWEEN ? AND ?
```

We may do the full table scan and then apply the filter. Alternatively, we may utilize a secondary index on the attribute `event_date`, merging the scan and the filter into a single index lookup. This sounds like a good idea because we reduce the amount of data that needs to be processed.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/607a85e7fe7bfa2c106c7233_index-is-better.png)

We may instruct the optimizer to apply such transformations unconditionally, based on the observation that the index lookup is likely to improve the plan's quality. This is an example of **heuristic** optimization.

Now consider that our filter has low selectivity. In this case, we may scan the same blocks of data several times, thus increasing the execution time.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/607a85f17332606a7a737099_index-is-worse.png)

In practice, rules that unanimously produce better plans are rare. A transformation may be useful in one set of circumstances and lead to a worse plan in another. For this reason, heuristic planning cannot guarantee optimality and may produce arbitrarily bad plans.

## Cost

In the previous example, we have two alternative plans, each suitable for a particular setting. Additionally, in some scenarios, the optimization target may change. For example, a plan that gives the smallest latency might not be the best if our goal is to minimize the hardware usage costs in the cloud. So how do we decide which plan is better?

First of all, we should define the optimization goal, which could be minimal latency, maximal throughput, etc. Then we may associate every plan with a value that describes how "far" the plan is from the ideal target. For example, if the optimization goal is latency, we may assign every plan with an estimated execution time. The closer the plan's cost to zero, the better.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/607aaba3f9f15f9bdabfdafd_cost-distance.png)

The underlying hardware and software are often complicated, so we rarely can estimate the optimization target precisely. Instead, we may use a collection of assumptions that approximate the behavior of the actual system. We call it the **cost model**. The cost model is usually based on parameters of the algorithms used in a plan, such as the estimated amount of consumed CPU and RAM, the amount of network and disk I/O, etc. We also need data statistics: operator cardinalities, filter selectivities, etc. The goal of the model is to consider these characteristics to produce a cost of the plan. For example, we may use coefficients to combine the parameters in different ways depending on the optimization goal.

The cost of the `Filter` might be a function of the input cardinality and predicate complexity. The cost of the `NestedLoopJoin` might be proportional to the estimated number of restarts of the inner input. The `HashJoin` cost might have a linear dependency on the inputs cardinalities and also model spilling to disk with some pessimistic coefficients if the size of the hash table becomes too large to fit into RAM.

In practical systems, the cost is usually implemented as a scalar value:

1. In **Apache Calcite**, the cost is modeled as a [scalar](https://github.com/apache/calcite/blob/branch-1.24/core/src/main/java/org/apache/calcite/plan/RelOptCostImpl.java#L42) representing the number of rows being processed.
2. In **Catalyst**, the Apache Spark optimizer, the cost is a [vector](https://github.com/apache/spark/blob/branch-3.1/sql/catalyst/src/main/scala/org/apache/spark/sql/catalyst/optimizer/CostBasedJoinReorder.scala#L384) of the number of rows and the number of bytes being processed. The vector is converted into a [scalar](https://github.com/apache/spark/blob/branch-3.1/sql/catalyst/src/main/scala/org/apache/spark/sql/catalyst/optimizer/CostBasedJoinReorder.scala#L372) value during comparison.
3. In **Presto/Trino**, the cost is a [vector](https://github.com/trinodb/trino/blob/355/core/trino-main/src/main/java/io/trino/cost/PlanCostEstimate.java#L34-L37) of estimated CPU, memory, and network usage. The vector is also converted into a [scalar](https://github.com/trinodb/trino/blob/355/core/trino-main/src/main/java/io/trino/cost/CostComparator.java#L64-L72) value during comparison.
4. In **CockroachDB**, the cost is an abstract 64-bit floating-point [scalar](https://github.com/cockroachdb/cockroach/blob/v20.2.7/pkg/sql/opt/memo/cost.go#L18) value.

The scalar is a common choice for practical systems, but this is not a strict requirement. Any representation could be used, as long as it satisfies the requirements of your system and allows you to decide which plan is better. In [multi-objective optimization](https://en.wikipedia.org/wiki/Multi-objective_optimization), costs are often represented as vectors that do not have a strict order in the general case. In parallel query planning, a parallel plan requiring a larger amount of work can provide better latency than a sequential plan that does less work.

## Cost-based Optimization

Once we know how to compare the plans, different strategies can be used to search for the best one. A common approach is to enumerate all possible plans for a query and choose a plan with the lowest cost.

Since the number of possible query plans grows exponentially with the query complexity, [dynamic programming](https://en.wikipedia.org/wiki/Dynamic_programming) or [memoization](https://www.querifylabs.com/blog/memoization-in-cost-based-optimizers) could be used to encode alternative plans in a memory-efficient way.

If the search space is still too large, we may prune the search space. In top-down optimizers, we may use the [branch-and-bound](https://en.wikipedia.org/wiki/Branch_and_bound) pruning to discard the alternative sub-plans if their costs are greater than the cost of an already known containing plan.

Heuristic pruning may reduce the search space at the cost of the possibility of missing the optimal plan. Common examples of heuristic pruning are:

1. Probabilistic join order enumeration may reduce the number of alternative plans (e.g., [genetic algorithms](https://en.wikipedia.org/wiki/Genetic_algorithm), [simulated annealing](https://en.wikipedia.org/wiki/Simulated_annealing)). Postgres uses the [genetic query optimizer](https://www.postgresql.org/docs/13/geqo-pg-intro.html).
2. The multi-phase optimizers split the whole optimization problem into smaller stages and search for an optimal plan locally within each step. Apache Flink, Presto/Trino, and CockroachDB all use multi-phase greedy optimization.

## Summary

The cost-based optimization estimates the quality of the plans concerning the optimization target, allowing an optimizer to choose the best execution plan. The cost model depends heavily on metadata maintained by the database, such as estimated cardinalities and selectivities.

Practical optimizers typically use ordered scalar values as a plan cost. This approach might not be suitable for some complex scenarios, such as the multi-objective query optimization or deciding on the best parallel plan.

Dynamic programming or memoization is often used in cost-based optimization to encode the search space efficiently. If the search space is too large, various pruning techniques could be used, such as branch-and-bound or heuristic pruning.

In future blog posts, we will explore some of these concepts in more detail. Stay tuned!

# Introduction to the Join Ordering Problem

A typical database may execute an SQL query in multiple ways, depending on the selected operators' order and algorithms. One crucial decision is the order in which the optimizer should join relations. The difference between optimal and non-optimal join order might be orders of magnitude. Therefore, the optimizer must choose the proper order of joins to ensure good overall performance. In this blog post, we define the join ordering problem and estimate the complexity of join planning.

## Example

Consider the [TPC-H](https://docs.snowflake.com/en/user-guide/sample-data-tpch.html#database-entities-relationships-and-characteristics) schema. The `customer` may have `orders`. Every order may have several positions defined in the `lineitem` table. The `customer` table has 150,000 records, the `orders` table has 1,500,000 records, and the `lineitem` table has 6,000,000 records. Intuitively, every customer places approximately ten orders, and every order contains four positions on average.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608d5a01332e56b1db26b8ce_example-schema.png)

Suppose that we want to retrieve all `lineitem` positions for all `orders` placed by the given `customer`:

```SQL
SELECT 
  lineitem.*
FROM 
  customer,
  orders,
  lineitem
WHERE
  c_custkey = ? 
  AND c_custkey = o_custkey
  AND o_orderkey = l_orderkey
```

Assume that we have a[ cost model](https://www.querifylabs.com/blog/what-is-cost-based-optimization) where an operator's cost is proportional to the number of processed tuples.

We consider two different join orders. We can join `customer` with `orders` and then with `lineitem`. This join order is very efficient because most customers are filtered early, and we have a tiny intermediate relation.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e53ad9b9ce03c18c69ac1_example-plan-1.png)

Alternatively, we can join `orders` with `lineitem` and then with `customer`. It produces a large intermediate relation because we map every `lineitem` to an `order` only to discard most of the produced tuples in the second join.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e53d5dc8f7c54784cc3d9_example-plan-2.png)

The two join orders produce plans with very different costs. The first join strategy is highly superior to the second.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e541346f3a77e929780b3_example-plans.png)

## Search Space

> A perfect optimizer would need to construct all possible equivalent plans for a given query and choose the best plan. Let's now see how many options the optimizer would need to consider.
>
> We model an n-way join as a sequence of `n-1` 2-way joins that form a full binary tree. Leaf nodes are original relations, and internal nodes are join relations. For 3 relations there are 12 valid join orders:
>
> ![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e6542c9c9012fc37fe2d9_join-graph-order.png)
>
> We count the number of possible join orders for `N` relations in two steps. First, we count the number of different orders of leaf nodes. For the first leaf, we choose one of `N` relations; for the second leaf, we choose one of remaining `N-1` relations, etc. This gives us `N!` different orders.
>
> ![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e675a6cbcc0cba198a7ab_join-leaf-order.png)
>
> Second, we need to calculate the number of all possible shapes of a full binary tree with `N` leaves, which is the number of ways of associating `*N-1*` applications of a binary operator. This number is known to be equal to [Catalan number](https://en.wikipedia.org/wiki/Catalan_number) `C(N-1)`. Intuitively, for the given fixed order of `N` leaf nodes, we need to find the number of ways to set `N-1` pairs of open and close parenthesis. E.g., for the four relations `[a,b,c,d]`, we have five different parenthesizations:
>
> ![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e6b4c89997418f3adb378_join-catalan.png)
>
> Multiplying the two parts, we get the final equation:
>
> ![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/609244fc97f5f05ecf8c08f8_join_equation.gif)

完美的优化器需要为给定查询构建所有可能的等价计划，并选择最佳计划。那么，优化器需要考虑多少选项呢？

我们将 n 路 Join 建模为由 `n-1` 个 2 路 Join 组成的完整二叉树序列。叶节点是原始的表，内部节点是 Join。对于 3 张表，有 12 个有效的 Join 顺序:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e6542c9c9012fc37fe2d9_join-graph-order.png)

我们分两步计算 `N` 张表的 Join 数量。 首先，我们统计叶子节点之间的排列。 对于第一片叶子，我们从 `N` 张表中选择一张表； 对于第二片叶子，我们从剩余的 `N-1` 表选择一张表，以此类推，不同的排列有  `N!`  种。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e675a6cbcc0cba198a7ab_join-leaf-order.png)

Second, we need to calculate the number of all possible shapes of a full binary tree with `N` leaves, which is the number of ways of associating `*N-1*` applications of a binary operator. This number is known to be equal to [Catalan number](https://en.wikipedia.org/wiki/Catalan_number) `C(N-1)`. Intuitively, for the given fixed order of `N` leaf nodes, we need to find the number of ways to set `N-1` pairs of open and close parenthesis. E.g., for the four relations `[a,b,c,d]`, we have five different parenthesizations:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/608e6b4c89997418f3adb378_join-catalan.png)

Multiplying the two parts, we get the final equation:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/609244fc97f5f05ecf8c08f8_join_equation.gif)

## Performance

The number of join orders grows exponentially. For example, for three tables, the number of all possible join plans is `12`; for five tables, it is `1,680`; for ten tables, it is `17,643,225,600`. Practical optimizers use different techniques to ensure the good enough performance of the join enumeration.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/6092494d20b58973a88c6454_chart%20(1).png)

First, optimizers might use caching to minimize memory consumption. Two widely used techniques are [dynamic programming](https://en.wikipedia.org/wiki/Dynamic_programming) and [memoization](https://www.querifylabs.com/blog/memoization-in-cost-based-optimizers).

Second, optimizers may use various heuristics to limit the search space instead of doing an exhaustive search. A common heuristic is to prune the join orders that yield cross-products. While good enough in the general case, this heuristic may lead to non-optimal plans, e.g., for some star joins. A more aggressive pruning approach is to enumerate only left- or right-deep trees. This significantly reduces planning complexity but degrades the plan quality even further. Probabilistic algorithms might be used (e.g., [genetic algorithms](https://en.wikipedia.org/wiki/Genetic_algorithm) or [simulated annealing](https://en.wikipedia.org/wiki/Simulated_annealing)), also without any guarantees on the plan optimality.

## Summary

In this post, we took a sneak peek at the join ordering problem and got a bird's-eye view of its complexity. In further posts, we will explore the complexity of join order planning for different graph topologies, dive into details of concrete enumeration techniques, and analyze existing and potential strategies of join planning in [Apache Calcite](https://calcite.apache.org/). Stay tuned!

# Relational Operators in Apache Calcite

> **Abstract** When a user submits a query to a database, the optimizer translates the query string to an intermediate representation (IR) and applies various transformations to find the optimal execution plan.
>
> Apache Calcite uses relational operators as the intermediate representation. In this blog post, we discuss <u>**the design of common relational operators in Apache Calcite**</u>.

**摘要** 当用户向数据库提交查询时，优化器将查询字符串转换为<u>中间表示</u>（IR），并应用各种转换以找到最佳执行计划。Apache Calcite 使用<u>关系运算符</u>作为中间表示。在本篇博文中，我们将讨论 <u>Apache Calcite 中常用运算符的设计</u>。

## Intermediate Representation

### Syntax Tree

> Query optimization starts with parsing when a query string is translated into a syntax tree, which defines the syntactic structure of the query.
>
> Since every database has a parser, the syntax tree might look like a good candidate for the intermediate representation because it is readily available to the database.
>
> There are two significant problems with syntax tree as query's IR:
>
> 1. AST has a highly complicated structure, thanks to the involved ANSI SQL syntax. For example, a `SELECT` node may have dedicated child nodes for `FROM`, `WHERE`, `ORDER BY`, `GROUP BY`, etc.
> 2. AST models the syntactic structure but not relational semantics. It could be problematic to map some valid relational transformations to the syntax tree. For example, a semi-join cannot be expressed easily with ANSI SQL syntax.
>
> Combined, this makes query optimization over syntax trees challenging and not flexible.

当查询字符串被翻译成语法树时，查询优化从解析开始，语法树定义了查询的句法结构。由于每个数据库都有一个解析器，语法树可能看起来像是中间表示的一个很好的候选者，因为它很容易被数据库使用。语法树作为查询的 IR 存在两个重大问题：

1. 由于涉及到ANSI SQL 语法，AST 的结构非常复杂。 例如，一个 `SELECT` 节点可能有 `FROM`、`WHERE`、`ORDER BY`、`GROUP BY` 等专用的子节点。
2. AST  为句法结构建模，但不是关系语义。 将一些有效的关系转换映射到语法树可能会有问题。 <u>例如，不能用 ANSI SQL 语法简单地表达半连接</u>。

综合起来，这使得对语法树的查询优化具有挑战性且不灵活。

### Rleational Tree

> An alternative IR is a relational operator tree. We may define common relational operators, such as `Project`, `Filter`, `Join`, `Aggregate`. The query represented in such a way is much simpler to optimize because relational operators have a well-defined scope and usually have only one input (except for joins and set operators). This dramatically simplifies common relational optimizations, such as operator transposition. **Also, it gives implementors flexibility to model operators independently of the database syntax rules**.

另一种 IR 是关系运算符树。我们可以定义常见的关系运算符，例如 `Project`、`Filter`、`Join`、`Aggregate`。 以这种方式表示查询，其优化要简单得多，因为**关系运算符**具有明确定义的范围，并且通常只有一个输入（连接和集合运算符除外）。这极大简化了常见的关系优化，例如**运算符转置**。 **此外，它使实现者可以灵活地独立于数据库语法规则对运算符进行建模**。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b3612efc0661ba1956b79b_ast-vs-rel.png)

> The main disadvantage is the need to translate the syntax tree into a relational tree, which is often non-trivial, especially with complex syntax constructs like subqueries or common table expressions. However, the simplicity and flexibility of relational operators usually outweigh by a high margin the additional efforts on translation.

主要缺点是需要将**语法树**转换为**关系树**，这通常是有成本的，<u>尤其是对于子查询或公用表表达式等复杂的语法结构</u>。 然而，关系运算符的简单性和灵活性通常远远超过翻译方面的额外努力。

## Basics

> Apache Calcite parses the query into a syntax tree. Then it performs the semantic validation of the syntax tree using the [SqlValidatorImpl](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/sql/validate/SqlValidatorImpl.java) class, resolving involved data types along the way. Finally, the validated syntax tree is converted into a tree or relational operators using the [SqlToRelConverter](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/sql2rel/SqlToRelConverter.java) class. The subsequent optimizations are performed on the relational tree.
>
> In this section, we discuss the design of Apache Calcite relational operators.

Apache Calcite 将查询解析为语法树。 然后它使用 [SqlValidatorImpl](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/ sql/validate/SqlValidatorImpl.java) 类，一路解析涉及的数据类型。 最后，使用[SqlToRelConverter](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/ apache/calcite/sql2rel/SqlToRelConverter.java) 类将经过验证的语法树转换为关系运算符树。后续优化在关系树上进行。

在本节中，我们将讨论 Apache Calcite 关系运算符的设计。

### Terminology

We start with several simplified definitions, which are not precise but sufficient for this blog post.

An **attribute** is a pair of a name and a data type. An **attribute value** is defined by an attribute name and value from the attribute type domain. A **tuple** is an unordered set of attribute values. No two attribute values in the tuple may have the same attribute name. A **relation** is a set of tuples. Every tuple within the relation has the same set of attributes. **Relational operators** take zero, one, or more input relations and produce an output relation.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b374a4be8579b98cbce816_blog08-definitions.png)

### Operators

To construct a tree of relational operators, we need the ability to define operator inputs. Many operators need access to attributes of the input relations. Therefore we also need the ability to reference input attributes. These are two key requirements for the relational operator interface.

In Apache Calcite, the relational operator is represented by the [RelNode](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/rel/RelNode.java) interface. The operator may have zero, one, or more input operators. For example, `TableScan` is an 0-ary operator, `Filter` is a unary operator, and `Union` is an N-ary operator. Every operator exposes the `RelDataType`, which is an ordered list of operator attributes. This is sufficient to construct arbitrarily complex relational trees.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b48ffda5f126e051e3a082_blog08-row-type.png)

### Row Expressions

> Operators describe various transformations to tuples. A [RexNode](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/rex/RexNode.java) interface defines an operation that applies to some attribute values of a tuple and produces another value. Common `RexNode` types:
>
> 1. `RexLiteral` - a constant.
> 2. `RexInputRef` - a reference to operator's input attribute.
> 3. `RexCall` - a function call.
>
> For example, the expression `name = "John"` would be represented as follows.

运算符描述了对元组的各种转换。[`RexNode`](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/rex/RexNode.java) 接口定义了如何根据元组的某些属性值以产生另一个值。常见的 `RexNode` 类型：

1. `RexLiteral` - 常数。
2. `RexInputRef` - **对运算符输入属性的引用**。
3. `RexCall` - 函数调用。

例如，表达式 `name = "John"` 将表示如下。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b7829f70d3200769e64e01_blog08-rex.png)

> Notice that `RexInputRef` references the input's attribute by index, which means that attribute order is important in Apache Calcite. On the bright side, it simplifies the design, as you do not need to care about attribute names and potential naming conflicts (think of a join of two tables, which have an attribute with the same name). On the other hand, it has a detrimental effect on join order planning, as we shall see below.

请注意，`RexInputRef` 通过索引引用输入的属性，**这意味着属性顺序在 Apache Calcite 中很重要**。从好的方面来说，它简化了设计，因为不需要关心属性名称和潜在的命名冲突（想想两个表的连接，它们有一个同名的属性）。 另一方面，它对 ==join order planning== 有不利影响，**我们在后面将会看到**。

## Operators

Now, as we understand the basics, let's discuss the most common Apache Calcite operators: `TableScan`, `Project`, `Filter`, `Calc`, `Aggregate`, and `Join`.

Other important operators are `Window` and `Union`. We omit them in this blog post because they follow the same design principles as the previously mentioned operators.

### TableScan

`TableScan` is a leaf 0-ary operator that defines a scan of some data source.

The operator contains the `org.apache.calcite.schema.Table` instance, which describes a data source that produces tuples. It could represent a relational table, an index, a view, a CSV file, a network connection, or anything else. As an implementor, you provide the schema of your database that contains some `Table` instances. Apache Calcite will create a `TableScan` operator with the referenced `Table` inside when you refer to that table in the query. The `Table` must expose the row type so that the parent operators know which attributes are available from the `TableScan`.

### Project

> The `Project` operator defines row expressions that should be applied to input tuples to produce new tuples. The operator produces one output tuple for every input tuple. Expressions are organized in a list.
>
> Because Apache Calcite uses local indexes to reference input attributes, the `Project` operator is also injected whenever we need to change the attribute's order. For example, if there is a table with attributes `[a, b]` in that order and we execute `SELECT b, a FROM t`, the `Project` operator will be added on top of the `TableScan` to reorder attributes as required by the query. This complicates query planning because the optimizer spends time applying transformation rules to otherwise useless operators that do a trivial reorder.
>
> Physical implementations of the `Project` operator must adjust the input [traits](https://www.querifylabs.com/blog/custom-traits-in-apache-calcite). E.g., if the `TableScan` produces tuples ordered by `[b]` but the `Project` operator doesn't project that column, the order will be lost.
>
> The relational tree of the query `SELECT a, a+b FROM t` might look like this:

`Project` 运算符定义了应用于输入元组以生成新元组的**行表达式**。运算符为每个输入元组生成一个输出元组。表达式被组织在一个列表中。

因为 Apache Calcite 使用本地索引来引用输入属性，所以每当我们需要更改属性的顺序时，也会注入 `Project` 运算符。例如，如果有一个按顺序具有属性 `[a, b]` 的表，我们执行 `SELECT b, a FROM t`，则`Project` 运算符将添加到 `TableScan` 之上以重新排序属性根据查询的要求。这使查询计划变得复杂，因为优化器将花费时间将转换规则应用到执行简单重排的无意义运算符上。

`Project` 操作符的物理实现必须调整输入 [traits](https://www.querifylabs.com/blog/custom-traits-in-apache-calcite)。例如，如果 `TableScan` 生成按 `[b]` 排序的元组，但 `Project` 运算符不投影 `[b]`  列，则排序信息将丢失。

查询“SELECT a, a+b FROM t”的关系树可能如下所示：

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b78e86342fb8c97b6540f5_blog08-project.png)

### Filter

The `Filter` operator returns tuples that satisfy a predicate. A predicate is a row expression. The `Filter` output row type is similar to the input's row type. Physical implementations of the `Filter` operator usually don't change input traits.

The query `SELECT a, a+b FROM t WHERE a+b>5` could be represented as:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b78be9128f38006b87f543_blog08-filter.png)

### Calc

The `Calc` is a special operator that combines the functionality of `Project` and `Filter` operators and performs the common sub-expression elimination. Internally, it splits all composite row expressions into primitive expressions. Expressions are organized in a list. The special `RexLocalRef` node is used to link siblings. `Project` becomes a list of expression indexes that should be exposed from the operator. `Filter` becomes an optional expression index that filters input tuples.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b78c01fcaf5405442e5ede_blog08-calc.png)

Apache Calcite provides a lot of optimization rules for `Project` and `Filter` operators. These same optimizations are generally not implemented for the `Calc` operator because it would essentially require duplication of rules logic. Instead, you may do the cost-based optimization with `Project` and `Filter` operations only and then convert `Project` and `Filter` operators into `Calc` in a separate heuristic phase. Apache Calcite provides [dedicated rules](https://github.com/apache/calcite/blob/calcite-1.26.0/core/src/main/java/org/apache/calcite/plan/RelOptRules.java#L55-L66) for that. We touched on the multi-phase optimization in our previous [blog post](https://www.querifylabs.com/blog/what-is-cost-based-optimization).

### Aggregate

The `Aggregate` operator models the application of aggregate functions to the input. The operator consists of two parts - the group keys and aggregate functions.

The group keys define which input attributes to use to construct the groups. The statement `GROUP BY a, b` yields the grouping key `[0, 1]` if `a` and `b` are located on input positions 0 and 1, respectively. If there is no `GROUP BY` clause, the group key would be empty.

There will be several group keys if there is a `ROLLUP` or `CUBE` clause. For example, `GROUP BY ROLLUP a, b` would yield the grouping keys `[0,1], [0], []`, which means that we would like to output groups for `[a, b]`, groups for `[a]`, and global aggregates without any grouping.

If there is an expression in the `GROUP BY` statement, it would be moved to a separate `Project` operator below `Aggregate`. This is why it is sufficient to define input attribute indexes for the group keys instead of defining row expressions. Separation of projections and aggregations is essential to keep the complexity of optimization rules under control. Otherwise, we would have to repeat logic from the `Project` optimization rules in the `Aggregate` optimization rules.

The aggregate functions are the list of aggregates that should be computed for the groups. The aggregate functions do not use the `RexNode` interface because they operate on multiple tuples as opposed to row expressions that are applied to a single tuple. Similar to group keys, aggregate functions refer to input columns by indexes. For example, the function `SUM(a)` is converted to `SUM(0)` if the input attribute `a` is located at position 0. Likewise, complex expressions are moved to a `Project` operator below the `Aggregate`. Aggregate functions may also have advanced properties, such as the `DISTINCT` flag or an optional filter. We will discuss these features in detail in future blog posts.

The `Aggregate` operator outputs group keys followed by aggregate functions. For the query `SELECT SUM(a), b GROUP BY b`, the relevant `Aggregate` operator would output `[0:b, 1:SUM(a)]`.

Consider the plan for the query `SELECT SUM(a+b), c FROM t GROUP BY c` below. Notice two `Project` operators: one to calculate `a+b` and another to output `SUM` before the attribute `c`.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b78c1759f1405dda985451_blog08-agg.png)

### Join
>
> The `Join` operator joins two inputs. The operator defines the join type (inner, left/right/full outer, semi, etc.) and the optional predicate.
>
> The `Join` operator outputs all columns from the left input followed by all columns from the right input. There is the convention: given the left input with `L` attributes and the right input with `R` attributes:
>
> - If the referenced column index `I` is between zero and `L` exclusive, we should use the left input's attribute at position `I`.
> - Otherwise, we should use the right input's attribute at position `I - L`.
>
> In our previous [blog post](#Memoization in Cost-based Optimizers), we discussed that cost-based optimizers rely on the equivalence property of operators to **<u>encode alternative plans</u>** efficiently in the MEMO data structure. In Apache Calcite, `Join(AxB)` and `Join(BxA)` are not semantically equivalent because Apache Calcite relies on attribute indexes in the `RexInputRef` class. Parent operators of `Join(AxB)` and `Join(BxA)` will have to use different indexes when referring to the same join attribute. Internal join predicates will also reference attributes at different indexes.
>
> Consider the `JoinCommute` rule that changes the order of inputs. To apply this rule, we need to (a) rewrite the internal predicate and (b) add the `Project` on top of the new `Join` to restore the original order of attributes.
>

`Join` 运算符连接两个输入。运算符定义了连接类型(内连接、左连接/右连接/全连接、半连接等)和可选谓词。`Join` 运算符输出左侧输入的所有列，然后输出右侧输入的所有列。这里有一个约定：假定左输入带有 `L` 属性，而右输入带有 `R` 属性：

- 如果引用的列索引 `I` 介于 0 和 `L` 之间，我们应该在位置 `I` 处使用左侧输入的属性。
- 否则，我们应该在 `I - L` 位置使用右侧输入属性。

在之前的[博客](#Memoization in Cost-based Optimizers)中，我们讨论了基于成本的优化器依赖于运算符的等价性来在 **MEMO** 数据结构中有效地<u>**编码替代计划**</u>。 在 Calcite 中，`Join(AxB)` 和 `Join(BxA)` 在语义上并不等效，因为 Calcite 依赖于 `RexInputRef` 类中的属性索引。 `Join(AxB)` 和 `Join(BxA)` 的父运算符在引用相同的连接属性时必须使用不同的索引。内部的**连接谓词**还得引用不同索引处的属性。

考虑改变输入顺序的 `JoinCommute` 规则。要应用此规则，我们需要 (a) 重写 Join 的内部谓词和 (b) 在新的 `Join` 之上添加 `Project` 以恢复属性的原始顺序。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b78c222b319033945b0cf1_blog08-join-1.png)

> This additional `Project` prevents the execution of other rules. For example, the `JoinAssociate` rule tries to reorder `(A join B) join C` to `A join (B join C)`. The rule looks for a pattern "Join on top of the Join". But with the additional `Project`, we have only "Join on top of the Project". To mitigate this, we may use the `JoinProjectTransposeRule` that transposes `Join` and `Project`, but this dramatically decreases planner's performance to the extent that Apache Calcite cannot do the exhaustive cost-based join planning on more than 5-6 tables in a reasonable time.

这个额外的 `Project` 阻止了其他规则的执行。 例如，`JoinAssociate` 规则尝试将`(A join B) join C` 重新排序为`A join (B join C)`。 该规则查找关系树中 **Join 之上的 Join** 的模式。但是有了这个额外的 `Project` ，关系树中的模式为  **`Project` 之上的 `Join`**。为了缓解这个问题，我们可以使用转置 `Join` 和 `Project` 的 `JoinProjectTransposeRule`，但这会大大降低优化划器的性能，以至于 Calcite  无法在合理的时间内对超过 5-6个 表的 `Join `进行详尽的基于成本的优化。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/60b4cbfba395d8e030cc1dbb_blog08-join-2.png)

> The alternative solution would be to operate on unique column names rather than indexes. Spark Catalyst and CockroachDB follow this approach. But this would require introducing some unique identifier to every equivalence group, which is also a challenge on its own.

另一种解决方案是对唯一的列名而不是索引进行操作。 Spark Catalyst 和 CockroachDB 使用这种方法。但这需要为每个等价组引入一些唯一标识符，这本身也是一个挑战。

## Summary

> Apache Calcite parses the query string into a syntax tree. The syntax tree is then translated into a tree of relational operators, which have a simpler internal structure and are more suitable for the subsequent optimizations.
>
> We discussed several common relational operators in Apache Calcite. `Project` transforms every tuple from the input into another tuple. `Filter` operator returns input tuples that pass the predicate. `Calc` combines `Project` and `Filter` functionality and eliminates the common sub-expressions. `Aggregate` operator performs the grouping and applies aggregate functions. `Join` operator combines tuples two inputs and applies the predicate.
>
> ==Designing relational operators is challenging. Every decision may open opportunities for new optimizations but block others. The index-based input attribute references in Apache Calcite are a good example of such a trade-off when a simplification useful for many optimization rules leads to severe problems with one of the most critical optimizer tasks - join order planning==.
>
> In future blog posts, we will dive into concrete optimizations that Apache Calcite applies to individual operators. Stay tuned!

Apache Calcite 将查询字符串解析为语法树。然后将语法树翻译成关系运算符树，其内部结构更简单，更适合后续优化。

我们讨论了 Apache Calcite 中的几个常见关系运算符。`Project` 将输入中的每个元组转换为另一个元组；`Filter` 运算符返回通过谓词的输入元组；`Calc` 结合了 `Project` 和 `Filter` 功能并消除了常见的子表达式；`Aggregate` 运算符执行分组并应用聚合函数；`Join` 运算符组合两个输入的元组并应用谓词。

==设计关系运算符具有挑战性。每一个决定都可能为新的优化打开机会，但会阻碍其他。当对许多优化规则有用的简化导致最关键的优化器任务之一 —— 连接顺序优划出现严重问题时，Apache Calcite 中基于索引的输入属性引用是一个很好的折衷例子==。

在以后的博客文章中，我们将深入探讨 Apache Calcite 应用于单个操作符的具体优化。敬请关注！

# Metadata Management in Apache Calcite


## Abstract

> Query optimizers use knowledge of your data's nature, such as statistics and schema, to find optimal plans. Apache Calcite collectively refers to this information as metadata and provides a convenient API to extract operator's metadata within optimization routines. In this blog post, we will discuss the design of the metadata framework in Apache Calcite.

查询优化器使用数据性质的相关知识（例如统计信息和 schema）来查找最佳计划。 Apache Calcite 将这些信息统称为元数据，并提供了一个方便的 API 来在优化过程中**提取算子的元数据**。在这篇博文中，我们将讨论 Apache Calcite 中元数据框架的设计。

### Example

> Recall the query from our previous [blog post](https://www.querifylabs.com/blog/introduction-to-the-join-ordering-problem) about join planning:

回想一下我们之前关于 `join` 的查询[文章](#Introduction to the Join Ordering Problem)：

```sql
SELECT 
  lineitem.*
FROM 
  customer,
  orders,
  lineitem
WHERE
  c_custkey = ? 
  AND c_custkey = o_custkey
  AND o_orderkey = l_orderkey
```

> Cheaper plans tend to generate smaller intermediate relations. To ensure that the optimizer prefers such plans, we may make the `Join` operator cost proportional to the number of produced rows.

成本较低的计划往往会产生更小的中间表。为了确保优化器首选这样的计划，得让 `Join` 运算符的成本与生成的行数成正比。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/612e81b84c903cc96d2db936_blog09-join-order-plans.png)

> But how to estimate the number of rows (**cardinality**) in the first place? For the `Scan` operator, we may rely on table statistics maintained by the database.
>
> For the `Filter` operator, we may estimate the fraction of rows that satisfy the predicate (**selectivity**) and multiply it by input's cardinality. For example, the selectivity of the equality condition on a non-unique attribute could be estimated as the number of distinct attribute values divided by the total number of rows. The equality condition on a unique attribute would produce no more than one row.
>
> For the `Join` operator, we may multiply the predicate's selectivity by the cardinalities of both inputs. To make the estimation more accurate, we may want to propagate information about predicates already applied to the given attribute in the child operators.
>
> We already defined quite a few metadata classes which might be required for the join order planning:
>
> - Operator cardinalities that depend on ...
> - Predicate selectivities that depend on ...
> - Number of attribute's distinct values (NDV) that might depend on ...
> - Attribute's uniqueness and applied predicates.
>
> We need some powerful infrastructure to propagate all these pieces of information efficiently across operators.

但是如何在一开始就估计行数（**基数**）？对于 `Scan` 操作符，可以依赖于数据库维护的**表统计信息**。

对于 `Filter` 运算符，可以估计满足谓词（**选择性**）行数，并将其乘以输入的基数。例如，在==非唯一属性==上的相等条件的选择性可以估计为不同属性值的数量除以总行数。==唯一属性==上的相等条件最多只产生一行。

对于 `Join` 运算符，我们可以将**谓词的选择性**乘以**两个输入的基数**。为了使估计更准确，我们可能希望传播==已应用到子运算符属性==上的谓词信息。

我们已经定义了相当多的元数据类，它们可能是规划 `Join` 顺序所需的:

- 运算符基数...
- 谓词选择性...
- 列的不同属性值 (NDV) 的数量
- 列性的唯一性和==已应用的谓词==。

我们需要一些强大的基础设施来在运算符之间高效地传播所有这些信息。

## Design Considerations

> As we understand the problem, let's outline the possible design consideration for the metadata infrastructure.
>
> First, we define the metadata consumers. In [cost-based optimizers](https://www.querifylabs.com/blog/what-is-cost-based-optimization), metadata is used extensively to estimate the operator's cost. In [rule-based optimizers](https://www.querifylabs.com/blog/rule-based-query-optimization), we may want to access metadata from within the optimization rules. For example, we may use the information about the attribute's uniqueness to eliminate the unnecessary `DISTINCT` clause from queries like `SELECT DISTINCT unique_column FROM t`. <u>==Therefore, metadata API should be part of the global context available to different optimizer parts==</u>.
>
> Second, in rule-based optimizers, you typically do not have access to the complete operator tree until the end of the optimization process. For example, cost-based optimizers often use the [MEMO data structure](# Memoization in Cost-based Optimizers), where normal operator inputs are replaced with dynamically changing equivalence groups. Therefore, metadata **calculation** must be performed on the operator level rather than the whole query plan. On the other hand, the derivation of a particular metadata class might depend on other metadata classes. For example, `Filter` cardinality might require `Filter` selectivity and input cardinality. Therefore, the API must allow for recursive access to input metadata.
>
> Third, SQL queries may produce complex plans with tens of initial operators that expand to thousands and even millions of other operators during the planning. The straightforward recursive **dives** might become too expensive. Caching is essential to mitigate the performance impact.
>
> Finally, if you create a query optimization framework, like Apache Calcite, you may want to decouple metadata from operators. This allows you to provide foundational operators and associated optimization rules from the framework while still allowing users to change their costs.

在理解这个问题之后，让我们概述一下元数据基础设施可能的设计考虑。

**首先**，定义**元数据的消费者**。在[基于成本的优化器](https://www.querifylabs.com/blog/what-is-cost-based-optimization)中，<u>元数据被广泛用于估算运算符的成本</u>。在[基于规则的优化器](https://www.querifylabs.com/blog/rule-based-query-optimization)中，我们可能希望从优化规则中访问元数据。例如，列是否唯一的信息来自于诸如 `SELECT DISTINCT unique_column FROM t` 之类的查询中消除重复值的 `DISTINCT` 子句。因此，元数据 API 应该是全局上下文的一部分，供优化器的不同组件使用。

**其次**，在基于规则的优化器中，**通常在优化过程结束之前无法访问完整的运算符树**。例如，基于成本的优化器通常使用 [MEMO 数据结构](# Memoization in Cost-based Optimizers)，其中正常的算子输入被动态变化的等价组替换。**因此，元数据访问必须在算子层面进行，而不是在整个查询计划上进行**。另一方面，特定元数据类的派生可能依赖于其他元数据类。例如，计算 `Filter` 的基数可能需要 `Filter` 的选择性和其输入的基数。因此，API 必须能递归地访问输入元数据。

**第三**，SQL 查询可能会产生复杂的计划，初始算子有几十个， 优化过程中扩展到其他数千甚至数百万个算子。直接的递归**访问**可能会变得过于昂贵。 缓存对于减轻性能影响至关重要。

**最后**，如果您创建查询优化框架，例如 Apache Calcite，**您可能希望将元数据与运算符解耦**。这允许框架提供基础运算符和相关的优化规则，同时允许用户更改其成本。



![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/612e913cc36b1f0b82d9ef81_blog09-metadata-recursion%20(1).png)

## Metadata in Apache Calcite

> We defined the requirements of the API. Now let's take a look at how metadata management works in Apache Calcite.

我们定义了 API 的要求。 现在让我们看看元数据管理在 Apache Calcite 中是如何工作的。

### API

> Apache Calcite provides a single entry point to all metadata through the [RelMetadataQuery](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/RelMetadataQuery.java) interface. The interface contains a single method for each metadata class that accepts the target operator and optional parameters specific to the concrete metadata class. For example, the cardinality requires only the target operator, while selectivity also requires the predicate that is going to be **analyzed**:

Apache Calcite 通过 [`RelMetadataQuery`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/RelMetadataQuery.java) 接口为所有元数据提供单一入口点。该接口包含每个元数据类的单个方法，该方法接受<u>特定于具体元数据类的目标运算符</u>和<u>可选参数</u>。 例如，**基数**只需要目标运算符，而**选择性**还需要**用于分析的**谓词：

```java
class RelMetadataQuery {
  // Cardinality
  public Double getRowCount(RelNode rel) { ... }
  
  // Selectivity
  public Double getSelectivity(RelNode rel, RexNode predicate) { ... }
}
```

> The `RelMetadataQuery` object is available from the <u>global optimization context</u> called [RelOptCluster](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/plan/RelOptCluster.java). `RelOptCluster` is passed as a constructor argument to every operator. Therefore you may access metadata easily from any part of the optimizer's infrastructure, such as the operator's cost function, optimization rule, or even the metadata handler routines that we explain below.

从优化器的全局上下文 `RelOptCluster` 中获得 `RelMetadataQuery` 对象。`RelOptCluster` 作为构造函数参数传递给每个运算符。因此，==<u>您可以很容易地从优化器的基础设施的任何地方访问元数据</u>==，例如运算符的成本函数、优化规则，甚至可以在我们下面解释的元数据处理函数中访问元数据。

### Dispatching

> Internally, `RelMetadataQuery` dispatches metadata requests to dedicated handler functions. To install the handlers, we create a class that contains a set of methods with signatures similar to the public API plus the additional `RelMetadataQuery` argument, **one method per operator type**.
>
> For example, if the public row count API accepts `RelNode` (operator), the handler must accept both operator and `RelMetadataQuery`.

在内部，`RelMetadataQuery` 将元数据请求分派给专用的 **handler**。 为了安装 **handler**，我们创建了一个类，该类包含一组具有类似于 public API 签名的方法，外加一个额外的  `RelMetadataQuery` 参数，**每个运算符类型一个方法**。

例如，如果 public  的行数 API 接受 `RelNode` 运算符，则 **handler** 必须同时接受运算符和 `RelMetadataQuery`。

```java
class RelMetadataQuery {
  public Double getRowCount(RelNode rel) { ... }  
}

class RelMdRowCount {
  // Handler for scan.
  Double getRowCount(TableScan scan, RelMetadataQuery mq) { ... }  
  
  // Handler for filter.
  Double getRowCount(Filter filter, RelMetadataQuery mq) { ... }
  
  // Handler for the equivalence set. Required for the cost-based
  // optimization with VolcanoPlanner.
  Double getRowCount(RelSubset rel, RelMetadataQuery mq) { ... }
  
  // Catch-all handler invoked if there is no dedicated handler
  // for the operator class.
  Double getRowCount(RelNode rel, RelMetadataQuery mq) { ... }
}
```

> Finally, you assemble all available handler classes into a composite object and install it to the global context, `RelOptCluster`. We omit the details for brevity, but you may take a look at [RelMdRowCount](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/RelMdRowCount.java), [BuiltInMetadata.RowCount](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/BuiltInMetadata.java#L195-L215),  [DefaultRelMetadataProvider](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/DefaultRelMetadataProvider.java), and [RelOptCluster.setMetadataProvider](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/plan/RelOptCluster.java#L149-L159) for more detail.
>
> Once you provided all handler functions, magic happens. Apache Calcite will analyze handler function signatures and various marker interfaces and link them together inside the `RelMetadataQuery` instance. Now, the invocation of`RelMetadataQuery.getRowCount(Filter)` will trigger the relevant handler function.
>
> Handler functions might be overridden if needed. By extending the `RelMetadataQuery` class, you can also add new metadata classes.
>

最后，您将所有可用的 **handler** 类组装到一个复合对象中，并将其安装到全局上下文 `RelOptCluster` 中。为简洁起见，我们省略了详细信息，但您可以查 [`RelMdRowCount`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/RelMdRowCount.java)、[`BuiltInMetadata.RowCount`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/BuiltInMetadata.java#L195-L215)、[`DefaultRelMetadataProvider`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/DefaultRelMetadataProvider.java) 和 [`RelOptCluster.setMetadataProvider`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/plan/RelOptCluster.java#L149-L159) 以了解更多详细信息。

一旦你提供了所有的 **handler**，奇迹就会发生。 Apache Calcite 将分析 **handler**  的函数签名和各种标记接口，并将它们链接到 `RelMetadataQuery` 实例中。现在，调用 `RelMetadataQuery.getRowCount(Filter)` 将触发相关的处理函数。

如果需要，**handler** 函数可能会被覆盖。通过扩展 `RelMetadataQuery` 类，您还可以添加新的元数据类。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/613085e0a2eca2854cf0c1e2_blog09-dispatching.drawio.png)

> Previously, Apache Calcite used Java reflection to dispatch metadata requests, see [ReflectiveRelMetadataProvider](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/ReflectiveRelMetadataProvider.java). However, due to performance [concerns](https://issues.apache.org/jira/browse/CALCITE-604), the reflective approach was replaced with code generation using the [Janino](http://janino-compiler.github.io/janino/) compiler, see [JaninoRelMetadataProvider](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/JaninoRelMetadataProvider.java). Internally, the generated code is basically a large `switch` block that dispatches the metadata request to a proper handler function.

之前 Apache Calcite 使用 Java 反射来调度元数据请求，参见 [`ReflectiveRelMetadataProvider`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/ReflectiveRelMetadataProvider.java)。 但是，由于性能[关注](https://issues.apache.org/jira/browse/CALCITE-604)，反射方法被使用 [Janino](http://janino-compiler. github.io/janino/) 编译器，参见 [`JaninoRelMetadataProvider`](https://github.com/apache/calcite/blob/calcite-1.27.0/core/src/main/java/org/apache/calcite/rel/metadata/JaninoRelMetadataProvider.java)。内部生成的代码基本上是一个大的 `switch` 块，它将元数据请求分派给适当的处理函数。 

### Caching

> Metadata calculation might be expensive. Intermediate operators, such as `Filter` or `Join`, often rely on children's metadata. This leads to recursive calls, which makes the complexity of metadata calculation proportional to the size of the query plan.
>
> A key observation is that metadata of a given operator remains stable for so long there are no changes to the operator's children. Therefore, we may cache the operator's metadata and invalidate it when a change to a child node is detected. Apache Calcite tracks connections between operators, which allows it to detect such changes and provide metadata caching capabilities out-of-the-box.

元数据计算可能很昂贵。 中间运算符，例如 `Filter` 或 `Join`，通常依赖于子节点的元数据。这将导致递归调用，这使得元数据计算的复杂性与查询计划的大小成正比。

一个关键的观察结果是，给定运算符的元数据保持稳定的时间很长，只要运算符的子节点没有变化。因此，我们可以会缓存运算符的元数据，并在检测到子节点发生更改时使其失效。 Apache Calcite 跟踪运算符之间的连接，这使其能够检测此类修改，并提供现场的元数据缓存功能。

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/613089a93018223cb784eebf_blog09-caching.png)

## Useful Metadata Classes

> In this section, we describe Apache Calcite metadata classes often used in practice.
>
> - **Cardinality** - estimates the number of rows emitted from the operator. Used by operator cost functions.
> - **A number of distinct values** (NDV)- estimates the number of distinct values for the given set of attributes. Facilitates cardinality estimation for operators with predicates and aggregations.
> - **Selectivity** - estimates the fraction of rows that pass the predicate. Helps to estimate cardinalities for operators with predicates, such as `Filter` and `Join`.
> - **Attribute uniqueness** - provides information about unique attributes. Used by optimization rules to simplify or reduce operators. E.g., to eliminate unnecessary aggregates.
> - **Predicates** - deduces the restrictions that hold on rows emitted from an operator. Used by optimization rules for operator simplification, ==transitive predicate derivation==, etc.
>

实践中，我们经常使用的 Apache Calcite 元数据类如下：

- **基数** - 估计运算符输出的行数。 由运算符的成本函数使用。
- **不同列值的数量** (NDV) - 估计一组给定列不同值的数量。有助于对带有谓词和聚合的运算符进行基数估计。
- **选择性** - 估计谓词过滤后的输出比例。用于<u>带有谓词的运算符</u>估计基数，例如 `Filter` 和 `Join`。
- **列的唯一性** - 提供列有关唯一性的信息。由优化规则用于简化或减少运算符。例如，消除不必要的聚合。
- **谓词** - 推断对运算符输出的限制。由优化规则用于运算符简化、==传递谓词派生==等。

## Summary

> Metadata is auxiliary information that helps optimizer find better plans. Examples are operator cardinality, predicate selectivity, attribute uniqueness.
>
> Apache Calcite comes with a rich metadata management framework. Users may access metadata through a single gateway, `RelMetadataQuery`, from any part of theoptimizer's code (operators, rules, metadata).
>
> Internally, Apache Calcite works with isolated metadata handler functions, one per metadata class per operator. You may override existing handler functions and provide new ones. Apache Calcite uses code generation to wire independent handler functions into a single **<u>facade</u>** exposed to the user. Additionally, Apache Calcite uses aggressive caching to minimize the overhead on recursive metadata calls.
>
> In further posts, we will explore in detail how cardinality is derived for different operators. Stay tuned!

元数据是帮助优化器找到更好计划的辅助信息。 例如运算符基数、谓词选择性、属性唯一性。

Apache Calcite 带有丰富的元数据管理框架。用户可以通过单个网关 `RelMetadataQuery` 从优化器代码的任何部分（运算符、规则、元数据）访问元数据。

Apache Calcite 在内部使用隔离的元数据处理函数，每个运算符每个元数据类一个。您可以覆盖现有的 **handler**  函数并提供新的函数。Apache Calcite 使用代码生成将独立的 **handler** 函数连接到向用户公开的单个**<u>外观</u>**中。 此外，Apache Calcite 尽可能的使用缓存来最小化递归调用元数据的开销。

在接下来的文章中，我们将详细探讨如何为不同的运算符导出基数。 敬请关注！

# Cross-Product Suppression in Join Order Planning

> **Abstract**   One complex problem a query optimizer has to solve is finding the optimal join order since the execution time for different join orders can vary by several orders of magnitude. Plans with cross-products are likely to be inefficient, and many optimizers exclude them from the consideration using a technique known as **cross-product suppression**.
>
> The number of cross-product free join orders for a query depends on join conditions between inputs. In this blog post, we discuss the complexity of the cross-product free join order enumeration for three common join graph topologies: clique, star, and chain.



**摘要**  查询优化器必须解决的一个复杂问题是找到最佳连接顺序，因为不同连接顺序的执行时间可能相差几个数量级。含有叉积的执行计划可能效率低下，许多优化器使用一种称为**叉积抑制**的技术将它们排除在考虑之外。查询（自由）的叉积联接顺序的数量取决于输入之间的联接条件。本文，我们讨论三种常见**连接图拓扑**的（自由）叉积联接顺序枚举的复杂性：clique、star 和 chain。

## General case complexity

Determining the best join order is a well-known [NP-hard problem](https://dl.acm.org/doi/10.1145/1270.1498) that cannot be solved in polynomial time in a general case. Let's estimate the number of possible join orders in the query based on the number of inputs. We already did that in our [previous blog post](# Introduction to the Join Ordering Problem), but we repeat that exercise here for clarity.

Consider that our system can execute two-way joins, like `AxB` or `BxA`. To join three inputs, we perform two two-way joins in a certain order. E.g., `Ax(CxB)` means that we first join `C` to `B` and then join `A` to the result. How many different join orders are there for N inputs?

First, we count the number of different orders of leaf nodes. Intuitively, for `N` inputs, we have `N` alternatives for the first position, `N-1` alternatives for the second position, etc., which gives us `N!` orders.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61ac76977e58ee8973a31487_join-leaf-order.drawio.png)

Next, for every particular leaf order, we determine the number of possible two-way join orders, which is the number of ways of associating `N-1` applications of a binary operator. This number is equal to the [Catalan number](https://en.wikipedia.org/wiki/Catalan_number) `C(N-1)`.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61ac7717d096cf8a67e5cfc3_join-catalan.drawio.png)

The Catalan number of `N` is determined as follows:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61ac782a4c1110060dbb539a_equation-catalan.gif)

We combine both parts to get the final formula:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61ac7932c7fb436831772f65_equation-join-clique.gif)

Consider the TPC-DS suite. [Query 3](https://github.com/Agirish/tpcds/blob/master/query3.sql#L6-L8) joins three tables, which gives 12 join orders, an easy target. [Query 17](https://github.com/Agirish/tpcds/blob/master/query17.sql#L29-L36) joins eight tables, which gives more than 17 million join orders. Many optimizers would already give up on exhaustive enumeration at this point. Finally, [query 64](https://github.com/Agirish/tpcds/blob/master/query64.sql#L35-L52) has a sub-plan that joins eighteen tables, giving us ~830 sextillion join orders, big trouble.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61b7a3683eee6f258f4ce3a7_chart-clique.png)

## Cross-product suppression

The straightforward enumeration is impractical for complex queries, so any production-grade optimizer must use some heuristic to keep the planning time sane.

The common wisdom is that plans with cross-products are likely to be inefficient. If we exclude such plans from consideration, we may substantially reduce the number of alternative join orders.

Note that this is merely a heuristic, and there are some queries where the optimal plan contains cross-products. For example, if we join a fact table to two dimension tables with highly selective predicates, it might be better to execute a cross-join on dimension tables and join the result with the fact table.

We introduce the **join topology**, a graph where vertices are inputs and edges are join conditions. The topology is called a **clique** when every input has a join condition with every other input. The topology is called a **star** when one input is joined to all other inputs. The topology is called a **chain** when two inputs are joined with one other input, and the rest are joined with two other inputs.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/617d989f885c2bc3ab4db913_join-topologies.drawio.png)

Now, let's count the number of cross-product free join orders for each topology.

### Clique

The cross-product suppression is not applicable for clique by definition since every input has join conditions with every other input. Therefore, the number of cross-product free join orders in cliques equals to the formula above.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61acdc2ae8edf7a87ec994d5_equation-join-clique.gif)

### Chain

For the chain topology, there is a single order of leaves, e.g., `A-B-C`. `C(N-1)` parenthesizations are available for that order of leaves. For each such parenthesization, we can change the order of inputs within every parenthesis, e.g., change `(AB)` to `(BA)`. This gives us `2^(N-1)` combinations.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61acdc7d50c1f4f974002cec_join-chain.drawio.png)

The final formula is:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61b85ac7d5eb4d3ed3e20f7b_equation-join-chain.gif)

### Star

For star queries, we count the number of left-deep trees starting with the fact table, giving us `(N-1)!` possible trees. For every such tree, we commute individual joins, which gives us `2^(N-1)` alternatives per tree.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61ace759cf072572e35d4fc3_join-star.drawio.png)

The final formula is:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61b85b27d85b32f1f7e94df0_equation-join-star.gif)

### Example

Consider the TPC-DS [query 17](https://github.com/Agirish/tpcds/blob/master/query17.sql#L29-L36) again. The join graph topology for this query looks as follows:

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61b7a4f9bb2df18aa3c06d31_q17.drawio.png)

Without the cross-product suppression, there are `17,297,280` possible join orders. To count the number of cross-product free join orders, we implement a simple bottom-up [join enumerator](https://github.com/querifylabs/querifylabs-blog/tree/main/join-enumerator) that discards the join orders with cross-products. The enumerator [gives](https://github.com/querifylabs/querifylabs-blog/blob/main/join-enumerator/src/test/java/com/querifylabs/blog/joins/JoinEnumeratorTcpdsTest.java) us `211,200` cross-product free join orders, roughly `1.3%` of all possible join orders. This example demonstrates how cross-join suppression may decrease the number of considered joins by several orders of magnitude.

## Discussion

Chain topologies produce the smallest number of cross-product free join orders, followed by star and clique. Real queries usually have mixed topologies, so counting the number of cross-product free join orders in them is not straightforward. Nevertheless, the number of plans with cross-products is vastly more than the number of cross-product free plans for most queries. Therefore, cross-product suppression is an important heuristic that allows discarding plenty of not optimal plans in advance.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61b7a4a732c408cbb1b32d85_chart-all.png)

Since the complexity remains exponential even for chain topologies, the cross-product suppression alone is not sufficient for production-grade databases. State-of-the-art optimizers attack the problem from two angles:

- Speed up the join order enumeration. Dynamic programming and [memoization](# Memoization in Cost-based Optimizers) are often used to avoid repetitive computations. [Branch-and-bound pruning](https://en.wikipedia.org/wiki/Branch_and_bound) removes non-promising plans from consideration early on. Clever enumeration algorithms like [DPccp](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.134.3827&rep=rep1&type=pdf) and [TDMinCutConservative](https://pi3.informatik.uni-mannheim.de/~moer/Publications/FeMo11.pdf) minimize the enumeration time, avoiding clusters of plans with cross-products.
- Apply more heuristics. Some optimizers avoid bushy trees; others use probabilistic algorithms, etc.

Altogether, these techniques allow query optimizers to find sensible join orders even for very complex queries, though the optimality is usually not guaranteed.

## Summary

The join order enumeration is a well-known NP-hard problem that cannot be solved in a polynomial time. Modern query optimizers apply various heuristics to limit the search space. One of the most important heuristics is a cross-product suppression that discards cross-joins from consideration, reducing the number of considered join orders. This heuristic may miss some optimal plans with cross-products, and the overall complexity remains exponential. Therefore, the usage of cross-product suppression alone is rarely sufficient for state-of-the-art product-grade optimizers.

In future posts, we will see how the cross-product suppression and [memoization](# Memoization in Cost-based Optimizers) may further improve the optimizer's performance. We will also discuss modern join enumeration algorithms and their implementations in practical optimizers. Stay tuned!

# Introduction to Data Shuffling in Distributed SQL Engines


## Abstract

Distributed SQL engines process queries on several nodes. Nodes may need to exchange tuples during query execution to ensure correctness and maintain a high degree of parallelism. This blog post discusses the concept of data shuffling in distributed query engines.

## Streams

SQL engines convert a query string to a sequence of operators, which will call an execution plan. We assume that operators in a plan are organized in a tree. Every operator consumes data from zero, one or more child operators, and produces an output that a single parent operator consumes. Practical engines may use DAGs, where several parent operators consume the operator's output, but we ignore such cases for simplicity.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f980d8f3cf42dff1804e5e_tree-dag.png)

In distributed engines, we may want to create several instances of the same plan's operator on different nodes. For example, a table might be partitioned into several segments that different workers read in parallel. Likewise, several nodes might execute a heavy `Join` operator concurrently, each instance producing only part of the output. In this case, we say that a single operator produces several physical data streams.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f980a865bddae70ede12fe_nway-operators.png)

## Operator Requirements

Operators must align their physical data streams carefully to ensure the correctness of results. Let us consider the behavior of a distributed `Join` operator.

The `Join` operator evaluates every pair of tuples from left and right inputs against a join condition. If we create several `Join` instances, we must ensure that the matching tuples always arrive at the same instance. How we do this depends on the join type and join condition. For equi join, we may **partition** inputs by join attributes, such that every tuple with the same value of the join key arrives at the same stream. Hashing is usually used, although any partitioning scheme will work, for so long the matching tuples are routed to the same stream.

Note that there might be multiple viable partitioning schemes. For example, for the join condition `a1=b1 AND a2=b2`, the input might be redistributed by `[a1, a2]`, `[a2, a1]`, `[a1]`, or `[a2]`. This adds considerable complexity to the query planning because different operator combinations might benefit from different partitioning schemes. We will discuss distributed planning in detail in the next blog post.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f56bf758a4e2456a71d64a_join-unicast.png)

Alternatively, we may **broadcast** one of the inputs. If there are `N` instances of the `Join` operator, we create `N` full copies of one of the inputs. This might be beneficial if one of the inputs is much smaller than the other, such that broadcasting of the smaller input is cheaper than re-distribution of both inputs. Also, the broadcast scheme is mandatory for non-equi joins and some outer joins.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f56d4a28293a380ed5a8a2_join-broadcast.png)

The academia proposed more distribution strategies. For example, [Track Join](https://w6113.github.io/files/papers/trackjoin-sigmod14.pdf) tries to minimize the network traffic by creating an individual transfer schedule for each tuple. However, partitioned and broadcast shuffles are the most commonly used strategies in practical systems.

Similar to the distributed `Join`, the distributed `Aggregate` must ensure that all input tuples with the same aggregate key are routed to the same stream. The distributed `Union` operator must route similar tuples from all inputs to the same stream for proper deduplication. In contrast, the pipelined operators, such as `Project` and `Filter`, can be safely placed on top of any physical stream.

## Planning

During query planning, optimizers usually maintain distribution metadata, such as distribution type, distribution function, and the number of shards. The common distribution types are:

- `PARTITIONED` (or `SHARDED`) - operator's output is split into several disjoint streams. This is a common distribution type for intermediate operators.
- `REPLICATED` - operator produces several data streams, all with the same complete set of tuples. This distribution often appears after the broadcast shuffle. Also, such distribution is common for small fact tables that are copied across all execution nodes.

The distribution function and the number of shards make sense only for the `PARTITIONED` output and describe how data is split between physical streams and how many such streams are. Common distribution function examples are hash, range, and random distribution.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f57f7fbbd0e1394007e0e4_distribution.drawio.png)

The convenient way to express the data shuffling in the optimizer is to use a dedicated plan operator, usually called `Exchange` or `Shuffle`. The optimizer's goal is to find the optimal placement of `Exchange` operators in the query plan. A variety of algorithms might be used for this, from simple heuristic rewrites to fully-fledged cost-based optimization with the Cascades algorithm. We will discuss shuffle planning in detail in the next blog post.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f983cf7b496fa7c8ea25c0_shuffle-operator.drawio.png)

## Execution

The engine needs to figure out which nodes should execute which operations. Usually, engines cut the plan into parts called **fragments** that could be executed independently. The scheduler then assigns fragment instances to execution units based on resource utilization, data locality, and other factors.

`Exchange` operators are replaced with specialized implementations that transmit data between participants. OLTP engines may prefer to transfer data through network sockets to minimize latency. Big data engines may decide to exchange data through a persistent medium, such as distributed file system, to avoid loss of result in the case of participant crash.

![img](https://assets-global.website-files.com/5fe5c475cb3c75040200bfe6/61f9837e7152b22dbce10443_exec.png)

Executors do not always strictly follow the original plan. Optimizers may produce not optimal plans due to imprecise statistics; system reconfiguration may happen during query execution, etc. Advanced executors may do runtime re-optimizations, overriding some planner decisions. For example, the executor may prefer one shuffle type over the other in the face of data skew or incorrect cardinality estimations or change the number of shuffle partitions in runtime. Please refer to the [query robustness survey](https://hal.archives-ouvertes.fr/hal-01316823/document) by Yin et al. for more ideas on possible runtime re-optimization strategies.

## Summary

Distributed SQL engines execute queries on several nodes. To ensure the correctness of results, engines reshuffle operator outputs to meet the requirements of parent operators. Two common shuffling strategies are partitioned and broadcast shuffles.

Both query planner and executor use shuffles. Planner uses distribution metadata to find the optimal placement of shuffle operators. The executor tracks the state of data streams, routes tuples to the proper physical nodes, and may also override planner decisions in the case of data skew.

In future blog posts, we will discuss how query planners decide on the optimal placement of shuffle operators.
