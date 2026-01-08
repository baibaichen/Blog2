
### 创建新 Gluten Suite 的指令

#### 1. 分析与准备阶段

目标：识别 Gluten 测试套件及其对应的 Spark 源文件，为后续比较和创建做准备。

1.  输入与输出
    *   输入目录：
        *   Gluten 测试目录: `/home/chang/SourceCode/gluten1/gluten-ut/spark40/src/test/scala/org/apache/spark/sql`
        *   Spark 40 源码目录: `/home/chang/OpenSource/spark40/sql`
        *   Spark 41 源码目录: `/home/chang/OpenSource/spark41/sql`
    *   输出文件：`/home/chang/SourceCode/gluten1/suite_analysis_report.md`

2.  核心操作流程
    *   步骤 1.1：枚举 Gluten 测试套件
        遍历 Gluten 测试目录，递归查找所有以 `Gluten` 为前缀、`Suite.scala` 为后缀的文件。记录其完整路径。
    *   步骤 1.2：生成对应的 Spark 套件路径
        对于每个找到的 `GlutenXxxSuite.scala` 文件，去除 `Gluten` 前缀，得到形如 `org/apache/spark/sql/.../XxxSuite.scala` 的相对路径。
    *   步骤 1.3：在 Spark 源码中查找
        使用上一步得到的相对路径，在 Spark 40 源码目录 (`/home/chang/OpenSource/spark40/sql`) 中递归查找是否存在同名文件。记录找到的 Spark 40 中的完整路径。
    *   步骤 1.4：分类与标记
        *   找到的文件：记录 `GlutenXxxSuite.scala` 和其在 Spark 40 中的完整路径。
        *   未找到的文件：检查该 Gluten 套件是否仅继承 `GlutenTestsTrait`。如果是，则标记为 "Gluten 专属测试"；否则，标记为 "疑似缺失的测试"。
    *   步骤 1.5：提取唯一包路径
        从所有"找到的文件"的 Spark 路径中，提取出目录路径（即去掉文件名），然后进行去重和升序排序。这个列表将用于下一阶段的比较。

#### 2. 比较与差异识别阶段

目标：基于第一阶段得到的包路径，找出 Spark 41 中新增的测试套件。

1.  核心操作流程
    *   步骤 2.1：扫描包路径中的测试文件
        遍历第一阶段生成的"唯一包路径列表"，分别在 Spark 40 和 Spark 41 的源码目录下，非递归地列出该包路径下所有以 `Suite.scala` 结尾的 `.scala` 文件（仅限一级目录）。
    *   步骤 2.2：标识新增套件
        对比两个版本的文件列表，找出仅在 Spark 41 中存在的 `Suite.scala` 文件。这些就是需要为其创建 Gluten 版本的新增测试套件。

#### 3. 生成与创建阶段

目标：为 Spark 41 新增的测试套件创建对应的 Gluten 测试套件文件。

1.  核心操作流程
    *   步骤 3.1：确定目标位置
        对于每个新增的 Spark 测试套件 `XxxSuite.scala`，其所在的包路径（如 `sql/catalyst/src/test/scala/org/apache/spark/sql/catalyst/expressions`）对应的 Gluten 目标包路径为 `org/apache/spark/sql/catalyst/expressions`。
        *   完整目标目录：`/home/chang/SourceCode/gluten1/gluten-ut/spark41/src/test/scala/` + `org/apache/spark/sql/catalyst/expressions`
        *   完整目标文件：上述目录下的 `GlutenXxxSuite.scala`
    *   步骤 3.2：创建目录（如需要）
        检查目标目录是否存在，若不存在则创建它（包括所有父目录）。
    *   步骤 3.3：生成文件内容
        使用以下模板生成新文件的内容。注意替换 `{full_package_name}` 和 `{SuiteName}`。
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
        package {full_package_name}
        
        class Gluten{SuiteName} extends {SuiteName} with GlutenSQLTestsTrait {}
        ```
    *   步骤 3.4：写入文件
        将生成的内容写入目标文件。如果目标文件已存在，应记录警告并跳过，避免覆盖。

### 最终报告与输出要求

将所有结果汇总到 `suite_analysis_report.md` 文件中，结构如下：

```markdown
# Gluten 测试套件分析报告

## 摘要
- 统计信息：找到的套件数量、未找到的套件数量、Gluten 专属测试数量、Spark 41 新增套件数量、已创建的套件数量。

## 第一阶段：Gluten 套件匹配结果
### 找到的 Spark 40 对应套件
| Gluten Suite | Found Spark Path |
| :--- | :--- |
| `GlutenApproxCountDistinctForIntervalsQuerySuite.scala` | `sql/core/src/test/scala/org/apache/spark/sql/ApproxCountDistinctForIntervalsQuerySuite.scala` |

### 未找到对应套件的 Gluten 测试
#### Gluten 专属测试
- `GlutenDecimalPrecisionSuite.scala` (仅继承自 `GlutenTestsTrait`)
#### 疑似缺失的测试
- `GlutenSomeOtherSuite.scala` (继承自其他基类)

### 唯一包路径列表
- `sql/catalyst/src/test/scala/org/apache/spark/sql/catalyst/expressions`
- `sql/core/src/test/scala/org/apache/spark/sql/execution`

## 第二阶段：Spark 41 新增测试套件
### 新增套件列表 (按包路径分组)
- Package: `org/apache/spark/sql/catalyst/expressions`
  - `NewExpressionSuite.scala`

## 第三阶段：Gluten Spark 41 套件创建日志
- Created: `GlutenNewExpressionSuite.scala`
- Skipped (Already exists): `GlutenExistingSuite.scala`
```

最后需要删除所有临时文件。