## 个人信息

- 陈畅/男/1976/上海/英语4级 | 手机：13651970500 , 邮箱：changchen@apache.org
- Github：https://github.com/baibaichen
- 求职意向：数据库内核开发 | 期望城市：上海

## 教育经历

| 学校         | 学历，专业     | 时间              |
| ------------ | -------------- | ----------------- |
| 复旦大学     | 硕士，软件工程 | 2013/03 - 2017/1  |
| 中国计量大学 | 学士，电磁检测 | 1994/09 - 1998/06 |

## 简介/IT 技能

-   Apache Gluten（Incubating）Initial Committers，把 Vanilla Spark 的性能提升 2 倍！
-   精通项目管理，善于带领团队把想法变为产品上线
-   20多年软件开发经验，14年C++经验，目前以C++、JAVA和Scala作为为工作语言
-   熟悉Hadoop平台上的各种组件，精通Spark
-   熟悉分布式系统理论，并发， 对计算机软硬件有深刻的理解，能快速学习各类新技术
-   性格开朗，容易与人相处，注重团队协作精神，能承受较大压力

## 职业生涯总结

| 时间                | 公司                                                                            | 职位                                     |
|---------------------|---------------------------------------------------------------------------------|------------------------------------------|
| 2019.10 - **至今** | [Kyligence Inc](https://kyligence.io/).                                         | 首席研究员                               |
| 2017.09 – 2019.10 | [连尚网络（WIFI万能钥匙）](https://www.ilinksure.com/)        | 大数据专家                               |
| 2013.01 – 2017.09 | 1号店                                                                           | 架构专家，**P10** 架构部大数据平台负责人 |
| 2003.10 – 2012.12^1^ | Sonic Solutions，Rovi Corporation 和 [Corel Corporation](http://www.corel.com/) | 技术经理 高级软件工程师                  |
| 2000.10 – 2003.09   | 上海超蓝软件有限公司                                                            | 高级软件工程师                           |
| 1998.09 – 2000.09   | Arcsoft Inc. (HangZhou)                                                         | 软件工程师                              |

> 1.  2009 年 Rovi 收购 Sonic， 2011 年 Corel 收购了 Rovi

<div style="page-break-after: always;"></div>

## 项目经历
<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Apache Gluten（Incubating）（2021年 10 月 ~ 至今）</strong></div>
  <div>负责人 & 首席研究员</div>
</div>
**项目描述**： [Apache Gluten](https://cn.kyligence.io/blog/gluten-spark/) - Apache 顶级项目 | 创始核心贡献者 & 战略合作推动者

  *   **主导促成 Intel 与 Kyligence 的战略技术合作**，共同定义并启动 Gluten 项目，打造高性能、**跨平台（x86 & ARM）** 的 Apache Spark Native Vectorized Execution 引擎。
  *   **从零构建项目核心团队与技术路线**，作为创始核心贡献者全程主导项目孵化、技术攻关及社区建设。
  *   **成功推动 Gluten 通过 Apache 软件基金会孵化**，确立其在 Spark 生态的重要地位，华为、BIGO、微软、阿里、Google 等都在使用。
  *   **深入探索国产化替代背景下的 ARM 架构深度优化**，提升其在关键场景的性能与适用性。
  *   **项目成果**：为 Spark 用户提供高性能向量化执行方案，大幅提升 Spark 执行效率与成本效益（较原生 Spark 至少提升 2 倍）。

**技术栈** ：Linux，C++，Spark
**工作内容/个人职责** :

1. 带领团队从一个初始的 idea 开始，完成 POC 验证，做好工程化，最后集成进 Kyligence Enterprise
1. Parquet Reader： 1. 支持 Page index，2. 支持 Row Index
1. 数据湖：1.支持 Delta 读写 Parquet 并收集统计信息，2 支持读取有轻量级更新的 Iceberg parquet

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Kyligence 企业版（2019年 10 月 ~ 2021 年 10 月）</strong></div>
  <div>架构专家 & 高级研发</div>
</div>
**产品描述**：Kyligence Enterprise 企业级 OLAP 平台，基于 Apache Kylin 核⼼，提供 PB 级数据集上的亚秒级标准 SQL 查询响应，为企业简化数据湖上的多维数据分析，助⼒业务⽤户快速发现海量数据中的业务价值，获取业务洞察，驱动商业决策。 
**技术栈** ：Linux，Hadoop生态系统，包括HDFS、MapReduce、Spark
**工作内容/个人职责** : 
1. 提升性能，例如使用 lazy or 提升 RoaringBitmap 的 union 的性能，某些场景下有5 到 6 倍的提升。
2. 熟悉 Spark 优化器，实现智能分层存储，并申请发明专利《基于云上分析场景的混合查询方法和系统、存储介质》，目前处于公示状态。专利号：2021110620674 

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>连尚网络招聘大数据平台建设（2017年9月 - 2019年10月）</strong></div>
  <div>架构专家</div>
</div>
**项目描述**：构建位置营销的大数据基础平台和数据平台的建设
**技术栈** ：Linux，Hadoop生态系统
**工作内容/个人职责** : 
1. 负责位置营销的大数据基础平台的建设 
2. 负责位置营销招聘和房产项目的数据体系建设 
3. 实时流平台的建设

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>一号店大数据平台建设（2015 - 2017）</strong></div>
  <div>架构专家 & 总监</div>
</div>
**项目描述**：构建1号店内部的大数据基础平台
**技术栈** ：Linux，Hadoop生态系统
**工作内容/个人职责** : 
1. 负责1号店大数据数据平台的建设
2. 优化Hadoop集群上的ETL，使得BI核心业务提高3小时 
3. 整合1号店基础数据平台，构建元数据库，数据处理管道 
4. 制定并实施1号店大数据应用规范 
5. 带领团队落地spark数据挖掘项目：用户流失模型和评论打标 
6. 参与优化1号店精准化的架构 
7. 带领团队加入Apache Egale的开发，培养出两个Apache Commiter 

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店异地三活（2014年4月-2015年1月）</strong></div>
  <div>高级架构师 & Domain Leader</div>
</div>
**项目描述**：战略性项目，1号店需要提供高可用的数据库服务 
**技术栈** ：Linux，C++，JAVA
**工作内容/个人职责** : 
1. 负责设计整体架构，推动各个团队在多IDC部署
2. 带领团队实现『维护多IDC之间缓存一致性』的功能，遇到的挑战有： 如何容灾，双写还是复制？如何处理依赖？如何发布配置 如何管理缓存之间的一致性，编程接口尽可能的对业务人员透明
3. 2014年双11，5个主要的前台业务可以在同城双IDC机房运行，可随时切换流量 
4. 2015年双11，1号店30%的订单来至于新建的IDC

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店订单服务去O分库（2013年8月-2014年8月）</strong></div>
  <div>高级架构师</div>
</div>
**项目描述**：将1号店的订单库从Oracle迁移到MySQL，并分库
**技术栈** ：Linux，JAVA
**工作内容/个人职责**
1. 设计订单库的分库标准 实现数据中间件层的聚合功能 设计并制定测试计划 
2. 2014年8月30日，1号店订单库全部迁移至MySQL，并分库： 上线当天只出现了一个小BUG 一个月后发现由拆库引起的排序问题 两个月后发现由拆库引起的数据导出问题 平稳度过2014年双11

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>1号店分布式缓存平台（2013年1月-2013年8月）</strong></div>
  <div>高级架构师 & Domain Leader</div>
</div>
**项目描述**：1号店缓存平台
**技术栈** ：Linux，JAVA
**工作内容/个人职责**
1. 参与设计整个缓存平台 负责开发yconsole，帮助SA管理缓存平台
2. 经过一年的努力，1号店全部接入缓存平台，我们围绕memcache打造了一整套生态系统： 完善容错、监控和预警机制 规范化缓存的分配 全面推动使用ycache 开发Capture工具，用以分析各个应用读取缓存行为

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>其它项目经验（互联网之前，1998年9月~ 2013年1月）</strong></div>
  <div>高级研发 & 软件工程师</div>
</div>

主要是使用 C++ 开发 Windows 下的桌面软件
1. **PC Game Capture**：一个帮助PC游戏玩家，录制其游戏视频的软件。
2. **MediaSky**：类似 Dropbox，帮组用户管理其各种设备上的多媒体文件，使得用户可以在各种设备上同步更新这些多媒体文件，及其meta数据。
3. **AuthorScript BDMV SDK & AuthorScript HDDVD SDK**：一个全面的蓝光制作SDK，将高清的视频内容按BD标准的要求刻录至蓝光盘，
4. 参与了多个图像编辑软件的开发，特别是实现了所见即所得打印预览。