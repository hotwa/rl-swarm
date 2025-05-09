#!/bin/bash

# —— 代理设置 —— 
# export HTTP_PROXY='http://192.168.103.58:7897'
# export HTTPS_PROXY='http://192.168.103.58:7897'
# # 确保对本地 127.0.0.1/localhost 的请求不走代理
# export NO_PROXY='localhost,127.0.0.1,::1'

MAX_RESTARTS=10000000
restart_count=0
LOGFILE="$HOME/rl-swarm/swarm.log"

# 激活虚拟环境
source ~/rl_env310/bin/activate
# 内存优化参数
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
export PYTORCH_MPS_ALLOCATOR_RESERVED_SIZE=4096
export PYTORCH_MPS_LOW_WATERMARK_RATIO=0.5
export PYTORCH_MPS_ALLOCATOR_FRAG_THRESHOLD=0.5
export PYTHONMALLOC=malloc
export MALLOC_TRIM_THRESHOLD_=65536
export BATCH_SIZE=4
export GRADIENT_ACCUMULATION_STEPS=4

cd ~/rl-swarm

while [ $restart_count -lt $MAX_RESTARTS ]; do
  restart_count=$((restart_count+1))
  echo "[$(date)] 启动 RL-Swarm (第 ${restart_count}/${MAX_RESTARTS} 次)…"
  # 清空旧日志
  : > "$LOGFILE"

  # 启动训练脚本，固定输入，后台运行并重定向到日志
  printf "B\n32\n" | ./run_rl_swarm.sh >> "$LOGFILE" 2>&1 &
  TRAIN_PID=$!

  # 监控线程：每 10s 检查日志中的关键错误
  (
    while kill -0 "$TRAIN_PID" &>/dev/null; do
      if grep -q "UnboundLocalError: local variable 'current_batch' referenced before assignment" "$LOGFILE" \
         || grep -q "404 Client Error" "$LOGFILE"; then
        echo "[$(date)] 检测到关键错误（UnboundLocalError 或 HTTP 404），杀掉训练进程 $TRAIN_PID"
        kill "$TRAIN_PID"
        break
      fi
      sleep 10
    done
  ) &

  # 等待主训练进程退出
  wait "$TRAIN_PID"
  exit_status=$?
  echo "[$(date)] 训练脚本 exit_code=$exit_status"

  # 如果正常结束或手动中断，直接退出循环
  if [ $exit_status -eq 0 ] || [ $exit_status -eq 130 ]; then
    echo "[$(date)] 训练脚本正常退出或手动中断，停止自动重启。"
    break
  fi

  # 否则重启前清理
  echo "[$(date)] 脚本异常退出（code=$exit_status），准备重启…"
  python - <<EOF
import gc; gc.collect()
EOF
  echo "[$(date)] 重启前休息 10 秒…"
  sleep 10
done

if [ $restart_count -ge $MAX_RESTARTS ]; then
  echo "[$(date)] 已达到最大重试次数 (${MAX_RESTARTS})，停止自动重启"
fi
