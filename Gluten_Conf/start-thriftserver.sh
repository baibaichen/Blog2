#!/bin/bash


# source gluten.env

export SPARK_LOCAL_DIRS=${LOCAL_DIR}/spark

if [ -z "${SPARK_HOME}" ]; then
  echo "Error: SPARK_HOME environment variable is not set"
  exit 1
fi

if [ ! -d "${SPARK_HOME}" ]; then
  echo "Error: SPARK_HOME directory does not exist: ${SPARK_HOME}"
  exit 1
fi

cd "${SPARK_HOME}" || {
  echo "Error: Failed to change directory to ${SPARK_HOME}"
  exit 1
}

./sbin/start-thriftserver.sh \
--master local[*] \
--name MergeTreeTest \
--files ${SPARK_HOME}/conf/log4j2.properties \
--deploy-mode client \
--driver-memory 32g \
--conf spark.driver.memoryOverhead=4G \
--conf spark.driver.extraClassPath=${GLUTEN_JARS} \
--conf spark.executor.extraClassPath=${GLUTEN_JARS} \
--conf spark.eventLog.enabled=true \
--conf spark.eventLog.dir=file://${SPARK_HOME}/spark_event_logs \
--conf spark.eventLog.compress=true \
--conf spark.eventLog.compression.codec=zstd \
--conf spark.gluten.sql.columnar.libpath=${LIBCH} \
--conf spark.executorEnv.LD_PRELOAD=${LIBCH} \
--conf spark.serializer=org.apache.spark.serializer.JavaSerializer \
--conf spark.default.parallelism=16 \
--conf spark.sql.shuffle.partitions=16 \
--conf spark.sql.files.minPartitionNum=1 \
--conf spark.sql.files.maxPartitionBytes=1G \
--conf spark.sql.adaptive.coalescePartitions.enabled=true \
--conf spark.sql.adaptive.advisoryPartitionSizeInBytes=64MB \
--conf spark.locality.wait=0 \
--conf spark.locality.wait.node=0 \
--conf spark.locality.wait.process=0 \
--conf spark.sql.columnVector.offheap.enabled=true \
--conf spark.memory.offHeap.enabled=true \
--conf spark.memory.offHeap.size=45g \
--conf spark.sql.autoBroadcastJoinThreshold=20MB \
--conf spark.sql.adaptive.autoBroadcastJoinThreshold=-1 \
--conf spark.memory.fraction=0.6 \
--conf spark.memory.storageFraction=0.3 \
--conf spark.eventLog.enabled=true \
--conf spark.eventLog.compress=true \
--conf spark.eventLog.compression.codec=snappy \
--conf spark.sql.adaptive.enabled=true \
--conf spark.plugins=org.apache.gluten.GlutenPlugin \
--conf spark.gluten.sql.columnar.columnartorow=true \
--conf spark.gluten.sql.columnar.loadnative=true \
--conf spark.gluten.sql.columnar.iterator=true \
--conf spark.gluten.sql.columnar.loadarrow=false \
--conf spark.gluten.sql.columnar.backend.lib=ch \
--conf spark.gluten.sql.columnar.hashagg.enablefinal=true \
--conf spark.gluten.sql.enable.native.validation=false \
--conf spark.gluten.sql.columnar.backend.ch.use.v2=false \
--conf spark.gluten.sql.columnar.separate.scan.rdd.for.ch=false \
--conf spark.gluten.sql.columnar.forceshuffledhashjoin=true \
--conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.execution.datasources.v2.clickhouse.ClickHouseSparkCatalog \
--conf spark.databricks.delta.maxSnapshotLineageLength=20 \
--conf spark.databricks.delta.snapshotPartitions=2 \
--conf spark.databricks.delta.properties.defaults.checkpointInterval=5 \
--conf spark.databricks.delta.stalenessLimit=7200000 \
--conf spark.gluten.sql.columnar.backend.ch.worker.id=1 \
--conf spark.gluten.sql.columnar.coalesce.batches=false \
--conf spark.gluten.sql.columnar.sort=true \
--conf spark.gluten.sql.columnar.backend.ch.runtime_config.logger.level=error \
--conf spark.shuffle.manager=org.apache.spark.shuffle.sort.ColumnarShuffleManager \
--conf spark.io.compression.codec=LZ4 \
--conf spark.gluten.sql.columnar.shuffle.customizedCompression.codec=LZ4 \
--conf spark.gluten.sql.columnar.backend.ch.customized.shuffle.codec.enable=true \
--conf spark.gluten.sql.columnar.backend.ch.customized.buffer.size=4096 \
--conf spark.gluten.sql.columnar.backend.ch.files.per.partition.threshold=2 \
--conf spark.gluten.sql.columnar.backend.ch.runtime_config.enable_nullable=true \
--conf spark.gluten.sql.columnar.backend.ch.runtime_config.local_engine.settings.metrics_perf_events_enabled=false \
--conf spark.gluten.sql.columnar.maxBatchSize=32768 \
--conf spark.gluten.sql.columnar.backend.ch.shuffle.hash.algorithm=sparkMurmurHash3_32 \
--conf spark.sql.decimalOperations.allowPrecisionLoss=false \
--conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension \
--conf spark.hadoop.fs.s3a.access.key=minioadmin \
--conf spark.hadoop.fs.s3a.secret.key=minioadmin \
--conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem \
--conf spark.hadoop.fs.s3a.endpoint=http://127.0.0.1:9000/ \
--conf spark.hadoop.fs.s3a.path.style.access=true \
--conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
--conf spark.broadcast.autoClean.enabled=true \
--conf spark.gluten.sql.columnar.backend.ch.runtime_settings.min_insert_block_size_bytes=524288000 \
--conf spark.gluten.sql.columnar.backend.ch.runtime_settings.min_insert_block_size_rows=100000000 \
--conf spark.sql.optimizer.runtime.bloomFilter.enabled=true \
--conf spark.sql.optimizer.runtime.bloomFilter.creationSideThreshold=100MB \
--conf spark.sql.optimizer.runtime.bloomFilter.applicationSideScanSizeThreshold=1KB \
--conf spark.gluten.sql.columnar.backend.ch.runtime_config.path=${LOCAL_DIR}/gluten \
--conf spark.gluten.sql.columnar.backend.ch.runtime_config.tmp_path=${LOCAL_DIR}/tmp_path \
--conf spark.gluten.sql.columnar.backend.ch.runtime_settings.enabled_driver_filter_mergetree_index=false \
--conf spark.sql.readSideCharPadding=false \
--conf spark.gluten.sql.columnar.backend.ch.runtime_settings.input_format_parquet_use_native_reader_with_filter_push_down=true