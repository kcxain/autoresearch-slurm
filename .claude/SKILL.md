# SLURM Workflow Skill

你正在一个 **SLURM 集群的登录节点**上运行。计算节点有 GPU 但无外网，只能通过 SLURM 调度访问。本文件描述你在此环境中应遵循的完整工作流。

---

## 环境约定

| 项目 | 说明 |
|------|------|
| 当前节点 | 登录节点（有外网，无 GPU） |
| GPU 访问 | 通过 `srun`（阻塞）或 `sbatch`（异步）提交到计算节点 |
| 文件系统 | 共享 FS，登录节点和计算节点看到同一份文件 |
| 日志路径约定 | `logs/slurm-<JOB_ID>.out`（stdout + stderr 合并） |

---

## 决策树：选择执行方式

```
需要运行 GPU 代码？
├─ 是短时间验证（< 10 分钟，单函数/环境检查）
│   └─ 用 srun（阻塞）→ 见「快速测试」
└─ 是完整训练/长时间任务
    └─ 用 sbatch（异步）→ 见「异步作业循环」
```

---

## 快速测试（srun）

```bash
srun --gres=gpu:1 --mem=16G --time=00:10:00 python <file.py>
# 或内联命令
srun --gres=gpu:1 python -c "<python_code>"
```

- 输出直接打印到终端，**无需轮询**
- 超时上限设 10 分钟；若任务更长，改用 sbatch
- 队列 pending 超过 5 分钟时，告知用户并询问是否继续等待

---

## 异步作业循环（sbatch）

### Step 1：提交

```bash
JOB_ID=$(sbatch <script.sh> [args...] | awk '{print $NF}')
echo "Submitted: $JOB_ID"
```

### Step 2：等待完成

每 30 秒轮询一次，直到作业离队：

```bash
while squeue -j $JOB_ID -h 2>/dev/null | grep -q .; do
  STATUS=$(squeue -j $JOB_ID -h | awk '{print $5}')
  echo "Job $JOB_ID: $STATUS"
  sleep 30
done
```

等待上限：2 小时。超时后停止并报告，等待用户决定。

### Step 3：读取日志

```bash
LOG="logs/slurm-${JOB_ID}.out"
cat $LOG
```

若日志文件不存在：先用 `sacct -j $JOB_ID --format=State,ExitCode` 确认作业状态。

### Step 4：判断结果

| 日志信号 | 判断 | 下一步 |
|----------|------|--------|
| 末尾含 `JOB COMPLETED SUCCESSFULLY` 或 exit 0 | 成功 | 报告结果，提取关键指标 |
| Python `Traceback` | 代码错误 | 定位源文件，修复，重新提交 |
| `CUDA out of memory` | 显存不足 | 减小 batch size（修改配置），重新提交 |
| `DUE TO TIME LIMIT` | 超时 | **不自动修改**，告知用户增大 `--time` |
| `slurmstepd: error` / `Killed` | OOM kill | **不自动修改**，告知用户增大 `--mem` |
| 日志为空 | 刚启动 | 等待 10 秒后重新读取 |

### Step 5：修复并重试

1. 修改代码前，用 `git diff` 确认当前状态
2. 修改后简要告知用户改了什么
3. 回到 Step 1 重新提交
4. **最多自动重试 5 次**；超过后总结失败历史，等待用户指令

---

## 禁止行为

- **不要**在未经用户确认的情况下修改 `#SBATCH` 资源参数（`--time`、`--mem`、`--gres`）
- **不要**在计算节点上尝试运行 Claude 或访问外部 API（无外网）
- **不要**在日志读取失败后反复 `cat` 同一文件——先用 `sacct` 确认作业状态

---

## Slash Commands

| 命令 | 场景 |
|------|------|
| `/slurm-run [script] [args]` | 完整的 sbatch 提交 + 等待 + 日志 + 自动修复循环 |
| `/slurm-test [file_or_cmd]` | srun 快速阻塞测试 |

---

## 典型完整流程

```
用户："让 train.py 在 A100 上跑通"
  │
  ├─ /slurm-test "import torch; print(torch.cuda.is_available())"
  │     确认 GPU 环境正常
  │
  ├─ /slurm-run scripts/run.sh --config configs/a100.yaml
  │     提交 → 等待 → 读日志
  │     ├─ 失败（OOM）→ 修改 batch_size → 重新提交
  │     ├─ 失败（Traceback）→ 修复代码 → 重新提交
  │     └─ 成功 → 报告 loss/accuracy，git commit
  │
  └─ 完成
```
