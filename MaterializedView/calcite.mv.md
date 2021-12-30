# 背景

> Apache Calcite is a dynamic data management framework.
>
> It contains many of the pieces that comprise a typical database management system, but omits some key functions: storage of data, algorithms to process data, and a repository for storing metadata.
>
> Calcite intentionally stays out of the business of storing and processing data. As we shall see, this makes it an excellent choice for **mediating** between applications and one or more data storage locations and data processing engines. It is also a perfect foundation for building a database: just add data.
>
> To illustrate, let’s create an empty instance of Calcite and then point it at some data.

Apache Calcite 是一个动态数据管理框架。

它包含构成典型数据库管理系统的许多部分，但省略了一些关键功能：数据存储、处理数据的算法以及用于存储元数据的存储库。

Calcite 有意不参与存储和处理数据的业务。正如我们将看到的，这使其成为在应用程序与一个或多个数据存储位置和数据处理引擎之间进行**调解**的绝佳选择。它也是构建数据库的完美基础：只需添加数据。

为了说明这一点，让我们创建一个 Calcite 的空实例，然后将其指向一些数据。

```JAVA
public static class HrSchema {
  public final Employee[] emps = 0;
  public final Department[] depts = 0;
}
Class.forName("org.apache.calcite.jdbc.Driver");
Properties info = new Properties();
info.setProperty("lex", "JAVA");
Connection connection =
    DriverManager.getConnection("jdbc:calcite:", info);
CalciteConnection calciteConnection =
    connection.unwrap(CalciteConnection.class);
SchemaPlus rootSchema = calciteConnection.getRootSchema();
Schema schema = new ReflectiveSchema(new HrSchema());
rootSchema.add("hr", schema);
Statement statement = calciteConnection.createStatement();
ResultSet resultSet = statement.executeQuery(
    "select d.deptno, min(e.empid)\n"
    + "from hr.emps as e\n"
    + "join hr.depts as d\n"
    + "  on e.deptno = d.deptno\n"
    + "group by d.deptno\n"
    + "having count(*) > 1");
print(resultSet);
resultSet.close();
statement.close();
connection.close();
```

> Where is the database? There is no database. The connection is completely empty until new ReflectiveSchema registers a Java object as a schema and its collection fields emps and depts as tables.
>
> Calcite does not want to own data; it does not even have a favorite data format. This example used in-memory data sets, and processed them using operators such as groupBy and join from the linq4j library. But Calcite can also process data in other data formats, such as JDBC. In the first example, replace

数据库在哪里？没有数据库。在 `new ReflectiveSchema` 将 Java 对象注册为 Schema，并将其集合字段 `emps` 和 `depts` 注册为表之前，连接是完全空的。

Calcite 不想拥有数据；它甚至没有最喜欢的数据格式。此示例使用内存数据集，并使用来自 `linq4j` 库的 `groupBy` 和 `join` 等运算符处理它们。 但是 Calcite 也可以处理其他数据格式的数据，例如 JDBC。 在第一个示例中，替换

```java
Schema schema = new ReflectiveSchema(new HrSchema());
```

为

```java
Class.forName("com.mysql.jdbc.Driver");
BasicDataSource dataSource = new BasicDataSource();
dataSource.setUrl("jdbc:mysql://localhost");
dataSource.setUsername("username");
dataSource.setPassword("password");
Schema schema = JdbcSchema.create(rootSchema, "hr", dataSource, null, "name");
```

> and Calcite will execute the same query in JDBC. To the application, the data and API are the same, but behind the scenes the implementation is very different. Calcite uses optimizer rules to push the JOIN and GROUP BY operations to the source database.
>
> In-memory and JDBC are just two familiar examples. Calcite can handle any data source and data format. To add a data source, you need to write an adapter that tells Calcite what collections in the data source it should consider “tables”.
>
> For more advanced integration, you can write optimizer rules. Optimizer rules allow Calcite to access data of a new format, allow you to register new operators (such as a better join algorithm), and allow Calcite to optimize how queries are translated to operators. Calcite will combine your rules and operators with built-in rules and operators, apply cost-based optimization, and generate an efficient plan.

那么 Calcite 将在 JDBC 中执行相同的查询。对应用来说，数据和 API 是一样的，但幕后的实现却大不相同。Calcite 使用优化器规则将 `JOIN` 和 `GROUP BY` 操作推送到源数据库。

In-memory 和 JDBC 只是两个熟悉的例子。Calcite 可以处理任何数据源和数据格式。要添加数据源，您需要编写一个适配器，告诉 Calcite 应将数据源中的哪些集合视为“表”。

对于更高级的集成，您可以编写优化器规则。 优化器规则允许 Calcite 访问新格式的数据，允许您注册新的运算符（例如更好的连接算法），使得 Calcite 优化如何将查询转换为运算符。Calcite 将您的规则和运算符与内置规则和运算符相结合，应用基于成本的优化，并生成有效的计划。

## 编写 Adapter

example/csv 下的子项目提供了一个 CSV 适配器，功能齐全，可用于应用程序，但如果您正在编写自己的适配器，它也足够简单，可以作为一个很好的模板。

有关使用 CSV 适配器和编写其他适配器的信息，请参阅[教程](https://calcite.apache.org/docs/tutorial.html)。

有关使用其他适配器以及一般使用 Calcite 的更多信息，请参阅 [HOWTO](https://calcite.apache.org/docs/howto.html)。

## 当前状态

以下功能是完整的。

- 查询解析器、验证器和优化器
- 支持读取 JSON 格式的**模型**
- 许多标准函数和聚合函数
- 针对 Linq4j 和 JDBC 后端的 JDBC 查询
- Linq4j 前端
- SQL特性：SELECT、FROM（包括JOIN语法）、WHERE、GROUP BY（包括GROUPING SETS）、聚合函数（包括COUNT(DISTINCT ...)和FILTER）、HAVING、ORDER BY（包括NULLS FIRST/LAST）、集合操作（ UNION、INTERSECT、MINUS）、子查询（包括相关子查询）、窗口聚合、LIMIT（语法为Postgres）； SQL 参考中的更多详细信
- 本地和远程 JDBC 驱动程序； 见 [Avatica](https://calcite.apache.org/avatica/docs/index.html)
- 几个适配器

# 教程

This is a step-by-step tutorial that shows how to build and connect to Calcite. It uses a simple adapter that makes a directory of CSV files appear to be a schema containing tables. Calcite does the rest, and provides a full SQL interface.

Calcite-example-CSV is a fully functional adapter for Calcite that reads text files in CSV (comma-separated values) format. It is remarkable that a couple of hundred lines of Java code are sufficient to provide full SQL query capability.

CSV also serves as a template for building adapters to other data formats. Even though there are not many lines of code, it covers several important concepts:

- user-defined schema using SchemaFactory and Schema interfaces;
- declaring schemas in a model JSON file;
- declaring views in a model JSON file;
- user-defined table using the Table interface;
- determining the record type of a table;
- a simple implementation of Table, using the ScannableTable interface, that enumerates all rows directly;
- a more advanced implementation that implements FilterableTable, and can filter out rows according to simple predicates;
- advanced implementation of Table, using TranslatableTable, that translates to relational operators using planner rules.

## 下载和编译

您需要 Java（版本 8、9 或 10）和 Git。

```shell
$ git clone https://github.com/apache/calcite.git
$ cd calcite/example/csv
$ ./sqlline
```

## 第一个查询

现在让我们使用 [sqlline](https://github.com/julianhyde/sqlline) 连接到 Calcite，这是一个包含在这个项目中的 SQL shell。

```shell
$ ./sqlline
sqlline> !connect jdbc:calcite:model=src/test/resources/model.json admin admin
```

（如果您运行的是 Windows，则命令为 sqlline.bat）

执行元数据查询：

```
sqlline> !tables
+------------+--------------+-------------+---------------+----------+------+
| TABLE_CAT  | TABLE_SCHEM  | TABLE_NAME  |  TABLE_TYPE   | REMARKS  | TYPE |
+------------+--------------+-------------+---------------+----------+------+
| null       | SALES        | DEPTS       | TABLE         | null     | null |
| null       | SALES        | EMPS        | TABLE         | null     | null |
| null       | SALES        | HOBBIES     | TABLE         | null     | null |
| null       | metadata     | COLUMNS     | SYSTEM_TABLE  | null     | null |
| null       | metadata     | TABLES      | SYSTEM_TABLE  | null     | null |
+------------+--------------+-------------+---------------+----------+------+
```

> JDBC 专家注意：sqlline 的 `!tables` 命令只是在后台执行 [`DatabaseMetaData.getTables()`](https://docs.oracle.com/javase/7/docs/api/java/sql/DatabaseMetaData.html#getTables(java.lang.String,%20java.lang.String,%20java.lang.String,%20java.lang.String[]))。它还有其他命令来查询 JDBC 元数据，例如 `!columns` 和 `!describe`。

系统中有 5 个表：当前 `SALES` schema 中的表 `EMPS`、`DEPTS` 和 `HOBBIES`，系统元数据 schema 中的 `COLUMNS` 和 `TABLES`。系统表始终存在于 Calcite 中，但其它的表由特定实现的 Schema 提供；本例中，`EMPS` 和 `DEPTS` 表基于 `resources/sales` 目录中的 `EMPS.csv` 和 `DEPTS.csv` 文件。

对这些表执行一些查询，以表明 Calcite 提供了 SQL 的完整实现。 首先，表扫描：

```shell
sqlline> SELECT * FROM emps;
+--------+--------+---------+---------+----------------+--------+-------+---+
| EMPNO  |  NAME  | DEPTNO  | GENDER  |      CITY      | EMPID  |  AGE  | S |
+--------+--------+---------+---------+----------------+--------+-------+---+
| 100    | Fred   | 10      |         |                | 30     | 25    | t |
| 110    | Eric   | 20      | M       | San Francisco  | 3      | 80    | n |
| 110    | John   | 40      | M       | Vancouver      | 2      | null  | f |
| 120    | Wilma  | 20      | F       |                | 1      | 5     | n |
| 130    | Alice  | 40      | F       | Vancouver      | 2      | null  | f |
+--------+--------+---------+---------+----------------+--------+-------+---+
```

然后是 `Join` 和 `Group by`：

```shell
sqlline> SELECT d.name, COUNT(*)
. . . .> FROM emps AS e JOIN depts AS d ON e.deptno = d.deptno
. . . .> GROUP BY d.name;
+------------+---------+
|    NAME    | EXPR$1  |
+------------+---------+
| Sales      | 1       |
| Marketing  | 2       |
+------------+---------+
```

最后，`VALUES` 运算符生成单行，是测试表达式和 SQL 内置函数的便捷方法：

```shell
sqlline> VALUES CHAR_LENGTH('Hello, ' || 'world!');
+---------+
| EXPR$0  |
+---------+
| 13      |
+---------+
```

Calcite 有许多其他 SQL 特性。 我们没有时间在这里介绍它们。可以写一些查询来试验。

## Schema 发现

现在，Calcite 如何找到这些表？请记住，Calcite Core 对 CSV 文件一无所知。 作为**没有存储层的数据库**，Calcite 不知道任何文件格式。Calcite 之所以知道这些表，是因为我们告诉它运行 `calcite-example-csv` 项目中的代码。

这里有几个步骤。**首先**，我们在模型文件中的 <u>Schema 工厂类</u>内定义了 Schema 。**然后** <u>Schema 工厂</u>创建 Schema，Schema 创建几个表，每个表都知道如何通过扫描 CSV 文件获取数据。**最后**，在 Calcite 解析查询并计划它使用这些表之后，Calcite 在执行查询时调用这些表来读取数据。现在让我们更详细地了解这些步骤。

在 JDBC 连接字符串上，我们以 JSON 格式给出了模型的路径。 这是模型：

```json
{
  version: '1.0',
  defaultSchema: 'SALES',
  schemas: [
    {
      name: 'SALES',
      type: 'custom',
      factory: 'org.apache.calcite.adapter.csv.CsvSchemaFactory',
      operand: {
        directory: 'sales'
      }
    }
  ]
}
```

该模型定义了一个名为 `SALES` 的 Schema，它由插件类 [`CsvSchemaFactory`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvSchemaFactory.java) 提供支持，该类是 calcite-example-csv 项目的一部分，并实现了 Calcite [`SchemaFactory`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/SchemaFactory.html) 接口，其 `create` 方法实例化一个模式，从模型文件中传入目录参数：

```java
public Schema create(SchemaPlus parentSchema, String name,
    Map<String, Object> operand) {
  String directory = (String) operand.get("directory");
  String flavorName = (String) operand.get("flavor");
  CsvTable.Flavor flavor;
  if (flavorName == null) {
    flavor = CsvTable.Flavor.SCANNABLE;
  } else {
    flavor = CsvTable.Flavor.valueOf(flavorName.toUpperCase());
  }
  return new CsvSchema(new File(directory), flavor);
}
```

模型驱动下，模式工厂实例化了一个名为 `SALES` 的 Schema。 该 Schema 是 [`CsvSchema`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvSchema.java) 的一个实例，并实现了 Calcite [Schema 接口](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schema.html)。

Shcema 的工作是生成表的列表。它还可以列出子 schema 和**表函数**，但这些是高级功能，calcite-example-csv 不支持它们。表实现了 Calcite 的 [`Table` 接口](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Table.html)。CsvSchema 生成的表是 [`CsvTable`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvTable.java) 及其子类的实例。

这是来自 `CsvSchema` 的相关代码，覆盖了 `AbstractSchema` 基类中的 `getTableMap()` 方法。

```java
rotected Map<String, Table> getTableMap() {
  // Look for files in the directory ending in ".csv", ".csv.gz", ".json",
  // ".json.gz".
  File[] files = directoryFile.listFiles(
      new FilenameFilter() {
        public boolean accept(File dir, String name) {
          final String nameSansGz = trim(name, ".gz");
          return nameSansGz.endsWith(".csv")
              || nameSansGz.endsWith(".json");
        }
      });
  if (files == null) {
    System.out.println("directory " + directoryFile + " not found");
    files = new File[0];
  }
  // Build a map from table name to table; each file becomes a table.
  final ImmutableMap.Builder<String, Table> builder = ImmutableMap.builder();
  for (File file : files) {
    String tableName = trim(file.getName(), ".gz");
    final String tableNameSansJson = trimOrNull(tableName, ".json");
    if (tableNameSansJson != null) {
      JsonTable table = new JsonTable(file);
      builder.put(tableNameSansJson, table);
      continue;
    }
    tableName = trim(tableName, ".csv");
    final Table table = createTable(file);
    builder.put(tableName, table);
  }
  return builder.build();
}

/** 根据 flavor 属性创建不同的表子类型 **/
private Table createTable(File file) {
  switch (flavor) {
  case TRANSLATABLE:
    return new CsvTranslatableTable(file, null);
  case SCANNABLE:
    return new CsvScannableTable(file, null);
  case FILTERABLE:
    return new CsvFilterableTable(file, null);
  default:
    throw new AssertionError("Unknown flavor " + flavor);
  }
}
```

**Schema** 扫描目录并找到名称以 `.csv` 结尾的所有文件，并为它们创建表。本例中， `sales` 目录包含文件 `EMPS.csv` 和 `DEPTS.csv`，它们成为表 `EMPS` 和 `DEPTS`。

## Schema 中的表和视图

注意，**我们不需要在模型中定义任何表**； schema 自动生成表。除了自动创建的表之外，您还可以使用 Schema 的 `tables` 属性定义额外的表。

让我们看看如何创建视图，一个重要且有用的表类型。当您编写查询时，视图看起来像一张表，但它不存储数据。它通过执行查询获得结果。在优划查询时，会展开视图，因此查询优化器通常可以执行优化，比如从 `SELECT` 子句中删除最终结果中没有使用的表达式。

这是定义视图的 Schema：

```json
{
  version: '1.0',
  defaultSchema: 'SALES',
  schemas: [
    {
      name: 'SALES',
      type: 'custom',
      factory: 'org.apache.calcite.adapter.csv.CsvSchemaFactory',
      operand: {
        directory: 'sales'
      },
      tables: [
        {
          name: 'FEMALE_EMPS',
          type: 'view',
          sql: 'SELECT * FROM emps WHERE gender = \'F\''
        }
      ]
    }
  ]
}
```

`type:'view'` 将 `FEMALE_EMPS` 标记为视图，而不是常规的表或者自定义的表。注意，视图定义中的单引号使用反斜杠转义，这是 JSON 的正常方式。JSON 并不便于写长字符串，因此 Calcite 支持另一种语法。如果创建视图是一个很长的 SQL ，可以写成多行：

```java
{
  name: 'FEMALE_EMPS',
  type: 'view',
  sql: [
    'SELECT * FROM emps',
    'WHERE gender = \'F\''
  ]
}
```

现在我们已经定义了一个视图，我们可以在查询中使用它，就像它是一个表一样：

```shell
sqlline> SELECT e.name, d.name FROM female_emps AS e JOIN depts AS d on e.deptno = d.deptno;
+--------+------------+
|  NAME  |    NAME    |
+--------+------------+
| Wilma  | Marketing  |
+--------+------------+
```

## 自定以表

自定义表是由用户代码实现的表，不需要在自定义 Schema 的中定义它们。在 `model-with-custom-table.json` 中有一个例子:

```json
{
  version: '1.0',
  defaultSchema: 'CUSTOM_TABLE',
  schemas: [
    {
      name: 'CUSTOM_TABLE',
      tables: [
        {
          name: 'EMPS',
          type: 'custom',
          factory: 'org.apache.calcite.adapter.csv.CsvTableFactory',
          operand: {
            file: 'sales/EMPS.csv.gz',
            flavor: "scannable"
          }
        }
      ]
    }
  ]
}
```

我们可以用通常的方式查询表：

```shell
sqlline> !connect jdbc:calcite:model=src/test/resources/model-with-custom-table.json admin admin
sqlline> SELECT empno, name FROM custom_table.emps;
+--------+--------+
| EMPNO  |  NAME  |
+--------+--------+
| 100    | Fred   |
| 110    | Eric   |
| 110    | John   |
| 120    | Wilma  |
| 130    | Alice  |
+--------+--------+
```

这是一个常规 Schema，并包含一个由 [`CsvTableFactory`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvTableFactory.java) 支持的自定义表，它实现了 Calcite [TableFactory](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/TableFactory.html) 接口。 它的 `create` 方法实例化一个 `CsvScannableTable`，`file` 参数从模型文件中传入：

```java
public CsvTable create(SchemaPlus schema, String name,
    Map<String, Object> map, RelDataType rowType) {
  String fileName = (String) map.get("file");
  final File file = new File(fileName);
  final RelProtoDataType protoRowType =
      rowType != null ? RelDataTypeImpl.proto(rowType) : null;
  return new CsvScannableTable(file, protoRowType);
}
```

实现自定义表通常是实现自定义 Schema 更简单的替代方法。这两种方法最终可能会创建 `Table` 接口的类似实现，对于自定义表，您不需要实现**<u>元数据发现</u>**。`CsvTableFactory` 创建一个 `CsvScannableTable`，就像 `CsvSchema` 一样，但<u>**表实现**</u>不会扫描文件系统以查找 `.csv` 文件。

自定义表需要模型文件的作者做更多的工作（作者需要明确指定每个表及其文件），但也给作者更多的控制权（例如，为每个表提供不同的参数）。

## 模型文件的注释

模型文件可以使用 /* ... */ 和 // 语法包含注释：

```json
{
  version: '1.0',
  /* Multi-line
     comment. */
  defaultSchema: 'CUSTOM_TABLE',
  // Single-line comment.
  schemas: [
    ..
  ]
}
```

注释不是标准的 JSON，而是一种无害的扩展。

## 使用优化器规则优化查询

只要表不包含大量数据，我们目前看到的表实现就可以了。但是，如果你客户的表有一百列和一百万行，那你肯定希望你的系统每次查询不要检索所有数据。您希望 Calcite 与适配器协商并找到一种更有效的数据访问方式。

这种协商是查询优化的一种简单形式。Calcite 通过添加优化器规则来支持查询优化。优化器规则通过在查询解析树中查找某种模式（例如某种表顶部的 `Project`）来操作，并用一组新的、实现了优化的节点替换树中匹配的节点。

就像 Schema 和表一样，优化器规则也是可扩展的。因此，如果您有一个要通过 SQL 访问的数据存储，则首先定义自定义表或 Schema·，然后定义一些规则以提高访问效率。

要查看实际效果，让我们使用优化器规则访问 CSV 文件中的列子集。我们对两个非常相似的模式运行相同的查询：

```json
sqlline> !connect jdbc:calcite:model=src/test/resources/model.json admin admin
sqlline> explain plan for select name from emps;
+-----------------------------------------------------+
| PLAN                                                |
+-----------------------------------------------------+
| EnumerableCalcRel(expr#0..9=[{inputs}], NAME=[$t1]) |
|   EnumerableTableScan(table=[[SALES, EMPS]])        |
+-----------------------------------------------------+
sqlline> !connect jdbc:calcite:model=src/test/resources/smart.json admin admin
sqlline> explain plan for select name from emps;
+-----------------------------------------------------+
| PLAN                                                |
+-----------------------------------------------------+
| EnumerableCalcRel(expr#0..9=[{inputs}], NAME=[$t1]) |
|   CsvTableScan(table=[[SALES, EMPS]])               |
+-----------------------------------------------------+
```

是什么导致执行计划上的差异？让我们跟着证据的线索走，在 `smart.json` 模型文件中，只有一行：

```json
flavor: "translatable"
```

这会导致创建一个带有 `flavor = TRANSLATABLE` 的 `CsvSchema`，并且它的 `createTable` 方法创建 `CsvTranslatableTable` 而不是 `CsvScannableTable` 的实例。

`CsvTranslatableTable` 实现 `TranslatableTable.toRel()` 方法来创建 `CsvTableScan`。 表扫描是查询运算符树的叶节点。 通常的实现是 `EnumerableTableScan`，但我们创建了一个独特的子类型，这将触发规则。

这是完整的规则：

```java
public class CsvProjectTableScanRule
    extends RelRule<CsvProjectTableScanRule.Config> {
  /** Creates a CsvProjectTableScanRule. */
  protected CsvProjectTableScanRule(Config config) {
    super(config);
  }

  @Override public void onMatch(RelOptRuleCall call) {
    final LogicalProject project = call.rel(0);
    final CsvTableScan scan = call.rel(1);
    int[] fields = getProjectFields(project.getProjects());
    if (fields == null) {
      // Project contains expressions more complex than just field references.
      return;
    }
    call.transformTo(
        new CsvTableScan(
            scan.getCluster(),
            scan.getTable(),
            scan.csvTable,
            fields));
  }

  private int[] getProjectFields(List<RexNode> exps) {
    final int[] fields = new int[exps.size()];
    for (int i = 0; i < exps.size(); i++) {
      final RexNode exp = exps.get(i);
      if (exp instanceof RexInputRef) {
        fields[i] = ((RexInputRef) exp).getIndex();
      } else {
        return null; // not a simple projection
      }
    }
    return fields;
  }

  /** Rule configuration. */
  public interface Config extends RelRule.Config {
    Config DEFAULT = EMPTY
        .withOperandSupplier(b0 ->
            b0.operand(LogicalProject.class).oneInput(b1 ->
                b1.operand(CsvTableScan.class).noInputs()))
        .as(Config.class);

    @Override default CsvProjectTableScanRule toRule() {
      return new CsvProjectTableScanRule(this);
    }
}
```

规则的默认实例驻留在 `CsvRules` 持有者类中：

```java
public abstract class CsvRules {
  public static final CsvProjectTableScanRule PROJECT_SCAN =
      CsvProjectTableScanRule.Config.DEFAULT.toRule();
}
```

在默认配置（ `Config` 接口中 `DEFAULT` 字段）中对 `withOperandSupplier` 方法的调用，声明了触发规则的关系表达式模式。如果规划器看到一个 `LogicalProject`，它的唯一输入是一个没有输入的 `CsvTableScan`，就会调用该规则。

规则的是可变的。例如，不同的规则实例可能与 `CsvTableScan` 上的 `EnumerableProject` 匹配。`onMatch` 方法生成一个新的关系表达式并调用 [`RelOptRuleCall.transformTo()`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/RelOptRuleCall.html#transformTo(org.apache.calcite.rel.RelNode)) 以指示规则已成功触发。

## 查询优化过程

关于 Calcite 的查询优化器有多聪明可以说很多，但我们不在这里说。这种聪明的设计是为了减轻你，即优化规则作者的负担。

**首先**，Calcite 不会按照规定的顺序触发规则。优化查询分支树中的各种分支，就像下棋程序检查许多可能的移动序列一样。如果规则 A 和 B 都匹配查询运算符树的给定部分，则 Calcite 可以同时触发。

**其次**，Calcite 使用成本选择计划，但成本模型并不能阻止规则的触发，这在短期内似乎更昂贵。

许多优化器都有一个线性优化方案。如上所述，面对规则 A 和规则 B 之间的选择，这样的优化器需要立即做出选择。它可能有这样的策略：将规则 A 应用于整棵树，然后将规则 B 应用于整棵树，或者应用基于成本的策略，应用生成成本更低结果的规则。

Calcite 不需要这样的妥协。这使得组合各种规则集变得简单。如果，假设您想将识别物化视图的规则与从 CSV 和 JDBC 源系统读取的规则结合起来，您只需将所有规则的集合提供给 Calcite，并告诉它进行操作。

Calcite 确实使用成本模型。成本模型决定最终使用哪个计划，有时裁剪搜索树以防止搜索空间爆炸，但它从不强迫您在规则 A 和规则 B 之间进行选择。这很重要，因为它避免<u>陷入局部最优，但在实际上不是最优的搜索空间</u>。

此外（您已经猜到了）成本模型是可插入的，它所基于的表和查询运算符统计也是如此，但这可以以后再谈。

## JDBC 适配器

JDBC 适配器将 JDBC 数据源中的 Schema 映射为 ==Calcite Schema==。例如，这个 Schema 从 MySQL foodmart 数据库中读取：

```json
{
  version: '1.0',
  defaultSchema: 'FOODMART',
  schemas: [
    {
      name: 'FOODMART',
      type: 'custom',
      factory: 'org.apache.calcite.adapter.jdbc.JdbcSchema$Factory',
      operand: {
        jdbcDriver: 'com.mysql.jdbc.Driver',
        jdbcUrl: 'jdbc:mysql://localhost/foodmart',
        jdbcUser: 'foodmart',
        jdbcPassword: 'foodmart'
      }
    }
  ]
```

使用过 Mondrian OLAP 引擎的人应该比较熟悉 **FoodMart** 数据库，因为它是 Mondrian 的主要测试数据集。要加载数据集，请按照 Mondrian 的安装说明进行操作。

**当前限制**：JDBC 适配器当前只下推表扫描操作； 所有其他处理（过滤、连接、聚合等）都发生在 Calcite 中。我们的目标是**将**尽可能多的处理，如翻译语法、数据类型和内置函数等推入源系统。如果 Calcite 查询基于来自单个 JDBC 数据库的表，原则上整个查询应该转到该数据库。如果表来自多个 JDBC 源，或者 JDBC 和非 JDBC 的混合，Calcite 将尽可能使用最有效的分布式查询方法。

## 克隆 JDBC 适配器

克隆的 JDBC 适配器会创建一个混合数据库。数据来自 JDBC 数据库，但每个表在第一次访问时，会被读入内存表。Calcite 基于这些内存表响应查询，实际上是数据库的缓存。

例如，以下模型从 MySQL foodmart 数据库读取表：

```json
{
  version: '1.0',
  defaultSchema: 'FOODMART_CLONE',
  schemas: [
    {
      name: 'FOODMART_CLONE',
      type: 'custom',
      factory: 'org.apache.calcite.adapter.clone.CloneSchema$Factory',
      operand: {
        jdbcDriver: 'com.mysql.jdbc.Driver',
        jdbcUrl: 'jdbc:mysql://localhost/foodmart',
        jdbcUser: 'foodmart',
        jdbcPassword: 'foodmart'
      }
    }
  ]
}
```

另一种技术是在现有 Schema 上克隆 Schema。可以使用 `source` 属性来引用模型中先前定义的 schema，如下所示：

```json
{
  version: '1.0',
  defaultSchema: 'FOODMART_CLONE',
  schemas: [
    {
      name: 'FOODMART',
      type: 'custom',
      factory: 'org.apache.calcite.adapter.jdbc.JdbcSchema$Factory',
      operand: {
        jdbcDriver: 'com.mysql.jdbc.Driver',
        jdbcUrl: 'jdbc:mysql://localhost/foodmart',
        jdbcUser: 'foodmart',
        jdbcPassword: 'foodmart'
      }
    },
    {
      name: 'FOODMART_CLONE',
      type: 'custom',
      factory: 'org.apache.calcite.adapter.clone.CloneSchema$Factory',
      operand: {
        source: 'FOODMART'
      }
    }
  ]
}
```

您可以使用这种方法在任何类型的 Scheam 上克隆 Schama，而不仅仅是 JDBC。

克隆适配器并不是万能的。我们计划开发更复杂的缓存策略，以及更完整和更高效的内存表实现，但现在克隆 JDBC 适配器展示了可能的内容，并允许我们尝试我们的初始实现。

## 后续话题

还有许多扩展 Calcite 的方法本教程没描述。[适配器规范](https://calcite.apache.org/docs/adapter.html)描述了所涉及的 API。

# 代数

> Relational algebra is at the heart of Calcite. Every query is represented as **a tree of relational operators**. You can translate from SQL to relational algebra, or you can build the tree directly.
>
> Planner rules transform expression trees using mathematical identities that preserve semantics. For example, it is valid to push a filter into an input of an inner join if the filter does not reference columns from the other input.
>
> Calcite optimizes queries by repeatedly applying planner rules to a relational expression. A cost model guides the process, and the planner engine generates an alternative expression that has the same semantics as the original but a lower cost.
>
> The planning process is extensible. You can add your own relational operators, planner rules, cost model, and statistics.

关系代数是 Calcite 的核心。 每个查询都表示为**关系运算符树**。 您可以从 SQL 转换为关系代数，也可以直接构建树。

**规划器规则**使用<u>保留语义的数学恒等式</u>来转换表达式树。 例如，如果 `Filter` 中不引用其他输入中的列，则将 `Filter` 推入 `Inner join` 的输入是有效的。

Calcite 通过将规划器规则重复应用于关系表达式来优化查询。成本模型指导该过程，规划器引擎生成与原始语义相同但成本较低的替代表达式。

规划过程是可扩展的。 您可以添加自己的**关系运算符**、**规划器规则**、**成本模型**和**统计信息**。

## Algebra builder

> The simplest way to build a relational expression is to use the **algebra builder**, [RelBuilder](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.html). Here is an example:

构建关系表达式的最简单方法是使用**代数构建器** [RelBuilder](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.html)。 下面是一个例子：

### `TableScan`

```java
final FrameworkConfig config;
final RelBuilder builder = RelBuilder.create(config);
final RelNode node = builder
  .scan("EMP")
  .build();
System.out.println(RelOptUtil.toString(node));
```

(您可以在 [RelBuilderExample.java](https://github.com/apache/calcite/blob/master/core/src/test/java/org/apache/calcite/examples/RelBuilderExample.java) 中找到此示例和其他示例的完整代码)，代码输出:

```java
LogicalTableScan(table=[[scott, EMP]])
```

它创建了对 `EMP` 表的扫描； 相当于如下的 SQL：

```sql
SELECT *
FROM scott.EMP;
```

### Adding a `Project`

现在，让我们添加一个 `Project`，相当于

```sql
SELECT ename, deptno
FROM scott.EMP;
```

我们只是在调用 `build` 之前添加对 `project` 方法的调用：

```java
final RelNode node = builder
  .scan("EMP")
  .project(builder.field("DEPTNO"), builder.field("ENAME"))
  .build();
System.out.println(RelOptUtil.toString(node));
```

输出是

```
LogicalProject(DEPTNO=[$7], ENAME=[$1])
  LogicalTableScan(table=[[scott, EMP]])
```

> The two calls to `builder.field` create simple expressions that return the fields from the input relational expression, namely the `TableScan` created by the `scan` call.
>
> Calcite has converted them to field references by ordinal, `$7` and `$1`.
>

对 `builder.field` 的两次调用创建了<u>==从输入关系表达式返回字段的==</u>简单表达式，即由 `scan` 调用创建的 `TableScan`。

Calcite 已将它们转换为按序数，即 `$7` 和 `$1` 这样的字段引用。

### Adding a Filter and Aggregate

带有 `Aggregate` 和  `Filter` 的查询：

```java
final RelNode node = builder
  .scan("EMP")
  .aggregate(builder.groupKey("DEPTNO"),
      builder.count(false, "C"),
      builder.sum(false, "S", builder.field("SAL")))
  .filter(
      builder.call(SqlStdOperatorTable.GREATER_THAN,
          builder.field("C"),
          builder.literal(10)))
  .build();
System.out.println(RelOptUtil.toString(node));
```

等价于如下的 SQL：

```SQL
SELECT deptno, count(*) AS c, sum(sal) AS s
FROM emp
GROUP BY deptno
HAVING count(*) > 10
```

输出是

```
LogicalFilter(condition=[>($1, 10)])
  LogicalAggregate(group=[{7}], C=[COUNT()], S=[SUM($5)])
    LogicalTableScan(table=[[scott, EMP]])
```

### Push and pop

> The builder uses a stack to store the relational expression produced by one step and pass it as an input to the next step. <u>==This allows the methods that produce relational expressions to produce a builder==</u>.
>
> Most of the time, the only stack method you will use is `build()`, to get the last relational expression, namely the root of the tree.
>
> Sometimes the stack becomes so deeply nested it gets confusing. To keep things straight, you can remove expressions from the stack. For example, here we are building a bushy join:

**构建器**使用堆栈来存储由每个步骤生成的关系表达式，并将其作为输入传递给下一步。<u>==这允许生成关系表达式的方法生成构建器==</u>。

大多数情况下，您唯一使用的堆栈方法是 `build()`，以获取最后一个关系表达式，即树的根。

有时堆栈会嵌套得如此之深，以至于令人困惑。为了保持简洁，可以从堆栈中删除表达式。例如，这里我们正在构建一个 `bushy join`：

```
.
               join
             /      \
        join          join
      /      \      /      \
CUSTOMERS ORDERS LINE_ITEMS PRODUCTS
```

> We build it in three stages. Store the intermediate results in variables `left` and `right`, and use `push()` to put them back on the stack when it is time to create the final `Join`:

分三个阶段进行构建。 将中间结果存储在变量 `left` 和 `right` 中，并在创建最终 `Join` 时使用 `push()` 将它们放回堆栈中：

```java
final RelNode left = builder
  .scan("CUSTOMERS")
  .scan("ORDERS")
  .join(JoinRelType.INNER, "ORDER_ID")
  .build();

final RelNode right = builder
  .scan("LINE_ITEMS")
  .scan("PRODUCTS")
  .join(JoinRelType.INNER, "PRODUCT_ID")
  .build();

final RelNode result = builder
  .push(left)
  .push(right)
  .join(JoinRelType.INNER, "ORDER_ID")
  .build();
```

### Switch Convention

> The default `RelBuilder` creates logical `RelNode` without coventions. But you could switch to use a different convention through `adoptConvention()`:

默认的 `RelBuilder` 创建了没有**约定**的逻辑 `RelNode`。 但是你可以通过 `adoptConvention()` 切换到使用不同的**约定**：


```java
final RelNode result = builder
  .push(input)
  .adoptConvention(EnumerableConvention.INSTANCE)
  .sort(toCollation)
  .build();
```

> In this case, we create an `EnumerableSort` on top of the input `RelNode`.

在本例中，我们在输入 `RelNode` 的顶部创建一个 `EnumerableSort`。

> Calling Convention 可以理解为一个特定数据引擎协议，拥有相同 Convention 的算子可以认为都是统一个数据引擎的算子可以相互连接起来

### Field names and ordinals（字段名和序数）

> You can reference a field by name or ordinal.
>
> Ordinals are zero-based. Each operator guarantees the order in which its output fields occur. For example, `Project` returns the fields generated by each of the scalar expressions.
>
> The field names of an operator are guaranteed to be unique, but sometimes that means that the names are not exactly what you expect. For example, when you join `EMP` to `DEPT`, one of the output fields will be called `DEPTNO` and another will be called something like `DEPTNO_1`.
>
> Some relational expression methods give you more control over field names:
>
> - `project` lets you wrap expressions using `alias(expr, fieldName)`. It removes the wrapper but keeps the suggested name (as long as it is unique).
> - `values(String[] fieldNames, Object... values)` accepts an array of field names. If any element of the array is null, the builder will generate a unique name.
>
> If an expression projects an input field, or a cast of an input field, it will use the name of that input field.
>
> **Once the unique field names have been assigned, the names are immutable. If you have a particular `RelNode` instance, you can rely on the field names not changing. In fact, the whole relational expression is immutable.**
>
> But if a relational expression has passed through several rewrite rules (see [RelOptRule](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/RelOptRule.html)), the field names of the resulting expression might not look much like the originals. At that point it is better to reference fields by ordinal.
>
> When you are building a relational expression that accepts multiple inputs, you need to build field references that take that into account. This occurs most often when building join conditions.
>
> Suppose you are building a join on `EMP`, which has 8 fields `[EMPNO, ENAME, JOB, MGR, HIREDATE, SAL, COMM, DEPTNO]` and `DEPT`, which has 3 fields [DEPTNO, DNAME, LOC]. Internally, Calcite represents those fields as offsets into a combined input row with 11 fields: the first field of the left input is field #0 (0-based, remember), and the first field of the right input is field #8.
>
> But through the builder API, you specify which field of which input. To reference `SAL`, internal field #5, write `builder.field(2, 0, "SAL")`, `builder.field(2, "EMP", "SAL")`, or `builder.field(2, 0, 5)`. This means “the field #5 of input #0 of two inputs”. <u>**(Why does it need to know that there are two inputs? Because they are stored on the stack; input #1 is at the top of the stack, and input #0 is below it. If we did not tell the builder that were two inputs, it would not know how deep to go for input #0**</u>.)
>
> Similarly, to reference “DNAME”, internal field #9 (8 + 1), write `builder.field(2, 1, "DNAME")`, `builder.field(2, "DEPT", "DNAME")`, or `builder.field(2, 1, 1)`.
>

可以按名称或序号引用字段。

序数是从零开始的。每个运算符保证<u>其输出字段出现的</u>顺序。 例如，`Project` 返回由每个<u>**标量表达式**</u>生成的字段。

运算符的字段名称保证是唯一的，**但有时这意味着名称并不完全符合您的预期**。 例如，当您关联 `EMP` 和 `DEPT` 时，其中一个输出字段将被称为 `DEPTNO`，另一个将被称为 `DEPTNO_1` 之类的内容。

一些关系表达式方法可以让您更好地控制字段名称：

- `project` 允许你使用 `alias(expr, fieldName)` 来包装表达式。它删除包装器但保留建议的名称（只要它唯一）。

- `values(String[] fieldNames, Object... values)` 接受一个字段名称数组。如果数组的任何元素为空，构建器将生成一个唯一的名称。

如果表达式**投影输入字段**或强制转换输入字段，则使用输入字段的名称。

一旦为字段分配了唯一的名称，这些名称就是不可变的。如果你有一个特定的 `RelNode` 实例，你可以依赖字段名称不变。事实上，整个关系表达式是不可变的。

但是如果一个关系表达式已经通过了几个重写规则（参见 [RelOptRule](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/RelOptRule.html)），结果表达式的字段名称可能看起来不像原版。此时最好按序数引用字段。

当您构建接受多个输入的关系表达式时，您需要构建考虑多个输入的字段引用。这在构建 `Join` 条件时最常见。

假设在有 8 个字段 `[EMPNO、ENAME、JOB、MGR、HIREDATE、SAL、COMM、DEPTNO]` 的 `EMP` 和有 3 个字段 `[DEPTNO、DNAME、LOC]` 的 `DEPT`上构建 `Join`。在 Calcite 内部，这些字段表示为具有 11 个字段的组合输入行的偏移量：左侧输入的第一个字段是字段 `#0`（记住，从 0 开始），右侧输入的第一个字段是字段 `#8`。

但是通过构建器 API，可以指定哪个输入的哪个字段。要引用 `SAL`，内部字段为 `#5`，则编写 `builder.field(2, 0, "SAL")`、`builder.field(2, "EMP", "SAL")` 或 `builder.field( 2, 0, 5)`，**这表示两个输入中，输入 `#0` 的字段 `#5`**。（**<u>为什么它需要知道有两个输入？因为它们存储在堆栈中；输入 `#1` 位于堆栈顶部，输入 `#0` 在其下方。如果我们不告诉构建器有两个输入，它不知道输入 #0 的深度</u>**）。

类似地，要引用 `DNAME`，内部字段为 `#9` (8 + 1)，则编写 `builder.field(2, 1, "DNAME")`, `builder.field(2, "DEPT", "DNAME")` ，或`builder.field(2, 1, 1)`。

### Recursive Queries

> Warning: The current API is experimental and subject to change without notice. A SQL recursive query, e.g. this one that generates the sequence 1, 2, 3, …10:

警告：当前API是实验性的，如有更改，恕不另行通知。**递归 SQL 查询**，例如，此查询生成序列1、2、3、…10：

```sql
WITH RECURSIVE aux(i) AS (
  VALUES (1)
  UNION ALL
  SELECT i+1 FROM aux WHERE i < 10
)
SELECT * FROM aux
```

> can be generated using a scan on a `TransientTable` and a `RepeatUnion`:

可以使用对 `TransientTable` 和 `RepeatUnion` 的扫描生成：

```java
final RelNode node = builder
  .values(new String[] { "i" }, 1)
  .transientScan("aux")
  .filter(
      builder.call(
          SqlStdOperatorTable.LESS_THAN,
          builder.field(0),
          builder.literal(10)))
  .project(
      builder.call(
          SqlStdOperatorTable.PLUS,
          builder.field(0),
          builder.literal(1)))
  .repeatUnion("aux", true)
  .build();
System.out.println(RelOptUtil.toString(node));
```

输出:

```
LogicalRepeatUnion(all=[true])
  LogicalTableSpool(readType=[LAZY], writeType=[LAZY], tableName=[aux])
    LogicalValues(tuples=[[{ 1 }]])
  LogicalTableSpool(readType=[LAZY], writeType=[LAZY], tableName=[aux])
    LogicalProject($f0=[+($0, 1)])
      LogicalFilter(condition=[<($0, 10)])
        LogicalTableScan(table=[[aux]])
```

### API summary ( API 摘要)

#### Relational operators（关系运算符）

> The following methods create a relational expression ([RelNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelNode.html)), push it onto the stack, and return the `RelBuilder`.

以下方法创建关系表达式（[RelNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelNode.html)），将其压入堆栈，并返回`RelBuilder` .

| METHOD                                                       | DESCRIPTION                                                  |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| `scan(tableName)`                                            | Creates a [TableScan](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableScan.html). |
| `functionScan(operator, n, expr...)` `functionScan(operator, n, exprList)` | Creates a [TableFunctionScan](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableFunctionScan.html) of the `n` most recent relational expressions. |
| `transientScan(tableName [, rowType])`                       | Creates a [TableScan](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableScan.html) on a [TransientTable](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/TransientTable.html) with the given type (if not specified, the most recent relational expression’s type will be used). |
| `values(fieldNames, value...)` `values(rowType, tupleList)`  | Creates a [Values](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Values.html). |
| `filter([variablesSet, ] exprList)` `filter([variablesSet, ] expr...)` | Creates a [Filter](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Filter.html) over the AND of the given predicates; if `variablesSet` is specified, the predicates may reference those variables. |
| `project(expr...)` `project(exprList [, fieldNames])`        | Creates a [Project](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Project.html). To override the default name, wrap expressions using `alias`, or specify the `fieldNames` argument. |
| `projectPlus(expr...)` `projectPlus(exprList)`               | Variant of `project` that keeps original fields and appends the given expressions. |
| `projectExcept(expr...)` `projectExcept(exprList)`           | Variant of `project` that keeps original fields and removes the given expressions. |
| `permute(mapping)`                                           | Creates a [Project](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Project.html) that permutes the fields using `mapping`. |
| `convert(rowType [, rename])`                                | Creates a [Project](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Project.html) that converts the fields to the given types, optionally also renaming them. |
| `aggregate(groupKey, aggCall...)` `aggregate(groupKey, aggCallList)` | Creates an [Aggregate](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Aggregate.html). |
| `distinct()`                                                 | Creates an [Aggregate](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Aggregate.html) that eliminates duplicate records. |
| `pivot(groupKey, aggCalls, axes, values)`                    | Adds a pivot operation, implemented by generating an [Aggregate](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Aggregate.html) with a column for each combination of measures and values |
| `unpivot(includeNulls, measureNames, axisNames, axisMap)`    | Adds an unpivot operation, implemented by generating a [Join](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Join.html) to a [Values](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Values.html) that converts each row to several rows |
| `sort(fieldOrdinal...)` `sort(expr...)` `sort(exprList)`     | Creates a [Sort](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Sort.html).  In the first form, field ordinals are 0-based, and a negative ordinal indicates descending; for example, -2 means field 1 descending.  In the other forms, you can wrap expressions in `as`, `nullsFirst` or `nullsLast`. |
| `sortLimit(offset, fetch, expr...)` `sortLimit(offset, fetch, exprList)` | Creates a [Sort](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Sort.html) with offset and limit. |
| `limit(offset, fetch)`                                       | Creates a [Sort](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Sort.html) that does not sort, only applies with offset and limit. |
| `exchange(distribution)`                                     | Creates an [Exchange](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Exchange.html). |
| `sortExchange(distribution, collation)`                      | Creates a [SortExchange](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/SortExchange.html). |
| `correlate(joinType, correlationId, requiredField...)` `correlate(joinType, correlationId, requiredFieldList)` | Creates a [Correlate](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Correlate.html) of the two most recent relational expressions, with a variable name and required field expressions for the left relation. |
| `join(joinType, expr...)` `join(joinType, exprList)` `join(joinType, fieldName...)` | Creates a [Join](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Join.html) of the two most recent relational expressions.  The first form joins on a boolean expression (multiple conditions are combined using AND).  The last form joins on named fields; each side must have a field of each name. |
| `semiJoin(expr)`                                             | Creates a [Join](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Join.html) with SEMI join type of the two most recent relational expressions. |
| `antiJoin(expr)`                                             | Creates a [Join](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Join.html) with ANTI join type of the two most recent relational expressions. |
| `union(all [, n])`                                           | Creates a [Union](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Union.html) of the `n` (default two) most recent relational expressions. |
| `intersect(all [, n])`                                       | Creates an [Intersect](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Intersect.html) of the `n` (default two) most recent relational expressions. |
| `minus(all)`                                                 | Creates a [Minus](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Minus.html) of the two most recent relational expressions. |
| `repeatUnion(tableName, all [, n])`                          | Creates a [RepeatUnion](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/RepeatUnion.html) associated to a [TransientTable](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/TransientTable.html) of the two most recent relational expressions, with `n` maximum number of iterations (default -1, i.e. no limit). |
| `snapshot(period)`                                           | Creates a [Snapshot](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Snapshot.html) of the given snapshot period. |
| `match(pattern, strictStart,` `strictEnd, patterns, measures,` `after, subsets, allRows,` `partitionKeys, orderKeys,` `interval)` | Creates a [Match](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Match.html). |

Argument types:

- `expr`, `interval` [RexNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexNode.html)
- `expr...`, `requiredField...` Array of [RexNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexNode.html)
- `exprList`, `measureList`, `partitionKeys`, `orderKeys`, `requiredFieldList` Iterable of [RexNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexNode.html)
- `fieldOrdinal` Ordinal of a field within its row (starting from 0)
- `fieldName` Name of a field, unique within its row
- `fieldName...` Array of String
- `fieldNames` Iterable of String
- `rowType` [RelDataType](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/type/RelDataType.html)
- `groupKey` [RelBuilder.GroupKey](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.GroupKey.html)
- `aggCall...` Array of [RelBuilder.AggCall](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.AggCall.html)
- `aggCallList` Iterable of [RelBuilder.AggCall](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.AggCall.html)
- `value...` Array of Object
- `value` Object
- `tupleList` Iterable of List of [RexLiteral](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexLiteral.html)
- `all`, `distinct`, `strictStart`, `strictEnd`, `allRows` boolean
- `alias` String
- `correlationId` [CorrelationId](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/CorrelationId.html)
- `variablesSet` Iterable of [CorrelationId](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/CorrelationId.html)
- `varHolder` [Holder](https://calcite.apache.org/javadocAggregate/org/apache/calcite/util/Holder.html) of [RexCorrelVariable](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexCorrelVariable.html)
- `patterns` Map whose key is String, value is [RexNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexNode.html)
- `subsets` Map whose key is String, value is a sorted set of String
- `distribution` [RelDistribution](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelDistribution.html)
- `collation` [RelCollation](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelCollation.html)
- `operator` [SqlOperator](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/SqlOperator.html)
- `joinType` [JoinRelType](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/JoinRelType.html)

The builder methods perform various optimizations, including:

- `project` returns its input if asked to project all columns in order
- `filter` flattens the condition (so an `AND` and `OR` may have more than 2 children), simplifies (converting say `x = 1 AND TRUE` to `x = 1`)
- If you apply `sort` then `limit`, the effect is as if you had called `sortLimit`

There are annotation methods that add information to the top relational expression on the stack:

| METHOD                | DESCRIPTION                                                  |
| :-------------------- | :----------------------------------------------------------- |
| `as(alias)`           | Assigns a table alias to the top relational expression on the stack |
| `variable(varHolder)` | Creates a correlation variable referencing the top relational expression |

#### Stack methods

| METHOD                | DESCRIPTION                                                  |
| :-------------------- | :----------------------------------------------------------- |
| `build()`             | Pops the most recently created relational expression off the stack |
| `push(rel)`           | Pushes a relational expression onto the stack. Relational methods such as `scan`, above, call this method, but user code generally does not |
| `pushAll(collection)` | Pushes a collection of relational expressions onto the stack |
| `peek()`              | Returns the relational expression most recently put onto the stack, but does not remove it |

#### Scalar expression methods

> `RexNode`：行表达式
>每个行表达式都有一个类型（与 `SqlNode` 相比，因为 `SqlNode` 是在验证前创建，所以其类型可能不可用）。
>
> 一些常见的行表达式是：`RexLiteral`（常量值）、`RexVariable`（变量）、`RexCall`（使用操作数调用运算符）。 表达式通常是使用 `RexBuilder` 工厂创建。
>
> `RexNode` 的所有子类都是不可变的。

The following methods return a scalar expression ([RexNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rex/RexNode.html)).

Many of them use the contents of the stack. For example, `field("DEPTNO")` returns a reference to the “DEPTNO” field of the relational expression just added to the stack.

| METHOD                                                       | DESCRIPTION                                                  |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| `literal(value)`                                             | Constant                                                     |
| `field(fieldName)`                                           | Reference, by name, to a field of the top-most relational expression |
| `field(fieldOrdinal)`                                        | Reference, by ordinal, to a field of the top-most relational expression |
| `field(inputCount, inputOrdinal, fieldName)`                 | Reference, by name, to a field of the (`inputCount` - `inputOrdinal`)th relational expression |
| `field(inputCount, inputOrdinal, fieldOrdinal)`              | Reference, by ordinal, to a field of the (`inputCount` - `inputOrdinal`)th relational expression |
| `field(inputCount, alias, fieldName)`                        | Reference, by table alias and field name, to a field at most `inputCount - 1` elements from the top of the stack |
| `field(alias, fieldName)`                                    | Reference, by table alias and field name, to a field of the top-most relational expressions |
| `field(expr, fieldName)`                                     | Reference, by name, to a field of a record-valued expression |
| `field(expr, fieldOrdinal)`                                  | Reference, by ordinal, to a field of a record-valued expression |
| `fields(fieldOrdinalList)`                                   | List of expressions referencing input fields by ordinal      |
| `fields(mapping)`                                            | List of expressions referencing input fields by a given mapping |
| `fields(collation)`                                          | List of expressions, `exprList`, such that `sort(exprList)` would replicate collation |
| `call(op, expr...)` `call(op, exprList)`                     | Call to a function or operator                               |
| `and(expr...)` `and(exprList)`                               | Logical AND. Flattens nested ANDs, and optimizes cases involving TRUE and FALSE. |
| `or(expr...)` `or(exprList)`                                 | Logical OR. Flattens nested ORs, and optimizes cases involving TRUE and FALSE. |
| `not(expr)`                                                  | Logical NOT                                                  |
| `equals(expr, expr)`                                         | Equals                                                       |
| `isNull(expr)`                                               | Checks whether an expression is null                         |
| `isNotNull(expr)`                                            | Checks whether an expression is not null                     |
| `alias(expr, fieldName)`                                     | Renames an expression (only valid as an argument to `project`) |
| `cast(expr, typeName)` `cast(expr, typeName, precision)` `cast(expr, typeName, precision, scale)` | Converts an expression to a given type                       |
| `desc(expr)`                                                 | Changes sort direction to descending (only valid as an argument to `sort` or `sortLimit`) |
| `nullsFirst(expr)`                                           | Changes sort order to nulls first (only valid as an argument to `sort` or `sortLimit`) |
| `nullsLast(expr)`                                            | Changes sort order to nulls last (only valid as an argument to `sort` or `sortLimit`) |
| `cursor(n, input)`                                           | Reference to `input`th (0-based) relational input of a `TableFunctionScan` with `n` inputs (see `functionScan`) |

#### Sub-query methods

The following methods convert a sub-query into a scalar value (a `BOOLEAN` in the case of `in`, `exists`, `some`, `all`, `unique`; any scalar type for `scalarQuery`). an `ARRAY` for `arrayQuery`, a `MAP` for `mapQuery`, and a `MULTISET` for `multisetQuery`).

In all the following, `relFn` is a function that takes a `RelBuilder` argument and returns a `RelNode`. You typically implement it as a lambda; the method calls your code with a `RelBuilder` that has the correct context, and your code returns the `RelNode` that is to be the sub-query.

| METHOD                                  | DESCRIPTION                                                  |
| :-------------------------------------- | :----------------------------------------------------------- |
| `all(expr, op, relFn)`                  | Returns whether *expr* has a particular relation to all of the values of the sub-query |
| `arrayQuery(relFn)`                     | Returns the rows of a sub-query as an `ARRAY`                |
| `exists(relFn)`                         | Tests whether sub-query is non-empty                         |
| `in(expr, relFn)` `in(exprList, relFn)` | Tests whether a value occurs in a sub-query                  |
| `mapQuery(relFn)`                       | Returns the rows of a sub-query as a `MAP`                   |
| `multisetQuery(relFn)`                  | Returns the rows of a sub-query as a `MULTISET`              |
| `scalarQuery(relFn)`                    | Returns the value of the sole column of the sole row of a sub-query |
| `some(expr, op, relFn)`                 | Returns whether *expr* has a particular relation to one or more of the values of the sub-query |
| `unique(relFn)`                         | Returns whether the rows of a sub-query are unique           |

#### Pattern methods

The following methods return patterns for use in `match`.

| METHOD                               | DESCRIPTION           |
| :----------------------------------- | :-------------------- |
| `patternConcat(pattern...)`          | Concatenates patterns |
| `patternAlter(pattern...)`           | Alternates patterns   |
| `patternQuantify(pattern, min, max)` | Quantifies a pattern  |
| `patternPermute(pattern...)`         | Permutes a pattern    |
| `patternExclude(pattern)`            | Excludes a pattern    |

#### Group key methods

The following methods return a [RelBuilder.GroupKey](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.GroupKey.html).

| METHOD                                                       | DESCRIPTION                                                  |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| `groupKey(fieldName...)` `groupKey(fieldOrdinal...)` `groupKey(expr...)` `groupKey(exprList)` | Creates a group key of the given expressions                 |
| `groupKey(exprList, exprListList)`                           | Creates a group key of the given expressions with grouping sets |
| `groupKey(bitSet [, bitSets])`                               | Creates a group key of the given input columns, with multiple grouping sets if `bitSets` is specified |

#### Aggregate call methods

The following methods return an [RelBuilder.AggCall](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.AggCall.html).

| METHOD                                                       | DESCRIPTION                                         |
| :----------------------------------------------------------- | :-------------------------------------------------- |
| `aggregateCall(op, expr...)` `aggregateCall(op, exprList)`   | Creates a call to a given aggregate function        |
| `count([ distinct, alias, ] expr...)` `count([ distinct, alias, ] exprList)` | Creates a call to the `COUNT` aggregate function    |
| `countStar(alias)`                                           | Creates a call to the `COUNT(*)` aggregate function |
| `sum([ distinct, alias, ] expr)`                             | Creates a call to the `SUM` aggregate function      |
| `min([ alias, ] expr)`                                       | Creates a call to the `MIN` aggregate function      |
| `max([ alias, ] expr)`                                       | Creates a call to the `MAX` aggregate function      |

To further modify the `AggCall`, call its methods:

| METHOD                               | DESCRIPTION                                                  |
| :----------------------------------- | :----------------------------------------------------------- |
| `approximate(approximate)`           | Allows approximate value for the aggregate of `approximate`  |
| `as(alias)`                          | Assigns a column alias to this expression (see SQL `AS`)     |
| `distinct()`                         | Eliminates duplicate values before aggregating (see SQL `DISTINCT`) |
| `distinct(distinct)`                 | Eliminates duplicate values before aggregating if `distinct` |
| `filter(expr)`                       | Filters rows before aggregating (see SQL `FILTER (WHERE ...)`) |
| `sort(expr...)` `sort(exprList)`     | Sorts rows before aggregating (see SQL `WITHIN GROUP`)       |
| `unique(expr...)` `unique(exprList)` | Makes rows unique before aggregating (see SQL `WITHIN DISTINCT`) |
| `over()`                             | Converts this `AggCall` into a windowed aggregate (see `OverCall` below) |

#### Windowed aggregate call methods

To create an [RelBuilder.OverCall](https://calcite.apache.org/javadocAggregate/org/apache/calcite/tools/RelBuilder.OverCall.html), which represents a call to a windowed aggregate function, create an aggregate call and then call its `over()` method, for instance `count().over()`.

To further modify the `OverCall`, call its methods:

| METHOD                                         | DESCRIPTION                                                  |
| :--------------------------------------------- | :----------------------------------------------------------- |
| `rangeUnbounded()`                             | Creates an unbounded range-based window, `RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` |
| `rangeFrom(lower)`                             | Creates a range-based window bounded below, `RANGE BETWEEN lower AND CURRENT ROW` |
| `rangeTo(upper)`                               | Creates a range-based window bounded above, `RANGE BETWEEN CURRENT ROW AND upper` |
| `rangeBetween(lower, upper)`                   | Creates a range-based window, `RANGE BETWEEN lower AND upper` |
| `rowsUnbounded()`                              | Creates an unbounded row-based window, `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` |
| `rowsFrom(lower)`                              | Creates a row-based window bounded below, `ROWS BETWEEN lower AND CURRENT ROW` |
| `rowsTo(upper)`                                | Creates a row-based window bounded above, `ROWS BETWEEN CURRENT ROW AND upper` |
| `rowsBetween(lower, upper)`                    | Creates a rows-based window, `ROWS BETWEEN lower AND upper`  |
| `partitionBy(expr...)` `partitionBy(exprList)` | Partitions the window on the given expressions (see SQL `PARTITION BY`) |
| `orderBy(expr...)` `sort(exprList)`            | Sorts the rows in the window (see SQL `ORDER BY`)            |
| `allowPartial(b)`                              | Sets whether to allow partial width windows; default true    |
| `nullWhenCountZero(b)`                         | Sets whether whether the aggregate function should evaluate to null if no rows are in the window; default false |
| `as(alias)`                                    | Assigns a column alias (see SQL `AS`) and converts this `OverCall` to a `RexNode` |
| `toRex()`                                      | Converts this `OverCall` to a `RexNode`                      |

# 适配器

## Schema 适配器

Schema 适配器允许 Calcite 读取特定类型的数据，将数据呈现为 Schema 中的表。

- Cassandra adapter (calcite-cassandra)

- CSV adapter (example/csv)

- Druid adapter (calcite-druid)

- Elasticsearch adapter (calcite-elasticsearch)

- File adapter (calcite-file)

- Geode adapter (calcite-geode)

- InnoDB adapter (calcite-innodb)

- JDBC adapter (part of calcite-core)

- MongoDB adapter (calcite-mongodb)

- OS adapter (calcite-os)

- Pig adapter (calcite-pig)

- Redis adapter (calcite-redis)

- Solr cloud adapter (solr-sql)

- Spark adapter (calcite-spark)

- Splunk adapter (calcite-splunk)

- Eclipse Memory Analyzer (MAT) adapter (mat-calcite-plugin)

- Apache Kafka adapter

其他语言的接口

- Piglet (calcite-piglet) runs queries in a subset of Pig Latin

## 引擎

许多项目和产品使用 Apache Calcite 进行 SQL 解析、查询优化、数据虚拟化/联合和物化视图重写。其中一些在 [Power by  Calcite](https://calcite.apache.org/docs/powered_by.html) 页面上列出。

## 驱动

驱动程序允许您从应用程序连接到 Calcite。

- [JDBC 驱动](https://calcite.apache.org/javadocAggregate/org/apache/calcite/jdbc/package-summary.html)

 JDBC 驱动程序由 Avatica 提供支持。连接可以是本地的或远程的（JSON over HTTP 或 Protobuf over HTTP）。JDBC 连接字符串的基本形式是 `jdbc:calcite:property=value;property2=value2` 其中，`property`、`property2` 是如下所述的属性。 连接字符串符合 OLE DB 连接字符串语法，由 Avatica 的 [`ConnectStringParser`](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/ConnectStringParser.html) 实现。

##  JDBC 连接字符串参数 

| Property                                                     | Description                                                  |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#APPROXIMATE_DECIMAL">approximateDecimal</a> | Whether approximate results from aggregate functions on `DECIMAL` types are acceptable. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#APPROXIMATE_DISTINCT_COUNT">approximateDistinctCount</a> | Whether approximate results from `COUNT(DISTINCT ...)` aggregate functions are acceptable. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#APPROXIMATE_TOP_N">approximateTopN</a> | Whether approximate results from "Top N" queries (`ORDER BY aggFun() DESC LIMIT n`) are acceptable. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#CASE_SENSITIVE">caseSensitive</a> | Whether identifiers are matched case-sensitively. If not specified, value from `lex` is used. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#CONFORMANCE">conformance</a> | SQL conformance level. Values: DEFAULT (the default, similar to PRAGMATIC_2003), LENIENT, MYSQL_5, ORACLE_10, ORACLE_12, PRAGMATIC_99, PRAGMATIC_2003, STRICT_92, STRICT_99, STRICT_2003, SQL_SERVER_2008. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#CREATE_MATERIALIZATIONS">createMaterializations</a> | Whether Calcite should create materializations. Default false. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#DEFAULT_NULL_COLLATION">defaultNullCollation</a> | How NULL values should be sorted if neither NULLS FIRST nor NULLS LAST are specified in a query. The default, HIGH, sorts NULL values the same as Oracle. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#DRUID_FETCH">druidFetch</a> | How many rows the Druid adapter should fetch at a time when executing SELECT queries. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#FORCE_DECORRELATE">forceDecorrelate</a> | Whether the planner should try de-correlating as much as possible. Default true. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#FUN">fun</a> | Collection of built-in functions and operators. Valid values are "standard" (the default), "oracle", "spatial", and may be combined using commas, for example "oracle,spatial". |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#LEX">lex</a> | Lexical policy. Values are BIG_QUERY, JAVA, MYSQL, MYSQL_ANSI, ORACLE (default), SQL_SERVER. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#MATERIALIZATIONS_ENABLED">materializationsEnabled</a> | Whether Calcite should use materializations. Default false.  |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#MODEL">model</a> | URI of the JSON/YAML model file or inline like `inline:{...}` for JSON and `inline:...` for YAML. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#PARSER_FACTORY">parserFactory</a> | Parser factory. The name of a class that implements [<code>interface SqlParserImplFactory</code>]({{ site.apiRoot }}/org/apache/calcite/sql/parser/SqlParserImplFactory.html) and has a public default constructor or an `INSTANCE` constant. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#QUOTING">quoting</a> | How identifiers are quoted. Values are DOUBLE_QUOTE, BACK_TICK, BACK_TICK_BACKSLASH, BRACKET. If not specified, value from `lex` is used. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#QUOTED_CASING">quotedCasing</a> | How identifiers are stored if they are quoted. Values are UNCHANGED, TO_UPPER, TO_LOWER. If not specified, value from `lex` is used. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#SCHEMA">schema</a> | Name of initial schema.                                      |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#SCHEMA_FACTORY">schemaFactory</a> | Schema factory. The name of a class that implements [<code>interface SchemaFactory</code>]({{ site.apiRoot }}/org/apache/calcite/schema/SchemaFactory.html) and has a public default constructor or an `INSTANCE` constant. Ignored if `model` is specified. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#SCHEMA_TYPE">schemaType</a> | Schema type. Value must be "MAP" (the default), "JDBC", or "CUSTOM" (implicit if `schemaFactory` is specified). Ignored if `model` is specified. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#SPARK">spark</a> | Specifies whether Spark should be used as the engine for processing that cannot be pushed to the source system. If false (the default), Calcite generates code that implements the Enumerable interface. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#TIME_ZONE">timeZone</a> | Time zone, for example "gmt-3". Default is the JVM's time zone. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#TYPE_SYSTEM">typeSystem</a> | Type system. The name of a class that implements [<code>interface RelDataTypeSystem</code>]({{ site.apiRoot }}/org/apache/calcite/rel/type/RelDataTypeSystem.html) and has a public default constructor or an `INSTANCE` constant. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#UNQUOTED_CASING">unquotedCasing</a> | How identifiers are stored if they are not quoted. Values are UNCHANGED, TO_UPPER, TO_LOWER. If not specified, value from `lex` is used. |
| <a href="{{ site.apiRoot }}/org/apache/calcite/config/CalciteConnectionProperty.html#TYPE_COERCION">typeCoercion</a> | Whether to make implicit type coercion when type mismatch during sql node validation, default is true. |

要根据内置 Schema 类型连接到单个 Schema，无需指定**模型**。例如，使用通过 JDBC Schema 适配器对应到 **foodmart** 数据库的 schema 创建连接。

```java
jdbc:calcite:schemaType=JDBC; schema.jdbcUser=SCOTT; schema.jdbcPassword=TIGER; schema.jdbcUrl=jdbc:hsqldb:res:foodmart
```

同样，您可以基于用户定义的 Schema  适配器连接到单个 Schema 。 例如，

```java
jdbc:calcite:schemaFactory=org.apache.calcite.adapter.cassandra.CassandraSchemaFactory; schema.host=localhost; schema.keyspace=twissandra
```

与 Cassandra 适配器建立连接，相当于编写以下模型文件：

```json
{
  "version": "1.0",
  "defaultSchema": "foodmart",
  "schemas": [
    {
      type: 'custom',
      name: 'twissandra',
      factory: 'org.apache.calcite.adapter.cassandra.CassandraSchemaFactory',
      operand: {
        host: 'localhost',
        keyspace: 'twissandra'
      }
    }
  ]
}
```

请注意操作数部分中的每个 key 如何与 schema 一起出现.

## Server

Calcite 的核心模块（calcite-core）支持 SQL 查询（`SELECT`）和 DML 操作（`INSERT、UPDATE、DELETE、MERGE`），但不支持 `CREATE SCHEMA` 或 `CREATE TABLE` 等 DDL 操作。 正如我们将看到的，DDL 使<u>==存储库的状态模型复杂化==</u>，并使解析器更难以扩展，因此我们将 DDL 排除在核心之外。

服务器模块 (calcite-server) 为 Calcite 添加了 DDL 支持。 使用与子项目相同的机制扩展 SQL 解析器，添加了一些 DDL 命令：

- `CREATE` 和 `DROP SCHEMA`
- `CREATE` 和 `DROP FOREIGN SCHEMA`
- `CREATE` 和 `DROP TABLE` (包括 `CREATE TABLE ... AS SELECT`)
- `CREATE` 和 `DROP MATERIALIZED VIEW`
- `CREATE` 和 `DROP VIEW`
- `CREATE` 和 `DROP FUNCTION`
- `CREATE` 和 `DROP TYPE`

[SQL 参考](https://calcite.apache.org/docs/reference.html#ddl-extensions)中描述了命令

类路径中包含 calcite-server.jar，并将 `SqlDdlParserImpl#FACTORY`  添加到 JDBC 连接字符串（请参阅连接字符串属性 `parserFactory`），即可启用。下面使用 sqlline shell 的示例：

```shell
$ ./sqlline
sqlline version 1.3.0
> !connect jdbc:calcite:parserFactory=org.apache.calcite.sql.parser.ddl.SqlDdlParserImpl#FACTORY sa ""
> CREATE TABLE t (i INTEGER, j VARCHAR(10));
No rows affected (0.293 seconds)
> INSERT INTO t VALUES (1, 'a'), (2, 'bc');
2 rows affected (0.873 seconds)
> CREATE VIEW v AS SELECT * FROM t WHERE i > 1;
No rows affected (0.072 seconds)
> SELECT count(*) FROM v;
+---------------------+
|       EXPR$0        |
+---------------------+
| 1                   |
+---------------------+
1 row selected (0.148 seconds)
> !quit
```

`calcite-server` 模块是可选的。它的目标之一是使用简洁的示例展示 Calcite  的功能(例如物化视图、外部表和生成的列)，您可以从SQL命令行尝试这些示例。`calcite-server` 使用的所有功能都可以通过 `calcite-core` 中的 API 获得。

如果您是子项目的作者，您的语法扩展不太可能与 `calcite-server` 中的匹配，因此我们建议您通过[扩展核心解析器](https://calcite.apache.org/docs/adapter.html#extending-the-parser)来添加您的 SQL 语法扩展；如果您需要 DDL 命令，您可以从 `calcite-server` 复制粘贴到您的项目中。

目前，还没有持久化<u>==存储库==</u>。在执行DDL命令时，通过添加和删除可从根 [Schema](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schema.html) 访问的对象来修改内存<u>==存储库==</u>。同一 SQL Session 中的所有命令都会看到这些对象。通过执行相同的SQL命令脚本，可以在以后的会话中创建相同的对象。

Calcite 还可以充当数据虚拟化或联合服务器：Calcite 管理多个外部 Schema 中的数据，但对于客户端而言，这些数据似乎都在同一个地方。Calcite 选择应在何处进行处理，以及是否创建数据副本以提高效率。 calcite-server 模块是朝着这个目标迈出的一步；行业实力的解决方案需要进一步包装（使 Calcite 作为服务可运行）、<u>==存储库==</u>持久性、授权和安全性。

## 可扩展性

还有许多其他 API 允许您扩展 Calcite 的功能。

在本节中，我们将简要介绍这些 API，让您了解哪些是可能的。要充分使用这些 API，您需要阅读其他文档，例如接口的 javadoc，并可能需要查找我们为它们编写的测试。

### 函数和运算符

有多种方法可以向 Calcite 添加运算符或函数。 我们将首先描述最简单的（也是最不强大的）。

1. 用户定义的函数是最简单的（但最不强大的）。 它们编写起来很简单（您只需编写一个 Java 类并将其注册到您的模式中），但在参数的数量和类型、解析重载函数或派生返回类型方面没有提供很大的灵活性。
2. 如果您想要这种灵活性，您可能需要编写一个用户定义的运算符（请参阅 [SqlOperator](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/SqlOperator.html) 接口）。
3. 如果运算符不遵守标准的 SQL 函数语法 `f(arg1, arg2, ...)`，则需要扩展解析器。

测试中有许多很好的例子：`class UdfTest` 测试用户定义函数和用户定义聚合函数。

### 聚合函数

**用户定义的聚合函数**类似于用户定义的函数，但每个函数都有几个对应的 Java 方法，对应于聚合生命周期中的每个阶段：

- `init` 创建一个累加器
- `add` 将一行的值添加到累加器
- `merge` 将两个累加器合二为一
- `result` 结束累加器并将其转换为结果。

例如，`SUM(int)` 的方法（伪代码）如下：

```c++
struct Accumulator {
  final int sum;
}
Accumulator init() {
  return new Accumulator(0);
}
Accumulator add(Accumulator a, int x) {
  return new Accumulator(a.sum + x);
}
Accumulator merge(Accumulator a, Accumulator a2) {
  return new Accumulator(a.sum + a2.sum);
}
int result(Accumulator a) {
  return a.sum;
}
```

以下是计算列值为 4 和 7 的两行之和的调用序列：

```sh
a = init()    # a = {0}
a = add(a, 4) # a = {4}
a = add(a, 7) # a = {11}
return result(a) # returns 11
```

### 窗口函数

窗口函数类似于聚合函数，但它应用于由 `OVER` 子句而不是 `GROUP BY` 子句收集的一组行。 每个聚合函数都可以用作窗口函数，但有一些关键的区别。窗口函数看到的行可能是有序的，**依赖于顺序（例如 `RANK`）的窗口函数不能用作聚合函数**。另一个区别是窗口是不相交的：特定行可以出现在多个窗口中。 例如，10:37 出现在 9:00-10:00 和 9:15-9:45 两个时间段。

窗口函数是递增计算的：当时钟从 10:14 到 10:15 滴答作响时，可能有两行进入窗口，而三行离开。 为此，窗口函数有一个额外的生命周期操作：

- `remove` 从累加器中移除一个值。

`SUM(int)` 的伪码是：

```c++
Accumulator remove(Accumulator a, int x) {
  return new Accumulator(a.sum - x);
}
```

以下是计算前 2 行的移动总和的调用序列，其中 4 行的值为 4、7、2 和 3：

```sh
a = init()       # a = {0}
a = add(a, 4)    # a = {4}
emit result(a)   # emits 4
a = add(a, 7)    # a = {11}
emit result(a)   # emits 11
a = remove(a, 4) # a = {7}
a = add(a, 2)    # a = {9}
emit result(a)   # emits 9
a = remove(a, 7) # a = {2}
a = add(a, 3)    # a = {5}
emit result(a)   # emits 5
```

### 分组窗口函数

> 和流有关

分组窗口函数是操作 `GROUP BY` 子句将记录收集到集合中的函数。实现 [`SqlGroupedWindowFunction`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/SqlGroupedWindowFunction.html) 接口来定义附加功能。内置的分组窗口函数是 `HOP`、`TUMBLE` 和 `SESSION`。 

### 表函数和表宏

用户定义表函数的定义方式与定义普通的 UDF 函数类似，但在查询的 `FROM` 子句中使用。以下查询使用名为 `Ramp` 的表函数：

```sql
SELECT * FROM TABLE(Ramp(3, 4))
```

用户定义的表宏使用与表函数相同的 SQL 语法，但定义不同。它们不是生成数据，而是生成关系表达式。在查询准备期间调用**表宏**，然后可以优化它们生成的关系表达式。Calcite 的视图实现使用了表宏。

[`TableFunctionTest`](https://github.com/apache/calcite/blob/master/core/src/test/java/org/apache/calcite/test/TableFunctionTest.java) 测试表函数并包含几个有用的示例

### 扩展 parser

假设您需要扩展 Calcite 的 SQL 语法，使其与将来对语法的更改兼容。 在项目中复制语法文件 Parser.jj 是愚蠢的，因为会经常编辑这个语法文件。

幸运的是，`Parser.jj` 实际上是一个 [Apache FreeMarker](https://freemarker.apache.org/) 模板，它包含可替换变量的。

`calcite-core` 中的解析器用变量的默认值实例化模板，通常为空，但可以覆盖。如果您的项目需要不同的解析器，您可以提供自己的 `config.fmpp` 和 `parserImpls.ftl` 文件，从而生成扩展解析器。

在 [[CALCITE-707]](https://issues.apache.org/jira/browse/CALCITE-707) 中创建并添加 DDL 语句，如 `CREATE TABLE` 的`calcite-server` 模块就是您可以遵循的一个示例。参见类`ExtensionSqlParserTest`。

### 生成并使用 SQL 方言

要自定义 parser 应接受的 SQL 扩展，请实现接口 [SqlConformance](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/validate/SqlConformance.html) 或使用枚举 [SqlConformanceEnum](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql/validate/SqlConformanceEnum.html) 中的内置值之一。

要控制如何为外部数据库生成 SQL（通常通过 JDBC 适配器），请使用 `SqlDialect`。该方言还描述了引擎的功能，例如它是否支持 `OFFSET` 和 `FETCH` 子句。

### 自定义 schema

要定义自定义 Schema，您需要实现 [SchemaFactory](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/SchemaFactory.html) 接口

在查询准备期间，Calcite 将调用此接口，以找出您的 Schema 包含哪些表和子Schema。当查询中引用架构中的表时，Calcite 将要求您的架构创建接口表的实例。当在查询中引用 Schema 中的表时，Calcite 将要求 Schema 创建 [table](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Table.html) 接口的实例。

这个表将被包装在 `TableScan` 中，并将经历查询优化过程。

### 反射的 Schema

反射 Schema [ReflectiveSchema](https://calcite.apache.org/javadocAggregate/org/apache/calcite/adapter/java/ReflectiveSchema.html) 是一种包装 Java 对象以将其显示为 Schema 的方法。其集合值字段将显示为表，它不是一个 Schema 工厂，而是一个实际的 Schema； 您必须创建对象并通过调用 API 将其包装在 Schema 中。

请参见类 [ReflectiveSchemaTest](https://github.com/apache/calcite/blob/master/core/src/test/java/org/apache/calcite/test/ReflectiveSchemaTest.java)

### 自定义表

要定义自定义表，需要实现 [TableFactory](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/TableFactory.html) 接口。 Schema 工厂是一组**==已命名表==**，而**表工厂**在绑定到具有特定名称的 Schema 时（以及可选的一组额外操作数）会生成单个表。

### 修改数据

如果您的表要支持DML操作(插入`INSERT`、更新`UPDATE`、删除`DELETE`、合并`MERGE`)，那么 `Table` 接口的实现必须实现 [ModifiableTable](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/ModifiableTable.html) 接口。

### Streaming

如果您的表要支持流式查询，则 `Table` 接口必须实现 [StreamableTable](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/StreamableTable.html) 接口。

有关示例，请参见 [StreamTest](https://github.com/apache/calcite/blob/master/core/src/test/java/org/apache/calcite/test/StreamTest.java)。

### 计算下推

如果您希望将处理下推到自定义表的源系统，请考虑实现 [`FilterableTable`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/FilterableTable.html) 接口或 [`ProjectableFilterableTable`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/ProjectableFilterableTable.html) 接口。

如果你想要更多的控制，你应该写一个[优化规则](https://calcite.apache.org/docs/adapter.html#planner-rule)。 这将允许您下推表达式，就是否下推处理做出基于成本的决定，并下推更复杂的操作，如连接、聚合和排序。

### 类型系统

通过实现 [RelDataTypeSystem](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/type/RelDataTypeSystem.html) 接口来自定义类型系统的某些方面。

### 关系运算符

所有关系运算符都实现 [RelNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelNode.html) 接口，大多数扩展至类 [AbstractRelNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/AbstractRelNode.html)。（由 [SqlToRelConverter](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql2rel/SqlToRelConverter.html) 使用并涵盖的常规关系代数，即）核心运算符是 [`TableScan`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableScan.html)、[`TableModify`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableModify.html)、[`Values`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Values.html)、[`Project`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Project.html)、[`Filter`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Filter.html)、[`Aggregate`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Aggregate.html)、[`Join`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Join.html)、[`Sort`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Sort.html)、[`Union`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Union.html)、[`Intersect`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Intersect.html)、[`Minus`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Minus.html)、[`Window`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Window.html) 和 [`Match`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Match.html)。

其中每一个都有一个**纯**的逻辑子类，比如 [`LogicalProject`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/logical/LogicalProject.html) 等等。任何给定的适配器都有对应的引擎可以有效实现的操作，例如，Cassandra 适配器有 [`CassandraProject`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/adapter/cassandra/CassandraProject.html) 但没有 `CassandraJoin`。

您可以定义自己的 `RelNode` 子类来添加新的运算符，或在特定引擎中实现现有运算符。

为了使运算符有用且强大，您需要[优化器规则](#优化器规则)将其与现有运算符相结合。并提供元数据，见[下文](https://calcite.apache.org/docs/adapter.html#statistics-and-cost)。**这是代数，效果是组合的：您编写一些规则，但它们组合起来处理指数数量的查询模式**。

如果可能，让你的运算符成为现有运算符的子类；那么您就可以重新使用或调整其规则。更好的是，如果您的运算符是一个可以根据现有运算符实现的逻辑运算（仍通过优化器规则），那么就应该这样做。您将无需额外工作即可重复使用这些运算符的规则、元数据和实现。

### 优化器规则

优化规则（[RelOptRule](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/RelOptRule.html)）将关系表达式转换为等价的关系表达式。

优划器引擎有许多已注册的规则，触发这些规则将输入查询转换为更有效的查询。因此，优化规则是优化过程的核心，但令人惊讶的是，每个规则本身并不用关心成本。优划器引擎负责<u>以生成最佳计划的顺序</u>触发规则，但是每个单独的规则只关注其自身的正确性。

Calcite 有两个内置的优化器引擎：[VolcanoPlanner](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/volcano/VolcanoPlanner.html) 使用动态规划，适合穷极搜索，而 [HepPlanner](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/hep/HepPlanner.html) 则以更固定的顺序触发一系列规则。

### 调用约定

调用约定是特定数据引擎使用的协议。例如，Cassandra 引擎有一系列关系运算符，`CassandraProject`、`CassandraFilter` 等，这些运算符可以相互连接，而无需将数据从一种格式转换为另一种格式。

如果数据需要从一种调用约定转换为另一种调用约定，Calcite 使用一个特殊的**关系表达式子类**，称为转换器（请参考 [Converter](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/convert/Converter.html) 接口）。当然，数据转换有运行成本。

在规划使用多个引擎的查询时，Calcite 根据其调用约定为关系表达式树的区域**着色**。规划器通过优化规则将操作推送到数据源中。如果引擎不支持特定操作，则规则不会触发。有时一项操作可能会发生在多个地方，最终会根据成本选择最佳方案。

**调用约定**是一个实现 [Convention](https://calcite.apache.org/javadocAggregate/org/apache/calcite/plan/Convention.html) 接口的类、一个辅助接口（例如 [CassandraRel](https://calcite.apache.org/javadocAggregate/org/apache/calcite/adapter/cassandra/CassandraRel.html) 接口），以及一组 [`RelNode`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelNode.html) 的子类，这些子类为核心关系操作符（Project、Filter、Aggregate 等）实现该接口。

### 内置的 SQL实现

如果适配器没有实现所有核心关系运算符，Calcite 如何实现 SQL？

答案是特定的内置调用约定 [`EnumerableConvention`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/adapter/enumerable/EnumerableConvention.html)。可枚举约定的关系表达式被实现为“内置”：Calcite 生成 Java 代码，编译它，并在它自己的 JVM 中执行。`EnumerableConvention` 的效率不如运行在面向列的数据文件上的分布式引擎，但它可以实现所有**核心关系运算符**和所有内置 SQL 函数和运算符。如果数据源无法实现关系运算符，则 `EnumerableConvention` 是一种后备。

### 统计和执行开销

Calcite 有一个元数据系统，允许您定义有关关系运算符的成本函数和统计信息，统称为元数据。每种元数据（通常）都有一个带有一个方法的接口。例如，选择性由 [`RelMdSelectivity`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/metadata/RelMdSelectivity.html) 和方法 [`getSelectivity(RelNode rel, RexNode predicate)`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/metadata/RelMetadataQuery.html#getSelectivity(org.apache.calcite.rel.RelNode,org.apache.calcite.rex.RexNode)) 定义。

有许多内置的元数据，包括[排序规则](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/metadata/RelMdCollation.html)、列起源、列唯一性、不同行数、分布、解释可见性、表达式沿袭、最大行数、节点类型、并行度、原始行百分比、人口大小、谓词、行计数、选择性、大小、表引用和唯一键；你也可以定义你自己的。

然后，您可以提供一个**元数据 provider**，为 `RelNode` 的特定子类计算这种类型的元数据。**元数据 provider** 可以处理内置和扩展的元数据类型，以及内置和扩展的 `RelNode` 类型。在准备查询时，Calcite 将所有适用的 **元数据 provider** 组合在一起，并维护一个缓存，以便只计算一次给定的元数据（例如特定 `Filter` 运算符中条件 `x > 10` 的选择性）。


# 考古
## 视图
### 第一次支持[视图匹配](https://github.com/apache/calcite/commit/13136f9e4b7f4341d5cdce5b9ca8d498f353bb30) 

具体算法不知道。随后的 Commit，[Before planning a query, prune the materialized tables used to those that might help](https://github.com/apache/calcite/commit/0eb66bbb462bfb9bfd3bdfc9f2fb2d602958bcbd) 在 `VocanoPlanner` 里增加了一个 `originalRoot`。

> 优化查询之前，找到那些可能有帮助的物化表。

### 第一次实现视图 [`SubstitutionVisitor`](https://github.com/apache/calcite/commit/026ff5186edb1c1735b7caa8e2b569e22a1b998c) 算法

用一个**关系表达式树**替换**另一个关系表达式树的一部分**。

调用 `new SubstitutionVisitor(target, query).go(replacement))` 返回每次 `target` 被 `replacement` 替换的查询。以下示例展示如何使用 `SubstitutionVisitor` 识别物化视图。

```
query = SELECT a, c FROM t WHERE x = 5 AND b = 4
target = SELECT a, b, c FROM t WHERE x = 5
replacement = SELECT * FROM mv
result = SELECT a, c FROM mv WHERE b = 4
```

请注意，结果使用了物化视图表 mv 和简化条件 b = 4。使用**自下而上**的匹配算法。节点不需要完全相同。 每层都返回残差。输入必须只包含核心**关系运算符**：`TableAccessRel`, `FilterRel`, `ProjectRel`, `JoinRel`, `UnionRel`, `AggregateRel`.

### 🔴 [支持视图 Filter](https://github.com/apache/calcite/commit/60e4da419027885e772abe209b2bfb04371c67ae)

识别包含过滤器的物化视图。为此，添加了将谓词（例如“x = 1 和 y = 2”）拆分为由底层谓词“y = 2”处理和未处理的部分的算法。

### 2013-11-15 [增加 `StarTable`](https://github.com/apache/calcite/commit/ef0acca555e6d78d08ea1aa5ecc6d7b42f689544)

这是**识别复杂物化**的第一步，**星型表**是通过多对一关系连接在一起的真实表组成的虚拟表。定义物化视图的查询和最终用户的查询按照星型表规范化。匹配(尚未完成)将是寻找 `sort`、`groupBy`、`Project` 的问题。

==现在，我们已经添加了一个虚拟模式 mat 和一个虚拟星型表 star。稍后，模型将允许显式定义星型表==。

- `StarTable`：**虚拟表**由两个或多个 `Join` 在一起的表组成。`StarTable` 不会出现在最终用户查询中，由优化器引入，以有助于查询和物化视图之间的匹配，并且仅在优化过程中使用。定义物化视图时，如果涉及 `Join`，则将其转换为基于 `StarTable` 的查询。候选查询和物化视图映射到同一个 `StarTable` 上

####  `OptiqMaterializer`：填充 `Prepare.Materialization` 的上下文

识别并替换 `queryRel` 中的 `StarTable`。

- 可能没有 `StarTable` 匹配。没关系，但是识别的物化模式不会那么丰富。
- 可能有多个 StarTable 匹配。**TBD**：我们应该选择最好的（不管这意味着什么），还是全部？

####   `RelOptMaterialization`：记录由特定表物化的特定查询

- `tryUseStar(...)`：将关系表达式转换为使用 `StarTable` 的关系表达式。 根据 `toLeafJoinForm(RelNode)`，关系表达式已经是**==叶连接形式==**。

### 🔴Support filter query on project materialization, where project contains expressions.

编译失败

### 🔴Support Group By

编译失败

### 2014-07-14 第一次实现 `Lattice` 结构 - [CALCITE-344](https://issues.apache.org/jira/browse/CALCITE-344)

添加数据结构 `lattice` ，以组织、收集统计信息并推荐物化查询。

这是一个可能的 SQL DDL 语法：

```SQL
CREATE LATTICE SalesStar AS
SELECT *
FROM SalesFact AS s
JOIN TimeDim AS t USING (timeId)
JOIN CustomerDim AS c USING (customerId)
```

- **结构**：物化查询可能属于某个 lattice。
- **约束**：创建 lattice 意味着第一个表是星型模式的事实表，所有连接都是多对一的。也就是说，隐含了外键、主键和 NOT NULL 约束。
- **统计数据**：当查询可以使用 **lattice** 时，计数器会增加。
- **推荐**：==代理==可以根据星型模式（例如表和列基数）的静态分析以及过去使用的统计信息推荐要创建的**物化视图**。
- **视图匹配**：优化器使用 **lattice** 来识别可以满足查询的物化查询。没有 latttice，这样的空间会大得多，因为优化器必须考虑许多连接排列。

### 2014-09-03 [CALCITE-402：Lattice should create materializations on demand](https://issues.apache.org/jira/browse/CALCITE-402)

Lattice should create materializations (in memory) the first time it is asked for them, and use the same materialization for subsequent queries.

Enabled by new connection parameter "createMaterializations".

#### `AggregateStarTableRule`

在 `StarTable.StarTableScan` 之上匹配 `AggregateRelBase` 的优化器规则。此模式表明可能存在聚合表。 该规则要求**星表**提供所需聚合级别的聚合表。

### 2014-09-13 [CALCITE-406：Add tile and measure elements to lattice model element](https://issues.apache.org/jira/browse/CALCITE-406)

将 `Tile` 和 `Measure` 元素添加到 lattice 模型元素，加载模型（在连接初始化）时加载 lattice 的预定义 `Tile`。

### [CALCITE-1389：Add rule to perform rewriting of queries using materialized views with joins](https://issues.apache.org/jira/browse/CALCITE-1389)

第一次按 [Optimizing Queries Using Materialized Views: A Practical, Scalable Solution]() 这篇 paper 来实现

> 自由形式的物化视图的问题在于它们往往有很多。这篇论文旨在解决这个问题，**lattice** 也是如此。但是 lattice 更好：它们可以收集统计数据，并建议创建不存在但可能有用的视图。
>
> **Lattice** 本质上与论文中描述的 ==SPJ 视图==相同，当然，今天需要手工创建它们。我认为对于 DW 风格的工作负载，手工创建 lattice 比手工创建 MV 实用得多。这不仅是为了让优化器的工作更轻松，也是为了让 DBA 的工作更轻松。MV 并不容易操作管理。无论如何，如果人们手工创建了很多 MV，我的想法是拥有一种自动创建 lattice 的算法，从而降低检查所有这些 MV 的成本。
>
> 在我看来，主要的缺失部分是一种算法，该算法在给定一组 MV 的情况下，创建一组最佳的 lattice，使得每个 MV 都属于一个 lattice。

### 2017-01-31 [ALCITE-1500：Decouple materialization and lattice substitution from VolcanoPlanner](https://issues.apache.org/jira/browse/CALCITE-1500)

TODO

### [CALCITE-1682：New metadata providers for expression column origin and all predicates in plan](https://issues.apache.org/jira/browse/CALCITE-1682)

我正在研究 Hive 中物化视图重写的集成。

一旦视图与 `operator plan` 相匹配，重写就分为两个步骤。

1. 第一步将验证<u>匹配计划</u>的<u>根运算符</u>的<u>输入</u>是否等价或包含在表示视图查询的<u>根运算符</u>的输入中。
2. 第二步将触发一个**统一**规则，它尝试将匹配的**运算符树**重写为对**视图的扫描**，可能还有一些额外的运算符来计算查询所需的确切结果（比较改变列顺序的 `Project`，视图上额外的 `Filter`、额外的 `Join` 操作等）

如果我们专注于**第一步**，即检查等价性/包含性，我想扩展 Calcite 中的 **metadata provider**，以便为我们提供有关匹配（子）计划的更多信息。特别是，我在考虑：

- **表达式列原点**。目前 Calcite 可以提供某个列的<u>列起源以及它是否派生</u>。但是，我们需要获取生成特定列的表达式。此表达式应包含对输入表的引用。例如，给定表达式列 c，新的 **metadata provider** 将返回它是由表达式 `A.a + B.b` 生成。
- **所有谓词**。目前 Calcite 可以提取已应用于 `RelNode` 输出的谓词（我们可以将它们视为对输出的约束）。但是，我想提取已应用于给定 `RelNode`（子）计划的所有谓词。由于节点可能不是输出的一部分，表达式应该包含对输入表的引用。例如，新的  **metadata provider** 可能会返回表达式 `A.a + B.b > C.c AND D.d = 100`。
- **PK-FK 关系**。我不打算立即实施这个。但是，公开此信息（如果已提供）可以帮助我们触发更多包含 `Join` 运算符的重写。因此，我想知道是否值得添加它。

一旦此信息可用，我们就可以依靠它来实现类似于 [[1]](#Optimizing Queries Using Materialized Views: A Practical, Scalable Solution) 的逻辑，以检查给定（子）计划是否**等价或包含在给定视图中**。

有一个问题是关于将**<u>表列</u>**表示为 `RexNode`，因为我认为这是新 **metadata provider** 返回的最简单方法。我检查了 `RexPatternFieldRef` 并且我认为它会满足我们的要求：alpha 将是合格的表名，而索引是表的列 idx。

**想法？**

我已经开始研究这个，很快就会提供一个补丁；非常感谢反馈

### [CALCITE-1731：Rewriting of queries using materialized views with joins and aggregates](https://issues.apache.org/jira/browse/CALCITE-1731)

还是类似 [[1]](#Optimizing Queries Using Materialized Views: A Practical, Scalable Solution) 来重写**计划**

我试图在 [CALCITE-1389](https://issues.apache.org/jira/browse/CALCITE-1389) 的基础上工作。然而，最后我还是创建了一个新的替代规则。主要原因是我想更密切地 <u>==follow==</u> 论文，而不是依赖于物化视图重写中触发的规则来查找表达式是否等价。相反，我们使用 [CALCITE-1682](https://issues.apache.org/jira/browse/CALCITE-1682) 中提出的新 **metadata provider** 从<u>查询计划</u>和<u>物化视图计划</u>中提取信息，然后我们使用该信息来验证和执行重写。

我还在规则中实现了新的统一/重写逻辑，因为现有的聚合统一规则假设查询中的聚合输入和物化视图需要等价（相同的 Volcano 节点）。该条件可以放宽，因为我们在规则中通过使用如上所述的新 **metadata provider**  验证查询结果是否包含在 物化视图 中。

我添加了多个测试，==但欢迎任何指向可以添加以检查正确性/覆盖率的新测试的反馈==。算法可以触发对同一个查询节点的多次重写。此外，<u>支持在查询/MV 中多次使用表</u>。

将遵循此问题的一些扩展：

- 扩展逻辑以过滤给定查询节点的相关 MV，因此该方法可随着 MV 数量的增长而扩展。
- 使用 Union 运算符生成重写，例如，可以从 MV (year = 2014) 和查询 (not(year = 2014)) 部分回答给定的查询。如果存储了 MV，例如在 Driud 中，这种重写可能是有益的。与其他重写一样，是否最终使用重写的决定应该基于成本。

### [CALCITE-1870：Suggest lattices based on queries and data profiles](https://issues.apache.org/jira/browse/CALCITE-1870)

### [CALCITE-3334：Refinement for Substitution-Based MV Matching](https://issues.apache.org/jira/browse/CALCITE-3334)

基于替换的物化视图匹配方法因其简单性和可扩展性而成为一种有效的方法。本 JIRA 建议通过以下几点改进现有的实现：

1. 在MV匹配之前规范化——通过这种规范化，我们可以显著简化**关系代数树**，并降低物化匹配的难度。
2. 将匹配规则分为两类，说清楚规则需要覆盖的常见匹配模式。

参见[设计文档](https://docs.google.com/document/d/1JpwGNFE3hw3yXb7W3-95-jXKClZC5UFPKbuhgYDuEu4/edit#heading=h.bmvjxz1h5evc)

### [CALCITE-3409：Add a method in RelOptMaterializations to allow registering UnifyRule](https://issues.apache.org/jira/browse/CALCITE-3409)

since 1.28

### [CALCITE-3478：Restructure tests for materialized views](https://issues.apache.org/jira/browse/CALCITE-3478)

Currently there are two strategies for materialized view matching:

**strategy-1**. Substitution based (SubstitutionVisitor.java) [1]
**strategy-2**. Plan structural information based (AbstractMaterializedViewRule.java) [2]
The two strategies are controlled by a single connection config of "materializationsEnabled". Calcite will apply strategy-1 firstly and then strategy-2.

The two strategies are tested in a single integration test called MaterializationTest.java, as a result we cannot run tests separately for a single strategy, which leads to:

1. When some new matching patterns are supported by strategy-1, we might need to update the old result plan, which was previously matched and generated by stragegy-2, e.g. [3], and corresponding testing pattern for stragegy-2 will be lost.
2. Some test failures are even hidden, e.g. MaterializationTest#testJoinMaterialization2 should but failed to be supported by stragegy-2. However strategy-1 lets the test passed.
3. Hard to test internals for SubstutionVisitor.java, e.g. [4] has to struggle and create a unit test

Of course we can add more system config or connection config just for testing and circle around some of the dilemmas I mentioned above. But it will make the code messy. Materialized view matching strategies are so important and worth a through unit test and to be kept clean.

Additionally, this JIRA targets to clean the code of MaterializationTest.java. As more and more fixes get applied, this Java file tends to be messy:

1. Helping methods and testing methods are mixed without good order.
2. Lots of methods called checkMaterialize. We need to sort it out if there's need to add more params, e.g. [5]
3. Some tests are not concise enough, e.g. testJoinMaterialization9 

#### Approach

1. Create unit test MaterializedViewSubstitutionVisitorTest to test strategy-1
2. Create unit test MaterializedViewRelOptRulesTest to test strategy-2
3. Move tests from MaterializationTest to unit tests correspondingly, and keep MaterializationTest for integration tests.

[1] https://calcite.apache.org/docs/materialized_views.html#substitution-via-rules-transformation
[2] https://calcite.apache.org/docs/materialized_views.html#rewriting-using-plan-structural-information
[3] https://github.com/apache/calcite/pull/1451/files#diff-d7e9e44fcb5fb1b98198415a3f78f167R1831
[4] https://github.com/apache/calcite/pull/1555
[5] https://github.com/apache/calcite/pull/1504

## Join



1. [Performance issue when enabling abstract converter for EnumerableConvention](https://issues.apache.org/jira/browse/CALCITE-2970)
2. [TPCH queries take forever for planning](https://issues.apache.org/jira/browse/CALCITE-3968)
3. [Problem with MERGE JOIN: java.lang.AssertionError: cannot merge join: left input is not sorted on left keys](https://issues.apache.org/jira/browse/CALCITE-3997)
4. [Pass through parent trait requests to child operators](https://issues.apache.org/jira/browse/CALCITE-3896)
   1. [[DISCUSS] On-demand traitset request](http://mail-archives.apache.org/mod_mbox/calcite-dev/201910.mbox/%3c393e0ff5-f105-4795-be4f-09deb2a6a491.h.yuan@alibaba-inc.com%3e)


# 基本概念

## `Schema`

**表**和**函数**的名称空间。[Schema](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schema.html) 还可以包含子 Schema，可以有任何层次的嵌套。大多数提供者的层次数量有限； 例如，大多数 JDBC 数据库有一个层次（Schema）或两个层次（Database 和 Catalog）。  

可能存在多个有相同名称的重载**函数**，它们的参数数量或类型不同。出于这个原因， [`getFunctions(String)`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schema.html#getFunctions(java.lang.String)) 返回一个列表 同名的所有成员。 Calcite 将调用 [`Schemas.resolve(RelDataTypeFactory, String, Collection, List)`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schemas.html#resolve(org.apache. calcite.rel.type.RelDataTypeFactory,java.lang.String,java.util.Collection,java.util.List)) 选择合适的一个。

最常见和最重要的成员类型是**没有参数且结果类型是记录集合的成员类型**，称为关系。相当于关系数据库中的一张表。例如，

```SQL
select * from sales.emps
```
如果 `sales` 是一个已注册的 Schema，并且 `emps` 是一个<u>没有参数的成员</u>，并且结果类型为  `Collection(Record(int: "empno"， String: "name"))` ，则查询有效。

一个 Schema 可以嵌套在另一个 Schema 中；参见 [`getSubSchema(String)`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schema.html#getSubSchema(java.lang.String))。

### `SchemaPlus`

[`Schema`](#Schema) 接口的扩展。

给定一个实现 [`Schema`](#Schema) 接口的自定义 Schema，Calcite 创建一个实现 `SchemaPlus ` 的接口。它提供了额外的功能，例如访问已显式添加的表。

用户定义的 `Schema` 不需要实现这个接口，但是当 Schema 被传递给用户定义的 Schema 或用户定义的表中的方法时，它已经被包装在这个接口中。

用户只使用`SchemaPlus` ，但不创建它们。用户应该只使用系统给他们的 `SchemaPlus`。 `SchemaPlus` 的目的是以只读方式向用户代码公开 Calcite 在注册 Schema 时创建的关于 Schema 的一些额外信息。它作为上下文出现在几个 SPI 调用中； 例如 [`SchemaFactory.create(SchemaPlus, String, Map)`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/SchemaFactory.html#create(org.apache.calcite.schema .SchemaPlus,java.lang.String,java.util.Map)) 包含一个父 Schema，它可能是用户定义的 [`Schema`](#Schema) 的包装实例，或者不是。 

## `RelNode`

`RelNode` 是一个关系表达式。

关系表达式处理数据，因此它们的名称通常是动词：**Sort**、**Join**、**Project**、**Filter**、**Scan**、**Sample**。关系表达式不是标量表达式；请参阅 `SqlNode` 和 `RexNode`。如果这种类型的关系表达式有一些特定的优化器规则，实现公共方法 `AbstractRelNode.register`。

当要实现一个**关系表达式**时，系统会分配一个 `org.apache.calcite.plan.RelImplementor` 来管理这个过程。每个可实现的关系表达式都有一个描述其物理属性的 `RelTraitSet`。`RelTraitSet` 总是包含一个 `Convention`，描述表达式如何将数据传递给其**消费关系表达式**，但可能包含其他 **trait**，包括一些应用于外部的 **trait**。因为 **trait** 可以在外部应用，所以 `RelNode` 的实现永远不应该假设其**特征集**的大小或内容（超出由 `RelNode` 本身配置的那些 **trait**）。

每个调用约定都有对应的 `RelNode`子接口。例如，`EnumerableRel` 具有管理转换为 `EnumerableConvention` 调用约定的操作，并且它与 `EnumerableRelImplementor` 交互。关系表达式仅在实际实现时才需要实现其调用约定的接口，即转换为计划/程序。这意味着无法实现的关系表达式，例如转换器，不需要实现其约定的接口。每个关系表达式都必须从 `AbstractRelNode` 派生。那为什么要有 `RelNode` 接口呢？我们需要一个根接口，因为接口只能从接口派生。

## `RelOptRule`

在 Calcite 中所有**规则类**都是从基类 `RelOptRule` 派生。`RelOptRule` 定义了Calcite 规则的基本结构和方法。`RelOptRule` 中包含一个 `RelOptRuleOperand` 的列表，这个列表在规则匹配<u>要变换的关系表达式中</u>有重要作用。`RelOptRuleOperand` 的列表中的 Operand 都是有层次结构的，对应着要匹配的关系表达式结构。当规则匹配到了目标的关系表达式后 `onMatch` 方法会被调用，规则生成的新的关系表达式通过 `RelOptRuleCall` 的 `transform()` 方法让优化器知道关系表达式的变化结果。

![](https://pic2.zhimg.com/80/v2-3574129f1b39c42e9201252e34ac2d41_1440w.jpg)


## Calcite 的 Trait

在 Calcite 中没有使用不同的对象代表**逻辑和物理算子**，但是使用 `trait` 来表示一个算子的物理属性。

<img src="https://pic3.zhimg.com/80/v2-5b9f7c4b29b19333cb135c7cfc810d92_1440w.jpg" alt="img" style="zoom: 25%;" />

Calcite 中使用接口 `RelTrait` 表示一个**关系表达式节点的物理属性**，使用 `RelTraitDef` 来表示 `RelTrait` 的 class。`RelTrait `与 `RelTraitDef` 的关系就像 Java 中对象与 Class 的关系一样，每个对象都有 Class。对于**物理关系表达式算子**，会有一些物理属性，这些物理属性都会用 `RelTrait` 来表示。比如每个算子都有 Calling Convention 这一 `Reltrait`。比如上图中 `Sort` 算子还会有一个物理属性 `RelCollation`，因为 `Sort` 算子会对表的一些字段进行排序，`RelCollation` 这一物理属性就会记录这个 Sort 算子要排序的<u>字段索引</u>、<u>排序方向</u>，怎么排序 `null` 值等信息。

### Calcite 的 Calling Convention

Calling Convention 在 Calcite 中使用接口 `Convention` 表示，`Convention` 接口是 `RelTrait` 的子接口，**所以是一个算子的属性**。可以把 Calling Convention 理解为**==一个特定数据引擎协议==**，拥有相同 `Convention` 的算子可以认为都是一个统一数据引擎的算子，<u>可以相互连接起来</u>。比如 JDBC 的算子 `JDBCXXX ` 都有 `JdbcConvention`，Calcite 内建的 `Enumerable` 算子 `EnumerableXXX` 都有 `EnumerableConvention`。

![](https://pic3.zhimg.com/v2-5ae8eafe4ea0e9cb405c7f1c71ddbd6a_r.jpg)

上图中，Jdbc 算子可以通过 `JdbcConvention` 获得对应数据库的 `SqlDialect` 和 `JdbcSchema` 等数据，这样可生成对应数据库的 sql，**获得数据库的连接池与数据库交互实现算子的逻辑**。 如果数据要从一个 Calling Convention 的算子到另一个 Calling Convention 算子的时候，比如[这篇使用 Calcite 进行跨库 join 文章描述的场景](https://zhuanlan.zhihu.com/p/143935885)。需要 `Converter` 接口的子类作为两种算子之间的桥梁将两种算子连接起来。

![](https://pic2.zhimg.com/80/v2-7ce0b21af232a9c29af18b56b4a08741_1440w.jpg)

比如上面的执行计划，要将 `Enumerable` 的算子与 `Jdbc` 的算子连接起来，中间就要使用 `JdbcToEnumerableConverter` 作为桥梁。

### `Converter`

如果关系表达式实现了接口 `Converter` ，则表示它将关系表达式的物理属性或特征从一个值转换为另一个值。有时这种转换是昂贵的； 例如，要将 non-distinct 的对象流转换为 distinct  的对象流，我们必须克隆输入中的每个对象。

`Converter` 不会改变正在求值的逻辑表达式；**转换后，行数和这些行的值仍然相同**。通过将自己声明为 `Converter`，关系表达式将这种等价性告诉优化器，优化器将逻辑上等价但具有不同物理特征的表达式分组，保存在称为 `RelSet` 的组中。

原则上，可以设计出同时改变多个特征的转换器（比如改变关系表达式的排序顺序和物理位置）。 在这种情况下，方法 `getInputTraits(`) 将返回一个 `RelTraitSet`。 但是为了简单起见，这个类一次只允许转换一个特征； 所有其他特征被认为保留了下来。

### `RelTrait`

`RelTrait` 表示 **trait 定义**中关系表达式 trait 的表现形式。 例如， `CallingConvention.JAVA` 是 `ConventionTraitDef` 定义的 trait。

关于 `equals()` 和 `hashCode()` 的注意事项：

如果特定 `RelTraitDef` 的所有 `RelTrait` 实例都在枚举中定义，并且运行时不能引入新的 `RelTrait`，则不需要覆盖 `hashCode()` 和 `equals(Object)`。但是，如果在运行时生成新的 `RelTrait` 实例（例如，基于优化器外部的状态），则必须实现 `hashCode()` 和 `equals(Object)` 以正确规范化 `RelTrait` 对象。

### `RelTraitDef`

`RelTraitDef` 表示一类 `RelTrait`。 在以下条件下，`RelTraitDef` 的实现可能是单例：

1. 如果所有可能关联的 `RelTrait`s 的集合是有限且固定的（例如，该 `RelTraitDef` 的所有 `RelTrait`s 在编译时都是已知的）。 例如，trait `CallingConvention` 满足这个要求，因为它实际上是一个枚举。
2. `canConvert(RelOptPlanner, RelTrait, RelTrait)` 和 `convert(RelOptPlanner, RelNode, RelTrait, boolean)` 不需要特定于优化器实例的信息，或者 `RelTraitDef` 在内部管理单独的转换数据集。 有关此示例，请参见 `ConventionTraitDef`。

否则，必须构造一个新的 `RelTraitDef` 实例，并注册到每个新的优化器实例中。

## `Relset`

关于 RelSet，源码中介绍如下：

> `RelSet`是表达式的等价集，即具有相同语义的表达式集。我们通常对使用成本最低的表达式感兴趣。`RelSet`中的所有表达式都具有**相同的调用约定**。

它有以下特点：

1. 描述一组等价关系表达式，所有的 `RelNode` 会记录在 `rels` 中
2. **相同的调用约定**
3. 具有相同物理属性的关系表达式会记录在其成员变量 `List<RelSubset> subsets` 中.

RelSet 中比较重要成员变量如下：

```java
class RelSet {
   // 记录属于这个 RelSet 的所有 RelNode
  final List<RelNode> rels = new ArrayList<>();
  /**
   * Relational expressions that have a subset in this set as a child. This
   * is a multi-set. If multiple relational expressions in this set have the
   * same parent, there will be multiple entries.
   */
  final List<RelNode> parents = new ArrayList<>();
  
  //注: 具体相同物理属性的子集合（本质上 RelSubset 并不记录 RelNode，
  //    也是通过 RelSet 按物理属性过滤得到其 RelNode 子集合，见下面的 RelSubset 部分）
  final List<RelSubset> subsets = new ArrayList<>();

  /**
   * List of {@link AbstractConverter} objects which have not yet been
   * satisfied.
   */
  final List<AbstractConverter> abstractConverters = new ArrayList<>();

  /**
   * Set to the superseding set when this is found to be equivalent to another
   * set.
   * note：当发现与另一个 RelSet 有相同的语义时，设置为替代集合
   */
  RelSet equivalentSet;
  RelNode rel;

  /**
   * Variables that are set by relational expressions in this set and available for use 
   * by parent and child expressions.
   * 由本集合中的关系表达式设置，并可由父表达式和子表达式使用的变量。
   */
  final Set<CorrelationId> variablesPropagated;

  /**
   * Variables that are used by relational expressions in this set.
   * 此集合中的关系表达式使用的变量。
   */
  final Set<CorrelationId> variablesUsed;
  final int id;

  /**
   * Reentrancy flag.
   */
  boolean inMetadataQuery;
}
```

## `RelSubset`

关于 RelSubset，源码中介绍如下：

> 具有相同物理属性的等价**关系表达式**的子集。

它的特点如下：

1. 描述一组物理属性相同的等价关系表达式，即它们具有相同的物理属性
2. 每个 `RelSubset` 都会记录其所属的 RelSet；
3. `RelSubset` 继承自 `AbstractRelNode`，它也是一种 `RelNode`，物理属性记录在其成员变量 `traitSet` 中。

`RelSubset` 一些比较重要的成员变量如下：

```java
public class RelSubset extends AbstractRelNode {
  /**
   * cost of best known plan (it may have improved since)
   * note: 已知最佳 plan 的 cost
   */
  RelOptCost bestCost;

  /**
   * The set this subset belongs to.
   * RelSubset 所属的 RelSet，在 RelSubset 中并不记录具体的 RelNode，直接记录在 RelSet 的 rels 中
   */
  final RelSet set;

  /**
   * best known plan
   * note: 已知的最佳 plan
   */
  RelNode best;

  /**
   * Flag indicating whether this RelSubset's importance was artificially
   * boosted.
   * note: 标志这个 RelSubset 的 importance 是否是人为地提高了
   */
  boolean boosted;

  //~ Constructors -----------------------------------------------------------
  RelSubset(
      RelOptCluster cluster,
      RelSet set,
      RelTraitSet traits) {
    super(cluster, traits); // 继承自 AbstractRelNode，会记录其相应的 traits 信息
    this.set = set;
    this.boosted = false;
    assert traits.allSimple();
    computeBestCost(cluster.getPlanner()); //note: 计算 best
    recomputeDigest(); //note: 计算 digest
  }
}
```

每个 `RelSubset` 都将会记录其最佳计划（`best`）和最佳 计划的成本（`bestCost`）信息。

![](https://pic1.zhimg.com/80/v2-ba6cd69392ab326dc9fd43ae1884ae0c_1440w.jpg)

## VolcanoPlanner 处理流程

1. [Calcite 处理一条SQL - II (Rels Into Planner)](https://zhuanlan.zhihu.com/p/58801070)

在应用 VolcanoPlanner 时，整体分为以下四步：

1. 初始化 `VolcanoPlanner`，并添加相应的 Rule（包括 `ConverterRule`）；
2. 对 `RelNode` 做等价转换，这里只是改变其**物理属性**（`Convention`）；
3. 通过 `VolcanoPlanner` 的 `setRoot()` 方法注册相应的 `RelNode`，并进行相应的初始化操作；
4. ==通过动态规划算法找到 cost 最小的 plan==；

下面来分享一下上面的详细流程。

### VolcanoPlanner#setRoot

![](https://matt33.com/images/calcite/14-volcano.png)

对于 `setRoot()` 方法来说，核心的处理流程是在 `registerImpl()` 方法中，在这个方法会进行相应的初始化操作（包括 `RelNode` 到 `RelSubset` 的转换、计算 `RelSubset` 的 importance 等），其他的方法在上面有相应的备注，这里我们看下 `registerImpl()` 具体做了哪些事情：

#### VolcanoPlanner#registerImpl

```java
private RelSubset registerImpl(RelNode rel, RelSet set)
```

注册一个新的表达式 `rel` 并将==**匹配的规则**==排队。如果 `set` 不为空，那么就使表达式成为等价集合（`RelSet`）的一部分。如果已经注册了相同的表达式，则不需要再注册这个表达式，也不对匹配的规则进行排队。

- **RelSet** 描述一组逻辑上相等的关系表达式
- **RelSubset** 描述一组物理上相等的关系表达式，即具有相同的物理属性

##### 参数

1. `rel` - 要注册的关系式表达式。必须是 `RelSubset` 或未注册的 `RelNode`
2. `Set` - `rel` 所属的集合，或为空
3. 返回: `equivalence-set`

##### 处理流程

`registerImpl()` 处理流程比较复杂，其方法实现，可以简单总结为以下几步：

1. 在经过最上面的一些验证之后，会通过 `rel.onRegister(this)` 这步操作，递归地调用 `VolcanoPlanner` 的 `ensureRegistered()` 方法对其 `inputs` `RelNode` 进行注册，最后还是调用 `registerImpl()` 方法先注册叶子节点，然后再父节点，最后到根节点；
2. 根据 RelNode 的 digest 信息（一般这个对于 RelNode 来说是全局唯一的），判断其是否已经存在 `mapDigestToRel` 缓存中，如果存在的话，那么判断会 RelNode 是否相同，如果相同的话，证明之前已经注册过，直接通过 `getSubset()` 返回其对应的 `RelSubset` 信息，否则就对其 `RelSubset` 做下合并；
3. 如果 `RelNode` 对应的 `RelSet` 为空，这里会新建一个 `RelSet`，并通过 `addRelToSet()` 将 `RelNode` 添加到 `RelSet` 中，并且更新 `VolcanoPlanner` 的 `mapRel2Subset` 缓存记录（`RelNode` 与 `RelSubset` 的对应关系），在 `addRelToSet()` 的最后还会更新 `RelSubset` 的 **best plan** 和 **best cost**（每当往一个 `RelSubset` 添加相应的 `RelNode` 时，都会判断这个 RelNode 是否代表了 best plan，如果是的话，就更新）；
4. 将这个 RelNode 的 inputs 设置为其对应 RelSubset 的 children 节点（实际的操作时，是在 RelSet 的 `parents` 中记录其父节点）；
5. 强制重新计算当前 RelNode 对应 RelSubset 的 importance；
6. 如果这个 RelSubset 是新建的，会再触发一次 `fireRules()` 方法（会先对 RelNode 触发一次），遍历找到所有可以 match 的 Rule，对每个 Rule 都会创建一个 VolcanoRuleMatch 对象（会记录 RelNode、RelOptRuleOperand 等信息，RelOptRuleOperand 中又会记录 Rule 的信息），并将这个 VolcanoRuleMatch 添加到对应的 RuleQueue 中（就是前面图中的那个 RuleQueue）。

## 物化视图匹配

### `RelOptPredicateList`

Predicates that are known to hold in the output of a particular relational expression.

**Pulled up predicates** field `pulledUpPredicates` are predicates that apply to every row output by the relational expression. They are inferred from the input relational expression(s) and the relational operator. For example, if you apply `Filter(x > 1)` to a relational expression that has a predicate `y < 10` then the pulled up predicates for the Filter are `[y < 10, x > 1]`.

**Inferred predicates** only apply to joins. If there there is a predicate on the left input to a join, and that predicate is over columns used in the join condition, then a predicate can be inferred on the right input to the join. (And vice versa)。 For example, in the query

```sql
SELECT * FROM emp JOIN dept ON emp.deptno = dept.deptno WHERE emp.gender = 'F' AND emp.deptno < 10
```

we have

1. left: `Filter(Scan(EMP), deptno < 10)`, predicates: `[deptno < 10]`
2. right: `Scan(DEPT)`, predicates: `[]`
3. join: `Join(left, right, emp.deptno = dept.deptno`, 
   1. leftInferredPredicates: [], 
   2. rightInferredPredicates: [deptno < 10], 
   3. pulledUpPredicates: `[emp.gender = 'F', emp.deptno < 10, emp.deptno = dept.deptno, dept.deptno < 10]`

Note that the predicate from the left input appears in `rightInferredPredicates`. Predicates from several sources appear in `pulledUpPredicates`.

## 数据读取相关

### `Table`

创建 `Table` 的典型方式是，当 Calcite 询问用户定义的 Schema，以验证出现在 SQL 查询中的名称时。Calcite 通过调用 **Connection** 上的 **Root Schema** 的 `Schema.getSubSchema(String)` 来找到 **Schema**，然后通过调用 `Schema.getTable(String)` 获取一个表。

注意，`Table` 不知道自己的名称。事实上，一个 `Table` 可能在多个名称下或在多个 Schema 下被多次使用。与 UNIX 文件系统中的 ==i-node== 概念进行比较。

一个特定的表实例也可以实现 `Wrapper`，以提供对子对象的访问。

`AbstractTable` 用于实现 Table 的抽象基类。如果子类的表可能包含汇总值，则子类应覆盖 `isRolledUp` 和 `Table.rolledUpColumnValidInsideAgg(String, SqlCall, SqlNode, CalciteConnectionConfig)`。 验证器使用此信息来检查这些列的非法使用。

`JBDCTable` 从 JDBC 连接的表中获取数据的可查询对象。然而，我们不会读取整个表。这里的思路是通过应用 `Queryable.where(Predicate2)` 等 `Queryable` 运算符，将其用作查询的构建块。然后，可以将结果查询转换为 SQL 查询，该查询可以在 JDBC 服务器上高效执行。

### `TableScan`

返回  <u>`Table`</u> 内容的关系运算符。

### `RelOptTable`

表示 `RelOptSchema` 中的关系数据集。具有描述和实现自身的方法。

!translating a table to relational expression!

### `RelOptSchema`

`RelOptSchema` 是一组 RelOptTable 对象。

<img src='https://g.gravizo.com/svg?
digraph G { 
  rankdir=BT  
  CatalogReader -> RelOptSchema [style=dashed]
  CatalogReader -> SqlValidatorCatalogReader [style=dashed]
  CatalogReader -> SqlOperatorTable [style=dashed]
  CalciteCatalogReader -> CatalogReader 
  CalciteCatalogReader -> CalciteSchema [dir=both, arrowtail=odiamond]
  {
      rank = same
      CalciteCatalogReader
      CalciteSchema
  }  
  PreparingTable -> RelOptTable [style=dashed]
  PreparingTable -> SqlValidatorTable [style=dashed]
  RelOptTableImpl->AbstractPreparingTable-> PreparingTable  
  CatalogReader -> PreparingTable [dir=both, arrowtail=odiamond label=getTableForMember  style=dotted]
  {
      rank = same
      CatalogReader
      PreparingTable
  }
  CalciteSchema -> Schema -> Table  [dir=both, arrowtail=odiamond]  
  Table -> PreparingTable [dir=both, arrowtail=odiamond]
}'>

## LatticeSuggester

[CALCITE-3286] In LatticeSuggester, allow join conditions that use expressions

![](http://www.plantuml.com/plantuml/png/XLPDRzms4BthLxpwv03s0krHCHPntAOnaFGZszvycPLc9ROKgP2Z9axh_FQAeWYJwmryIGJEztjlPltA2pcP1brz9pqF3B7tbQ61_KWDOo1XfqYhBun_Aw3Hv3tUaOXgU3Uxn6VWFOrNxvINgvquPRhjHNBwW_QQjv3mt-oqEF_iQEolSeSBx8J7BRh5_ZKtmN6dlB0x_y3wrr7Yexo8dY4CrBO_jHsV5s7UJgxXYpjJl0gvZYMyXcPlZVn6octnDz_xaF6X0emLnjwAsA56dF6JabuPVEfLqqF7V1xyMNcfIbHIdOXAqV7o4k41QKN-LBroP6wX3AHdT06oJOK2-xhkSFRz6UpbvHPdvgneeNh8U4nHKzTnI1pQexqNHutWZPlzOiDOO7bhPofwE_gNsUFxANB8v2V7Mmpn8_diMAwMkX_u4EYENycgZA2nUXhCZPsClCn75plMk3K7wmOIPGreRoTPfXx9iH7O0mwATUjnS7O0mR5UN4dF98oElLVMR1wfc0V0EX1Ua-SRg-TcLaayVO-Yo7jogkkbndL00Sg3y9TL1eqrhPAYLfOdL4mGGAfrwbCipmxis3HXU13sv3d24n9dpCIyHqtTB8vmASTZAp-oK_zmcxg9p9safLh4-VaNspAuUbwNnnstiTBQz9qvbvu4ob-0J4R9YqUSCcXYP-LM1i6kEh6kLORqhVbzOdT_gfa_FGTDK8nBsqdu608sT-PwDJHai6TCdbiCrZ6a9mDh6ixwAdMTLBFxgA-xxiracYZ9hdFSaIJnxAtLJ0Qjyg9cd_Nvwu9tn7yBSjqqi14VhGdZi9Mdj9PLGKDQpuEyviOEx45fsz8vE0I4uYKgXbaWYpCKHzg7VzEX3cUFEtONEAsCI8CN7kU7PL-VhEjR6xRHI-ZrO1qehEfSRjBa8WthnRepjoQtHMB8j4l-Hn5xDA5GNF0lx2oOcdvbjCAw2RZwx_8osxZIKEg_GkPOrv9TolaZJLuXYugE2OdYj6O1yLxMTM_7qYUSdKVpitaYMQlZJCjpzTB1BVrA-LOe7-QmfCAZk0HIQ3fQWk67inpTXqePONUWXlEVikheCeHj3mNAmzoIa6V1ifanUjVqF53GXA0dZu6bjws7MBJi6wVsKHfg63M7dg74ipvigkFVhqs2fs0r_tDbKnoOEWhlQPw5WsUJn2MgrpNwLfKYJG8ibQzUiMcdGVyF)

### `LatticeSpace`

Lattice 存在的空间。

###  `Hop`

一跳是一个 Join 条件， 同一源和目标之间的**一跳或多跳**组合形成一个**Step**。

表已注册，但 **Step** 未注册。在我们收集了几个 Join 条件之后，我们可能会发现这些 **key** 是组合的，例如：

```sql
x.a = y.a AND
x.b = z.b AND
x.c = y.c
```

有 3 个 ==semi-hops==:

- x.a = y.a

- x.b = z.b

- x.c = y.c

这变成了 2 个 Step，其中第一个是组合 Step：

- x.[a, c] = y.[a, c]
- x.b = z.b

### `Step`

连接图中的边。它是有向的：“父”必须是包含外键的“多”侧，“目标”是包含主键的“一”侧。 例如，`EMP → DEPT`。当通过 `LatticeSpace.addEdge(LatticeTable, LatticeTable, List)` 创建时，它在 `LatticeSpace` 中是唯一的。

###  `LatticeSuggester#Frame`

关系表达式中字段父级的相关信息。

# 其他有趣的 issue

## 2014-08-14 [[CALCITE-360]](https://issues.apache.org/jira/browse/CALCITE-360) Introduce a Rule to infer predicates from equi join conditions

引入 `RelOptPredicateList`  和  `RelMdPredicates`

## [[CALCITE-419]](https://issues.apache.org/jira/browse/CALCITE-419) Naming convention for planner rules

I propose a new naming convention for planner rules. This change would rename existing rules.

The naming convention is advisory, not mandatory. Rule authors would not need to follow it if they don’t feel that it makes things clearer.

Discussion from the dev list:

As the number of rules grows, it becomes more difficult to find out whether a similar rule has already been added. The fact that there are several ways to name a rule adds to the confusion.

For instance, consider a rule that converts ‘join(project( x ), project( y ))’ into ‘project(join(x, y))’. The actual rule is called PullUpProjectsAboveJoinRule but it could equally be called PushJoinThroughProjectsRule.

There are lots of rules called PushXxxThroughYyyRule, too.

I propose the naming convention

<Reltype1><Reltype2>[…]<Verb>Rule

where ReltypeN is the class of the Nth RelNode matched, in depth-first order, ignoring unimportant operands, and removing any ‘Rel’ suffix
Verb is what happens — typically Transpose, Swap, Merge, Optimize.

Thus:

- PullUpProjectsAboveJoinRule becomes JoinProjectTransposeRule
- PushAggregateThroughUnionRule becomes AggregateUnionTransposeRule
- MergeProjectRule becomes ProjectMergeRule
- MergeFilterOntoCalcRule becomes FilterCalcMergeRule
- EnumerableJoinRule remains EnumerableJoinRule (Or how about JoinAsEnumerableRule?)
- SwapJoinRule becomes JoinSwapInputsRule

## [[CALCITE-707]](https://issues.apache.org/jira/browse/CALCITE-707) Add "server" module, with built-in support for simple DDL statements

> I would like Calcite to support simple DDL.
>
> DDL (and other commands such as KILL STATEMENT) make it possible to do a wide range of operations over a REST or JDBC interface. We can't expect everything do be done locally, using Java method calls.
>
> I expect that projects that use Calcite will define their own DDL. (In fact Drill and Phoenix already do; see PHOENIX-1706.) Those projects are very likely to have their own variations on CREATE TABLE etc. so they will want to extend the parser. What I did in Phoenix (which was in turn adapted from Drill) is a model that other projects can follow.
>
> But the base Calcite project should have CREATE TABLE, DROP TABLE, CREATE SCHEMA, DROP SCHEMA, CREATE [ OR REPLACE ] VIEW etc. There will be an AST (extending SqlNode) for each of these commands, and a command-handler. Each project that uses Calcite could extend those
>
> ASTs, but it would be fine if it built its own AST and command-handler.

See [Server](http://calcite.apache.org/docs/adapter.html#server)

The default parser in core does not contain DDL. We do not want to impose our DDL dialect on sub-projects. 

1. In server module's parser, add CREATE [FOREIGN] SCHEMA, DROP SCHEMA, CREATE TABLE, CREATE TABLE AS ..., DROP TABLE, CREATE VIEW, CREATE MATERIALIZED VIEW, DROP VIEW.
2. CREATE TABLE supports STORED and VIRTUAL generated columns, default column values, and constraints.
3. Add Quidem test in server module; QuidemTest is now abstract, and has sub-class CoreQuidemTest in core module.
4. Add class ColumnStrategy, which describes how a column is populated.
5. All CREATE commands have IF NOT EXISTS (except CREATE VIEW, which has OR REPLACE), and all DROP commands have IF EXISTS.
6. Add SqlDdl as base class for SqlCreate and SqlDrop. Add SqlOperator as first argument to SqlCreate and SqlDrop constructors, and deprecate
   previous constructors. 
7. Ensure that collations deduced for Calc are sorted.
8. Add Static.cons as short-hand for ConsList.of.

##  [[CALCITE-1216]](https://issues.apache.org/jira/browse/CALCITE-1216) Add new rules for Materialised view optimisation of join queries

> 语义缓存

This is to keep track of adding new rules that would enable optimisation using view of join queries. For instance, when we have materialised view of table 'X' named 'X_part' defined by query: " select * from X where X.a > '2016-01-01' " then we expect following query to be optimised by 'X_part':

select * from X inner join Y on X.id = Y.xid inner join Z on Y.id=Z.yid where X.a > '2016-02-02' and Y.b = "Bangalore"

Following are the changes done in Quark which we are planning to pull into Calcite:
1. Add a new Rule for Filter on TableScan. Basically, after predicate has been pushed through join onto table scan, new rule checks if it can be optimised by Materialised View.
https://github.com/qubole/quark/blob/master/optimizer/src/main/java/com/qubole/quark/planner/MaterializedViewFilterScanRule.java

2. Add a new Unify rule to MaterialisedSubstitutionVisitor:
https://github.com/qubole/incubator-calcite/commit/2d031d14d23810291377d92dc5ef2eaa515d35b7

##  [[CALCITE-2280]](https://issues.apache.org/jira/browse/CALCITE-2280) Liberal "babel" parser that accepts all SQL dialects

> Create a parser that accepts all SQL dialects.
>
> It would accept common dialects such as Oracle, MySQL, PostgreSQL, BigQuery. If you have preferred dialects, please let us know in the comments section. (If you're willing to work on a particular dialect, even better!)
>
> We would do this in a new module, inheriting and extending the parser in the same way that the DDL parser in the "server" module does.
>
> This would be a messy and difficult project, because we would have to comply with the rules of each parser (and its set of built-in functions) rather than writing the rules as we would like them to be. That's why I would keep it out of the core parser. But it would also have large benefits.
>
> This would be new territory Calcite: as a tool for manipulating/understanding SQL, not (necessarily) for relational algebra or execution.
>
> Some possible uses:
>
> 1. analyze query lineage (what tables and columns are used in a query);
> 2. translate from one SQL dialect to another (using the JDBC adapter to generate SQL in the target dialect);
> 3. a "deep" compatibility mode (much more comprehensive than the current compatibility mode) where Calcite could pretend to be, say, Oracle;
> 4. SQL parser as a service: a REST call gives a SQL query, and returns a JSON or XML document with the parse tree.
>
> If you can think of interesting uses, please discuss in the comments.
>
> There are similarities with Uber's QueryParser tool. Maybe we can collaborate, or make use of their test cases.
>
> We will need a lot of sample queries. If you are able to contribute sample queries for particular dialects, please discuss in the comments section. It would be good if the sample queries are based on a familiar schema (e.g. scott or foodmart) but we can be flexible about this.

##  [[CALCITE-3923]](https://issues.apache.org/jira/browse/CALCITE-3923) Refactor how planner rules are parameterized

> People often want different variants of planner rules. An example is `FilterJoinRule`, which has a 'boolean smart’ parameter, a predicate (which returns whether to pull up filter conditions), operands (which determine the precise sub-classes of `RelNode` that the rule should match) and a `RelBuilderFactory` (which controls the type of `RelNode` created by this rule).
>
> Suppose you have an instance of `FilterJoinRule` and you want to change `smart` from true to false. The `smart` parameter is immutable (good!) but you can’t easily create a clone of the rule because you don’t know the values of the other parameters. Your instance might even be (unbeknownst to you) a sub-class with extra parameters and a private constructor.
>
> So, my proposal is to put all of the config information of a `RelOptRule` into a single `config` parameter that contains all relevant properties. Each sub-class of `RelOptRule` would have one constructor with just a ‘config’ parameter. Each config knows which sub-class of `RelOptRule` to create. Therefore it is easy to copy a config, change one or more properties, and create a new rule instance.
>
> Adding a property to a rule’s config does not require us to add or deprecate any constructors.
>
> The operands are part of the config, so if you have a rule that matches a `EnumerableFilter` on an `EnumerableJoin` and you want to make it match an `EnumerableFilter` on an `EnumerableNestedLoopJoin`, you can easily create one with one changed operand.
>
> The config is immutable and self-describing, so we can use it to automatically generate a unique description for each rule instance.
>
> (See the email thread [[DISCUSS\] Refactor how planner rules are parameterized](https://lists.apache.org/thread.html/rfdf6f9b7821988bdd92b0377e3d293443a6376f4773c4c658c891cf9%40).)

# Avatica

Avatica is a framework for building JDBC and ODBC drivers for databases, and an RPC wire protocol.

![Avatica Architecture](https://raw.githubusercontent.com/julianhyde/share/master/slides/avatica-architecture.png)

Avatica的Java绑定依赖很少。即使它是 Apache Calcite 的一部分，它也不依赖于 Calcite 的其他部分。它只依赖于 JDK 8+ 和 Jackson。Avatica 的协议是 HTTP 上的 JSON 或 Protocol Buffers。JSON 协议的 Java 实现使用 [Jackson](https://github.com/FasterXML/jackson)，将请求/响应命令对象与 JSON 相互转换。Avatica-Server 是 Avatica RPC 的 Java 实现。

核心概念：

- [Meta](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/Meta.html) 是一个本地 API，足以实现任何 Avatica Provider
- [AvaticaFactory](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/AvaticaFactory.html) 在 `Meta` 之上创建 JDBC 类的实现
- [Service](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/remote/Service.html) 是一个接口，在请求和响应命令对象方面实现了 `Meta` 的功能

## JDBC

Avatica 通过 [AvaticaFactory](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/AvaticaFactory.html) 实现 JDBC。`AvaticaFactory` 的实现在 `Meta` 之上创建了 JDBC 类的实现 ([Driver](https://docs.oracle.com/javase/8/docs/api//java/sql/Driver.html), [Connection](https ://docs.oracle.com/javase/8/docs/api//java/sql/Connection.html), [Statement](https://docs.oracle.com/javase/8/docs/api// java/sql/Statement.html)、[ResultSet](https://docs.oracle.com/javase/8/docs/api//java/sql/ResultSet.html)) 。



![](https://img-blog.csdn.net/20140612101655500?watermark/2/text/aHR0cDovL2Jsb2cuY3Nkbi5uZXQvbHVhbmxvdWlz/font/5a6L5L2T/fontsize/400/fill/I0JBQkFCMA==/dissolve/70/gravity/SouthEast)

## ODBC

Work has not started on Avatica ODBC.

Avatica ODBC would use the same wire protocol and could use the same server implementation in Java. The ODBC client would be written in C or C++.

Since the Avatica protocol abstracts many of the differences between providers, the same ODBC client could be used for different databases.

Although the Avatica project does not include an ODBC driver, there are ODBC drivers written on top of the Avatica protocol, for example [an ODBC driver for Apache Phoenix](http://hortonworks.com/hadoop-tutorial/bi-apache-phoenix-odbc/).

## HTTP Server

Avatica-server embeds the Jetty HTTP server, providing a class [HttpServer](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/server/HttpServer.html) that implements the Avatica RPC protocol and can be run as a standalone Java application.

Connectors in HTTP server can be configured if needed by extending `HttpServer` class and overriding its `configureConnector()` method. For example, user can set `requestHeaderSize` to 64K bytes as follows:

```
HttpServer server = new HttpServer(handler) {
  @Override
  protected ServerConnector configureConnector(
      ServerConnector connector, int port) {
    HttpConnectionFactory factory = (HttpConnectionFactory)
        connector.getDefaultConnectionFactory();
    factory.getHttpConfiguration().setRequestHeaderSize(64 << 10);
    return super.configureConnector(connector, port);
  }
};
server.start();
```

## Project structure

We know that it is important that client libraries have minimal dependencies.

Avatica is a sub-project of [Apache Calcite](https://calcite.apache.org/), maintained in a separate repository. It does not depend upon any other part of Calcite.

Packages:

- [org.apache.calcite.avatica](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/package-summary.html) Core framework
- [org.apache.calcite.avatica.remote](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/remote/package-summary.html) JDBC driver that uses remote procedure calls
- [org.apache.calcite.avatica.server](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/server/package-summary.html) HTTP server
- [org.apache.calcite.avatica.util](https://calcite.apache.org/avatica/javadocAggregate/org/apache/calcite/avatica/util/package-summary.html) Utilities

## Status

### Implemented

- Create connection, create statement, metadata, prepare, bind, execute, fetch
- RPC using JSON over HTTP
- Local implementation
- Implementation over an existing JDBC driver
- Composite RPCs (combining several requests into one round trip)
  - Execute-Fetch
  - Metadata-Fetch (metadata calls such as getTables return all rows)

### Not implemented

- ODBC
- RPCs
  - CloseStatement
  - CloseConnection
- Composite RPCs
  - CreateStatement-Prepare
  - CloseStatement-CloseConnection
  - Prepare-Execute-Fetch (Statement.executeQuery should fetch first N rows)
- Remove statements from statement table
- DML (INSERT, UPDATE, DELETE)
- Statement.execute applied to SELECT statement

## Clients

The following is a list of available Avatica clients. Several describe themselves as adapters for [Apache Phoenix](http://phoenix.apache.org/) but also work with other Avatica back-ends. Contributions for clients in other languages are highly welcomed!

### Microsoft .NET driver for Apache Phoenix Query Server

- [Home page](https://github.com/Azure/hdinsight-phoenix-sharp)
- Language: C#
- *License*: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Avatica version 1.2.0 onwards
- *Maintainer*: Microsoft Azure

### Apache Phoenix/Avatica SQL Driver

- [Home page](https://github.com/apache/calcite-avatica-go)
- *Language*: Go
- *License*: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Avatica version 1.8.0 onwards
- *Maintainer*: Boostport and the Apache Calcite community

### Avatica thin client

- [Home page](https://calcite.apache.org/avatica)
- *Language*: Java
- *License*: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Any Avatica version
- *Maintainer*: Apache Calcite community

### Apache Phoenix database adapter for Python

- [Home page](https://bitbucket.org/lalinsky/python-phoenixdb)
- Language: Python
- *License*: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Avatica version 1.2.0 to 1.6.0
- *Maintainer*: Lukáš Lalinský

### JavaScript binding to Calcite Avatica Server

- [Home page](https://github.com/waylayio/avatica-js)
- Language: JavaScript
- *License*: [MIT](https://opensource.org/licenses/MIT)
- Any Avatica version
- *Maintainer*: Waylay.io



![](http://www.plantuml.com/plantuml/png/ZPD1JuGm48Nl_8hnfeVz0ys6hDbus8E9ojLB0ozAKWOiK-F-UokbDCL5zyhxtkjCUJsCegsupXGtyeuE9FsvE9eMBBGhwTWpevQsPqMrXHPKeiLpBBTtHL9fv-7PfiX2d6KQ9vIbq9xvr09QpEc8vHCfVA5sWcS7U_RfISa76Im6RN7FpIi_1Ck91PQrMSrKqYD4AqgEcVVSZp85QrEtWcGxTODHvFbncUGYaynu2lcAzljmIMMPTiwPQxCehbbzJ5lbeiV_EZEAsxOyVT4JGAhrSw5ZMUbvPFpNqTQyO7H6YWR_ph9zzo4ogbNxnjf_G0gzzbBd0f3QIWmboEeLsRafOPzLqrEF8nsm2f9Qcps9NrY32u_Y06vSPxu1)

<img src='https://g.gravizo.com/svg?
digraph G {
  rankdir=BT
  CalcitePrepareImpl->CalcitePrepare
  CalciteJdbc41Statement->CalciteStatement->AvaticaStatement->Statement
  CalciteJdbc41Connection->CalciteConnectionImpl->AvaticaConnection->Connection
  CalciteMetaImpl->MetaImpl->Meta
  {
      rank=same
      Statement
      Connection
  }
  {
      rank=same
      Meta
      AvaticaConnection
  }
  AvaticaConnection->Meta [label=创建 style=dashed]
  Connection->Statement [label=创建 style=dashed]
  CalciteConnectionImpl->CalcitePrepare [label=parseQuery style=dashed]
  {
      rank=same
      CalciteConnectionImpl
      CalcitePrepare
  }
  CalciteMaterializer->CalcitePreparingStmt -> Prepare
  CalciteSignature->Signature
}'>

![](http://www.plantuml.com/plantuml/png/TP31JiCm38RlVWfpHMeVO4BLE710uiHu0I-OKId9giGxeB5tfwd1IwXsI_t_ts__tMQX9AVWuKu-EJ1EdiO8OnHE7-GOtsZl6MYV9P4JV8gIll1y0USfPtmXaT7nCdqEavy5aEE1vwo4Pq0qq9pALvAkC65EqFV3TzSrM3s_Cc0M4rTdjPvZDzGxDtXWsGcbPOO3LDhzdnLkzRg2RQbNzhrfEqTHkxKf-XCVVvagHeMIyPzNKwdPSc1VPh3r0FR4lX_MjstG9IOfvI5Iu3oHus9RhZIRhcr8kC2Mu_if-1y0)                                                                                                                                                                                                                                                  