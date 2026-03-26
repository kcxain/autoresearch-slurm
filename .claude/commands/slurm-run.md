提交一个 sbatch 作业，等待完成，读取日志，如果失败则自动修复代码并重新提交，直到成功为止。

## 用法

```
/slurm-run [job_script] [额外参数]
```

- `job_script`：要提交的 SLURM 脚本路径，默认为 `scripts/run.sh`
- 额外参数会透传给 sbatch 脚本（通过 `"$@"` 机制）

## 执行步骤

1. **提交作业**
   ```bash
   JOB_ID=$(sbatch $ARGUMENTS | awk '{print $NF}')
   echo "Submitted job $JOB_ID"
   ```

2. **等待完成**：每隔 30 秒轮询一次，直到作业离队：
   ```bash
   while squeue -j $JOB_ID -h 2>/dev/null | grep -q .; do
     echo "Job $JOB_ID still running... ($(squeue -j $JOB_ID -h | awk '{print $5}'))"
     sleep 30
   done
   ```
   若等待超过 2 小时仍未结束，停止轮询并报告超时。

3. **读取日志**
   ```bash
   LOG_FILE="logs/slurm-${JOB_ID}.out"
   cat $LOG_FILE
   ```
   若日志文件不存在，用 `sacct -j $JOB_ID` 检查作业是否曾经启动。

4. **判断结果**

   - 日志末尾含 `JOB COMPLETED SUCCESSFULLY` 或退出码为 0 → 报告成功，输出关键指标（loss、accuracy 等）
   - 发现错误 → 进入修复循环（步骤 5）

5. **修复并重新提交**

   根据日志中的错误信息定位问题：
   - `CUDA out of memory` → 减小 batch size（修改配置文件或脚本参数）
   - Python Traceback → 读取对应源文件，修复 bug
   - `DUE TO TIME LIMIT` → 提示用户增大 `--time`，不自动修改
   - `slurmstepd: error` / `Killed` → 检查内存需求，提示用户调整 `--mem`

   修复代码后回到步骤 1 重新提交。每轮修复后说明做了什么改动。

   最多自动重试 **5 次**；超过后停止并总结失败原因，等待用户指令。

## 注意事项

- 不要修改 `#SBATCH` 资源参数（`--time`、`--mem`、`--gres`），这些属于用户配置；若确实需要调整，先说明原因并征得同意
- 每次重新提交前先用 `git diff` 确认修改内容，并简要告知用户
