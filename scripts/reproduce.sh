#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$ROOT_DIR/service/CMakeLists.txt" ]; then
    echo "Не найден service/CMakeLists.txt. Запусти скрипт из репозитория с каталогом service/." >&2
    exit 1
fi

RUN_NAME="run-$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$ROOT_DIR/results/$RUN_NAME"
mkdir -p "$RESULT_DIR"

{
    echo "Дата: $(date)"
    echo
    echo "Операционная система:"
    cat /etc/os-release
    echo
    echo "Ядро:"
    uname -a
    echo
    echo "Процессор:"
    lscpu
    echo
    echo "Память:"
    free -h
} > "$RESULT_DIR/host-hardware.txt"

IMG=ghcr.io/userver-framework/ubuntu-22.04-userver
DIGEST=sha256:fca9c8ac7e97b4e2b042d822facbb152aec10a9d4e09c0862e44c50640f3f303

docker pull "$IMG@$DIGEST"

if docker run --rm \
    --cpus=4 \
    --cpuset-cpus=0-3 \
    --memory=8g \
    --memory-swap=8g \
    -e RESULT_DIR="/workspace/results/$RUN_NAME" \
    -v "$ROOT_DIR:/workspace" \
    -w /workspace \
    "$IMG@$DIGEST" \
    bash /workspace/scripts/reproduce_in_docker.sh \
    > "$RESULT_DIR/container.log" 2>&1; then
    echo "Готово. Результаты сохранены в: $RESULT_DIR"
else
    echo "Что-то не получилось. Подробности: $RESULT_DIR/container.log" >&2
    exit 1
fi
