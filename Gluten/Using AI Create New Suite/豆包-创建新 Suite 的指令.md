# 创建新 Gluten Suite 的指令

## 1. 环境与路径定义
在执行所有步骤前，请明确以下基准路径：

*   **Gluten 项目根目录**: `/home/chang/SourceCode/gluten1`
*   **Gluten Spark40 测试源码路径**: `${GLUTEN_ROOT}/gluten-ut/spark40/src/test/scala`
*   **Spark 4.0 源码路径**: `/home/chang/OpenSource/spark40/sql`
*   **Spark 4.1 源码路径**: `/home/chang/OpenSource/spark/sql` (注意：此处目录名为 `spark`，请确保上下文正确)
*   **Gluten Spark41 目标路径**: `${GLUTEN_ROOT}/gluten-ut/spark41/src/test/scala`

---

## 2. 步骤一：扫描与映射 (Spark40)
**目标**: 分析 Gluten 现有的 Spark40 测试，找出它们对应的 Spark 原生测试文件。

### 2.1 扫描 Gluten 文件
1.  递归扫描 `${GLUTEN_SPARK40_TEST}` 目录。
2.  **筛选规则**: 仅匹配文件名以 `Gluten` 开头且以 `Suite.scala` 结尾的文件。
3.  **路径转换**: 对每个找到的文件执行以下转换：
    *   **移除前缀**: 将文件名中的 `Gluten` 前缀去掉 (例如 `GlutenXXXSuite.scala` -> `XXXSuite.scala`)。
    *   **提取相对路径**: 计算该文件相对于 `${GLUTEN_SPARK40_TEST}` 的路径。
    *   **目标搜索模式**: 组合为 `{relative_path_without_Gluten_prefix}`。

### 2.2 查找 Spark 4.0 文件
1.  在 `${SPARK_40_ROOT}` 目录下递归查找。
2.  **匹配规则**: 查找路径后缀完全等于上述“目标搜索模式”的文件。
    *   *例如*: 搜索模式为 `org/apache/spark/sql/XXXSuite.scala`，则必须找到 `${SPARK_40_ROOT}/.../org/apache/spark/sql/XXXSuite.scala`。

### 2.3 结果分类与 Markdown 生成
将结果整理并保存为 `${GLUTEN_ROOT}/suite_mapping_report.md`。

#### 分类逻辑:
*   **Found (已找到)**: Gluten 文件在 Spark 4.0 中找到了对应的源文件。
*   **Not Found (未找到)**: Gluten 文件在 Spark 4.0 中未找到。
    *   **标签化**: 读取未找到的 Gluten 文件内容。如果类定义是 `class Gluten[...] extends GlutenTestsTrait` (且**没有**继承其他 Spark Suite 类)，则标记为 `[Gluten Exclusive]` (Gluten 专属测试)；否则标记为 `[Missing Source]`。

#### Markdown 格式要求:
> **Section 1: Spark 40 Suite Mapping**
>
> **Found Suites:**
> | Gluten Suite Path (Relative) | Spark 40 Source Path (Absolute) |
> |---|---|
> | org/apache/spark/.../GlutenXXX.scala | /home/chang/OpenSource/spark40/.../XXX.scala |
>
> **Not Found Suites:**
> | Gluten Suite Path (Relative) | Status |
> |---|---|
> | org/apache/spark/.../GlutenYYY.scala | [Gluten Exclusive] |

---

## 3. 步骤二：提取唯一包名 (Unique Packages)
**目标**: 从已匹配成功的测试中，提取出需要关注的包路径，用于下一步的增量检查。

1.  提取 **步骤一** 中所有 **"Found"** 状态的 Spark 40 文件路径。
2.  **处理**:
    *   去掉文件名，只保留目录路径。
    *   相对于 `${SPARK_40_ROOT}` 提取相对目录路径。
3.  **去重与排序**: 对目录列表去重，并按字母顺序升序排列。
4.  **输出**: 将结果追加到 Markdown 文件中：
    > **Section 2: Unique Packages from Found Files**
    > *   core/src/test/scala/org/apache/spark/sql/...
    > *   catalyst/src/test/scala/org/apache/spark/sql/...

---

## 4. 步骤三：对比 Spark 4.1 增量
**目标**: 找出 Spark 4.1 在上述“唯一包名”下新增的测试文件。

1.  获取 **步骤二** 生成的“唯一包名”列表。
2.  **遍历对比**: 对列表中的每一个包路径 `PACKAGE_DIR`：
    *   **Spark 4.0 列表**: 在 `${SPARK_40_ROOT}/${PACKAGE_DIR}` 下执行 **非递归** 搜索 (Max Depth 1)，找出所有 `.scala` 文件。
    *   **Spark 4.1 列表**: 在 `${SPARK_41_ROOT}/${PACKAGE_DIR}` 下执行 **非递归** 搜索 (Max Depth 1)，找出所有 `.scala` 文件。
    *   *注意*: 如果 Spark 4.1 的目录结构变更导致该路径不存在，则跳过。

3.  **差异分析**:
    *   找出 **仅存在于 Spark 4.1** 中的文件。
    *   **过滤**: 仅保留文件名以 `Suite.scala` 结尾的文件。

4.  **输出**: 将这些“Spark 4.1 新增 Suite”追加到 Markdown 文件中。

---

## 5. 步骤四：创建 Gluten Spark41 Suite
**目标**: 为 Spark 4.1 新增的 Suite 在 Gluten 项目中生成对应的适配代码。

### 5.1 路径映射逻辑
对于每一个 Spark 4.1 新增的文件 `${SPARK_41_FILE}`:
1.  **计算相对路径**: 相对于 `${SPARK_41_ROOT}` 的路径 (例如: `core/src/test/scala/org/apache/spark/.../NewSuite.scala`)。
2.  **确定 Gluten 目标目录**:
    *   拼接路径: `${GLUTEN_SPARK41_TARGET}/{package_path}`
    *   **包路径计算**: 去掉文件名，取剩余目录结构。
3.  **确定 Gluten 目标文件名**:
    *   在原文件名前添加 `Gluten` 前缀 (例如: `NewSuite.scala` -> `GlutenNewSuite.scala`)。

### 5.2 文件生成模板
在目标目录下创建新文件。如果目录不存在，请自动创建 (`mkdir -p`)。

**文件内容模板**:
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

// PACKAGE: 请根据文件路径自动推导 Scala 包名 (例如: org.apache.spark.sql.xxx)
package org.apache.spark.sql.xxx

// IMPORTS: 确保引入了 GlutenSQLTestsTrait

// CLASS: 类名 = Gluten + 原类名
// EXTENDS: 原类名 with GlutenSQLTestsTrait
class GlutenNewSuite extends NewSuite with GlutenSQLTestsTrait {}
```

### 5.3 执行保障
*   **包名推导**: 根据目标文件的目录结构自动生成正确的 `package` 声明。
*   **防覆盖**: 如果目标文件已经存在，**请勿覆盖**，并在控制台输出警告信息。

---

## 6. 清理工作
*   如果过程中生成了任何临时的 `.txt` 或中间缓存文件，请在任务结束时删除。
*   确保最终生成的 Markdown 报告格式整齐，无乱码。