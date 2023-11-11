# MergeTree Over S3

## Backgroud

Object storage support for `MergeTree` tables has been added into ClickHouse in 2020 and evolved since then. The current implementation is described in the Double.Cloud article “[How S3-based ClickHouse hybrid storage works under the hood](https://double.cloud/blog/posts/2022/11/how-s3-based-clickhouse-hybrid-storage-works-under-the-hood/)”. We will use S3 as a synonym of object storage, but it also applies to GCS and Azure blob storage.

While S3 support has improved substantially in recent years there are still a number of problems with the current implementation (see also [3] and [4]):

- Data is stored in two places: local metadata files and S3 objects.
- Data stored in S3 is not self-contained, i.e. it is not possible to attach table stored in S3 without the local metadata data files
- Every modification requires **synchronization between 2 different non-transactional media**: local metadata files on a local disk and the data itself stored in object storage. That leads to consistency problems.
- Because of the above, [zero-copy replication](https://clickhouse.com/docs/en/operations/storing-data#zero-copy) is also not reliable, and is [known for bugs](https://github.com/ClickHouse/ClickHouse/labels/comp-s3)
- Backups are not trivial since two different sources need to be backed up separately

ClickHouse Inc. made their own solution to this with the [SharedMergeTree storage engine](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates), which is not going to be released in open source. The purpose of this document is to propose a solution that makes object storage support for MergeTree much better, and can be implemented by the open source ClickHouse community under Apache 2.0 license.

## Requirements

We consider that MergeTree over S3 should meet the following high level requirements:

- It should store MergeTree table data (fully or selected parts/partitions) in object storage
- It should allow to read S3 MergeTree table from multiple replicas
- It should allow to write into S3 MergeTree table from multiple replicas
- It should be self-contained, i.e. all the data and metadata should be stored in one bucket
- It should build incrementally on existing ClickHouse functionality
- The solution should be cloud provider agnostic, and work for GCP and Azure as well ([s3proxy](https://github.com/gaul/s3proxy) may be used as an integration layer).

Additional requirements to consider:

- <u>==Ability to distribute merges between replicas==</u> (see also “worker-replicas” proposal [Replica groups for Replicated databases #53620](https://github.com/ClickHouse/ClickHouse/issues/53620))
- Reduce the number of S3 operations, which can drive costs up unnecessarily.

## Proposal

We propose to focus on two different tracks that can be executed in parallel:

1. improving zero-copy replication, that builds on existing S3 disk design
2. improving storage model for S3 data

We do not need to address the dynamic sharding that is also a feature of ClickHouse’s `SharedMergeTree`.

### 1. Improving zero-copy replication

The problem with current zero-copy replication is that it has to manage both replication for local metadata files in a traditional way, and zero-copy replication for data on object storage. Mixing those two in one solution is error prone. In order to make zero-copy replication more robust, S3 metadata needs to be moved from a local storage to Keeper. Here is how it can be done:

- Make metadata storage configurable, allow S3 metadata to be stored locally (for backward compatibility) or in Keeper
- When stored in Keeper, all part related operations should be done in a single Keeper transaction, that ensures that parts metadata and S3 are in sync
- When S3 metadata is stored in Keeper, zero-copy replication becomes simpler, since no replication is needed
- Make periodic metadata snapshot to S3 bucket, so the table can be mounted/restored in case of metadata is lost in local file system and keeper
- Allow migration from local metadata to Keeper metadata. E.g. if Keeper metadata is configured, and ClickHouse to starts without metadata – it can read from local storage and populate Keeper

Since this may increase the amount of data stored in Keeper, compact metadata also needs to be implemented. That will also reduce S3 overheads (see [5])

We can keep the local storage metadata option for compatibility, and for single-node operation. Alternatively, since Keeper can be used in embedded mode, it can be used in single-node deployments as well, but ClickHouse would require more complex configuration.

### 2. Improving MergeTree over S3 storage model

The current MergeTree over S3 implementation is backed in S3 disk. We can not change it <u>==without breaking changes==</u>. There is another undocumented `S3_plain` disk that is better in the long term. `S3_plain` disk differs from S3 disk in that it stores data in exactly the same structure as it does in a local file system: file path matches the object path, so no local metadata files are needed. This has following implications:

- It is easy to manage since all the data is in one place
- S3_plain disk can be transparently attached to any ClickHouse instance, since no extra metadata is required
- As a side feature – S3_plain can be attached to any ClickHouse in read-only node for testing purposes (e.g. version upgrades)
- The data modifications for S3_plain disk have to be limited compared to a file system. In particular, some mutations and renames can not be easily done. See Appendix A for compatibility matrix.
- Backup is also much easier to implement. E.g. even S3 bucket versioning can be used.
- It can open the door to running ClickHouse lambdas over S3 data

We propose using S3_plain disk instead of S3, in order to address the s3 local metadata problem. The current implementation of S3_plain disk is very limited, and needs to be improved. The following changes are needed:

Storage level:

- Extend ClickHouse storage model to work with storages that do not support hard links – those storages may not support all the functionality, but most of it.
- Allow to execute MOVE without using hard links. Instead, some flag files can be used to mark the completion. This will make S3_disk usable for cold partitions, and also allow migrating existing data from S3 disk.
- Implement operations that re-write the part completely: INSERT, MERGE, ALTER TABLE DELETE
- Implement adding a column/index in-place that can be done without hard links/renames
- Implement adding/removing TTL, MATERIALIZE TTL
- Allow renaming a column in place (without renaming the part) – optional
- Implement ALTER TABLE UPDATE using copy or server-side copy.

Replication:

- Integrate S3_plain with zero-copy replication. In this case, metadata in Keeper serves as a cache during ClickHouse start.
- Alternatively, S3 metadata can be removed completely. Instead, the S3 prefix that corresponds to part can be stored directly in the part node that exists in Keeper already. It simplifies the replication protocol and reduces the amount of data in Keeper.
- Could be covered by this [Zero copy support clustered file system(CFS) #53629](https://github.com/ClickHouse/ClickHouse/pull/53629) – Zero copy support NFS.

The functionality should be generic and applied to other object storage types using corresponding APIs or s3proxy ([8])

## References

1. https://clickhouse.com/blog/concept-cloud-merge-tree-tables – Cloud MergeTree tables concept
2. [Simplify ReplicatedMergeTree (RFC) #13978](https://github.com/ClickHouse/ClickHouse/issues/13978) – Simplify `ReplicatedMergeTree` (RFC) (Yandex)
3. https://gist.github.com/filimonov/75360ce79c4a73e6adfab76a3a5705d1 – S3 discussion (Altinity)
4. https://docs.google.com/document/d/1sltWM2UJnAvtmYK_KMPvrKO9xB7PcHPfWsiOa7MbA14/edit – S3 Zero Copy replication RFC (Yandex Cloud)
5. [Unite all table metadata files in one #46813](https://github.com/ClickHouse/ClickHouse/issues/46813) – Compact Metadata
6. [Shared metadata storage #48620](https://github.com/ClickHouse/ClickHouse/issues/48620) – `SharedMetadataStorage` community request
7. [Trivial Support For Resharding (RFC) #45766](https://github.com/ClickHouse/ClickHouse/issues/45766) – trivial support for re-sharding (RFC), in progress by Azat.
8. https://github.com/gaul/s3proxy – s3 API proxy to over clouds, can be used for Azure and GCP
9. [The implementation of shared metadata storage with FoundationDB. #54567](https://github.com/ClickHouse/ClickHouse/pull/54567) – SharedMetadataStorage community PR
10. [Replica groups for Replicated databases #53620](https://github.com/ClickHouse/ClickHouse/issues/53620) – replica groups proposal

## Appendix A. Feature compatibility for different MergeTree over S3 implementations

|                               | ** S3**  | **S3_plain**                      |
| ----------------------------- | -------- | --------------------------------- |
| metadata                      | separate | combined                          |
| can be restored from S3 only  | no       | yes                               |
| SELECT                        | yes      | yes                               |
| INSERT                        | yes      | yes                               |
| Merges                        | yes      | yes                               |
| ALTER TABLE DELETE            | yes      | yes                               |
| ALTER TABLE UPDATE            | yes      | **may require full data rewrite** |
| Moves                         | yes      | yes                               |
| Adding/removing column        | yes      | **yes, w/o mutation**             |
| Adding/removing index and TTL | yes      | **yes, w/o mutation**             |
| Rename table                  | yes      | yes, table is referenced by uuid  |
| Rename column                 | yes      | **no, may require add/remove**    |
| Lightweight delete            | yes      | **?**                             |

# How S3-based ClickHouse hybrid storage works under the hood

> *Written by Anton Ivashkin, DoubleCloud Dev lead for ClickHouse service.*

Everyone knows that ClickHouse is extremely fast at processing a lot of data. A dataset may reach tens/hundreds of terabytes or even a hundred petabytes. Of course, this data needs to be stored somewhere with the following core requirements: cost-efficiency, high speed, accessibility, security, and reliability. S3 or object storage is a perfect match, but the only critical point it lacks is speed. Therefore, we built a hybrid approach where you can fuse the speed of SSD disks and the affordability of S3.

Our team at DoubleCloud started developing the S3 hybrid storage feature a year ago, and it was successfully merged in version 22.3 on April 18, 2022 with further fixes and optimizations in the version 22.8. It was widely accepted by the community and Clickhouse team primarily because compute is now decoupled from the storage. We see a reduction from 3-5 times in storage cost in those scenarios where hybrid storage is applicable, and that’s a real game changer for scenarios like logs, metrics, traces, or other data scenarios where users primarily work with fresh data and the rest is stored for rare cases.

Below I will describe how it’s working under the hood and on what principles it’s based.

## The conservative approach

The classical approach is to use a sharded ClickHouse cluster. Let’s say the data is 100 TB, and there is 10 TB of storage space available on each VM. Then a perfect partitioning would require ten shards, with two replicated nodes per shard. This requirement adds up to 20 machines. However, it’s only sometimes the case that the data gets evenly split, so you can safely multiply that number by one and a half.

Plus, ClickHouse works sub-optimally when the storage has no free space. With read-only data, which is completely frozen, you can still manage, but if the new data flows in regularly, you must have at least 10 percent more free space for it to work correctly.

Now we face the need to run 30+ machines, which is quite significant. In this case, most VMs will use only disk space, and the CPU and RAM will be almost idle.

Of course, there are situations when there is a large flow of requests, and other resources will get their share of the load, but according to our data on clusters with 10+ shards, they tend to be indefinitely idle.

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-1.png)

## The alternate approach

ClickHouse can use S3-compatible storage. The advantages of this approach are the following:

- Almost unlimited capacity,
- Significantly lower cost than dedicated VMs with the same amount of disk space.

The main disadvantage is that S3-compatible storage is a network resource, so the speed of access to data, as a consequence, increases the time of operations.

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-2.png)

Let’s see how it works. An `IDisk` interface provides methods for basic file operations such as create, copy, rename, delete, etc. The ClickHouse engine works with that interface. Most of the time, it doesn’t matter what’s under the hood. There are implementations for specific storage methods:

- local disk (`DiskLocal`),
- in-memory storage (`DiskMemory`),
- cloud storage (`DiskObjectStorage`).

The latter implements logic for storing data in different types of storage, notably in S3. The other storages are HDFS and MS Azure. They’re similar conceptually, but for now let’s focus on S3.

### Managing data in S3

When the engine wants to “create a file” on an S3 disk, it creates an object in S3 with a random name, writes a data stream to it and creates a metadata file on the local disk with the name, size and some other information. The size of such a local metadata file is tens of bytes.

Then operations such as renaming and creating hard links are performed only on the local metadata file, while the object on S3 remains untouched.

S3 doesn’t provide a straightforward way to modify created S3 objects. For example, the renaming operation is a load-intensive procedure to create a new object. The above scheme with a small local metadata file allows you to bypass this limitation.

```sql
# aws s3 ls s3://double-cloud-storage-chc8d6h0ehe98li0k4sn/cloud_storage/chc8d6h0ehe98li0k4sn/s1/
2022-11-21 12:32:58      8 bpmwovnptyvtbxrxpaixgnjhgsjfekwd
2022-11-21 12:32:58     80 enmwkqfptmghyxzxhiczjgpkhzsvexgi
2022-11-21 12:32:59     10 mjgumajoilbkcpnvlbbglgajrkvqbpea
2022-11-21 12:32:59      1 aoazgzkryvhceolzichwyprzsmjotkw
2022-11-21 12:32:59      4 xiyltehvfxbkqbnytyjwbsmyafgjscwg
2022-11-21 12:32:59    235 ickdlneqkzcrgpeokcubmkwtyyayukmg
2022-11-21 12:32:59     65 lyggepidqbgyxqwzsfoxltxpbfbehrqy
2022-11-21 12:32:59     60 ytfhoupmfahdakydbfumxxkqgloakanh
2022-11-21 12:32:59      8 tddzrmzildnwtmvescmbkhqzhoxwoqmq
# ls -l /var/lib/clickhouse/disks/object_storage/store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/2_0_0_0/
total 36
-rw-r----- 1 clickhouse clickhouse 120 Nov 21 12:32 checksums.txt
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 columns.txt
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 count.txt
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 data.bin
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 data.mrk3
-rw-r----- 1 clickhouse clickhouse 118 Nov 21 12:32 default_compression_codec.txt
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 minmax_key.idx
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 partition.dat
-rw-r----- 1 clickhouse clickhouse 116 Nov 21 12:32 primary.idx
# cat /var/lib/clickhouse/disks/object_storage/store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/2_0_0_0/data.mrk3
3                                       # [metadata file format version]
1    80                                 # [objects count] [total size]
80    enmwkqfptmghyxzxhiczjgpkhzsvexgi  # [object size] [object name]
0                                       # [reference count]
0                                       # [readonly flag]
```

A separate operation is adding data to the file. As mentioned earlier, S3 doesn’t allow changing objects after creation, so we create another object to which a new portion of data is added. The name of this object is written in the meta data file mentioned earlier, and it starts referring to multiple objects.

Please note that such operation in ClickHouse is performed only for [Log family engines](https://clickhouse.com/docs/en/engines/table-engines/log-family/), which almost nobody uses. In the popular [MergeTree engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/), the file is created once and is never modified again.

For some operations, such as **mutation**, the engine creates a new `part` with a new structure when adding a new column. However, as some data doesn’t change, we use the operation to create hard links to the old ones instead of copying them. Only the local metadata file is linked, where, among other things, we store the link counter, which increases with this operation.

#### ClickHouse limitations with S3 data operations

When you perform the deletion, the engine decrements the link count and deletes the local metadata file, and if this is the last hard link to the deleted file, it possibly removes the object in S3. We’ll get back to why it’s possible when discussing replication.

**==ClickHouse doesn’t use such manipulations as data replacement in the middle of the file. Thus, it wasn’t implemented==**.

Let’s elaborate on two more points.

The first one is that the object’s name in S3 is random. It’s pretty inconvenient because it isn’t clear from the object itself what it is. Below we’ll talk about the operations log, it’s a mechanism that allows us to streamline things somewhat, but it’s not perfect either.

The second point is that storing the count of hard links in the metadata file seems unnecessary since we can obtain it from the file system. <u>==But in the case of manual manipulation of local files past ClickHouse, the link could get broken==</u>. In this case, both copies would have an increased counter, which wouldn’t allow the object to be deleted in S3 when one of the copies is deleted. Deleting the second one won’t delete it either, but it’s better to leave the garbage on S3 than lose the needed data.

When a local metadata file is read, it learns the name of the object or objects in S3, and S3 requests the desired portion of data. It helps that S3 allows you to download a fragment of an object by offset and size.

#### Caching

In the [latest ClickHouse versions](https://clickhouse.com/docs/en/whats-new/changelog/), we can cache data downloaded from object storage. <u>==我We can add data into the cache while writing with a separate option. It can speed up requests execution when different requests access the same data==</u>. Within one request, repeated reading of the same data doesn’t occur. This functionality is built into the engine. However, the cache size is limited, so the best choice depends on your case.

#### Operations log in hybrid storage

There is a default `send_metadata` setting, which is disabled by default. ClickHouse keeps a counter of operations, which increments with each operation of file creation, renaming and hard link creation.

When creating, the operation number is added to the object name in binary form, and **S3 metadata** (not to be confused with the local metadata file, we have a certain deficit in terminology here) is added to the object, ==in which the original file name is written==.

When renaming and hard linking, a special small object is created in S3, whose name also contains the operation number and whose S3 metadata records from which local name to which a hard link was renamed or created.

When performing the deletion, the operation counter isn’t incremented after the object is deleted. It allows you to restore local metadata — S3 queries the complete list of objects containing data. It enables you to recover the original name using the S3 metadata, then rename and hard link operations are applied to the existing files. It’s triggered by creating a special file before the disk starts.

This mechanism allows to perform not all operations but only up to some revision, which can be used for backups.

```sql
# aws s3 ls s3://double-cloud-storage-chc8d6h0ehe98li0k4sn/cloud_storage/chc8d6h0ehe98li0k4sn/s1/
             PRE operations/
2022-11-21 12:32:59      1 .SCHEMA_VERSION
2022-11-21 12:32:58      8 r0000000000000000000000000000000000000000000000000000000000000001-file-bpmwovnptyvtbxrxpaixgnjhgsjfekwd
2022-11-21 12:32:58     80 r0000000000000000000000000000000000000000000000000000000000000010-file-enmwkqfptmghyxzxhiczjgpkhzsvexgi
2022-11-21 12:32:59     10 r0000000000000000000000000000000000000000000000000000000000000011-file-mjgumajoilbkcpnvlbbglgajrkvqbpea
2022-11-21 12:32:59      1 r0000000000000000000000000000000000000000000000000000000000000100-file-aaoazgzkryvhceolzichwyprzsmjotkw
2022-11-21 12:32:59      4 r0000000000000000000000000000000000000000000000000000000000000101-file-xiyltehvfxbkqbnytyjwbsmyafgjscwg
2022-11-21 12:32:59    235 r0000000000000000000000000000000000000000000000000000000000000110-file-ickdlneqkzcrgpeokcubmkwtyyayukmg
2022-11-21 12:32:59     65 r0000000000000000000000000000000000000000000000000000000000000111-file-lyggepidqbgyxqwzsfoxltxpbfbehrqy
2022-11-21 12:32:59     60 r0000000000000000000000000000000000000000000000000000000000001000-file-ytfhoupmfahdakydbfumxxkqgloakanh
2022-11-21 12:32:59      8 r0000000000000000000000000000000000000000000000000000000000001001-file-tddzrmzildnwtmvescmbkhqzhoxwoqmq
# aws s3api head-object --bucket double-cloud-storage-chc8d6h0ehe98li0k4sn --key cloud_storage/chc8d6h0ehe98li0k4sn/s1/r0000000000000000000000000000000000000000000000000000000000000010-file-enmwkqfptmghyxzxhiczjgpkhzsvexgi
{
  "AcceptRanges": "bytes",
  "LastModified": "Mon, 21 Nov 2022 12:32:58 GMT",
  "ContentLength": 80,
  "ETag": "\"fbc2bf6ed653c03001977f21a1416ace\"",
  "ContentType": "binary/octet-stream",
  "Metadata": {
      "path": "store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/moving/2_0_0_0/data.mrk3"
  }
}
# aws s3 ls s3://double-cloud-storage-chc8d6h0ehe98li0k4sn/cloud_storage/chc8d6h0ehe98li0k4sn/s1/operations/
2022-11-21 12:33:02      1 r0000000000000000000000000000000000000000000000000000000000000001-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
2022-11-21 12:33:02      1 r0000000000000000000000000000000000000000000000000000000000000010-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
2022-11-21 12:32:59      1 r0000000000000000000000000000000000000000000000000000000000001010-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
# aws s3api head-object --bucket double-cloud-storage-chc8d6h0ehe98li0k4sn --key cloud_storage/chc8d6h0ehe98li0k4sn/s1/operations/r0000000000000000000000000000000000000000000000000000000000001010-ach-euc1-az1-s1-1.chc8d6h0ehe98li0k4sn.at.yadc.io-rename
{
  "AcceptRanges": "bytes",
  "LastModified": "Mon, 21 Nov 2022 12:32:59 GMT",
  "ContentLength": 1,
  "ETag": "\"cfcd208495d565ef66e7dff9f98764da\"",
  "ContentType": "binary/octet-stream",
  "Metadata": {
      "to_path": "store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/2_0_0_0/",
      "from_path": "store/133/13344eec-d80a-4a5b-b99d-6177f144e62a/moving/2_0_0_0"
  }
}
```

#### Backups

On a live VM and with data on local disks, backups are made by calling `FREEZE TABLE` for each table. This command creates a snapshot of the tables (hard links to all files) in a separate directory so that they can be copied somewhere for the future, then delete the directories manually or via `TABLE UNFREEZE`. It allows you to keep the tables in a consistent (but not atomic) condition.

This option isn’t suitable for S3 because only local metadata can be copied this way. Objects in S3 have to be extracted separately.

We use a way that isn’t a backup for S3 per se but a snapshot:

- Execute `TABLE FREEZE`,
- Save the revision number,
- Delete the directory with frozen data once the backup is no longer relevant.

The presence of these hard links prevents ClickHouse from deleting objects in S3. When restoring from the operation log, we restore the state for the desired revision.

When a backup becomes obsolete, delete the frozen metadata via `UNFREEZE` to correctly delete unnecessary objects in S3.

At the same time, since some tables from the backup may already be deleted in the working version and `TABLE UNFREEZE` cannot be done for them, run the `SYSTEM UNFREEZE` command. It removes all the frozen data from all the tables by backup name and can work with tables that don’t exist now. Please note that this mechanism can take a long time to execute if you have a big log of operations. At the moment, an alternative system for creating backups is in development.

The above method isn’t a classic backup, the data is in a single object in S3, and its safety relies on the high reliability of cloud storage. For example, in case of a logical error or unauthorized access, you’ll lose the data when an object is deleted.

Working with just S3 storage has a disadvantage — the `Merge` operation. It downloads all the partitions ClickHouse wants to merge and uploads a new higher-level part. If the workflow is not organized correctly, adding new data to already merged large chunks, can generate unexpectedly heavy traffic compared to the data being added.

For example, if S3 has a 1 Gb partition, and 1 kb of new data is added, ClickHouse will download this 1 Gb, measure the partitions and upload a new part to S3. As a result, adding a small chunk of data causes significantly more traffic.

One possible solution is to prohibit merges on the S3 disk ([prefer_not_to_merge](https://clickhouse.tech/docs/en/engines/table-engines/mergetree-family/mergetree/) setting), but this will cause another problem — a large number of small parts, which can significantly (sometimes catastrophically) reduce performance for `SELECT` queries. So, in a normal situation, it’s better not to use prefer_not_to_merge — this is a mechanism for serious breakdowns that can lead to fairly negative consequences. In a situation where the data arrives more or less consistently, there will be no network load problems.

### Hybrid storage

A better solution is hybrid storage. Hybrid storage uses a pair of disks, local and S3. New data is stored on the local disk, gets merged into large parts, and then these parts, which aren’t expected to merge further, are sent to S3. In this case, the access speed to local data will be higher, and this approach, in most cases, combines the performance of local disks and the volume of cloud storage. You can configure the move:

- By data age ([TTL MOVE TO …](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/)),
- By the amount of free space on the local disk ([move_factor](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/)),
- Move the data yourself ([ALTER TABLE MOVE PARTITION](https://clickhouse.com/docs/en/sql-reference/statements/alter/partition/)).

Setting up a move by time should be chosen to consider the uniformity of data flow so that the principal amount of merges occur while the data is still on the local drive. Another thing to consider is the need to read data: reading from the local drive will usually be much faster. Thus, it makes sense to transfer cold data to S3, which is expected to be accessed less frequently. It would be best if you also didn’t rely on the free space transfer alone, as hot, actively used data may be moved, reducing performance.

However, note that there is no special mechanism to reduce merge number specifically on S3 apart from a total restriction. So, if new data is added to an old partition already located in S3, the merge operation will involve downloading and uploading. To reduce the number of merges, you can use the [maxBytesToMergeAtMaxSpaceInPool](https://double.cloud/docs/en/managed-clickhouse/settings-reference#maxbytestomergeatmaxspaceinpool) setting, which limits the maximum chunk size, but it applies to all disks with table data, including the local one.

Additionally, the mechanics of using multiple disks aren’t limited to this case. For example, you can have a small, fast SSD disk and a larger but slow HDD, or even organize a multi-tiered pie with cloud storage at the end.

### Replication

By default, S3 uses the same replication mechanism as for local disks:

1. New data is written to any node, information about the new part is put into ZooKeeper/ClickHouse Keeper (for convenience, we’ll refer to both as just “Keeper”),
2. Other nodes from Keeper learn about this,
3. They access the node where this data exists and download it from this node (Fetch operation).

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-3.png)

For S3, the sequence looks as follows:

1. The first node downloaded the part from S3,
2. The second node downloaded the part from the first node,
3. The second node uploaded the part to S3.

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-4.png)

### Zero-copy replication

This can be avoided by enabling the zero-copy replication mechanism ([the allowRemoteFsZeroCopyReplication](https://double.cloud/docs/en/managed-clickhouse/settings-reference) setting).

As a rule, nodes share the same S3. When the second node requests data from the first one, the first one only sends a small bit of local metadata. The second node checks that it can get data from this metadata (in fact, it only requests the presence of one object); if it does, it stores this metadata and uses the S3 objects together with the first one. If there is no access (different S3 bucket or storage), the full copy of the data from the conservative approach takes place. This mechanism with accessibility testing makes it possible, for example, to move live to another object storage — two more replicas working with S3-A are added to S3-B, they replicate data to themselves via full copying, and each pair shares objects in its S3.

With zero-copy, each replica additionally marks in the Keeper which parts it uses in S3, and when deleting the last hard link from a node, it checks if someone else uses that data, and if it does, it doesn’t touch the object in S3.

This is the case of the “object on S3 will probably get deleted” we mentioned earlier.

#### Zero-copy limitations and issues

The zero-copy mechanism isn’t yet considered production-ready; sometimes, there are bugs. The last example, which is already fixed in recent versions — is the case of double replication during mutations.

When one node creates a part, the following happens:

1. The second node replicates it,
2. A mutation is run on the part, resulting in a new part with hard links to the original data,
3. The second node replicates the new part.

At the same time, the second node knows nothing about the connections between these parts.

If the first node deletes the old part before, the second node at the moment of deletion will decide that it’s deleting the last local link to the objects. As a result, it’ll get information from the Keeper that no one else uses objects of this part, and thus, it’ll delete objects in S3.

As stated above, this bug has already been fixed, and we have been using zero-copy in our solution for a long time.

![img](https://double.cloud/assets/blog/articles/%D1%81h-over-S3-scheme-5.png)

## Final thoughts

We also see that that community has started to add other object storage providers like [Azure blob storage developed](https://github.com/ClickHouse/ClickHouse/issues/29430) by our friends from Content Square, which once again showed us that we are moving in the right direction.

Small note about the availability of that feature at DoubleCloud. All clusters at DoubleCloud already have S3-based hybrid storage by default; you don’t need to provision or set up anything additional. [Just create a table](https://double.cloud/docs/en/managed-clickhouse/step-by-step/use-hybrid-storage) with your preferred hybrid storage profile, and you are ready to go.

[Contact our architects](mailto:viktor@double.cloud) to find out how to apply this approach to your project or even if you are looking for help setting up and using that functionality and want to chat with us.

ClickHouse® is a trademark of ClickHouse, Inc. [https://clickhouse.com](https://clickhouse.com/)