# SLURM 集群 + Claude Code 开发工作流

适用场景：Claude Code 运行在登录节点（有外网），GPU 代码运行在计算节点（无外网，通过 SLURM 调度）。

## 架构

```
Login Node                        Compute Node (GPU)
+------------------+   sbatch     +------------------+
| Claude Code      | -----------> | SLURM job        |
| (有外网，可调API) |              | (无外网)          |
|                  | <----------- |                  |
|  读取日志、修改代码|   共享文件系统 | logs/slurm-*.out |
+------------------+              +------------------+
```

Claude 永远在登录节点运行，通过 `srun`/`sbatch` 把代码推到 GPU 节点执行，再读取日志输出来迭代。

## 前置条件

- Claude Code 安装在登录节点
- 项目目录在共享文件系统（计算节点可访问）
- `logs/` 目录已存在（或在 job script 中创建）

## Claude 的 SLURM 调试循环

### 快速测试：`srun`（阻塞）

适合验证单个函数、环境检查、短时间测试：

```bash
srun --gres=gpu:1 --mem=16G python test_forward_pass.py
```

`srun` 会阻塞直到完成，输出直接打印到终端——Claude 无需轮询，立即得到结果。

### 完整训练：`sbatch` 异步循环

Claude 提交 `sbatch` 后需要主动轮询，不能直接得到输出：

```bash
# 1. 提交，捕获 Job ID
JOB_ID=$(sbatch scripts/run.sh | awk '{print $NF}')

# 2. 轮询直到作业离队（结束或失败）
while squeue -j $JOB_ID -h | grep -q .; do sleep 30; done

# 3. 读取日志
cat logs/slurm-${JOB_ID}.out
```

Claude 读取日志后分析错误、修改代码、再次提交，直到成功。

### 日志分析要点

Claude 读日志时应关注：

| 信号 | 含义 |
|------|------|
| `CUDA out of memory` | 减小 batch size 或换更大 GPU |
| `slurmstepd: error` | SLURM 级别错误（超时、OOM kill） |
| `Traceback` | Python 异常，定位到具体行 |
| 日志文件不存在 | 作业还未开始运行（pending 状态） |
| 日志文件为空 | 作业刚启动，等待几秒再读 |

查看作业是否还在队列中：

```bash
squeue -j $JOB_ID -h       # 无输出 = 已结束
squeue -u $USER             # 查看所有作业
sacct -j $JOB_ID --format=State,ExitCode  # 查看退出码
```

## 让 Claude 更好地使用 SLURM 的建议

### Job Script 设计

在 job script 末尾加明确的成功/失败标记，让 Claude 能可靠地判断结果：

```bash
#!/bin/bash
#SBATCH --output=logs/slurm-%j.out
#SBATCH --error=logs/slurm-%j.out   # 合并 stdout/stderr，只需读一个文件

set -e   # 出错即退出，避免静默失败

python train.py "$@"

echo "=== JOB COMPLETED SUCCESSFULLY ==="
```

### 日志路径约定

统一使用 `logs/slurm-${SLURM_JOB_ID}.out`（SLURM 默认 `%j` 展开为 Job ID），这样 Claude 能从提交输出中直接推算日志路径，无需额外查询。

## 使用 Skills 自动化

项目提供以下 Claude Code slash commands（见 `.claude/commands/`）：

| 命令 | 用途 |
|------|------|
| `/slurm-run` | 提交 sbatch 作业、等待完成、读取日志、自动迭代修复 |
| `/slurm-test` | 用 srun 快速测试一段代码或脚本 |

## 典型工作流

```
1. 告诉 Claude 要调试的目标（"让 train.py 跑通"）
       ↓
2. Claude 用 srun 快速检查环境和单步逻辑
       ↓
3. Claude 用 sbatch 提交完整作业
       ↓
4. Claude 轮询 squeue，等待结束后读取日志
       ↓
5. Claude 分析错误、修改代码
       ↓
6. 重复 3-5 直到成功
       ↓
7. Claude commit 结果
```
