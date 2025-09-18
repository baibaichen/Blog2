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
**Description**: Hadoop based data warehouse solution
**Skills** : Linux, Hadoop, Spark
**Achievements**:  Improving data extraction and transformation speeds by 55%, and supporting more efficient downstream processing. 
**Responsibility** : 

1.  Engineered a new data pipeline leveraging Apache Kafka, reducing data processing latency by 60%, and enabling real-time analytics for over 20 million daily user behavior.
2. Directed the adoption of ETL processes using Hadoop and Spark.

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Hadoop Big Data Platform（2015 - 2017）</strong></div>
  <div>Senior Architect & Director</div>
</div>

**Description**: Design, build and maintaining of Yihaodian's Big Data platform
**Skills**: Linux, Hadoop
**Responsibility** : 

1. Optimized ETL processes on Hadoop clusters, improving core BI business operations by 3 hours.
2. Integrated Yihaodian’s foundational data platform, built metadata databases, and established data processing pipelines.
3. Developed and implemented big data application standards at Yihaodian.
4. Lead the team in executing Spark data mining projects: customer churn models and comment tagging.
5. Participated in optimizing the precision marketing architecture at Yihaodian.
6. Lead the team to contribute the development of Apache Eagle, nurturing two Apache Committers.

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Deploy Yihaodian’s service in geographically distributed datacenter（Apr. 2014 - Jan. 2015）</strong></div>
  <div>Senior Architect & Domain Leader</div>
</div>
**Description**: This is one of our company’s strategic projects. As Yihaodian grows, we must ensure highly available services even in the event of failures such as fires. 
**Skills** : Linux, C++, JAVA
**Achievements**: As of November 11, 2014, we had successfully deployed our most critical services across two new data center. Approximately 30% of orders were being processed in these newly deployed data center. 
**Responsibility**:

1. Design the whole architecture for deploying company’s various service
2. Design and lead the team to implement: 
   1. Cache invalidation mechanism in multiple data centers  
   2. Single Sign on in multiple data centers 
   3. Avoid connection storm

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Sharding the Order Database and moving it to MySQL （Aug. 2013 - Aug. 2014）</strong></div>
  <div>Senior Architect</div>
</div>
**Description**: This is one of our company’s strategic projects. The order database is critically important, and our goal is to migrate the order database from Oracle to MySQL. We aim to share the order data for scaling out while ensuring a smooth migration process that does not impact the online system.
**Skills**: Linux, JAVA
**Responsibility**: 

1. Design the database sharing plan 
1. Implement DB aggregation function in DAL 
1. Design the test plan 
1. Optimize the SQL 
1. Our new system went online on August 31, 2014, and successfully achieved all of its objectives. 

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Yihaodian Distributed Cache Platform（Jan. 2013 - Aug. 2013）</strong></div>
  <div>Senior Architect & Domain Leader</div>
</div>

**Description**: A Distributed KV stores builds on top of memcache and zookeeper. The feature includes: Automatically Failover, Dynamically increasing capacity, Manageable, Client-side Load Balance and Cache Invalidation.
**Skills**: Linux, JAVA
**Responsibility**: 

1. Design and lead the team to implement distributed memcache store 
2. As of October 2014, our client library was being used company-wide for accessing Memcached. This allowed us to dynamically increase cache capacity during the 11.11 promotion and subsequently remove the added cache once the promotion ended.

<div style="display: flex; justify-content: space-between;">
  <div style="font-size: 18px;"><strong>Other Projects（Before Entering the Internet Industry, Sep. 1998 ~ Jan.2013）</strong></div>
  <div>Senior Software Engineer & Software Engineer</div>
</div>

Primarily used C++ to develop desktop software for Windows.

1. **PC Game Capture**: Software for recording gameplay videos.
2. **MediaSky**: Cross-device multimedia file management and synchronization.
3. **AuthorScript BDMV SDK & AuthorScript HDDVD SDK**: Blu-ray authoring SDK.
4. Image editing software with WYSIWYG print preview.