用 `srun` 在 GPU 计算节点上快速执行一段代码或脚本，立即返回输出。适合单步验证、环境检查、快速调试。

## 用法

```
/slurm-test [command_or_file] [--gpu N] [--mem MG]
```

- `command_or_file`：要运行的 Python 文件或 shell 命令
- `--gpu N`：申请 N 块 GPU，默认 1
- `--mem MG`：内存需求，默认 `16G`

若未指定，Claude 根据当前任务上下文推断最合适的测试命令。

## 执行步骤

1. **构造 srun 命令**

   ```bash
   srun --gres=gpu:$N --mem=$MEM --time=00:10:00 $COMMAND
   ```

   - 对于 Python 文件：`python $FILE`
   - 对于裸命令（如 `import torch; print(torch.cuda.is_available())`）：`python -c "$CMD"`
   - 时间上限固定为 10 分钟（快速测试不应更长）

2. **运行并等待**：`srun` 阻塞，输出直接打印到终端，无需轮询。

3. **分析结果**

   - 成功 → 报告关键输出（如 GPU 信息、shape、loss 等）
   - 失败 → 定位错误，询问是否立即修复并重新测试

## 典型使用场景

```bash
# 检查 GPU 可用性和环境
/slurm-test "import torch; print(torch.cuda.is_available(), torch.version.cuda)"

# 测试数据加载
/slurm-test scripts/test_dataloader.py

# 测试单次前向传播
/slurm-test scripts/test_forward.py --batch-size 2
```

## 注意事项

- `srun` 是**同步阻塞**的，Claude 在命令返回前无法做其他事；若预期超过 10 分钟，改用 `/slurm-run`
- 若集群队列繁忙导致长时间 pending，Claude 会告知当前状态并提供取消选项
