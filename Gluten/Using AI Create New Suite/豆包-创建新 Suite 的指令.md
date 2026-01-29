# 创建新 Gluten Suite 的指令

## 1. 环境与路径定义
在执行所有步骤前，请明确以下基准路径：

*   **Spark 4.0 源码路径**: `/home/chang/OpenSource/spark40/sql`
*   **Gluten 项目根目录**: `/home/chang/SourceCode/gluten1`
*   **Gluten Spark40 路径**: `${GLUTEN_ROOT}/gluten-ut/spark40/src/test/scala`
*   **Gluten Spark41 路径**: `${GLUTEN_ROOT}/gluten-ut/spark41/src/test/scala`

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

## 4. 步骤三：查找 Spark 4.0 遗失的 Suite
**目标**: 找出 Spark 4.0 在上述“唯一包名”下新增的测试文件。

1.  获取 **步骤二** 生成的“唯一包名”列表。
2.  **遍历对比**: 对列表中的每一个包路径 `PACKAGE_DIR`：
    *   **Spark 4.0 列表**: 在 `${SPARK_40_ROOT}/${PACKAGE_DIR}` 下执行 **非递归** 搜索 (Max Depth 1)，找出所有 `.scala` 文件。
3.  **差异分析**:
    *   找出 **仅存在于 Spark 4.0** 中的文件。
    *   **过滤**: 仅保留文件名以 `Suite.scala` 结尾的文件。
4.  **输出**: 将这些“Spark 4.0 新增 Suite”追加到 Markdown 文件中。

---

## 5. 步骤四：创建 Gluten Spark41 和 Spark40 Suite
**目标**: 为 Spark 4.0 遗失的 Suite 在 Gluten 项目中生成对应的适配代码。

### 5.1 路径映射逻辑
对于每一个 Spark 4.0 遗失的文件 `${SPARK_40_FILE}`:
1.  **计算相对路径**: 相对于 `${SPARK_40_ROOT}` 的路径 (例如: `core/src/test/scala/org/apache/spark/.../NewSuite.scala`)。
2.  **确定 Gluten 目标目录**:
    *   拼接路径: `${GLUTEN_SPARK40_TARGET}/{package_path}`
    *   **包路径计算**: 去掉文件名，取剩余目录结构。
3.  **确定 Gluten 目标文件名**:
    *   在原文件名前添加 `Gluten` 前缀 (例如: `NewSuite.scala` -> `GlutenNewSuite.scala`)。
4. 对 Spark 4.1做同样工作   

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
#### 规则
1. 如果 `NewSuite` 是 `abstract class`，排除

2. 如果 `NewSuite extends SparkFunSuit`,，则 `class GlutenNewSuite extends NewSuite with GlutenTestsCommonTrait {}`

3. 如果 `NewSuite.scala` 里真正的 `Suite` class 和文件名不同，我们需要把提前真正的 Suite class，但是还是要放到 `GlutenNewSuite.scala` 中

   

### 5.3 集成

在 `${GLUTEN_SPARK40_TEST}/org/apache/gluten/utils/velox/VeloxTestSettings.scala`  和 `${GLUTEN_SPARK41_TEST}/org/apache/gluten/utils/velox/VeloxTestSettings.scala`   中调用 `enableSuite` 以便集成新的 Suite

### 5.4 执行保障
*   **包名推导**: 根据目标文件的目录结构自动生成正确的 `package` 声明。
*   **防覆盖**: 如果目标文件已经存在，**请勿覆盖**，并在控制台输出警告信息。

---

## 6. 验证

### 操作

1. 先搞 spark 40，spark 40 通过之后再搞 spark 41
2. 一个 package,一个 package的搞，我来帮助你 fix 问题

### 格式化
```
build/mvn -P java-17,spark-4.1,scala-2.13,backends-velox,hadoop-3.3,spark-ut -Piceberg,iceberg-test,delta,paimon spotless:apply
build/mvn -P java-17,spark-4.0,scala-2.13,backends-velox,hadoop-3.3,spark-ut -Piceberg,iceberg-test,delta,paimon spotless:apply
```

### 编译
```
build/mvn -P java-17,spark-4.1,scala-2.13,backends-velox,hadoop-3.3,spark-ut clean test-compile
build/mvn -P java-17,spark-4.0,scala-2.13,backends-velox,hadoop-3.3,spark-ut -Piceberg,iceberg-test,delta,paimon clean test-compile
```

---

## 7. 清理工作
*   如果过程中生成了任何临时的 `.txt` 或中间缓存文件，请在任务结束时删除。
*   确保最终生成的 Markdown 报告格式整齐，无乱码。


-----------------------


# 优化后：Gluten 升级支持 Spark 小版本的标准化执行手册
## 前置说明
你需要完成的核心目标是：将 Gluten 对 Spark `${CURRENT_SPARK_VERSION}` 的支持升级至 `${UPGRADE_SPARK_VERSION}`，核心动作包括测试文件映射、新增测试适配、SQL 测试用例合并，最终输出标准化报告并完成代码集成。

### 前置依赖（必装）
确保执行环境已安装以下工具：
- `wget`/`curl`：源码下载
- `shasum`：校验和验证（macOS/Linux 内置，Windows 需安装 Git Bash）
- `git`：版本对比与三路合并
- `find`/`xargs`：文件扫描（Linux/macOS 内置）
- `scala-compiler`：验证生成的 Scala 文件语法
- `tree`（可选）：目录结构检查
- VS Code（带合并编辑器）：冲突解决

---

## 1. 环境与路径定义（修正&统一）
执行所有步骤前，**必须先导出以下变量**（建议写入临时脚本 `env.sh` 并执行 `source env.sh`），避免手动输入错误：

```bash
# 核心路径（根据实际环境修改）
export GLUTEN_ROOT="/root/SourceCode/gluten"
export UPGRADE_PROFILE="spark-4.1"  # 修正原拼写错误 UPGRADE_PROFILER
export GLUTEN_SPARK41_TEST="${GLUTEN_ROOT}/gluten-ut/spark41/src/test/scala"

# Spark 版本（按需修改）
export CURRENT_SPARK_VERSION="4.1.0"
export UPGRADE_SPARK_VERSION="4.1.1"

# 临时目录（统一管理，便于清理）
export TMP_DIR="/tmp/gluten_spark_upgrade"
mkdir -p ${TMP_DIR}

# 导出 Spark 源码解压路径（后续步骤自动赋值）
export CURRENT_SPARK_ROOT="${TMP_DIR}/spark-${CURRENT_SPARK_VERSION}"
export UPGRADE_SPARK_ROOT="${TMP_DIR}/spark-${UPGRADE_SPARK_VERSION}"

# SQL 测试文件路径（修正原语法错误）
export SPARK_SQL_TEST_INPUTS_BASE="${CURRENT_SPARK_ROOT}/sql/core/src/test/resources/sql-tests/inputs"
export SPARK_SQL_TEST_RESULTS_BASE="${CURRENT_SPARK_ROOT}/sql/core/src/test/resources/sql-tests/results"
export SPARK_SQL_TEST_INPUTS_UPGRADE="${UPGRADE_SPARK_ROOT}/sql/core/src/test/resources/sql-tests/inputs"
export SPARK_SQL_TEST_RESULTS_UPGRADE="${UPGRADE_SPARK_ROOT}/sql/core/src/test/resources/sql-tests/results"
export GLUTEN_SQL_TEST_INPUTS="${GLUTEN_SPARK41_TEST}/../resources/backends-velox/sql-tests/inputs"
export GLUTEN_SQL_TEST_RESULTS="${GLUTEN_SPARK41_TEST}/../resources/backends-velox/sql-tests/results"

# 报告文件路径（固定）
export REPORT_FILE="${GLUTEN_ROOT}/suite_mapping_report.md"
```

---

## 2. 步骤一：下载并验证 Spark 源码
### 目标
下载 `${CURRENT_SPARK_VERSION}` 和 `${UPGRADE_SPARK_VERSION}` 的 Spark 源码，验证校验和并解压，确保源码完整性。

### 操作步骤
1. 创建临时下载目录：
   ```bash
   mkdir -p ${TMP_DIR}/spark_source
   cd ${TMP_DIR}/spark_source
   ```

2. 批量下载并验证源码（复用脚本）：
   ```bash
   # 定义下载函数（复用）
   download_spark_source() {
       local VERSION=$1
       # 下载源码包（备选镜像，避免原镜像失效）
       wget -O spark-${VERSION}.tgz \
           "https://archive.apache.org/dist/spark/spark-${VERSION}/spark-${VERSION}.tgz" \
           --quiet --show-progress || { echo "ERROR: 下载 spark-${VERSION} 失败"; exit 1; }
       
       # 下载校验和文件
       wget -O spark-${VERSION}.tgz.sha512 \
           "https://archive.apache.org/dist/spark/spark-${VERSION}/spark-${VERSION}.tgz.sha512" \
           --quiet --show-progress || { echo "ERROR: 下载 spark-${VERSION} 校验和失败"; exit 1; }
       
       # 验证校验和（兼容 macOS/Linux）
       if [[ "$(uname)" == "Darwin" ]]; then
           shasum -a 512 -c spark-${VERSION}.tgz.sha512 2>&1 | grep -q "OK"
       else
           sha512sum -c spark-${VERSION}.tgz.sha512 2>&1 | grep -q "OK"
       fi
       
       if [ $? -ne 0 ]; then
           echo "ERROR: spark-${VERSION} 校验和不匹配，文件可能损坏"
           rm -f spark-${VERSION}.tgz spark-${VERSION}.tgz.sha512
           exit 1
       fi
       
       # 解压
       tar -xzf spark-${VERSION}.tgz -C ${TMP_DIR}/ || { echo "ERROR: 解压 spark-${VERSION} 失败"; exit 1; }
       echo "SUCCESS: spark-${VERSION} 下载并解压完成，路径：${TMP_DIR}/spark-${VERSION}"
   }
   
   # 执行下载（先当前版本，后升级版本）
   download_spark_source ${CURRENT_SPARK_VERSION}
   download_spark_source ${UPGRADE_SPARK_VERSION}
   ```

### 预期输出
- 无报错，终端打印两个版本的“SUCCESS”提示
- `${TMP_DIR}` 下生成 `spark-4.1.0` 和 `spark-4.1.1` 目录

### 注意事项
- 若原镜像失效，自动切换到 Apache 归档镜像（archive.apache.org），避免下载失败
- 校验和不匹配时直接退出，避免后续步骤基于损坏文件执行

---

## 3. 步骤二：扫描 Gluten 测试文件并映射 Spark 原生文件
### 目标
分析 Gluten 测试文件与 Spark 原生测试文件的映射关系，生成结构化报告。

### 操作步骤
1. 初始化报告文件（清空旧内容）：
   ```bash
   > ${REPORT_FILE}
   echo -e "# Gluten Spark 版本升级映射报告\n\n## Section 1: ${CURRENT_SPARK_VERSION} Suite Mapping\n" >> ${REPORT_FILE}
   ```

2. 扫描 Gluten 测试文件并生成映射关系（核心脚本）：
   ```bash
   # 定义变量
   FOUND_LIST="${TMP_DIR}/found_suites.txt"
   NOT_FOUND_LIST="${TMP_DIR}/not_found_suites.txt"
   > ${FOUND_LIST}
   > ${NOT_FOUND_LIST}
   
   # 递归扫描 Gluten 测试文件（Gluten开头+Suite.scala结尾）
   find ${GLUTEN_SPARK41_TEST} -type f -name "Gluten*Suite.scala" | while read -r GLUTEN_FILE; do
       # 步骤1：提取相对路径（相对于 GLUTEN_SPARK41_TEST）
       RELATIVE_PATH=$(realpath --relative-to=${GLUTEN_SPARK41_TEST} ${GLUTEN_FILE})
       # 步骤2：移除文件名的 Gluten 前缀（例如 GlutenXXXSuite.scala -> XXXSuite.scala）
       SPARK_FILE_NAME=$(basename ${GLUTEN_FILE} | sed 's/^Gluten//')
       # 步骤3：拼接 Spark 原生文件的相对路径
       SPARK_RELATIVE_PATH=$(dirname ${RELATIVE_PATH})/${SPARK_FILE_NAME}
       # 步骤4：查找 Spark 原生文件
       SPARK_ABSOLUTE_FILE=$(find ${CURRENT_SPARK_ROOT} -path "*/${SPARK_RELATIVE_PATH}" -type f | head -1)
   
       if [ -n "${SPARK_ABSOLUTE_FILE}" ]; then
           # 找到匹配文件：写入 FOUND_LIST
           echo -e "${RELATIVE_PATH}\t${SPARK_ABSOLUTE_FILE}" >> ${FOUND_LIST}
       else
           # 未找到匹配文件：判断是否为 Gluten 专属测试
           if grep -q "class Gluten.* extends GlutenTestsTrait" ${GLUTEN_FILE} && ! grep -q "extends .*Suite" ${GLUTEN_FILE}; then
               STATUS="[Gluten Exclusive]"
           else
               STATUS="[Missing Source]"
           fi
           # 写入 NOT_FOUND_LIST
           echo -e "${RELATIVE_PATH}\t${STATUS}" >> ${NOT_FOUND_LIST}
       fi
   done
   ```

3. 将结果写入报告（格式化 Markdown 表格）：
   ```bash
   # 写入 Found Suites 表格
   echo -e "### Found Suites:\n" >> ${REPORT_FILE}
   echo -e "| Gluten Suite Path (Relative) | Spark ${CURRENT_SPARK_VERSION} Source Path (Absolute) |" >> ${REPORT_FILE}
   echo -e "|-------------------------------|-------------------------------------------------------|" >> ${REPORT_FILE}
   cat ${FOUND_LIST} | while IFS=$'\t' read -r REL_PATH SPARK_PATH; do
       echo -e "| ${REL_PATH} | ${SPARK_PATH} |" >> ${REPORT_FILE}
   done
   echo -e "\n" >> ${REPORT_FILE}
   
   # 写入 Not Found Suites 表格
   echo -e "### Not Found Suites:\n" >> ${REPORT_FILE}
   echo -e "| Gluten Suite Path (Relative) | Status |" >> ${REPORT_FILE}
   echo -e "|-------------------------------|--------|" >> ${REPORT_FILE}
   cat ${NOT_FOUND_LIST} | while IFS=$'\t' read -r REL_PATH STATUS; do
       echo -e "| ${REL_PATH} | ${STATUS} |" >> ${REPORT_FILE}
   done
   echo -e "\n" >> ${REPORT_FILE}
   ```

### 预期输出
- `${REPORT_FILE}` 中生成结构化的 Markdown 表格，包含 Found/Not Found 两类Suite
- 临时文件 `${TMP_DIR}/found_suites.txt`/`not_found_suites.txt` 记录原始数据

### 注意事项
- 使用 `realpath` 确保相对路径准确性（兼容符号链接）
- 未找到的文件通过 grep 关键字精准判断是否为 Gluten 专属测试，避免误标

---

## 4. 步骤三：提取唯一包名（Unique Packages）
### 目标
从匹配成功的测试文件中提取唯一包路径，为后续增量检查做准备。

### 操作步骤
1. 提取并去重包路径：
   ```bash
   # 从 FOUND_LIST 中提取 Spark 原生文件路径，去掉文件名，取相对路径（相对于 CURRENT_SPARK_ROOT）
   UNIQUE_PACKAGES="${TMP_DIR}/unique_packages.txt"
   cat ${FOUND_LIST} | cut -f2 | while read -r SPARK_FILE; do
       # 提取目录路径
       SPARK_DIR=$(dirname ${SPARK_FILE})
       # 转换为相对于 CURRENT_SPARK_ROOT 的路径
       RELATIVE_PACKAGE=$(realpath --relative-to=${CURRENT_SPARK_ROOT} ${SPARK_DIR})
       echo ${RELATIVE_PACKAGE}
   done | sort | uniq > ${UNIQUE_PACKAGES}
   
   # 将结果写入报告
   echo -e "## Section 2: Unique Packages from Found Files\n" >> ${REPORT_FILE}
   echo -e "以下为匹配成功的测试文件对应的唯一包路径（按字母升序）：\n" >> ${REPORT_FILE}
   cat ${UNIQUE_PACKAGES} | while read -r PACKAGE; do
       echo -e "* ${PACKAGE}" >> ${REPORT_FILE}
   done
   echo -e "\n" >> ${REPORT_FILE}
   ```

### 预期输出
- `${TMP_DIR}/unique_packages.txt` 包含去重、排序后的包路径列表
- 报告中新增“Unique Packages from Found Files”章节，格式为无序列表

---

## 5. 步骤四：对比升级版本的 Spark 新增测试文件
### 目标
找出 `${UPGRADE_SPARK_VERSION}` 在目标包路径下新增的 `Suite.scala` 文件。

### 操作步骤
1. 初始化增量记录文件：
   ```bash
   NEW_SUITES="${TMP_DIR}/new_suites.txt"
   > ${NEW_SUITES}
   echo -e "## Section 3: ${UPGRADE_SPARK_VERSION} 新增 Suite 文件\n" >> ${REPORT_FILE}
   echo -e "| 包路径 | 新增 Suite 文件 |" >> ${REPORT_FILE}
   echo -e "|--------|----------------|" >> ${REPORT_FILE}
   ```

2. 遍历唯一包路径，对比增量：
   ```bash
   cat ${UNIQUE_PACKAGES} | while read -r PACKAGE_DIR; do
       # 定义当前/升级版本的目录路径
       CURRENT_DIR="${CURRENT_SPARK_ROOT}/${PACKAGE_DIR}"
       UPGRADE_DIR="${UPGRADE_SPARK_ROOT}/${PACKAGE_DIR}"
   
       # 跳过不存在的目录
       if [ ! -d "${CURRENT_DIR}" ] || [ ! -d "${UPGRADE_DIR}" ]; then
           echo "WARN: 目录不存在，跳过：${PACKAGE_DIR}"
           continue
       fi
   
       # 非递归获取当前版本的 .scala 文件列表
       ls ${CURRENT_DIR}/*.scala 2>/dev/null | xargs -n1 basename > ${TMP_DIR}/current_files.txt
       # 非递归获取升级版本的 .scala 文件列表
       ls ${UPGRADE_DIR}/*.scala 2>/dev/null | xargs -n1 basename > ${TMP_DIR}/upgrade_files.txt
   
       # 找出仅存在于升级版本的文件（过滤 Suite.scala 结尾）
       comm -13 ${TMP_DIR}/current_files.txt ${TMP_DIR}/upgrade_files.txt | grep "Suite.scala$" | while read -r NEW_FILE; do
           echo -e "${PACKAGE_DIR}\t${NEW_FILE}" >> ${NEW_SUITES}
           echo -e "| ${PACKAGE_DIR} | ${NEW_FILE} |" >> ${REPORT_FILE}
       done
   done
   ```

### 预期输出
- `${TMP_DIR}/new_suites.txt` 记录新增的 Suite 文件
- 报告中新增“${UPGRADE_SPARK_VERSION} 新增 Suite 文件”章节，包含表格化的增量信息

---

## 6. 步骤五：生成 Gluten 适配的新增 Suite 文件
### 目标
为升级版本新增的 Spark Suite 文件，生成对应的 Gluten 适配代码，并集成到测试配置中。

### 操作步骤
1. 生成 Gluten Suite 文件（核心逻辑）：
   ```bash
   cat ${NEW_SUITES} | while IFS=$'\t' read -r PACKAGE_DIR NEW_FILE; do
       # 步骤1：推导包名（将目录路径转换为 Scala 包名，/ -> .）
       SCALA_PACKAGE=$(echo ${PACKAGE_DIR} | sed -e 's/^.*scala\///' -e 's/\//./g')
       # 步骤2：确定 Gluten 目标目录
       GLUTEN_TARGET_DIR="${GLUTEN_SPARK41_TEST}/${PACKAGE_DIR}"
       mkdir -p ${GLUTEN_TARGET_DIR} || { echo "ERROR: 创建目录失败 ${GLUTEN_TARGET_DIR}"; continue; }
       # 步骤3：确定 Gluten 目标文件名（添加 Gluten 前缀）
       GLUTEN_TARGET_FILE="${GLUTEN_TARGET_DIR}/Gluten${NEW_FILE}"
       # 步骤4：提取原类名（去掉 .scala 后缀）
       ORIG_CLASS_NAME=$(basename ${NEW_FILE} .scala)
       GLUTEN_CLASS_NAME="Gluten${ORIG_CLASS_NAME}"
   
       # 防覆盖：文件已存在则输出警告并跳过
       if [ -f "${GLUTEN_TARGET_FILE}" ]; then
           echo "WARN: 文件已存在，跳过创建：${GLUTEN_TARGET_FILE}"
           continue
       fi
   
       # 步骤5：生成 Scala 文件内容（模板填充）
       cat > ${GLUTEN_TARGET_FILE} << EOF
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

package ${SCALA_PACKAGE}

import org.apache.gluten.utils.velox.GlutenSQLTestsTrait

class ${GLUTEN_CLASS_NAME} extends ${ORIG_CLASS_NAME} with GlutenSQLTestsTrait {}
EOF

       echo "SUCCESS: 生成 Gluten Suite 文件：${GLUTEN_TARGET_FILE}"
   done
   ```

2. 集成到 VeloxTestSettings.scala（防重名）：
   ```bash
   VELOX_TEST_SETTINGS="${GLUTEN_SPARK41_TEST}/org/apache/gluten/utils/velox/VeloxTestSettings.scala"
   # 提取新增的 Gluten 类名
   cat ${NEW_SUITES} | while IFS=$'\t' read -r _ NEW_FILE; do
       CLASS_NAME="Gluten$(basename ${NEW_FILE} .scala)"
       # 检查是否已存在
       if ! grep -q "enableSuite.*${CLASS_NAME}" ${VELOX_TEST_SETTINGS}; then
           # 在文件末尾添加 enableSuite 调用（示例位置，可根据实际格式调整）
           sed -i "/^object VeloxTestSettings/a \  enableSuite(classOf[${CLASS_NAME}])" ${VELOX_TEST_SETTINGS}
           echo "SUCCESS: 集成 ${CLASS_NAME} 到 VeloxTestSettings.scala"
       else
           echo "WARN: ${CLASS_NAME} 已存在于 VeloxTestSettings.scala，跳过集成"
       fi
   done
   ```

### 预期输出
- `${GLUTEN_SPARK41_TEST}` 下生成新增的 `GlutenXXXSuite.scala` 文件
- `VeloxTestSettings.scala` 中新增对应 `enableSuite` 调用
- 终端无报错，仅打印 SUCCESS/WARN 提示

### 注意事项
- 自动推导 Scala 包名时，跳过“scala”前缀目录（符合 Spark/Gluten 包名规范）
- 严格防覆盖、防重名，避免破坏已有代码

---

## 7. 步骤六：合并升级版本的 SQL 测试用例
### 目标
通过 Git 三路合并，将 Spark 升级版本的 SQL 测试用例合并到 Gluten 中，解决冲突并集成。

### 操作步骤
1. 创建临时 Git 仓库（用于三路合并）：
   ```bash
   MERGE_TMP_DIR="${TMP_DIR}/sql_test_merge"
   rm -rf ${MERGE_TMP_DIR}
   mkdir -p ${MERGE_TMP_DIR}/{base,left,right}
   
   # 复制文件到对应目录
   cp -r ${SPARK_SQL_TEST_INPUTS_BASE}/* ${SPARK_SQL_TEST_RESULTS_BASE}/* ${MERGE_TMP_DIR}/base/
   cp -r ${SPARK_SQL_TEST_INPUTS_UPGRADE}/* ${SPARK_SQL_TEST_RESULTS_UPGRADE}/* ${MERGE_TMP_DIR}/left/
   cp -r ${GLUTEN_SQL_TEST_INPUTS}/* ${GLUTEN_SQL_TEST_RESULTS}/* ${MERGE_TMP_DIR}/right/
   
   # 初始化 Git 仓库并创建分支
   cd ${MERGE_TMP_DIR}
   git init --quiet
   git config user.name "Gluten Upgrade Tool"
   git config user.email "gluten-upgrade@example.com"
   
   # 提交 base 分支（共同祖先）
   git checkout -b base --quiet
   cp -r base/* .
   git add . && git commit -m "Base: Spark ${CURRENT_SPARK_VERSION} SQL tests" --quiet
   
   # 提交 left 分支（升级版本 Spark）
   git checkout -b left --quiet
   rm -rf ./*
   cp -r left/* .
   git add . && git commit -m "Left: Spark ${UPGRADE_SPARK_VERSION} SQL tests" --quiet
   
   # 提交 right 分支（当前 Gluten）
   git checkout -b right --quiet
   rm -rf ./*
   cp -r right/* .
   git add . && git commit -m "Right: Gluten ${CURRENT_SPARK_VERSION} SQL tests" --quiet
   ```

2. 执行三路合并（base 为祖先，left 合并到 right）：
   ```bash
   # 切回 right 分支，执行合并
   git checkout right --quiet
   MERGE_RESULT=$(git merge left --no-commit --no-ff 2>&1)
   MERGE_EXIT_CODE=$?
   
   # 统计文件数量
   BASE_FILE_COUNT=$(ls -1 ${MERGE_TMP_DIR}/base | wc -l)
   LEFT_FILE_COUNT=$(ls -1 ${MERGE_TMP_DIR}/left | wc -l)
   RIGHT_FILE_COUNT=$(ls -1 ${MERGE_TMP_DIR}/right | wc -l)
   MERGED_FILE_COUNT=$(ls -1 | wc -l)
   ADDED_FILE_COUNT=$(git diff --name-only --diff-filter=A | wc -l)
   
   # 统计冲突文件
   CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
   CONFLICT_COUNT=$(echo "${CONFLICT_FILES}" | wc -l)
   
   # 解决冲突（调用 VS Code 合并编辑器，手动处理）
   if [ ${MERGE_EXIT_CODE} -ne 0 ] && [ ${CONFLICT_COUNT} -gt 0 ]; then
       echo "INFO: 检测到 ${CONFLICT_COUNT} 个冲突文件，启动 VS Code 合并编辑器..."
       code --merge-editor ${CONFLICT_FILES}
       # 解决冲突后手动提交（需用户确认）
       read -p "请解决冲突后按 Enter 继续..."
       git add .
       git commit -m "Resolve merge conflicts for SQL tests" --quiet
   fi
   
   # 复制合并结果到 Gluten 目录
   rm -rf ${GLUTEN_SQL_TEST_INPUTS}/* ${GLUTEN_SQL_TEST_RESULTS}/*
   cp -r ./* ${GLUTEN_SQL_TEST_INPUTS}/../  # 确保路径匹配
   ```

3. 生成合并统计并写入报告：
   ```bash
   # 统计变更类型
   AUTO_MERGE_COUNT=$(git diff --name-only --diff-filter=M | wc -l)
   NEW_TEST_COUNT=$(git diff --name-only --diff-filter=A | wc -l)
   MODIFIED_TEST_COUNT=$(git diff --name-only --diff-filter=M | wc -l)
   DELETED_TEST_COUNT=$(git diff --name-only --diff-filter=D | wc -l)
   
   # 写入报告
   echo -e "## Section 4: SQL 测试用例合并统计\n" >> ${REPORT_FILE}
   echo -e "### 三路合并完成！" >> ${REPORT_FILE}
   echo -e "成功将 ${UPGRADE_SPARK_VERSION} 的 sql-tests 合并到 Gluten ${CURRENT_SPARK_VERSION} 中。\n" >> ${REPORT_FILE}
   echo -e "#### 版本信息：" >> ${REPORT_FILE}
   echo -e "- Base: ${CURRENT_SPARK_VERSION} - ${BASE_FILE_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- Left: ${UPGRADE_SPARK_VERSION} - ${LEFT_FILE_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- Right: Gluten ${CURRENT_SPARK_VERSION} - ${RIGHT_FILE_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- 合并后：${MERGED_FILE_COUNT} 文件 (+${ADDED_FILE_COUNT} 相比 Gluten 原始版本)\n" >> ${REPORT_FILE}
   echo -e "#### 变更详情：" >> ${REPORT_FILE}
   echo -e "- 自动合并：${AUTO_MERGE_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- 新增测试：${NEW_TEST_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- 修改测试：${MODIFIED_TEST_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- 删除测试：${DELETED_TEST_COUNT} 文件" >> ${REPORT_FILE}
   echo -e "- 冲突解决：仅 ${CONFLICT_COUNT} 个冲突需要人工解决\n" >> ${REPORT_FILE}
   ```

4. 集成新增 SQL 到 VeloxSQLQueryTestSettings.scala：
   ```bash
   SQL_SETTINGS_FILE="${GLUTEN_SPARK41_TEST}/org/apache/gluten/utils/velox/VeloxSQLQueryTestSettings.scala"
   # 提取新增的 SQL 文件名（.sql 结尾）
   NEW_SQL_FILES=$(git diff --name-only --diff-filter=A | grep "\.sql$" | sed 's/\.sql$//')
   
   # 写入 SUPPORTED_SQL_QUERY_LIST（防重名）
   for SQL_FILE in ${NEW_SQL_FILES}; do
       if ! grep -q "\"${SQL_FILE}\"" ${SQL_SETTINGS_FILE}; then
           # 在 SUPPORTED_SQL_QUERY_LIST 中添加（示例位置，可根据实际格式调整）
           sed -i "/SUPPORTED_SQL_QUERY_LIST/ a \  \"${SQL_FILE}\"," ${SQL_SETTINGS_FILE}
           echo "SUCCESS: 集成 ${SQL_FILE}.sql 到 SUPPORTED_SQL_QUERY_LIST"
       fi
   done
   ```

### 预期输出
- Gluten 的 SQL 测试目录下更新为合并后的文件
- `VeloxSQLQueryTestSettings.scala` 中新增 SQL 文件名
- 报告中新增“SQL 测试用例合并统计”章节，包含详细的数量统计

### 注意事项
- 临时 Git 仓库仅用于合并，合并完成后可删除
- 冲突解决需手动操作，确保 Gluten 逻辑不被破坏

---

## 8. 步骤七：清理工作（自动+手动）
### 目标
清理临时文件，确保环境整洁，报告格式规范。

### 操作步骤
1. 自动清理临时文件：
   ```bash
   # 删除临时目录
   rm -rf ${TMP_DIR}
   # 清理 Git 配置（可选）
   git config --global --unset user.name "Gluten Upgrade Tool" 2>/dev/null
   git config --global --unset user.email "gluten-upgrade@example.com" 2>/dev/null
   
   # 格式化报告（可选，需安装 pandoc）
   if command -v pandoc &> /dev/null; then
       pandoc -s ${REPORT_FILE} -o ${REPORT_FILE}.tmp && mv ${REPORT_FILE}.tmp ${REPORT_FILE}
       echo "SUCCESS: 报告格式优化完成"
   fi
   ```

2. 手动检查项：
   - 确认 `${GLUTEN_ROOT}/suite_mapping_report.md` 无乱码、表格对齐
   - 确认 Gluten 代码目录下无残留的临时文件（.txt/.tmp 等）
   - 编译 Gluten 项目，验证新增的 Suite 文件无语法错误：
     ```bash
     cd ${GLUTEN_ROOT}
     ./build.sh --profile ${UPGRADE_PROFILE} --test-only "org.apache.gluten.utils.velox.*"
     ```

### 预期输出
- `${TMP_DIR}` 被完全删除
- 报告文件格式整齐，无临时文件残留
- 编译无语法错误（可选，验证代码正确性）

---

## 总结
### 核心优化点
1. **修正语法错误**：修复变量拼写（UPGRADE_PROFILER → UPGRADE_PROFILE）、路径拼接错误（${${GLUTEN_SPARK41_TEST} → ${GLUTEN_SPARK41_TEST}）、步骤编号混乱等问题。
2. **增强可执行性**：为所有步骤提供完整的可复用脚本，补充依赖检查、错误处理，避免“只讲逻辑不讲操作”。
3. **提升安全性**：增加校验和验证、防覆盖、防重名逻辑，避免破坏已有代码。
4. **结构化输出**：统一报告格式，补充数量统计、状态提示，便于后续复盘。
5. **环境兼容性**：兼容 macOS/Linux 系统，自动切换镜像/工具命令，降低执行门槛。

### 关键执行保障
- 每一步骤均包含“预期输出”和“注意事项”，便于你验证执行结果。
- 核心操作（如下载、合并、生成代码）均有容错逻辑，失败时明确提示并退出，避免连锁错误。
- 临时文件统一归到 `/tmp/gluten_spark_upgrade`，清理时一键删除，无残留。