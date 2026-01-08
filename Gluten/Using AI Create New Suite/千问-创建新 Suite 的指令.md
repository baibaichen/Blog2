# 创建新 Gluten Suite 的指令

## 阶段一：匹配现有 Gluten Suite 与 Spark 40 原始测试

### 目标
在 `/home/chang/SourceCode/gluten1/gluten-ut/spark40/src/test/scala/org/apache/spark/sql` 下，
找出所有以 `Gluten` 开头、以 `Suite.scala` 结尾的测试文件，并尝试在 Spark 40 源码中找到对应的原始测试文件。

### 步骤
1. 提取候选文件  
   递归查找所有匹配模式 `Gluten*Suite.scala` 的文件。
2. 构造原始路径  
   对每个文件，移除前缀 `Gluten`，得到原始测试文件名（如 `GlutenResolvedDataSourceSuite.scala` → `ResolvedDataSourceSuite.scala`），并保留其相对包路径。
3. 在 Spark 40 中查找  
   在 `/home/chang/OpenSource/spark40/sql` 下递归搜索该文件（全路径匹配）。

### 输出要求
生成一个 Markdown 报告，保存为 `/home/chang/SourceCode/gluten1/gluten_suite_analysis.md`，包含以下三部分：

---

### 1. Found Suites（在 Spark 40 中找到对应文件）

> Found suite under `/home/chang/OpenSource/spark40/`

| Gluten Suite File | Original Spark 40 Path |
|-------------------|------------------------|
| `GlutenApproxCountDistinctForIntervalsQuerySuite.scala` | `sql/core/src/test/scala/org/apache/spark/sql/ApproxCountDistinctForIntervalsQuerySuite.scala` |

---

### 2. Gluten-Only Suites（未在 Spark 40 中找到）

这些文件仅存在于 Gluten 项目中，且其类定义仅继承自 `GlutenTestsTrait`（即不包装任何 Spark 原生 Suite）。

> 示例：
> ```scala
> class GlutenDecimalPrecisionSuite extends GlutenTestsTrait
> ```

| Gluten-Only Suite |
|------------------|
| `GlutenDecimalPrecisionSuite.scala` |

> ⚠️ 注意：如果某个未找到的 Suite 实际上继承了某个 Spark Suite（如 `extends SomeSparkSuite with GlutenTestsTrait`），则不应归入此类。

---

### 3. Unique Packages from Found Files

从“Found Suites”中提取所有 原始 Spark 40 文件的目录路径（不含文件名），执行：
- 去重
- 按字典序升序排序

> 示例输入路径：  
> `sql/core/src/test/scala/org/apache/spark/sql/sources/ResolvedDataSourceSuite.scala`  
> → 提取为：`sql/core/src/test/scala/org/apache/spark/sql/sources`

输出格式：

```
Unique Packages from Found Files:
- sql/core/src/test/scala/org/apache/spark/sql/sources
- sql/catalyst/src/test/scala/org/apache/spark/sql/catalyst/expressions
...
```

---

## 阶段二：识别 Spark 41 新增的测试 Suite

### 目标
基于上述“Unique Packages”列表，对比 Spark 40 与 Spark 41，找出仅在 Spark 41 中新增的 `*Suite.scala` 文件。

### 步骤
对每个 package 路径（如 `sql/core/src/test/scala/org/apache/spark/sql/sources`）：
1. 在 `/home/chang/OpenSource/spark40/sql/<package_path>` 中列出所有 `*Suite.scala` 文件（非递归）。
2. 在 `/home/chang/OpenSource/spark41/sql/<package_path>` 中列出所有 `*Suite.scala` 文件（非递归）。
3. 找出 只存在于 Spark 41 而不在 Spark 40 中的文件。

> 💡 注意：仅比较同名 package 下的直接子文件，不递归子目录。

### 输出（追加到同一 Markdown 文件）
#### New Suites in Spark 41 (Not in Spark 40)

| Package Path | New Suite File |
|--------------|----------------|
| `sql/catalyst/src/test/scala/org/apache/spark/sql/catalyst/expressions` | `NewExpressionSuite.scala` |

---

## 阶段三：为 Spark 41 新增 Suite 自动生成 Gluten 包装类

### 目标
为每个“Spark 41 新增 Suite”生成对应的 Gluten 测试类。

### 生成规则
- 输出目录：  
  `/home/chang/SourceCode/gluten1/gluten-ut/spark41/src/test/scala/` + `<package_path>`
- 文件名：在原文件名前加 `Gluten` 前缀  
  （如 `NewExpressionSuite.scala` → `GlutenNewExpressionSuite.scala`）
- 内容模板：

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
package org.apache.spark.sql.catalyst.expressions  // ← 根据实际 package 动态生成

class GlutenNewExpressionSuite extends NewExpressionSuite with GlutenSQLTestsTrait {}
```

### 要求
- 确保目标目录存在，必要时自动创建。
- 若原 Suite 是 `final class` 或无法继承，需人工介入（可在报告中标记⚠️）。
- 所有生成文件必须符合 Apache License 2.0 头部要求（已包含在模板中）。

---

## 附注
- 无需保留中间临时文件（如无显式生成，则此条可忽略）。
- 最终报告路径：`/home/chang/SourceCode/gluten1/gluten_suite_analysis.md`
