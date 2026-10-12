## 个人信息

- 陈畅/男/1976/上海/英语4级 | 手机：13651970500 , 邮箱：changchen@apache.org
- GitHub：https://github.com/baibaichen
- 求职意向：高性能数据库解决方案架构师（Solutions Architect） | 期望城市：上海

## 教育经历

| 学校         | 学历，专业     | 时间              |
| ------------ | -------------- | ----------------- |
| 复旦大学     | 硕士，软件工程 | 2013.03 - 2017.01 |
| 中国计量大学 | 学士，电磁检测 | 1994.09 - 1998.06 |

## 简介/IT 技能

-   **Microsoft Senior Software Engineer**，负责 Gluten / Velox 性能优化及 Spark 4.1 支持，专注列式执行、Native 内存管理和 SQL 表达式优化
-   **Apache Gluten Initial Committer**，主导 Intel 与 Kyligence 技术合作，推动 Spark Native 向量化执行从 POC 到产品落地
-   擅长项目管理及跨团队、跨公司技术协作，带领团队完成技术验证与产品交付
-   25 年以上软件开发经验，长期从事 C++ 开发，工作语言为 C++、Java 和 Scala
-   精通 Spark，熟悉 Hadoop 生态，具备 Gluten / Velox、OLAP 和 ETL 优化经验
-   熟悉分布式系统、并发、内存管理及计算机体系结构，具备软硬件协同优化经验
-   **授权发明专利发明人之一**，从事云上混合查询与智能分层存储研发

## 职业生涯总结

| 时间                | 公司                                                                            | 职位                                     |
|---------------------|---------------------------------------------------------------------------------|------------------------------------------|
| 2025.11 - 至今 | Microsoft | Senior Software Engineer |
| 2019.10 - 2025.05 | [Kyligence Inc](https://kyligence.io/).                                         | 首席研究员                               |
| 2017.09 - 2019.10 | [连尚网络（WiFi万能钥匙）](https://www.ilinksure.com/)        | 大数据专家                               |
| 2013.01 - 2017.09 | 1号店                                                                           | 架构专家，**P10** 架构部大数据平台负责人 |
| 2003.10 - 2012.12^1^ | Sonic Solutions，Rovi Corporation 和 [Corel Corporation](http://www.corel.com/) | 技术经理 高级软件工程师                  |
| 2000.10 - 2003.09   | 上海超蓝软件有限公司                                                            | 高级软件工程师                           |
| 1998.09 - 2000.09   | ArcSoft Inc. (Hangzhou)                                                         | 软件工程师                              |

> 1.  2011 年 Rovi 完成对 Sonic Solutions 的收购；2012 年 Corel 收购 Rovi 旗下的 Roxio 业务。

<div style="page-break-after: always;"></div>

## 项目经历
<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Microsoft Gluten / Velox 后端（2025.11 - 至今）</strong></div>
  <div>Senior Software Engineer</div>
</div>

**项目描述**：负责微软 Gluten / Velox 后端性能优化与 Spark 4.1 支持，涉及执行效率、内存管理和版本兼容。
**技术栈** ：Linux，C++，Java，Scala，Spark SQL，Gluten，Velox
**工作内容/个人职责** :

1. **高性能数据分析引擎优化**：优化微软内部 Gluten / Velox 后端，分析 Spark SQL 负载的计算与内存开销，改进 C++ Native 执行效率。
1. **Spark 4.1 支持与查询执行**：适配 Spark 4.1 核心接口，完善列式 Union 分区语义，确保省略 Shuffle 后的聚合、Join 正确性，并补齐回归测试。
1. **内存管理与并发资源控制**：增加 Native 内存动态准入控制，保留既有虚拟地址范围，完善并发分配预留与回收，为按 Spark 内存压力调整缓存容量提供支持。
1. **SQL 表达式与 CPU 执行效率**：优化向量化表达式，减少冗余初始化与重复处理，评估不同数据类型、NULL 分布及编码下的收益与适用范围。
1. **性能分析与验证**：用可复现的对照微基准和回归测试验证性能与正确性；跟踪 ANSI SQL 表达式的下推、回退及失败，定位覆盖缺口并确定修复优先级。
1. **跨语言工程与开源协作**：推进 Spark、Gluten、Velox 接口适配、C++ 依赖管理和持续集成，向上游贡献引擎改进，保障跨版本兼容与构建可靠性。

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Apache Gluten（2022.10 - 至今）</strong></div>
  <div>负责人 & 首席研究员（Kyligence 任职期间）</div>
</div>

**项目描述**： [Apache Gluten](https://cn.kyligence.io/blog/gluten-spark/) - Apache 顶级项目 | 创始核心贡献者 & 战略合作推动者

  *   **主导促成 Intel 与 Kyligence 的战略技术合作**，共同定义并启动 Gluten，构建面向 **x86 & ARM** 的 Spark Native 向量化执行引擎。
  *   **从零组建核心团队并制定技术路线**，主导项目孵化、技术攻关与社区建设。
  *   **推动 Gluten 完成 Apache 孵化**，项目已被华为、BIGO、微软、阿里、Google 等采用。
  *   **ARM 架构性能优化**：结合硬件特性与数据分析负载，优化关键场景的执行效率。
  *   **项目成果**：通过向量化执行，在部分关键负载中实现约 2 倍于原生 Spark 的查询性能。

**技术栈** ：Linux，C++，Spark
**工作内容/个人职责** :

1. 带领团队从初始方案出发，完成 POC 验证、工程化及 Kyligence Enterprise 产品集成
1. Parquet Reader：支持 Page Index 和 Row Index
1. 数据湖：支持 Delta 读写 Parquet 并收集统计信息，支持读取 Iceberg Parquet 数据

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Kyligence 企业版（2019.10 - 2022.10）</strong></div>
  <div>架构专家 & 高级研发</div>
</div>

**产品描述**：基于 Apache Kylin 的企业级 OLAP 平台，面向 PB 级数据提供亚秒级 SQL 查询，支持数据湖上的多维分析。
**技术栈** ：Linux，Hadoop 生态系统，包括 HDFS、MapReduce、Spark
**工作内容/个人职责** : 
1. 使用 Lazy OR 优化 RoaringBitmap 的 Union 操作，在特定场景下实现 5 到 6 倍加速。
2. 基于 Spark 优化器实现智能分层存储，相关专利《基于云上分析场景的混合查询方法和系统、存储介质》于 2025.07.18 获授权，本人为发明人之一；授权公告号：CN113918561B，申请号：202111062067.4。

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>连尚网络招聘大数据平台建设（2017.09 - 2019.10）</strong></div>
  <div>架构专家</div>
</div>

**项目描述**：建设位置营销大数据基础平台与业务数据体系
**技术栈** ：Linux，Hadoop 生态系统
**工作内容/个人职责** : 
1. 建设位置营销大数据基础平台
2. 建设招聘和房产业务的数据体系
3. 建设实时流处理平台

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店大数据平台建设（2015 - 2017）</strong></div>
  <div>架构专家 & 总监</div>
</div>

**项目描述**：构建1号店内部的大数据基础平台
**技术栈** ：Linux，Hadoop 生态系统
**工作内容/个人职责** : 
1. 负责1号店大数据平台建设
2. 优化 Hadoop 集群 ETL，使核心 BI 任务提前 3 小时完成
3. 整合基础数据平台，构建元数据库与数据处理管道
4. 制定并实施1号店大数据应用规范 
5. 带领团队落地 Spark 数据挖掘项目：用户流失模型和评论打标
6. 参与优化1号店精准营销架构
7. 带领团队参与 Apache Eagle 开发，培养出两名 Apache Committer

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店异地三活（2014.04 - 2015.01）</strong></div>
  <div>高级架构师 & Domain Leader</div>
</div>

**项目描述**：战略性项目，1号店需要提供高可用的数据库服务 
**技术栈** ：Linux，C++，Java
**工作内容/个人职责** : 
1. 设计整体架构，协调各团队完成多 IDC 部署
2. 带领团队实现跨 IDC 缓存一致性，处理容灾、复制策略、依赖管理与配置发布，尽量保持业务接口透明
3. 2014年双11，支持 5 个主要前台业务在同城双 IDC 运行，并随时切换流量
4. 后续运营成果：2015年双11，新建 IDC 承载1号店 30% 的订单

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店订单服务去O分库（2013.08 - 2014.08）</strong></div>
  <div>高级架构师</div>
</div>

**项目描述**：将1号店订单库从 Oracle 迁移至 MySQL，并实施分库
**技术栈** ：Linux，Java
**工作内容/个人职责**
1. 设计订单库分库标准，实现数据中间件聚合功能并制定测试计划
2. 2014.08.30 完成订单库迁移与分库，解决上线后的排序与数据导出问题，平稳支撑2014年双11

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店分布式缓存平台（2013.01 - 2013.08）</strong></div>
  <div>高级架构师 & Domain Leader</div>
</div>

**项目描述**：1号店缓存平台
**技术栈** ：Linux，Java
**工作内容/个人职责**
1. 参与设计缓存平台，开发 yconsole 管理工具
2. 围绕 Memcached 完善容错、监控、预警与缓存分配机制，推广 ycache，一年后实现全公司接入；开发 Capture 工具分析缓存访问行为

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>其它项目经验（互联网之前，1998.09 - 2013.01）</strong></div>
  <div>高级研发 & 软件工程师</div>
</div>

主要是使用 C++ 开发 Windows 下的桌面软件
1. **PC Game Capture**：帮助 PC 游戏玩家录制游戏视频。
2. **MediaSky**：支持跨设备多媒体文件及元数据的管理与同步。
3. **AuthorScript BDMV SDK & AuthorScript HDDVD SDK**：蓝光制作 SDK，将高清视频按 BD 标准刻录至蓝光盘。
4. 参与多款图像编辑软件开发，实现所见即所得的打印预览。