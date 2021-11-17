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

（如果您运行的是 Windows，则命令为 sqlline.bat。）

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

## Schema

现在，Calcite 如何找到这些表？请记住，Calcite Core 对 CSV 文件一无所知。 作为**没有存储层的数据库**，Calcite 不知道任何文件格式。Calcite 知道这些表，因为我们告诉它运行 `calcite-example-csv` 项目中的代码。

这里有几个步骤。**首先**，我们根据模型文件中的 <u>Schema 工厂类</u>定义 Schema 。**然后** <u>Schema 工厂</u>创建 Schema，Schema 创建几个表，每个表都知道如何通过扫描 CSV 文件获取数据。**最后**，在 Calcite 解析查询并计划它使用这些表之后，Calcite 在执行查询时调用这些表来读取数据。现在让我们更详细地了解这些步骤。

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

该模型定义了一个名为 `SALES` 的 Schema，它由插件类 [`org.apache.calcite.adapter.csv.CsvSchemaFactory`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvSchemaFactory.java) 提供支持，该类是 calcite-example-csv 项目的一部分，并实现了 Calcite [`SchemaFactory`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/SchemaFactory.html) 接口，其 `create` 方法实例化一个模式，从模型文件中传入目录参数：

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

模型驱动下，模式工厂实例化了一个名为 `SALES` 的 Schema。 该 Schema 是 [`org.apache.calcite.adapter.csv.CsvSchema`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvSchema.java) 的一个实例，并实现了 Calcite [Schema 接口](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/Schema.html)。

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

**注意**，我们不需要在模型中定义任何表； schema 自动生成表。除了自动创建的表之外，您还可以使用 Schema 的 `tables` 属性定义额外的表。

让我们看看如何创建一个重要且有用的表类型，即视图。当您编写查询时，视图看起来像一张表，但它不存储数据。它通过执行查询获得结果。在优划查询时，会展开视图，因此查询优化器通常可以执行优化，比如从 `SELECT` 子句中删除最终结果中没有使用的表达式。

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

`type:'view'` 将 `FEMALE_EMPS` 标记为视图，而不是常规的表或者自定义的表。注意，视图定义中的单引号使用反斜杠转义，这是 JSON 的正常方式。

JSON 并不便于写长字符串，因此 Calcite 支持另一种语法。如果创建视图是一个很长的 SQL ，可以改为提供行列表而不是单个字符串：

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

自定义表是由用户代码实现的表，不需要在自定义模式的中定义它们。在 `model-with-custom-table.json` 中有一个例子:

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

这是一个常规 Schema，并包含一个由 [`org.apache.calcite.adapter.csv.CsvTableFactory`](https://github.com/apache/calcite/blob/master/example/csv/src/main/java/org/apache/calcite/adapter/csv/CsvTableFactory.java) 支持的自定义表，它实现了 Calcite [TableFactory](https://calcite.apache.org/javadocAggregate/org/apache/calcite/schema/TableFactory.html) 接口。 它的 `create` 方法实例化一个 `CsvScannableTable`，`file` 参数从模型文件中传入：

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

实现自定义表通常是实现自定义模式的更简单的替代方法。这两种方法最终可能会创建 `Table` 接口的类似实现，对于自定义表，您不需要实现元数据发现。`CsvTableFactory` 创建一个 `CsvScannableTable`，就像 `CsvSchema` 一样，但表实现不会扫描文件系统以查找 `.csv` 文件。

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

Calcite 确实使用成本模型。成本模型决定最终使用哪个计划，有时裁剪搜索树以防止搜索空间爆炸，但它从不强迫您在规则 A 和规则 B 之间进行选择。这很重要，因为它避免<u>陷入局部最小值，但在实际上不是最优的搜索空间</u>。

此外（您已经猜到了）成本模型是可插入的，它所基于的表和查询运算符统计也是如此，但这可以以后再谈。

## JDBC 适配器

JDBC 适配器将 JDBC 数据源中的 Schema 映射为 Calcite Schema。例如，这个 Schema 从 MySQL foodmart 数据库中读取：

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

还有许多扩展 Calcite 的方法没在本教程中描述。[适配器规范](https://calcite.apache.org/docs/adapter.html)描述了所涉及的 API。

# 代数

内容在其他

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

类路径中包含 calcite-server.jar，并将 `parserFactory=org.apache.calcite.sql.parser.ddl.SqlDdlParserImpl#FACTORY`  添加到 JDBC 连接字符串（请参阅连接字符串属性 `parserFactory`），即可启用。下面使用 sqlline shell 的示例：

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

所有关系运算符都实现 [RelNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/RelNode.html) 接口，大多数扩展至类 [AbstractRelNode](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/AbstractRelNode.html)。核心运算符（由 [SqlToRelConverter](https://calcite.apache.org/javadocAggregate/org/apache/calcite/sql2rel/SqlToRelConverter.html) 使用并涵盖常规关系代数）是 [`TableScan`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableScan.html)、[`TableModify`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/TableModify.html)、[`Values`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Values.html)、[`Project`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Project.html)、[`Filter`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Filter.html)、[`Aggregate`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Aggregate.html)、[`Join`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Join.html)、[`Sort`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Sort.html)、[`Union`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Union.html)、[`Intersect`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Intersect.html)、[`Minus`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Minus.html)、[`Window`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Window.html) 和 [`Match`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/core/Match.html)。

其中每一个都有一个**纯**的逻辑子类，比如 [`LogicalProject`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/rel/logical/LogicalProject.html) 等等。任何给定的适配器都有对应的引擎可以有效实现的操作，例如，Cassandra 适配器有 [`CassandraProject`](https://calcite.apache.org/javadocAggregate/org/apache/calcite/adapter/cassandra/CassandraProject.html) 但没有 `CassandraJoin`。

您可以定义自己的 `RelNode` 子类来添加新的运算符，或在特定引擎中实现现有运算符。

为了使运算符有用且强大，您需要[优化器规则](https://calcite.apache.org/docs/adapter.html#planner-rule)将其与现有运算符相结合。并提供元数据，见[下文](https://calcite.apache.org/docs/adapter.html#statistics-and-cost)。**这是代数，效果是组合的：您编写一些规则，但它们组合起来处理指数数量的查询模式**。

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


# 历史 

## 第一次支持[视图匹配](https://github.com/apache/calcite/commit/13136f9e4b7f4341d5cdce5b9ca8d498f353bb30) 

具体算法不知道。随后的 Commit，[Before planning a query, prune the materialized tables used to those that might help](https://github.com/apache/calcite/commit/0eb66bbb462bfb9bfd3bdfc9f2fb2d602958bcbd) 在 `VocanoPlanner` 里增加了一个 `originalRoot`。

> 优化查询之前，找到那些可能有帮助的物化表。

## 第一次实现视图 [`SubstitutionVisitor`](https://github.com/apache/calcite/commit/026ff5186edb1c1735b7caa8e2b569e22a1b998c) 算法

用一个**关系表达式树**替换**另一个关系表达式树的一部分**。

调用 `new SubstitutionVisitor(target, query).go(replacement))` 返回每次 `target` 被 `replacement` 替换的查询。以下示例展示如何使用 `SubstitutionVisitor` 识别物化视图。

```
query = SELECT a, c FROM t WHERE x = 5 AND b = 4
target = SELECT a, b, c FROM t WHERE x = 5
replacement = SELECT * FROM mv
result = SELECT a, c FROM mv WHERE b = 4
```

请注意，结果使用了物化视图表 mv 和简化条件 b = 4。使用**自下而上**的匹配算法。节点不需要完全相同。 每层都返回残差。输入必须只包含核心**关系运算符**：`TableAccessRel`, `FilterRel`, `ProjectRel`, `JoinRel`, `UnionRel`, `AggregateRel`.

## 🔴 [支持视图 Filter](https://github.com/apache/calcite/commit/60e4da419027885e772abe209b2bfb04371c67ae)

识别包含过滤器的物化视图。为此，添加了将谓词（例如“x = 1 和 y = 2”）拆分为由底层谓词“y = 2”处理和未处理的部分的算法。

## 2013-11-15 [增加 `StarTable`](https://github.com/apache/calcite/commit/ef0acca555e6d78d08ea1aa5ecc6d7b42f689544)

这是**识别复杂物化**的第一步，**星型表**是通过多对一关系连接在一起的真实表组成的虚拟表。定义物化视图的查询和最终用户的查询按照星型表规范化。匹配(尚未完成)将是寻找 `sort`、`groupBy`、`Project` 的问题。

==现在，我们已经添加了一个虚拟模式 mat 和一个虚拟星型表 star。稍后，模型将允许显式定义星型表==。

- `StarTable`：**虚拟表**由两个或多个 `Join` 在一起的表组成。`StarTable` 不会出现在最终用户查询中，由优化器引入，以有助于查询和物化视图之间的匹配，并且仅在优化过程中使用。定义物化视图时，如果涉及 J`oin`，则将其转换为基于 `StarTable` 的查询。候选查询和物化视图映射到同一个 `StarTable` 上

###  `OptiqMaterializer`：填充 `Prepare.Materialization` 的上下文

识别并替换 `queryRel` 中的 `StarTable`。

- 可能没有 `StarTable` 匹配。 没关系，但是识别的物化模式不会那么丰富。
- 可能有多个 StarTable 匹配。**TBD**：我们应该选择最好的（不管这意味着什么），还是全部？

###   `RelOptMaterialization`：记录由特定表物化的特定查询

- `tryUseStar(...)`：将关系表达式转换为使用 `StarTable` 的关系表达式。 根据 `toLeafJoinForm(RelNode)`，关系表达式已经是**==叶连接形式==**。

## 🔴Support filter query on project materialization, where project contains expressions.

编译失败

## 🔴Support Group By

编译失败

## 2014-7-14 第一次实现 `Lattice` 结构 - [CALCITE-344](https://issues.apache.org/jira/browse/CALCITE-344)

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

## [CALCITE-1389: Add rule to perform rewriting of queries using materialized views with joins](https://issues.apache.org/jira/browse/CALCITE-1389)

第一次按 Optimizing Queries Using Materialized Views: A Practical, Scalable Solution 这篇 paper 来实现

> 自由形式的物化视图的问题在于它们往往有很多。这篇论文旨在解决这个问题，**lattice** 也是如此。但是 lattice 更好：它们可以收集统计数据，并建议创建不存在但可能有用的视图。
>
> **Lattice** 本质上与论文中描述的 ==SPJ 视图==相同，当然，今天需要手工创建它们。我认为对于 DW 风格的工作负载，手工创建格子比手工创建 MV 实用得多。这不仅是为了让优化器的工作更轻松，也是为了让 DBA 的工作更轻松。MV 并不容易操作管理。无论如何，如果人们手工创建了很多 MV，我的想法是拥有一种自动创建 lattice 的算法，从而降低检查所有这些 MV 的成本。
>
> 在我看来，主要的缺失部分是一种算法，该算法在给定一组 MV 的情况下，创建一组最佳的 lattice，使得每个 MV 都属于一个格子。

## 2017-01-31: [CALCITE-1500: Decouple materialization and lattice substitution from VolcanoPlanner](https://issues.apache.org/jira/browse/CALCITE-1500)



## [CALCITE-1682: New metadata providers for expression column origin and all predicates in plan](https://issues.apache.org/jira/browse/CALCITE-1682)

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

## [CALCITE-1731: Rewriting of queries using materialized views with joins and aggregates](https://issues.apache.org/jira/browse/CALCITE-1731)

还是类似 [[1]](#Optimizing Queries Using Materialized Views: A Practical, Scalable Solution) 来重写**计划**

我试图在 [CALCITE-1389](https://issues.apache.org/jira/browse/CALCITE-1389) 的基础上工作。然而，最后我还是创建了一个新的替代规则。主要原因是我想更密切地 <u>==follow==</u> 论文，而不是依赖于 物化视图重写中触发的规则来查找表达式是否等价。相反，我们使用 [CALCITE-1682](https://issues.apache.org/jira/browse/CALCITE-1682) 中提出的新 **metadata provider** 从<u>查询计划</u>和<u>物化视图计划</u>中提取信息，然后我们使用该信息来验证和执行重写。

我还在规则中实现了新的统一/重写逻辑，因为现有的聚合统一规则假设查询中的聚合输入和物化视图需要等价（相同的 Volcano 节点）。该条件可以放宽，因为我们在规则中通过使用如上所述的新 **metadata provider**  验证查询结果是否包含在 物化视图 中。

我添加了多个测试，==但欢迎任何指向可以添加以检查正确性/覆盖率的新测试的反馈==。算法可以触发对同一个查询节点的多次重写。此外，<u>支持在查询/MV 中多次使用表</u>。

将遵循此问题的一些扩展：

- 扩展逻辑以过滤给定查询节点的相关 MV，因此该方法可随着 MV 数量的增长而扩展。
- 使用联合运算符生成重写，例如，可以从 MV (year = 2014) 和查询 (not(year = 2014)) 部分回答给定的查询。如果存储了 MV，例如在 Driud 中，这种重写可能是有益的。与其他重写一样，是否最终使用重写的决定应该基于成本。



---
# 基本概念

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

## Calcite 的 Calling Convention

Calling Convention 在 Calcite 中使用接口 `Convention` 表示，`Convention` 接口是 `RelTrait` 的子接口，**所以是一个算子的属性**。可以把 Calling Convention 理解为**==一个特定数据引擎协议==**，拥有相同 `Convention` 的算子可以认为都是一个统一数据引擎的算子，<u>可以相互连接起来</u>。比如 JDBC 的算子 `JDBCXXX ` 都有 `JdbcConvention`，Calcite 内建的 `Enumerable` 算子 `EnumerableXXX` 都有 `EnumerableConvention`。

![](https://pic3.zhimg.com/v2-5ae8eafe4ea0e9cb405c7f1c71ddbd6a_r.jpg)

上图中，Jdbc 算子可以通过 `JdbcConvention` 获得对应数据库的 `SqlDialect` 和 `JdbcSchema` 等数据，这样可生成对应数据库的 sql，**获得数据库的连接池与数据库交互实现算子的逻辑**。 如果数据要从一个 Calling Convention 的算子到另一个 Calling Convention 算子的时候，比如[这篇使用 Calcite 进行跨库 join 文章描述的场景](https://zhuanlan.zhihu.com/p/143935885)。需要 `Converter` 接口的子类作为两种算子之间的桥梁将两种算子连接起来。

![](https://pic2.zhimg.com/80/v2-7ce0b21af232a9c29af18b56b4a08741_1440w.jpg)

比如上面的执行计划，要将 `Enumerable` 的算子与 `Jdbc` 的算子连接起来，中间就要使用 `JdbcToEnumerableConverter` 作为桥梁。

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

## 数据读取相关

### `Table`

创建 `Table` 的典型方式是，当 Calcite 询问用户定义的 Schema，以验证出现在 SQL 查询中的名称时。Calcite 通过调用 **Connection** 上的 **Root Schema** 的 `Schema.getSubSchema(String)` 来找到 **Schema**，然后通过调用 `Schema.getTable(String)` 获取一个表。

注意，`Table` 不知道自己的名称。事实上，一个 `Table` 可能在多个名称下或在多个 Schema 下被多次使用。与 UNIX 文件系统中的 ==i-node== 概念进行比较。

一个特定的表实例也可以实现 `Wrapper`，以提供对子对象的访问。

`AbstractTable` 用于实现 Table 的抽象基类。如果子类的表可能包含汇总值，则子类应覆盖 `isRolledUp` 和 `Table.rolledUpColumnValidInsideAgg(String, SqlCall, SqlNode, CalciteConnectionConfig)`。 验证器使用此信息来检查这些列的非法使用。

`JBDCTable` 从 JDBC 连接的表中获取数据的可查询对象。然而，我们不会读取整个表。这里的思路是通过应用 `Queryable.where(org.apache.calcite.linq4j.function.Predicate2)` 等 `Queryable` 运算符，将其用作查询的构建块。然后，可以将结果查询转换为 SQL 查询，该查询可以在 JDBC 服务器上高效执行。

### `TableScan`

返回  <u>`Table`</u> 内容的关系运算符。

### `RelOptTable`

表示 `RelOptSchema` 中的关系数据集。具有描述和实现自身的方法。

### `RelOptSchema`

`RelOptSchema` 是一组 RelOptTable 对象。

# 其他有趣的 issue

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