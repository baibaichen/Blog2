# MergeTree Over S3

## Backgroud

Object storage support for `MergeTree` tables has been added into ClickHouse in 2020 and evolved since then. The current implementation is described in the Double.Cloud article “[How S3-based ClickHouse hybrid storage works under the hood](https://double.cloud/blog/posts/2022/11/how-s3-based-clickhouse-hybrid-storage-works-under-the-hood/)”. We will use S3 as a synonym of object storage, but it also applies to GCS and Azure blob storage.

While S3 support has improved substantially in recent years there are still a number of problems with the current implementation (see also [[3](https://gist.github.com/filimonov/75360ce79c4a73e6adfab76a3a5705d1)] and [[4](https://docs.google.com/document/d/1sltWM2UJnAvtmYK_KMPvrKO9xB7PcHPfWsiOa7MbA14/edit#heading=h.czg4grkvo6gy)]):

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

# Using ClickHouse with S3

## Why S3 

* cost (of storage)
* scalability
* durability

but 
* latency
* cost (of operations)
* performance
* consistency (overwrites and deletes are eventually consistent)
* more complex (than local disk)
* no hardlinks / renames (used a lot in ClickHouse)
* lot of implemetations (aws, gcs, azure, minio, ceph, etc)

## State of S3 support in ClickHouse

Different modes of S3 support in ClickHouse:
* s3 disk (all operations supported, local drive used for metadata, bucket stores objects with random names), extra 'state' is needed to read s3 (metadata from local disk) + normal replica state in zookeeper
* s3plain disk - the bucket stores the files exactly the same way as they are stored on disk, 
  currently is 'write once' thing (using backup to s3)
* s3 table engine / table function - can read the data from s3 bucket in various formats, supports ==globs==
* s3Cluster - same as above, when reading a lot of files (with globs selector) - will distribute different files between different nodes (can't scale up for a single file)
* backups

Quite active developement recenetly, lot of changes, lot of new settings, etc. Not very well tested.

## Who needs that?

**Does small / medium size users really need S3?**

==Benefits of using S3== mainly for backups, or archive. Block devices (EBS) typically is faster / cheaper. 

**Does large users really need S3?**

That can give significant benefits. But typically it still better to have the active dataset on the local disks. So if they will use S3 as the main storage they still may want to have some local cache. <u>Instead of that tiered storage can be used (then active data is on the local disks, and cold data is on S3). This way you don't have to worry about the cache, and costs of S3 are lower.</u>

**What about separating compute and storage?**

Options:

1) s3 disk + zero copy replication  (+ eventually TTL MOVE rules)
   - zero copy replication still require to create / maintain state of replica in zookeeper.(not easy to scale up / down, semi-manual provisioning / deprovisioning needed).
   - offline replica will need to resync it's state
   - replicas still need to execute the replication queue all the time (it only have some 'shortcuts' to reduce the traffic)
   - you need to use fixed sharding schema always (so if the data was written for 3 shards you can only use 3 nodes to process that)
   - experimental, and can be changed in newer versions, but works for simple cases good, not ready for prod (?)
   - metadata stored on the local filesystem, and need to be backed up manually
   - all data is online, realtime, and accessible via singe table interface.
   - TTL move can be used to make multitiered system

2) s3 disk + zero copy replication + parallel replicas. same as above but no fixed sharding needed, so you can have single shard 
   - experimental, and can be changed in newer versions
   - every replica can act as a shard.
   - may be tricky with certain queries (JOINs)
   - there are 3 'generations' of that feature, first 2 was not very successful, the last one seems to work good (at least for simple cases)
   
3) offloading the data to archive-alike s3 storage which you can access later
   - not realtime
   - to access the archive you need to use different queries / different tables 
   - no automatic movements / TTL so that require to  (may be that can be implemented)
   - standard formats (Parquet etc) can be used
   - can also work for realtime

   Picking the storage format:
   1) clickhouse on-disk format via s3plain
      - have marks / indexes / metadata
      - native for clickhouse
      - good compression
      - range reads
      - proprietary format (not easy to read outside clickhouse)
      
      How: `OPTIMIZE TABLE PARTITION ... ; BACKUP old partition to s3_plain disk; ATTACH TABLE` 
   
   2) Parquet
      - columnar format
      - standard and can be used by other tools
      - good compression
      - range reads
      - no marks / indexes other extra metadata used by clickhouse
      - not native for clickhouse, and clickhouse is not able currenly to use all it's features (like indexes)

      How: `insert into s3(...) select ... WHERE partition;`  

   3) ORC - similar to Parquet

   4) JSONEachRow / TSV etc - row-based

4) serverless / external orchestation- use stateless clickhouse-local executors, orchestated by some extra layer or by one more clickhouse-local


##  Problem which would be nice to address:

1) starting new replica (new compute node - when separate compute & storage) - is very expensive (schema deployment + replication / registering in zookeeper etc).
2) metadata stored on local disk - is not reliable (no replication, hard to backup), data on s3 is not self-describing (no metadata)
3) some partially closed-source solution is used inside ClickHouse inc. for the p.1, and they can be against accepting the alternative community implementation of the same.
4) s3 is not a filesystem - mostly renames & hardlinks are problematic, and that is used a lot in ClickHouse
   -  problem with alters / mutations / merges / moves etc.
   - distributed hard links / refcounts
5) cost vs performance - s3 api calls cost vs s3 performance
6) lot of changes & improvements recently, with some new / esoteric settings: need a lot of testing.
7) very noisy logs
8) backups
9) better (atomic) offloading of immutable data

What would be nice to do:
1) testing on the large scale
2) test / make improvements on s3cluster with dynamic cluster support (for serverless)
3) s3 for the mutable / hot data: test / consider improvements (maybe use keeper more intensively? Mike Kot will work on that)
4) s3 plain: expand usage to make it writable - it should support simple inserts, simple merges, simple moves (but no mutations / moving data between tables etc)
   1) avoid folder renames (use file-markers instead)
       currently writes in many cases happen with rename: moves: part -> tmp_clone (long running), and tmp_clone -> part (target disk)
       we can use some filemarkers: positive (part is ready) or negative (part is not ready)
   2) ~~complain on attampts to use hardlinks, test basic scenarios to test what will be complaining.~~
5) test different approaches of multitiered setup which include s3plain
   a) having s3plain in the normal (mutable) MergeTree table
      - immutable / 'cold' / 'on-rest' partition - all the mutations automatically work 'IN PARTITION <mutable set of partitions>'
      - set marker ? or by disk capabilities? so partitions immutable automatically when at least one part is on immutable disk
      - test it with caching layer
      - moving to immutable partition using normal TTL rules
      - merge to another disk
   b) having s3plain data ( or data in other format, like Parquet ) in the separate table
      - s3plain table  + usual MergeTree table + engine=Merge
            events_local engine=MergeTree
            events_cold engine=MergeTree SETTINGS disk = disk(s3plain,...)
            events_full engine=Merge
         how to move atomically? 
      - s3plain table  + engine=S3(Parquet) + engine=Merge
6) Parquet improvements to use indexing / partitioning / predicate pushdown / virtual projection (like counts)
7) test encryption on s3 level
8) analyze / optimize s3 api calls (batching, parallelism, caching, retries, etc) - to reduce the cost

# ClickHouse Cloud boosts performance with SharedMergeTree and Lightweight Updates

## Table of Contents

- [Introduction](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#introduction)
- [MergeTree table engines are the core of ClickHouse](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#mergetree-table-engines-are-the-core-of-clickhouse)
- [ClickHouse Cloud enters the stage](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#clickhouse-cloud-enters-the-stage)
- [Challenges with running ReplicatedMergeTree in ClickHouse Cloud](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#challenges-with-running-replicatedmergetree-in-clickhouse-cloud)
- [Zero-copy replication does not address the challenges](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#zero-copy-replication-does-not-address-the-challenges)
- [SharedMergeTree for cloud-native data processing](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#sharedmergetree-for-cloud-native-data-processing)
- [Benefits for ClickHouse Cloud users](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#benefits-for-clickhouse-cloud-users)
- [The new ClickHouse Cloud default table engine](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#the-new-clickhouse-cloud-default-table-engine)
- [SharedMergeTree in action](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#sharedmergetree-in-action)
- [Introducing Lightweight Updates, boosted by SharedMergeTree](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#introducing-lightweight-updates-boosted-by-sharedmergetree)
- [Summary](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#summary)

## Introduction

ClickHouse is the fastest and most resource-efficient database for real-time applications and analytics. Tables from the family of MergeTree table engines are a core component of ClickHouse’s fast data processing capabilities. In this post, we describe the motivation and mechanics behind a new member of this family – the SharedMergeTree table engine.

This table engine is a more efficient drop-in replacement for the ReplicatedMergeTree table engine in [ClickHouse Cloud](https://clickhouse.com/cloud) and is engineered and optimized for cloud-native data processing. We look under the hood of this new table engine, explain its benefits, and demonstrate its efficiency with a benchmark. And we have one more thing for you. We are introducing lightweight updates which have a synergy effect with the `SharedMergeTree`.

## MergeTree table engines are the core of ClickHouse

Table engines from the MergeTree family are the main [table engines](https://clickhouse.com/docs/en/engines/table-engines) in ClickHouse. They are responsible for storing the data received by an insert query, merging that data in the background, applying engine-specific data transformations, and more. Automatic [data replication](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication) is supported for most tables in the MergeTree family through the replication mechanism of the `ReplicatedMergeTree` base table engine.

In traditional [shared-nothing](https://en.wikipedia.org/wiki/Shared-nothing_architecture) ClickHouse [clusters](https://clickhouse.com/company/events/scaling-clickhouse), replication via ReplicatedMergeTree is used for data availability, and [sharding](https://clickhouse.com/docs/en/architecture/horizontal-scaling) can be used for cluster scaling. [ClickHouse Cloud](https://clickhouse.com/cloud) took a new approach to build a cloud-native database service based on ClickHouse, which we describe below.

## ClickHouse Cloud enters the stage

ClickHouse Cloud [entered](https://clickhouse.com/blog/clickhouse-cloud-public-beta) public beta in October 2022 with a radically different [architecture](https://clickhouse.com/docs/en/cloud/reference/architecture) optimized for the cloud (and we [explained](https://clickhouse.com/blog/building-clickhouse-cloud-from-scratch-in-a-year) how we built it from scratch in a year). By storing data in virtually limitless [shared](https://en.wikipedia.org/wiki/Shared-disk_architecture) [object storage](https://en.wikipedia.org/wiki/Object_storage), storage and compute are separated: All [horizontally](https://en.wikipedia.org/wiki/Scalability#Horizontal_or_scale_out) and [vertically](https://en.wikipedia.org/wiki/Scalability#Vertical_or_scale_up) scalable ClickHouse servers have access to the same physical data and are effectively multiple replicas of a single limitless [shard](https://clickhouse.com/docs/en/architecture/horizontal-scaling#shard):
![smt_01.png](https://clickhouse.com/uploads/smt_01_d28f858be6.png)

### Shared object storage for data availability

Because ClickHouse Cloud stores all data in shared object storage, there is no need to create physical copies of data on different servers explicitly. Object storage implementations like Amazon AWS [Simple Storage Service](https://aws.amazon.com/s3/), Google GCP [Cloud Storage](https://cloud.google.com/storage), and Microsoft Azure [Blob Storage](https://azure.microsoft.com/en-us/products/storage/blobs/) ensure storage is highly available and fault tolerant.

Note that ClickHouse Cloud services feature a multi-layer [read-through](https://en.wiktionary.org/wiki/read-through) and [write-through](https://en.wikipedia.org/wiki/Cache_(computing)#WRITE-THROUGH) cache (on local [NVM](https://en.wikipedia.org/wiki/Non-volatile_memory)e SSDs) that is designed to work natively on top of object storage to provide fast analytical query results despite the slower access latency of the underlying primary data store. Object storage exhibits slower access latency, but provides highly concurrent throughput with large aggregate bandwidth. ClickHouse Cloud exploits this by [utilizing](https://clickhouse.com/docs/knowledgebase/async_vs_optimize_read_in_order#asynchronous-data-reading) multiple I/O threads for accessing object storage data, and by asynchronously [prefetching](https://clickhouse.com/docs/en/whats-new/cloud#performance-and-reliability-3) the data.

### Automatic cluster scaling

Instead of using sharding for scaling the cluster size, ClickHouse Cloud allows users to simply increase the size and number of the servers operating on top of the shared and virtually infinite object storage. This increases the parallelism of data processing for both INSERT and SELECT queries.

Note that the ClickHouse Cloud servers are effectively multiple replicas of a **single limitless shard**, but they are not like replica servers in shared-nothing clusters. Instead of containing local copies of the same data, these servers have access to the same data stored in shared object storage. This turns these servers into dynamic compute units or compute nodes, respectively, whose size and number can be easily adapted to workloads. Either manually or fully [automatically](https://clickhouse.com/docs/en/cloud/reference/architecture#compute). This diagram illustrates that:![smt_02.png](https://clickhouse.com/uploads/smt_02_a2d0b54be6.png)① Via scale up and ② scale down operations, we can change the size (amount of CPU cores and RAM) of a node. And per ③ scale out, we can increase the number of nodes participating in parallel data processing. Without requiring any physical resharding or rebalancing of the data, we can freely add or remove nodes.

For this cluster scaling approach, ClickHouse Cloud needs a table engine supporting higher numbers of servers accessing the same shared data.

## Challenges with running ReplicatedMergeTree in ClickHouse Cloud

The ReplicatedMergeTree table engine isn’t ideal for the intended architecture of ClickHouse Cloud since its replication mechanism is designed to create physical copies of data on a small number of replica servers. Whereas ClickHouse Cloud requires an engine with support for a high amount of servers on top of shared object storage.

### Explicit data replication is not required

We briefly explain the replication mechanism of the ReplicatedMergeTree table engine. This engine uses [ClickHouse Keeper](https://clickhouse.com/docs/en/guides/sre/keeper/clickhouse-keeper) (also referred to as “Keeper”) as a coordination system for data replication via a [replication log](https://youtu.be/vBjCJtw_Ei0?t=1150). Keeper acts as a central store for replication-specific metadata and table schemas and as a [consensus](https://en.wikipedia.org/wiki/Consensus_(computer_science)) system for distributed operations. Keeper ensures sequential block numbers are assigned in order for part names. Assignment of [merges](https://clickhouse.com/blog/asynchronous-data-inserts-in-clickhouse#data-needs-to-be-batched-for-optimal-performance) and [mutations](https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations) to specific replica servers is made with the consensus mechanisms that Keeper provides.

The following diagram sketches a shared-nothing ClickHouse cluster with 3 replica servers and shows the data replication mechanism of the ReplicatedMergeTree table engine:![smt_03.png](https://clickhouse.com/uploads/smt_03_21a5b48f65.png)When ① server-1 receives an insert query, then ② server-1 creates a new data [part](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#mergetree-data-storage) with the query's data on its local disk. ③ Via the replication log, the other servers (server-2, server-3) are informed that a new part exists on server-1. At ④, the other servers independently download (“fetch”) the part from server-1 to their own local filesystem. After creating or receiving parts, all three servers also update their own metadata describing their set of parts in Keeper.

Note that we only showed how a newly created part is replicated. Part merges (and mutations) are replicated in a similar way. If one server decides to merge a set of parts, then the other servers will automatically execute the same merge operation on their local part copies (or just [download](https://clickhouse.com/docs/en/operations/settings/merge-tree-settings#always_fetch_merged_part) the merged part).

In case of a complete loss of local storage or when new replicas are added, the ReplicatedMergeTree clones data from an existing replica.

ClickHouse Cloud uses durable shared object storage for data availability and doesn’t need the explicit data replication of the ReplicatedMergeTree.

### Sharding for cluster scaling is not needed

Users of shared-nothing ClickHouse [clusters](https://clickhouse.com/company/events/scaling-clickhouse) can use replication in combination with [sharding](https://clickhouse.com/docs/en/architecture/horizontal-scaling) for handling larger datasets with more servers. The table data is split over multiple servers in the form of [shards](https://clickhouse.com/docs/en/architecture/horizontal-scaling#shard) (distinct subsets of the table’s data parts), and each shard usually has 2 or 3 replicas to ensure storage and data availability. Parallelism of data ingestion and query processing can be [increased](https://clickhouse.com/company/events/scaling-clickhouse) by adding more shards. Note that ClickHouse abstracts clusters with more complex topologies under a [distributed table](https://clickhouse.com/docs/en/engines/table-engines/special/distributed) so that you can do distributed queries in the same way as local ones.

ClickHouse Cloud doesn’t need sharding for cluster scaling, as all data is stored in virtually limitless shared object storage, and the level of parallel data processing can be simply increased by adding additional servers with access to the shared data. However, the replication mechanism of the ReplicatedMergeTree is designed initially to work on top of local filesystems in shared-nothing cluster architectures and with a small number of replica servers. Having a high number of replicas of ReplicatedMergeTree is an [anti-pattern](https://en.wikipedia.org/wiki/Anti-pattern), with the servers creating too much [contention](https://en.wikipedia.org/wiki/Resource_contention) on the replication log and overhead on the inter-server communication.

## Zero-copy replication does not address the challenges

ClickHouse Cloud offers automatic vertical scaling of servers – the number of CPU cores and RAM of servers is automatically adapted to workloads based on CPU and memory pressure. We started with each ClickHouse Cloud service having a fixed number of 3 servers and eventually introduced horizontal scaling to an arbitrary number of servers.

In order to support these advanced scaling operations on top of shared storage with ReplicatedMergeTree, ClickHouse Cloud used a special modification called [zero-copy replication](https://clickhouse.com/docs/en/operations/storing-data#zero-copy) for adapting the ReplicatedMergeTree tables’ replication mechanism to work on top of shared object storage.

This adaptation uses almost the same original replication model, except that only one copy of data is stored in object storage. Hence the name zero-copy replication. Zero data is replicated between servers. Instead, we replicate just the metadata:![smt_04.png](https://clickhouse.com/uploads/smt_04_712af233a0.png)When ① server-1 receives an insert query, then ② the server writes the inserted data in the form of a part to object storage, and ③ writes metadata about the part (e.g., where the part is stored in object storage) to its local disk. ④ Via the replication log, the other servers are informed that a new part exits on server-1, although the actual data is stored in object storage. And ⑤ the other servers independently download (“fetch”) the metadata from server-1 to their own local filesystem. To ensure data is not deleted until all the replicas remove metadata pointing to the same object, a distributed mechanism of reference counting is used: After creating or receiving metadata, all three servers also update their own metadata set of parts info in ClickHouse Keeper.

For this, and for assigning operations like merges and mutations to specific servers, the zero-copy replication mechanism relies on creating exclusive [locks](https://zookeeper.apache.org/doc/r3.1.2/recipes.html#sc_recipes_Locks) in Keeper. Meaning that these operations can block each other and need to wait until the currently executed operation is finished.

Zero-copy replication does not sufficiently address the challenges with ReplicatedMergeTree on top of shared object storage:

- Metadata is still coupled with servers: metadata storage is not separated from compute. Zero-copy replication still requires a local disk on each server for storing the metadata about parts. Local disks are additional points of failure with reliability depending on the number of replicas, which is tied to compute overhead for high availability.
- Durability of zero-copy replication depends on guarantees of 3 components: object storage, Keeper, and local storage. This number of components adds complexity and overhead as this stack was built on top of existing components and not reworked as a cloud-native solution.
- This is still designed for a small number of servers: metadata is updated using the same replication model designed initially for shared-nothing cluster architectures with a small number of replica servers. A high number of servers creates too much contention on the replication log and creates a high overhead on locks and inter-server communication. Additionally, there is a lot of complexity in the code implementing the replication and cloning of data from one replica to another. And it is impossible to make atomic commits for all replicas as metadata is changed independently.

## SharedMergeTree for cloud-native data processing

We decided (and [planned](https://github.com/ClickHouse/ClickHouse/issues/44767) from the beginning) to implement a new table engine from scratch for ClickHouse Cloud called `SharedMergeTree` – designed to work on top of a shared storage. The `SharedMergeTree` is the cloud-native way for us to (1) make the MergeTree code more straightforward and maintainable, (2) to [support](https://clickhouse.com/changes) not only vertical but also horizontal auto-scaling of servers, and (3) to enable future features and improvements for our Cloud users, like higher consistency guarantees, better durability, point-in-time restores, time-travel through data, and more.

Here we describe briefly how the [SharedMergeTree](https://clickhouse.com/docs/en/guides/developer/shared-merge-tree) natively supports ClickHouse Cloud's automatic cluster scaling [model](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#automatic-cluster-scaling). As a reminder: the ClickHouse Cloud servers are compute units with access to the same shared data whose size and number can be automatically changed. For this mechanism, the SharedMergeTree completely separates the storage of data and metadata from the servers and uses interfaces to Keeper to read, write and modify the shared metadata from all servers. Each server has a local cache with subsets of the metadata and gets automatically informed about data changes by a subscription mechanism.

This diagram sketches how a new server is added to the cluster with the SharedMergeTree:![smt_05.png](https://clickhouse.com/uploads/smt_05_a45df09927.png)When server-3 is added to the cluster, then this new server ① subscribes for metadata changes in Keeper and fetches parts of the current metadata into its local cache. This doesn't require any locking mechanism; the new server basically just says, "Here I am. Please keep me up to date about all data changes". The newly added server-3 can participate in data processing almost instantly as it finds out what data exists and where in object storage by fetching only the necessary set of shared metadata from Keeper.

The following diagram shows how all servers get to know about newly inserted data:![smt_06.png](https://clickhouse.com/uploads/smt_06_dbf29bf0dc.png)When ① server-1 receives an insert query, then ② the server writes the query’s data in the form of a part to object storage. ③ Server-1 also stores information about the part in its local cache and in Keeper (e.g., which files belong to the part and where the blobs corresponding to files reside in object storage). After that, ④ ClickHouse acknowledges the insert to the sender of the query. The other servers (server-2, server-3) are ⑤ automatically notified about the new data existing in object storage via Keeper’s subscription mechanism and fetch metadata updates into their local caches.

Note that the insert query’s data is durable after step ④. Even if Server-1 crashes, or any or all of the other servers, the part is stored in highly available object storage, and the metadata is stored in Keeper (which has a highly available setup of at least 3 Keeper servers).

Removing a server from the cluster is a straightforward and fast operation too. For a graceful removal, the server just deregisters himself from Keeper in order to handle ongoing distributed queries properly without warning messages that a server is missing.

## Benefits for ClickHouse Cloud users

In ClickHouse Cloud, the SharedMergeTree table engine is a more efficient drop-in replacement for the ReplicatedMergeTree table engine. Bringing the following powerful benefits to ClickHouse Cloud users.

### Seamless cluster scaling

ClickHouse Cloud stores all data in virtually infinite, durable, and highly available shared object storage. The SharedMergeTree table engine adds shared metadata storage for all table components. It enables virtually limitless scaling of the servers operating on top of that storage. Servers are effectively stateless compute nodes, and we can almost instantly change their size and number.

#### Example

Suppose a ClickHouse Cloud user is currently using three nodes, as shown in this diagram:![smt_07.png](https://clickhouse.com/uploads/smt_07_9e7ecdd514.png)It is straightforward to (manually or automatically) double the amount of compute by either doubling the size of each node or (for example, when the maximum size per node is reached) by doubling the number of nodes from three to six:![smt_08.png](https://clickhouse.com/uploads/smt_08_a32f622149.png)This [doubles](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#sharedmergetree-in-action) the ingest throughput. For SELECT queries, increasing the number of nodes increases the level of parallel data processing for both the execution of concurrent queries and the [concurrent execution of a single query.](https://clickhouse.com/blog/clickhouse-release-23-03#parallel-replicas-for-utilizing-the-full-power-of-your-replicas-nikita-mikhailov) Note that increasing (or decreasing) the number of nodes in ClickHouse Cloud doesn’t require any physical resharding or rebalancing of the actual data. We can freely add or remove nodes with the same effect as manual sharding in shared-nothing clusters.

Changing the number of servers in a shared-nothing cluster requires more effort and time. If a cluster currently consists of three shards with two replicas per shard:![smt_09.png](https://clickhouse.com/uploads/smt_09_52c758d36c.png)Then doubling the number of shards requires resharding and rebalancing of the currently stored data:![smt_10.png](https://clickhouse.com/uploads/smt_10_43b84bbb96.png)

### Automatic stronger durability for insert queries

With the ReplicatedMergeTree, you can use the [insert_quorum](https://clickhouse.com/docs/en/operations/settings/settings#settings-insert_quorum) setting for ensuring data durability. You can configure that an insert query only returns to the sender when the query’s data (meta-data in case of zero-copy replication) is stored on a specific number of replicas. For the SharedMergeTree, insert_quorum is not needed. As shown above, when an insert query successfully returns to the sender, then the query’s data is stored in highly available object storage, and the metadata is stored centrally in Keeper (which has a highly available setup of at least 3 Keeper servers).

### More lightweight strong consistency for select queries

If your use case requires consistency guarantees that each server is delivering the same query result, then you can run the [SYNC REPLICA](https://clickhouse.com/docs/en/sql-reference/statements/system#sync-replica) system statement, which is a much more lightweight operation with the SharedMergeTree. Instead of syncing data (or metadata with zero-copy replication) between servers, each server just needs to fetch the current version of metadata from Keeper.

### Improved throughput and scalability of background merges and mutations

With the `SharedMergeTree`, there is no performance degradation with higher amounts of servers. The throughput of background merges scales with the number of servers as long as Keeper has enough resources. The same is true for [mutations](https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations) which are implemented via explicitly triggered and (by [default](https://clickhouse.com/docs/en/operations/settings/settings#mutations_sync)) asynchronously executed merges.

This has positive implications for other new features in ClickHouse, like [lightweight updates](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#introducing-lightweight-updates-powered-by-sharedmergetree), which get a performance boost from the SharedMergeTree. Similarly, engine-specific [data transformations](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views) (aggregations for [`AggregatingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/aggregatingmergetree), deduplication for [`ReplacingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree), etc.) benefit from the better merge throughput of the `SharedMergeTree`. These transformations are incrementally applied during background part merges. To ensure correct query results with potentially unmerged parts, users need to merge the unmerged data at query time by utilising the [FINAL](https://clickhouse.com/docs/en/sql-reference/statements/select/from#final-modifier) modifier or using explicit GROUP BY clauses with aggregations. In both cases, the execution speed of these queries benefits from better merge throughput. Because then the queries have less query-time data merge work to do.

## The new ClickHouse Cloud default table engine

The `SharedMergeTree` table engine is now generally available as the default table engine in ClickHouse Cloud for new Development tier services. Please reach out to us if you would like to create a new Production tier service with the `SharedMergeTree` table engine.

All table engines from the `MergeTree` family that are [supported](https://clickhouse.com/docs/en/whats-new/cloud-compatibility#database-and-table-engines) by ClickHouse Cloud are automatically based on the `SharedMergeTree`. For example, when you create a [`ReplacingMergeTree`](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree) table, ClickHouse Cloud will automatically create a `SharedReplacingMergeTree` table under the hood:

```sql
CREATE TABLE T (id UInt64, v String)
ENGINE = ReplacingMergeTree
ORDER BY (id);

SELECT engine
FROM system.tables
WHERE name = 'T';

┌─engine───────────────────┐
│ SharedReplacingMergeTree │
└──────────────────────────┘
```

Note that existing services will be migrated from `ReplicatedMergeTree` to the `SharedMergeTree` engine overtime. Please reach out to the ClickHouse Support team if you'd like to discuss this.

Also note that the current implementation of `SharedMergeTree` does not yet have support for more advanced capabilities present in `ReplicatedMergeTree`, such as [deduplication of async inserts](https://clickhouse.com/blog/asynchronous-data-inserts-in-clickhouse#inserts-are-idempotent) and encryption at rest, but this support is planned for future versions.

## `SharedMergeTree` in action

In this section, we are going to demonstrate the seamless ingest performance scaling capabilities of the SharedMergeTree. We will explore the performance scaling of SELECT queries in another blog.

### Ingest scenarios

For our example, we [load](https://gist.github.com/tom-clickhouse/d11e56ea677be787dac1198017a64141) the first six months of 2022 from the [WikiStat](https://clickhouse.com/docs/en/getting-started/example-datasets/wikistat) data set hosted in an S3 bucket into a [table](https://gist.github.com/tom-clickhouse/7c88c3a231c602b44382f2ffdf98148c) in ClickHouse Cloud. For this, ClickHouse needs to load ~26 billion records from ~4300 compressed files (one file represents one specific hour of one specific day). We are using the [s3Cluster table function](https://clickhouse.com/docs/en/sql-reference/table-functions/s3Cluster) in conjunction with the [parallel_distributed_insert_select](https://clickhouse.com/docs/en/operations/settings/settings#parallel_distributed_insert_select) setting to utilize all of the cluster’s compute nodes. We are using four configurations, each with a different number of nodes. Each node has 30 CPU cores and 120 GB RAM:

- 3 nodes
- 10 nodes
- 20 nodes
- 80 nodes

Note that the first two cluster configurations both use a dedicated 3-node ClickHouse Keeper service, with 3 CPU cores and 2 GB RAM per node. For the 20-node and 80-node configurations, we increased the size of Keeper to 6 CPU cores and 6 GB RAM per node. We monitored Keeper during the data loading runs to ensure that Keeper resources were not a bottleneck.

### Results

The more nodes we use in parallel, the faster (hopefully) the data is loaded, but also, the more parts get created per time unit. To achieve maximum performance of [SELECT queries](https://clickhouse.com/docs/en/sql-reference/statements/select), it is necessary to [minimize](https://clickhouse.com/blog/asynchronous-data-inserts-in-clickhouse#data-needs-to-be-batched-for-optimal-performance) the number of parts processed. For that, each ClickHouse MergeTree family table engine is, in the [background](https://clickhouse.com/docs/en/operations/server-configuration-parameters/settings#background_pool_size), continuously [merging](https://www.youtube.com/watch?v=QDAJTKZT8y4&t=428s) data parts into [larger](https://clickhouse.com/docs/en/operations/settings/merge-tree-settings#max-bytes-to-merge-at-max-space-in-pool) parts. The default healthy amount of parts (per table [partition](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/custom-partitioning-key)) of a table [is](https://clickhouse.com/docs/en/operations/settings/merge-tree-settings#parts-to-throw-insert) `3000` (and used to be `300`).

Therefore we are measuring for each data load run the time it took (from the start of each data load) for the engine to merge the parts created during ingest to a healthy number of less than 3000 parts. For that, we use a SQL [query](https://gist.github.com/tom-clickhouse/0c45c9306c9af393d8fdba48217005db) over a ClickHouse [system table](https://clickhouse.com/blog/clickhouse-debugging-issues-with-system-tables) to introspect (and visualize) the changes over time in the number of [active](https://clickhouse.com/blog/asynchronous-data-inserts-in-clickhouse#data-needs-to-be-batched-for-optimal-performance) parts.

Note that we optionally also include numbers for the data ingest runs with the ReplicatedMergeTree engine with zero-copy replication. As mentioned above, this engine was not designed to support a high number of replica servers, we want to highlight that here.

This chart shows the time (in seconds) it took to merge all parts to a healthy amount of less than 3000 parts:![smt_11.png](https://clickhouse.com/uploads/smt_11_45ee5ae47f.png)The SharedMergeTree supports seamless cluster scaling. We can see that the throughput of background merges scales quite linearly with the number of nodes in our test runs. When we approximately triple the number of nodes from 3 to 10, then we also triple the throughput. And when we again increase the number of nodes by a factor of 2 to 20 nodes and then by a factor of 4 to 80 nodes, then the throughput is approximately doubled and quadrupled, respectively, as well. As expected, the ReplicatedMergeTree with zero-copy replication doesn’t scale as well (or even decreases ingest performance with larger cluster sizes) as the SharedMergeTree with an increasing amount of replica nodes. Because its replication mechanics were never designed to work with a large number of replicas.

For completeness, this chart shows the time to merge until less than 300 parts remain:![smt_12.png](https://clickhouse.com/uploads/smt_12_ba6edc8307.png)

### Detailed results

#### 3 nodes

The following chart visualizes the number of active parts, the number of seconds it took to successfully load the data (see the `Ingest finished` marks), and the amount of seconds it took to merge the parts to less than 3000, and 300 active parts during the benchmark runs on the cluster with 3 replica nodes:![smt_13.png](https://clickhouse.com/uploads/smt_13_fae20cde02.png)We see that the performance of both tables engines is very similar here.

We can see that both engines execute approximately the same number of merge operations during the data loading:![smt_14.png](https://clickhouse.com/uploads/smt_14_1e5485ee98.png)

#### 10 nodes

On our cluster with 10 replica nodes, we can see a difference:![smt_15.png](https://clickhouse.com/uploads/smt_15_d618b9e3c8.png)The difference in ingest time is just 19 seconds. The amount of active parts, when the ingest is finished, is very different for both table engines, though. For the ReplicatedMergeTree with zero-copy replication, the amount is more than three times higher. And it takes twice as much time to merge the parts to an amount of less than 3000 and 300 with the ReplicatedMergeTree. Meaning that we get faster query performance sooner with the SharedMergeTree. The amount of ~4 thousand active parts when the ingest is finished is still ok to query. Whereas ~15 thousand is infeasible.

Both engines create the same amount of ~23 thousand initial parts with a size of ~10 MB containing ~ [1 million](https://clickhouse.com/docs/en/operations/settings/settings#min-insert-block-size-rows) rows for ingesting the ~26 billion rows from the WikiStat data subset:

```sql
WITH
    'default' AS db_name,
    'wikistat' AS table_name,
    (
        SELECT uuid
        FROM system.tables
        WHERE (database = db_name) AND (name = table_name)
    ) AS table_id
SELECT
    formatReadableQuantity(countIf(event_type = 'NewPart')) AS parts,
    formatReadableQuantity(avgIf(rows, event_type = 'NewPart')) AS rows_avg,
    formatReadableSize(avgIf(size_in_bytes, event_type = 'NewPart')) AS size_in_bytes_avg,
    formatReadableQuantity(sumIf(rows, event_type = 'NewPart')) AS rows_total
FROM clusterAllReplicas(default, system.part_log)
WHERE table_uuid = table_id;

┌─parts──────────┬─rows_avg─────┬─size_in_bytes_avg─┬─rows_total────┐
│ 23.70 thousand │ 1.11 million │ 9.86 MiB          │ 26.23 billion │
└────────────────┴──────────────┴───────────────────┴───────────────┘
```

And the creation of the ~23 thousand initial parts is evenly distributed over the 10 replica nodes:

```sql
WITH
    'default' AS db_name,
    'wikistat' AS table_name,
    (
        SELECT uuid
        FROM system.tables
        WHERE (database = db_name) AND (name = table_name)
    ) AS table_id
SELECT
    DENSE_RANK() OVER (ORDER BY hostName() ASC) AS node_id,
    formatReadableQuantity(countIf(event_type = 'NewPart')) AS parts,
    formatReadableQuantity(sumIf(rows, event_type = 'NewPart')) AS rows_total
FROM clusterAllReplicas(default, system.part_log)
WHERE table_uuid = table_id
GROUP BY hostName()
    WITH TOTALS
ORDER BY node_id ASC;

┌─node_id─┬─parts─────────┬─rows_total───┐
│       1 │ 2.44 thousand │ 2.69 billion │
│       2 │ 2.49 thousand │ 2.75 billion │
│       3 │ 2.34 thousand │ 2.59 billion │
│       4 │ 2.41 thousand │ 2.66 billion │
│       5 │ 2.30 thousand │ 2.55 billion │
│       6 │ 2.31 thousand │ 2.55 billion │
│       7 │ 2.42 thousand │ 2.68 billion │
│       8 │ 2.28 thousand │ 2.52 billion │
│       9 │ 2.30 thousand │ 2.54 billion │
│      10 │ 2.42 thousand │ 2.68 billion │
└─────────┴───────────────┴──────────────┘

Totals:
┌─node_id─┬─parts──────────┬─rows_total────┐
│       1 │ 23.71 thousand │ 26.23 billion │
└─────────┴────────────────┴───────────────┘
```

But the SharedMergeTree engine is merging the parts much more effectively during the data load run:![smt_16.png](https://clickhouse.com/uploads/smt_16_203c52f971.png)

#### 20 nodes

When 20 nodes are inserting the data in parallel, the ReplicatedMergeTree with zero-copy replication struggles to cope with the amount of newly created parts per time unit:![smt_17.png](https://clickhouse.com/uploads/smt_17_fd501062b2.png)Although the ReplicatedMergeTree finishes the data ingestion process before the SharedMergeTree, the amount of active parts continues to increase to ~10 thousand parts. Because the engine still has insert operations in a [queue](https://clickhouse.com/docs/en/operations/system-tables/replication_queue) that still need to be replicated across the 20 nodes. See the `Inserts in replication queue` line whose values we got with this [query](https://gist.github.com/tom-clickhouse/8fe01e952076dceb3be909da5d891edb). It took almost 45 minutes to process this queue. 20 nodes creating a high amount of newly created parts per time unit causes too much contention on the replication log and too high overhead on locks and inter-server communication. A way to mitigate this would be to throttle the amount of newly created parts by manually tuning some settings of the insert query. E.g., you can [reduce](https://clickhouse.com/docs/en/operations/settings/settings#settings-max-insert-threads) the number of parallel insert threads per node and [increase](https://clickhouse.com/docs/en/operations/settings/settings#min-insert-block-size-rows) the number of rows written into each new part. Note that the latter increases main memory usage.

Note that Keeper hardware was not overloaded during the test runs. The following screenshots show the CPU and memory usage of Keeper for both table engines:![smt_19.png](https://clickhouse.com/uploads/smt_19_16d0097257.png)

#### 80 nodes

On our cluster with 80 nodes, we load the data only into a SharedMergeTree table. We already showed above that the ReplicatedMergeTree with zero-copy replication is not designed for higher replica node numbers.

![smt_18.png](https://clickhouse.com/uploads/smt_18_d4aa0bc425.png)

The insertion of 26 billion rows finished in 67 seconds, which gives 388 million rows/sec.

## Introducing Lightweight Updates, boosted by `SharedMergeTree`

`SharedMergeTree` is a powerful building block that we see as a foundation of our cloud-native service. It allows us to build new capabilities and improve existing ones when it was not possible or too complex to implement before. Many features benefit from working on top of `SharedMergeTree` and make ClickHouse Cloud more performant, durable, and easy to use. One of these features is “Lightweight Updates” – an optimization that allows to instantly make results of ALTER UPDATE queries available while using fewer resources.

### Updates in traditional analytical databases are heavy operations

[ALTER TABLE … UPDATE](https://clickhouse.com/docs/en/sql-reference/statements/alter/update) queries in ClickHouse are implemented as [mutations](https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations). A mutation is a heavyweight operation that rewrites parts, either synchronously or asynchronously.

#### Synchronous mutations

![smt_20.png](https://clickhouse.com/uploads/smt_20_fc56fe2e17.png)

In our example scenario above, ClickHouse ① receives an insert query for an initially empty table, ② writes the query’s data into a new data part on storage, and ③ acknowledges the insert. Next, ClickHouse ④ receives an update query and executes that query by ⑤ mutating Part-1. The part is loaded into the main memory, the modifications are done, and the modified data is written to a new Part-2 on storage (Part-1 is deleted). Only when that part rewrite is finished, ⑥ the acknowledgment for the update query is returned to the sender of the update query. Additional update queries (which can also delete data) are executed in the same way. For larger parts, this is a very heavy operation.

#### Asynchronous mutations

By [default](https://clickhouse.com/docs/en/operations/settings/settings#mutations_sync), update queries are executed asynchronously in order to fuse several received updates into a single mutation for mitigating the performance impact of rewriting parts:

![smt_21.png](https://clickhouse.com/uploads/smt_21_f1b7f214ce.png)

When ClickHouse ① receives an update query, then the update is added to a [queue](https://clickhouse.com/docs/en/operations/system-tables/mutations) and executed asynchronously, and ② the update query immediately gets an acknowledgment for the update.

Note that SELECT queries to the table don’t see the update before it ⑤ **==gets materialized with a background mutation==**.

Also, note that ClickHouse can fuse queued updates into a single part rewrite operation. For this reason, it is a best practice to batch updates and send 100s of updates with a single query.

### Lightweight updates

The aforementioned explicit batching of update queries is no longer necessary, and from the user's perspective, modifications from single update queries, even when being materialized asynchronously, will occur instantly.

This diagram sketches the new lightweight and instant update [mechanism](https://clickhouse.com/docs/en/guides/developer/lightweght-update) in ClickHouse:

![smt_22.png](https://clickhouse.com/uploads/smt_22_e303a94b55.png)

When ClickHouse ① receives an update query, then the update is added to a queue and executed asynchronously. ② Additionally, the update query’s update expression is put into the main memory. The update expression is also stored in Keeper and distributed to other servers. When ③ ClickHouse receives a SELECT query before the update is materialized with a part rewrite, then ClickHouse will execute the SELECT query as usual - use the [primary index](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes) for reducing the set of rows that need to be streamed from the part into memory, and then the update expression from ② is applied to the streamed rows on the fly. That is why we call this mechanism `on [the] fly` mutations. When ④ another update query is received by ClickHouse, then ⑤ the query’s update (in this case a delete) expression is again kept in main memory, and ⑥ a succeeding SELECT query will be executed by applying both (②, and ⑤) update expressions on the fly to the rows streamed into memory. The on-the-fly update expressions are removed from memory when ⑦ all queued updates are materialized with the next background mutation. ⑧ Newly received updates and ⑩ SELECT queries are executed as described above.

This new mechanism can be enabled by simply setting the `apply_mutations_on_fly` setting to `1`.

#### Benefits

Users don’t need to wait for mutations to materialize. ClickHouse delivers updated results immediately, while using less resources. Furthermore, this makes updates easier to use for ClickHouse users, who can send updates without having to think about how to batch them.

#### Synergy with the SharedMergeTree

From the user's perspective, modifications from lightweight updates will occur instantly, but users will experience slightly reduced SELECT query performance until updates are materialized because the updates are executed at query time in memory on the streamed rows. As updates are materialized as part of merge operations in the background, the impact on query latency goes away. The SharedMergeTree table engine comes with [improved throughput and scalability of background merges and mutations](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#improved-throughput-and-scalability-of-background-merges-and-mutations), and as a result, mutations complete faster, and SELECT queries after lightweight updates return to full speed sooner.

#### What’s next

The mechanics of lightweight updates that we described above are just the first step. We are already planning additional phases of implementation to improve the performance of lightweight updates further and eliminate current [limitations](https://clickhouse.com/docs/en/guides/developer/lightweght-update).

## Summary

In this blog post, we have explored the mechanics of the new ClickHouse Cloud SharedMergeTree table engine. We explained why it was necessary to introduce a new table engine natively supporting the ClickHouse Cloud architecture, where vertically and horizontally scalable compute nodes are separated from the data stored in virtually limitless shared object storage. The SharedMergeTree enables seamless and virtually limitless scaling of the compute layer on top of the storage. The throughput of inserts and background merges can be easily scaled, which benefits other features in ClickHouse, such as lightweight updates and engine-specific data transformations. Additionally, the SharedMergeTree provides stronger durability for inserts and more lightweight strong consistency for select queries. Finally, it opens the door to new cloud-native capabilities and improvements. We demonstrated the engine’s efficiency with a benchmark and described a new feature boosted by the SharedMergeTree, called Lightweight Updates.

We are looking forward to seeing this new default table engine in action to boost the performance of your ClickHouse Cloud use cases.

[Get started](https://clickhouse.cloud/signUp?loc=blog-cta-footer&utm_source=clickhouse&utm_medium=web&utm_campaign=blog) with ClickHouse Cloud today and receive $300 in credits. At the end of your 30-day trial, continue with a pay-as-you-go plan, or [contact us](https://clickhouse.com/company/contact?loc=blog-cta-footer) to learn more about our volume-based discounts. Visit our [pricing page](https://clickhouse.com/pricing?loc=blog-cta-header) for details.

# Shared metadata storage
> https://github.com/ClickHouse/ClickHouse/issues/48620

## Use case

Currently, ClickHouse (CK) stores all metadata in local files. Each CK instance in a cluster has its own local metadata. These metadata represent one kind of system state of a CK instance. It is hard to dynamically remove or add CK instances without separating the metadata. To this end, we want to add an option to store metadata on a shared storage (e.g. keeper or distributed KV stores).

## Describe the solution you'd like

For compatibility purposes, each instance stores its metadata in a different namespace in the shared store. When recreating an instance you only need to select the corresponding namespace in the shared store without using original local disk storage. For example:

```
instance-1 → /clickhouse/instance-1/{databases,tables,acl,...}
instance-2 → /clickhouse/instance-2/{databases,tables,acl,...}
```

The logic for manipulating metadata on shared storage is roughly the same as on local disk, except that it calls the remote storage interface and uses a different serialization method. In addition, we need to consider how to upload metadata from the local storage to the shared storage when CK nodes first boot with the shared storage option. We plan to support the following types of metadata:

### Database DDL

Database DDL is stored as pure sql txt files in metadata/. When CK nodes first boot on the shared storage, the original code for metadata initialization is used to load DDL from txt files in metadata/, then upload them to the shared storage. When these CK nodes boot again, the original code is skipped and the SQL String (i.e. Database metadata) is loaded directly from the shared storage.

### Table DDL

Similar to Database DDL, Table DDL is stored as pure sql txt files in `metadata/$DB_UUID/`. Due to the asynchronous operation of the drop table, there may be some dropped table sql files under metadata_dropped/ . When CK nodes first boot on the shared storage, the original code for loading Table metadata is used to load DDL from txt files in metadata/$DB_UUID/and metadata_dropped/ , then upload them to the shared storage. When these CK nodes reboot, the original code is skipped and the SQL String is loaded directly from the shared storage.

### MergeTreePart

MergeTreePart-related metadata includes uuid, columns, checksums, partition, ttl_infos, rows_count and so on, which used to be loaded from disk when the node initially starts. After we add the option of storing metadata in the shared storage, the processing of MergeTreePart-related metadata is as follows:

- When CK nodes first boot on the shared storage, the original code for metadata initialization is used to load MergeTreePart from files in data part directory in disk, then upload them to the shared storage.

- When these CK nodes boot again, the original code is skipped and we directly load MergeTreePart-related metadata from the shared storage, then builds the MergeTreePart.

- Every time we remove, add and modify any parts, we remove metadata of these parts in the shared storage (add metadata of new parts to the shared storage if generating new parts).

### Config

The main server configuration files are stored in `config.xml`, `users.xml`, `{config, users}.d/*.xml.` When CK nodes first boot on the shared storage, the original code for Config metadata is used to load configs from these xml files, then upload them to the shared storage. When rebooting, the original code is skipped and the config is loaded directly from the shared storage as an in-memory object. Since we stored the config metadata on the shared storage, the original way of changing configs by altering xml files is no longer applicable. Hence, we have implemented new sql statements to add/modify/delete config parameters on the shared storage.

### Dict

Dictionaries can be created with xml files or DDL queries. The process of dictionaries DDL queries on the shared storage is the same as table DDL. For dictionaries created with xml files, the configuration files on the local disk are uploaded to the shared storage at first startup. At subsequent startup, the configuration files of the dictionary will not be obtained from the local disk but from the shared storage. The update and creation of dictionaries with xml files are also performed directly in the shared storage and then synchronized to the nodes. The process of dictionary queries has not changed.

### UDF

There are two types of user defined functions, namely executable user defined functions and sql user defined functions.
The xml configuration files of external executable user-defined functions and the DDL queries of sql user defined functions are migrated to the shared storage at first startup. At subsequent startup, these xml configuration files and DDL queries are fetched from the shared storage instead of local disks. In addition, the executable files for executable user defined functions are still kept locally on the node instead of the shared storage. The update and creation of executable user defined functions are also performed directly in the shared storage and then synchronized to the nodes. The process of user defined functions queries has not changed.

### ACL

ACL-related metadata mainly includes two types of permission management objects: (1) Access Entity statically defined in the configuration file with tag entries and (2) Access Entity dynamically generated in SQL-driven way with pure sql text. When CK nodes first boot on the shared storage, the original code for ACL metadata is used to parse access entities from configuration files and sql text files, then upload them to the shared storage. It is worth noting that with shared storage configured, the access entities persisted on local disk are migrated to shared storage on the first startup. When rebooting, the original code is skipped and the access entity is loaded directly from the shared storage as an in-memory objects instead of from local disk.

## About Shared Storage

In our current implementation, we choose FoundationDB as the shared storage because of its good performance and scalability. To avoid the bottleneck of ZooKeeper in large-scale CK deployment, we have also developed FDBKeeper as an alternative implementation of IKeeper. This can avoid deploying both ZooKeeper and FoundationDB.