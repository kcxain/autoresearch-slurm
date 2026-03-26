# slurm-ai-workflow

让 Claude Code 在 SLURM 集群上自主调试 GPU 代码的工作流与 Skill 套件。

**适用场景**：Claude Code 运行在登录节点（有外网），GPU 在计算节点（无外网，通过 SLURM 调度）。

## 包含内容

```
.claude/
├── SKILL.md                  # Agent 工作流指南（Claude 自动读取）
└── commands/
    ├── slurm-run.md          # /slurm-run：提交作业 + 等待 + 读日志 + 自动修复
    └── slurm-test.md         # /slurm-test：srun 快速阻塞测试
slurm-claude-workflow.md      # 详细说明文档
```

## 快速上手

1. 在登录节点的项目目录启动 Claude Code：
   ```bash
   claude
   ```

2. 让 Claude 测试 GPU 环境：
   ```
   /slurm-test "import torch; print(torch.cuda.is_available())"
   ```

3. 让 Claude 提交训练作业并自动迭代：
   ```
   /slurm-run scripts/run.sh
   ```

Claude 会自动提交作业、等待完成、读取日志，遇到错误时修复代码并重新提交，直到成功。

## 要求

- Claude Code 安装在登录节点
- 项目目录在计算节点可访问的共享文件系统上（NFS / Lustre 等）
- `logs/` 目录存在，job script 将输出写入 `logs/slurm-%j.out`

## Agent 行为说明

Claude 读取 `.claude/SKILL.md` 了解完整的执行策略，包括：

- 何时用 `srun`（阻塞）vs `sbatch`（异步）
- 如何轮询作业状态、读取日志
- 各类错误的处理方式（OOM / Traceback / 超时）
- 自动重试上限（5 次）与资源参数修改限制
