我当时把 编译和 UT 执行分开：先用 SBT 编译生产代码和选中的测试源码，再直接用 ScalaTest Runner 跑 11 个相关 case，没有跑全量  sbt test 。

以下命令均在  gluten41  容器的 Bash 中执行。

1. 编译

当时验证的是 PR 工作树： /root/delta-worktrees/pr-metadata-overhead-20261019 ，使用 JDK 21、Spark 4.1。

 repo=/root/delta-worktrees/pr-metadata-overhead-20261019
 cd "$repo"

 export JAVA_HOME=/usr/lib/jvm/msopenjdk-21
 export PATH="$JAVA_HOME/bin:$PATH"

 JDK_JAVA_OPTIONS=-Xmx6g build/sbt \
   -DsparkVersion=4.1 \
   -Dsbt.log.noformat=true \
   -Dsbt.supershell=false \
   "set storage / Test / unmanagedSources := Seq(file(\"$repo/storage/src/test/scala/io/delta/storage/AzureLogStoreWildfireSuite.scala\"))" \
   "set kernelDefaults / Test / unmanagedSources := Seq(file(\"$repo/kernel/kernel-defaults/src/test/scala/io/delta/kernel/defaults/internal/logstore/LogStoreProviderSuite.scala\"))" \
   "set spark / Test / unmanagedSources := Seq(file(\"$repo/spark/src/test/scala/com/microsoft/spark/telemetry/delta/DeltaSynapseEventSuite.scala\"))" \
   'storage / Test / compile' \
   'kernelDefaults / Test / compile' \
   'spark / Test / compile' \
   'show storage / Compile / packageBin' \
   'show spark / Compile / packageBin' \
   'show storage / Test / fullClasspath' \
   'show kernelDefaults / Test / fullClasspath' \
   'show spark / Test / fullClasspath'

 unmanagedSources  只限制测试源码范围；相应的生产代码及必要依赖仍会编译。最后三个  fullClasspath  用于取得运行 UT 的完整 classpath。

2. 跑测试

我实际使用的进程命令是：

 unshare -n /usr/lib/jvm/msopenjdk-21/bin/java @临时参数文件

 unshare -n  禁用测试进程的网络访问；参数文件中包含  -Xmx4g 、所需的  --add-opens 、完整 classpath 和  org.scalatest.tools.Runner  参数。使用  @参数文件  是为了避免超长 classpath 触发命令行长度限制。

┌────────────────────────────────────────────────────────────────────┬───────────────┬──────────┐
│ Suite                                                              │ 过滤条件      │ 执行数量 │
├────────────────────────────────────────────────────────────────────┼───────────────┼──────────┤
│  io.delta.storage.AzureLogStoreWildfireSuite                       │ 整个 suite    │ 8        │
├────────────────────────────────────────────────────────────────────┼───────────────┼──────────┤
│  io.delta.kernel.defaults.internal.logstore.LogStoreProviderSuite  │  -z listFrom  │ 2        │
├────────────────────────────────────────────────────────────────────┼───────────────┼──────────┤
│  com.microsoft.spark.telemetry.delta.DeltaSynapseEventSuite        │ 整个 suite    │ 1        │
└────────────────────────────────────────────────────────────────────┴───────────────┴──────────┘

要原样复用当时保存的完整参数，可以在容器中执行：

 python3 - <<'PY'
 import json
 import subprocess
 import tempfile
 import time
 from pathlib import Path

 root = Path(
     "/root/chang/.copilot/session-state/"
     "cd962c48-daaa-42d2-a2ec-29adb188a03a/files/"
     "delta-token-prs-20261019"
 )
 deadline = time.monotonic() + 600

 for name in ("delta-storage", "delta-kernel", "delta-telemetry"):
     request = json.loads(
         (root / f"{name}-publish-ut-request.json").read_text(encoding="utf-8")
     )
     command = request["command"]
     with tempfile.NamedTemporaryFile(
         mode="w", encoding="utf-8", newline="\n", delete=False
     ) as args:
         for argument in command[1:]:
             escaped = argument.replace("\\", "\\\\").replace('"', '\\"')
             args.write('"' + escaped + '"\n')
     try:
         remaining = deadline - time.monotonic()
         if remaining <= 0:
             raise TimeoutError("Aggregate UT execution exceeded 600 seconds")
         subprocess.run(
             ["unshare", "-n", command[0], "@" + args.name],
             check=True,
             timeout=remaining,
         )
     finally:
         Path(args.name).unlink()
 PY

这是本次 PR 验证时保存的 classpath 和参数，不是通用的其他版本参数。当时编译约 3 分 43 秒；发布前最后一次 Delta UT 共 11 项全部通过，执行约 11.8 秒，不含编译。