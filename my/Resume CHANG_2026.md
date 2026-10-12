## Personal Information

- Chang Chen / Male / 1976 / Shanghai / CET-4 | Mobile: 13651970500, Email: changchen@apache.org
- GitHub: https://github.com/baibaichen
- Career Objective:  Solutions Architect, High-Performance Databases  | Preferred Location: Shanghai

## EDUCATION

| University            | Degree & Major | Duration      |
| ------------------------- | -------------- | ----------------- |
| Fudan University | Master's in Software Engineering | Mar. 2013 - Jan. 2017 |
| China Jiliang University              | Bachelor's in Electromagnetic Measurement | Sep. 1994 - Jun. 1998 |

## SUMMARY/IT Skills
-   **Microsoft Senior Software Engineer**, working on Gluten / Velox performance and Spark 4.1 support, with a focus on columnar execution, native memory management, and SQL expressions.  
-   [Apache Gluten](https://github.com/apache/gluten) **Initial Committer**: Led the technical partnership between Intel and Kyligence, taking Spark native vectorized execution from proof of concept (POC) to product delivery.  
-   Over 25 years of software development experience, with a long-term focus on C++. Use C++, Java, and Scala in daily work.  
-   Expert in **Spark** and familiar with the Hadoop ecosystem. Experienced in optimizing Gluten / Velox, OLAP, and ETL workloads.  
-   Strong knowledge of **distributed systems**, concurrency, memory management, and computer architecture, with experience tuning software for hardware features.  
-   Skilled in project management and technical work across teams and companies, leading teams through technical validation and product delivery.  
-   **Co-inventor of a granted patent**, with experience developing hybrid queries and intelligent tiered storage for cloud analytics.

## Working Experience

| Period          | Company                                                                     | Job Title                   |
|---------------------|---------------------------------------------------------------------------------|------------------------------------------|
| Nov. 2025 - Present | Microsoft | Senior Software Engineer |
| Oct. 2019 - May 2025 | [Kyligence Inc](https://kyligence.io/).                                         | Chief Researcher             |
| Sep. 2017 - Oct. 2019 | [Shanghai Lianshang Network Technology Co., Ltd.](https://www.wifi.com/) | Big Data Expert                 |
| Jan. 2013 - Sep. 2017 | Yihaodian                                                               | Senior Architect (P10), Head of Big Data Platform |
| Oct. 2003 - Dec. 2012^1^ | Sonic Solutions, Rovi Corporation, and Corel Corporation | Technical Manager & Senior Software Engineer |
| Oct. 2000 - Sep. 2003   | Shanghai **UltraBlue** Software Co. Ltd             | Senior Software Engineer   |
| Sep. 1998 - Sep. 2000   | ArcSoft Inc. (Hangzhou)                                                         | Software Engineer       |

> 1. Rovi completed its acquisition of Sonic Solutions in 2011. Corel acquired the Roxio business from Rovi in 2012.

## Projects
<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Microsoft Gluten / Velox Backend (Nov. 2025 - Present)</strong></div>
  <div>Senior Software Engineer</div>
</div>

**Description**: Improve Gluten / Velox performance at Microsoft and support Spark 4.1, covering execution efficiency, memory management, and version compatibility.
**Skills** : Linux, C++, Java, Scala, Spark SQL, Gluten, Velox
**Responsibilities** :

1. **High-performance analytics engines**: Optimize the Gluten / Velox backend for internal Microsoft workloads. Analyze compute and memory costs in Spark SQL to improve C++ native execution.
1. **Spark 4.1 and query execution**: Adapt core interfaces for Spark 4.1 and preserve partitioning in columnar Union. Add regression tests to ensure correct aggregation and joins when a shuffle is skipped.
1. **Memory management and concurrency**: Add dynamic admission control for new native memory allocations while preserving existing virtual address ranges. Improve memory reservation and reclamation for concurrent allocations to support cache size changes under Spark memory pressure.
1. **SQL expressions and CPU efficiency**: Optimize vectorized expressions by reducing unnecessary initialization and repeated work. Check performance gains and limits across data types, NULL distributions, and encodings.
1. **Performance analysis and validation**: Use repeatable before-and-after microbenchmarks and regression tests to check performance and correctness. Track native offloading, fallbacks, and failures in ANSI SQL expressions to find coverage gaps and set fix priorities.
1. **Cross-language integration and open-source collaboration**: Work on API compatibility, C++ dependencies, and continuous integration across Spark, Gluten, and Velox. Contribute engine improvements upstream to support reliable builds and compatibility across versions.

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Apache Gluten（Oct. 2022 - Present）</strong></div>
  <div>Project Lead & Chief Researcher (while at Kyligence)</div>
</div>

**Description**: [Apache Gluten](https://gluten.apache.org/) is an Apache top-level project that speeds up Spark SQL through native vectorized execution. As a founding core contributor, I helped build Gluten and develop technical partnerships.
**Skills** : Linux, C++, Spark
**Achievements**:  
1. Led the technical partnership between Intel and Kyligence to define and launch Gluten, a Spark native vectorized execution engine for x86 and ARM.
2. Built the core team and set the technical roadmap. Led project incubation, technical development, and community work.
3. Helped Gluten complete Apache incubation. The project is used by Huawei, BIGO, Microsoft, Alibaba, and Google.
4. Improved ARM performance by tuning execution for hardware features and data analytics workloads.
5. Achieved about 2x the query performance of vanilla Spark on selected key workloads through vectorized execution.

**Responsibilities** :

1. Led the team from the initial design through POC validation, engineering work, and integration into Kyligence Enterprise.  
1. Added Page Index and Row Index support to the Parquet Reader.  
1. Added Parquet read/write and statistics collection support for Delta Lake, and Parquet reading support for Iceberg.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Kyligence Enterprise（Oct. 2019 - Oct. 2022）</strong></div>
  <div>Senior Architect & Senior Software Engineer</div>
</div>

**Description**: An enterprise OLAP platform based on Apache Kylin, providing sub-second SQL queries on petabyte-scale data and multidimensional analysis on data lakes.
**Skills** : Linux, Hadoop ecosystem, HDFS, MapReduce, Spark
**Responsibilities** : 

1. Optimized RoaringBitmap Union with Lazy OR, achieving a 5-6x speedup in specific cases.  
2. Built intelligent tiered storage based on the Spark optimizer.  
3. Co-inventor of ["Hybrid Query Method and System for Cloud-Based Analytical Scenarios, and Storage Medium"](https://patents.google.com/patent/CN113918561B/en), granted on July 18, 2025. Grant publication No.: CN113918561B; application No.: 202111062067.4.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>LinkSure Recruitment Data Platform（Sep. 2017 - Oct. 2019）</strong></div>
  <div>Senior Architect</div>
</div>

**Description**: Built a big data platform and business data systems for location-based marketing.
**Skills** : Linux, Hadoop ecosystem
**Responsibilities** : 

1.  Built the big data platform for location-based marketing.  
2.  Built data systems for recruitment and real estate businesses.  
3.  Built a real-time stream processing platform.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Hadoop Big Data Platform（2015 - 2017）</strong></div>
  <div>Senior Architect & Director</div>
</div>

**Description**: Led the development of Yihaodian's internal big data platform.  
**Skills**: Linux, Hadoop ecosystem
**Responsibilities** : 

1. Optimized Hadoop ETL so that core BI tasks finished 3 hours earlier.  
2. Integrated data platforms and built metadata databases and data processing pipelines.  
3. Defined and applied standards for big data applications. 
4. Led Spark data mining projects for customer churn prediction and comment tagging. 
5. Helped improve the targeted marketing architecture.  
6. Led the team's work on **Apache Eagle** and mentored two Apache Committers.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Multi-Data-Center Active-Active-Active Deployment（Apr. 2014 - Jan. 2015）</strong></div>
  <div>Senior Architect & Domain Leader</div>
</div>

**Description**: A strategic project to provide highly available database services for Yihaodian. 
**Skills** : Linux, C++, Java
**Achievements**: 
1. Follow-up result: the new data center handled 30% of Yihaodian's orders during the November 11 shopping event in 2015.  
2. Enabled 5 major front-end services to run across two data centers in the same city, with traffic switching available during the November 11 shopping event in 2014. 

**Responsibilities**:

1. Designed the overall architecture and coordinated deployment across data centers.  
2. Led the work on cross-data-center cache consistency, covering:  
   1. Disaster recovery and replication strategies  
   2. Dependency management 
   3. Configuration rollout 
3. Kept application interfaces unchanged where possible. 

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Order Database Sharding and Migration from Oracle to MySQL （Aug. 2013 - Aug. 2014）</strong></div>
  <div>Senior Architect</div>
</div>

**Description**: Migrated Yihaodian's order database from Oracle to MySQL and introduced database sharding.  
**Skills**: Linux, Java
**Responsibilities**: 

1. Defined the order database sharding rules.  
1. Implemented aggregation functions in the data access layer.  
1. Prepared the test plan. 
1. Completed migration and sharding on August 30, 2014. Resolved sorting and data export issues after launch and supported the November 11 shopping event in 2014.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Distributed Cache Platform（Jan. 2013 - Aug. 2013）</strong></div>
  <div>Senior Architect & Domain Leader</div>
</div>

**Description**: Built Yihaodian's internal cache platform based on Memcached.
**Skills**: Linux, Java
**Responsibilities**: 

1. Helped design the cache platform. 
2. Developed `yconsole` for cache management.  
3. Improved fault tolerance, monitoring, alerts, and cache allocation.  
4. Promoted `ycache` across the company, reaching full adoption after one year. Built `Capture` to analyze cache access patterns.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Earlier Projects（Sep. 1998 - Jan. 2013）</strong></div>
  <div>Senior Software Engineer & Software Engineer</div>
</div>


Developed Windows desktop applications primarily using C++.  

1. **PC Game Capture**: Helped PC gamers record gameplay videos.
2. **MediaSky**: Managed and synchronized media files and metadata across devices.
3. **AuthorScript BDMV SDK & AuthorScript HDDVD SDK**: Blu-ray authoring SDKs for recording HD video on Blu-ray discs based on the BD standard.
4. Worked on several image editing products and implemented WYSIWYG (what you see is what you get) print preview.