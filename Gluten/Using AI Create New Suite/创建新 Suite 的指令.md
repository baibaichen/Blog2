# 创建新 Suite 的指令

## 找到需要测试的 Spark Package

进入 `/home/chang/SourceCode/gluten1/gluten-ut/spark40/src/test/scala/org/apache/spark/sql` 递归枚举所有后缀为 `Suite.scala` 的前缀为 `Gluten` 的文件，去掉前缀之后以`包名/文件名`的形式，去 `/home/chang/OpenSource/spark40/sql` 递归查找这些文件。

> 例子
> ```
> /home/chang/SourceCode/gluten1/gluten-ut/spark40/src/test/scala/org/apache/spark/sql/sources/GlutenResolvedDataSourceSuite.scala
> ```
> 我们取得 `org/apache/spark/sql/sources/ResolvedDataSourceSuite.scala`，然后去 `/home/chang/OpenSource/spark40/sql` 递归查找到：
> ```
> /home/chang/OpenSource/spark40/sql/core/src/test/scala/org/apache/spark/sql/sources/ResolvedDataSourceSuite.scala
> ```

### 要求
1. 分别列出所有找到和未找到的文件
2. 结果保成到 markdown 格式文件中，保存在 `/home/chang/SourceCode/gluten1`
3. 删除所有临时文件

#### 找到文件的输出格式表格如下：

> Found suite under `/home/chang/OpenSource/spark40/`
>
> | Gluten Suite | Found Spark Path |
> | --- | --- |
> | `GlutenApproxCountDistinctForIntervalsQuerySuite.scala` | `sql/core/src/test/scala/org/apache/spark/sql/ApproxCountDistinctForIntervalsQuerySuite.scala` |

#### 未找到的文件

对于未找到文件，如果以文件名为名的类，只从 `GlutenTestsTrait` 扩展 ， 比如 `GlutenDecimalPrecisionSuite.scala`

```scala
class GlutenDecimalPrecisionSuite extends GlutenTestsTrait {
//...
}
```
这样的测试是 Gluten 专有的测试。给这些未找到的测试文件打标签

#### 找到 Package

对于所有 `Found Spark Path`， 我们

1. 删除文件名，只保留目录名
2. 去重
3. 升序排序输出
4. 单独放到 `Unique Packages from Found Files` 一节中

## 找到新增的 Spark Suite
1. /home/chang/OpenSource/spark40/sql 是 spark40 sql 测试 Suite 的根目录
2. /home/chang/OpenSource/spark/sql 是 spark41 sql 测试 Suite 的根目录

从找到的 Unique Packages 中分别从 spark40 和 spark41 中搜索 `.scala` 文件，注意不要递归，输出只出现在spark40 或 spark41 中的 文件

## 创建 Gluten Spark41 Suite

为 `spark41` 中新增的，以 `Suite.scala`为后缀的文件，创建以 `Gluten` 为前缀的文件，放到 `/home/chang/SourceCode/gluten1/gluten-ut/spark41/src/test/scala/` 对应的 **package** 中

### 例子

对于 `sql/catalyst/src/test/scala/org/apache/spark/sql/catalyst/expressions` 它的 pacakge 是 `org/apache/spark/sql/catalyst/expressions`

因此，此 package 下的新测试文件，应该放到 `/home/chang/SourceCode/gluten1/gluten-ut/spark41/src/test/scala/org/apache/spark/sql/catalyst/expressions`

假设新的 Spark 测试文件是 `XXXSuite.scala`，新文件名 文件内容模板如下：

```scala
/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.spark.sql

class GlutenXXXSuite extends XXXSuite with GlutenSQLTestsTrait {}
```
### 要求

为所有 Spark 41 新增的 Suite 创建 Gluten Suite