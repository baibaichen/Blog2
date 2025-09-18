## Personal Information

- Chang Chen/Male/1976/Shanghai/ CTE - 4 | Mobile: 13651970500, Email: changchen@apache.org
- Github: https://github.com/baibaichen
- Career Objective:  Database Development  | Preferred Location: Shanghai

## EDUCATION

| University            | Degree & Major | Duration      |
| ------------------------- | -------------- | ----------------- |
| Fudan University | Master in Software Engineering | Mar. 2013 - Jan. 2017 |
| China Jiliang University              | Bachelor in Electricity and Magnetism Metrology | Sep. 1994 - Jun.1998 |

## SUMMARY/IT Skills
-   [Apache Gluten（Incubating）](https://github.com/apache/incubator-gluten)Initial Committer & PMC member:  Led the project from concept to Apache incubation, doubling the performance of Vanilla Spark.  
-   Over 25 years of software development experience, including 14 years in C++; proficient in C++, Java, and Scala.  
-   Expert in **Spark**, familiar with Hadoop ecosystem components (HDFS, MapReduce, YARN).  
-   Strong background in **distributed systems**, concurrency, and computer architecture; capable of rapid adoption of new technologies.  
-   Proven leader in cross-functional teams, skilled in project management and turning ideas into production-ready products.  
-   Outgoing, team-oriented, and able to thrive under pressure.

## Working Experience

| Period          | Compary                                                                     | Job Title                   |
|---------------------|---------------------------------------------------------------------------------|------------------------------------------|
| Oct. 2019 - May 2025 | [Kyligence Inc](https://kyligence.io/).                                         | Chief Researcher             |
| Sep. 2017 – Oct. 2019 | [Shanghai Lianshang Network Technology Co., Ltd.](https://www.wifi.com/) | Big Data Expert                 |
| Jan. 2013 – Sep. 2017 | Yihaodian                                                               | Senior Architecture &  Director |
| Oct. 2003 – Dec. 2012   | Corel Corporation(Sonic Solutions, Rovi Corporation) | Technical Manager & Senior Software Engineer |
| Oct. 2000 – Sep. 2003   | Shanghai **UltraBlue** Software Co. Ltd             | Senior Software Engineer   |
| Sep. 1998 – Sep. 2000   | Arcsoft Inc. (HangZhou)                                                         | Software Engineer       |

## Projects
<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Apache Gluten（Incubating）（Oct. 2021 ~ Present）</strong></div>
  <div>Leader & Chief Researcher</div>
</div>
**Description**: [Apache Gluten](https://github.com/apache/incubator-gluten) is an open-source project under the Apache Incubator that aims to enhance the performance of Apache Spark by integrating native vectorized execution engines. 
**Skills** : Linux, C++, Spark
**Achievements**:  
1. Doubled the performance of Vanilla Spark in key workloads.  
2. Successfully incubated into the Apache Software Foundation, establishing its role in the Spark ecosystem.  
3. Advanced ARM architecture optimization for domestic technology substitution scenarios.

**Responsibility** :

1. Led the team from initial concept to POC validation, engineering implementation, and integration into Kyligence Enterprise.  
1. Implemented Parquet Reader features: Page Index and Row Index support.  
1. Extended data lake support: Delta Lake (read/write with statistics collection) and Iceberg (read support for lightweight-updated Parquet files).  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Kyligence Enterprise（Oct. 2019 ~ Oct. 2021）</strong></div>
  <div>Senior Architect & Senior Software Engineer</div>
</div>
**Description**: Kyligence Enterprise, based on Apache Kylin, provides sub-second standard SQL query responses based on PB-scale datasets, simplifying multidimensional data analysis on data lakes for enterprises and enabling business users to quickly discover business value in massive amounts of data and drive better business decisions.
**Skills** : Linux, Hadoop, Spark
**Responsibility** : 

1. Improved performance by optimizing `RoaringBitmap`’s union operation using lazy OR, achieving 5–6x speedup in certain scenarios.  
2. Designed and implemented intelligent tiered storage leveraging Spark’s optimizer.  
3. Filed an invention patent: ["Hybrid Query Method and System for Cloud-Based Analytical Scenarios, and Storage Medium"](https://patents.google.com/patent/CN113918561A/zh)  (Patent No.: 2021110620674), currently under public review.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>LinkSure Recruiting data warehousing solution（Sep. 2017 - Oct. 2019）</strong></div>
  <div>Senior Architect</div>
</div>
**Description**: Built a Hadoop-based big data platform for location-based marketing, recruitment, and real-time analytics.
**Skills** : Linux, Hadoop, Spark
**Achievements**:  

1. Increased data extraction and transformation speed by 55%, enabling more efficient downstream processing.  
2. Reduced data processing latency by 60% through a new Kafka-based data pipeline, supporting real-time analytics for over 20 million daily user behaviors.  

**Responsibility** : 

1.  Led the design and implementation of the big data foundation and data pipeline.  
2.  Directed ETL processes using Hadoop and Spark.  
3.  Built real-time streaming platform for recruitment and real estate projects.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Hadoop Big Data Platform（2015 - 2017）</strong></div>
  <div>Senior Architect & Director</div>
</div>
**Description**: Designed, built, and maintained Yihaodian’s internal big data platform.  
**Skills**: Linux, Hadoop
**Responsibility** : 

1. Optimized ETL processes on Hadoop clusters, improving core BI operations by 3 hours.  
2. Integrated foundational data platforms, built metadata databases, and established data processing pipelines.  
3. Developed and enforced big data application standards. 
4. Led Spark-based data mining projects: customer churn prediction and comment tagging. 
5. Participated in optimizing the precision marketing architecture.  
6. Led team contributions to **Apache Eagle**, mentoring two Apache Committers.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Geographically Distributed Deployment (Multi-DC Active-Active-Active)（Apr. 2014 - Jan. 2015）</strong></div>
  <div>Senior Architect & Domain Leader</div>
</div>

**Description**: A strategic project to ensure high availability and disaster recovery for critical services. 
**Skills** : Linux, C++, JAVA
**Achievements**: 
1. By Nov. 11, 2014, 30% of orders were processed in newly deployed data centers.  
2. Achieved seamless traffic switching across multiple IDCs for 5 major front-end services by Double 11, 2014. 

**Responsibility**:

1. Designed the overall multi-data-center architecture.  
2. Led implementation of:  
   1. Cache invalidation mechanism in multiple data centers  
   2. Single Sign on in multiple data centers 
   3. Protection against connection storms 
3. Ensured business transparency during cache consistency management. 

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Order Database Sharding and Migration from Oracle to MySQL （Aug. 2013 - Aug. 2014）</strong></div>
  <div>Senior Architect</div>
</div>

**Description**: Migrated Yihaodian’s critical order database from Oracle to MySQL with sharding for scalability, ensuring zero downtime.  
**Skills**: Linux, JAVA
**Responsibility**: 

1. Designed the sharding strategy and data sharing plan.  
1. Implemented aggregation functions in the Data Access Layer (DAL).  
1. Designed test plans and optimized SQL. 
1. Successfully went live on August 31, 2014, with minimal issues and smoothly handled the 2014 Double 11 peak.  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Distributed Cache Platform（Jan. 2013 - Aug. 2013）</strong></div>
  <div>Senior Architect & Domain Leader</div>
</div>
**Description**: Built a distributed key-value cache platform based on Memcached and ZooKeeper, featuring automatic failover, dynamic capacity scaling, client-side load balancing, and cache invalidation.
**Skills**: Linux, JAVA
**Responsibility**: 

1. Designed and led the implementation of the distributed Memcached system. 
2. Developed `yconsole` for cache management and `Capture` tool for analyzing cache access patterns.  
3. Established monitoring, alerting, and standardized cache allocation.  
4. By Oct. 2014, the platform was adopted company-wide, enabling dynamic scaling during promotions (e.g., Double 11).  

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Other Projects（Pre-Internet Industry, Sep. 1998 ~ Jan.2013）</strong></div>
  <div>Senior Software Engineer & Software Engineer</div>
</div>


Developed Windows desktop applications primarily using C++.  

1. **PC Game Capture**: Software for recording gameplay videos.
2. **MediaSky**: Cross-device multimedia file management and synchronization.
3. **AuthorScript BDMV SDK & AuthorScript HDDVD SDK**: Blu-ray authoring SDK.
4. Contributed to multiple image editing software projects, including implementing WYSIWYG print preview.