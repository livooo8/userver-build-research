#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_DIR=/workspace/service
RESULT_DIR="${RESULT_DIR:?Не задан RESULT_DIR}"
BUILD_DIR="$SERVICE_DIR/build-release"
HPP="$SERVICE_DIR/src/hello_postgres.hpp"
CPP="$SERVICE_DIR/src/hello_postgres.cpp"

TMP_DIR=$(mktemp -d)
TMP_LOG=$(mktemp)

cp "$HPP" "$TMP_DIR/hello_postgres.hpp"
cp "$CPP" "$TMP_DIR/hello_postgres.cpp"

restore_sources() {
    cp "$TMP_DIR/hello_postgres.hpp" "$HPP"
    cp "$TMP_DIR/hello_postgres.cpp" "$CPP"
    rm -rf "$TMP_DIR"
    rm -f "$TMP_LOG"
}

trap restore_sources EXIT

run_quiet() {
    local description="$1"
    shift

    if "$@" >"$TMP_LOG" 2>&1; then
        return 0
    else
        local status=$?
        echo "Ошибка: $description (код $status)." >&2
        tail -n 25 "$TMP_LOG" >&2
        return "$status"
    fi
}

run_quiet "обновление пакетов" apt-get update

run_quiet "установка инструментов" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends \
    clang-14 git ninja-build build-essential ca-certificates

ANALYZER_SRC=/tmp/ClangBuildAnalyzer-src
ANALYZER="$ANALYZER_SRC/build/ClangBuildAnalyzer"

rm -rf "$ANALYZER_SRC"

run_quiet "скачивание анализатора" \
    git clone --depth 1 --branch v1.6.0 \
    https://github.com/aras-p/ClangBuildAnalyzer.git \
    "$ANALYZER_SRC"

run_quiet "настройка анализатора" \
    cmake -S "$ANALYZER_SRC" -B "$ANALYZER_SRC/build" \
    -DCMAKE_BUILD_TYPE=Release

run_quiet "сборка анализатора" \
    cmake --build "$ANALYZER_SRC/build" --parallel 2

cd "$SERVICE_DIR"

run_quiet "настройка сервиса" \
    cmake --preset release \
    -DCMAKE_CXX_COMPILER=clang++-14 \
    -DCMAKE_CXX_FLAGS=-ftime-trace

BUILD_PROBLEM=0

measure_build() {
    local variant="$1"
    local name="$RESULT_DIR/$variant"

    run_quiet "очистка сборки" \
        cmake --build "$BUILD_DIR" --target clean --parallel 4

    run_quiet "начало профилирования" \
        "$ANALYZER" --start "$BUILD_DIR"

    sleep 2

    if env CCACHE_DISABLE=1 \
        cmake --build "$BUILD_DIR" --parallel 4 \
        >"$TMP_LOG" 2>&1; then
        :
    else
        local status=$?
        BUILD_PROBLEM=1
        echo "Сборка $variant завершилась с ошибкой." >&2
        tail -n 15 "$TMP_LOG" >&2
    fi

    run_quiet "сохранение трасс" \
        "$ANALYZER" --stop "$BUILD_DIR" "$name.bin"

    if "$ANALYZER" --analyze "$name.bin" \
        >"$nam-analysis.txt" 2>&1; then
        :
    else
        local status=$?
        echo "Ошибка анализа $variant (код $status)." >&2
        tail -n 25 "$name-analysis.txt" >&2
        return "$status"
    fi
}

measure_build baseline

sed -i \
    's|#include <userver/components/component.hpp>|#include <userver/components/component_fwd.hpp>|' \
    "$HPP"

sed -i \
    '/#include <userver\/storages\/postgres\/component.hpp>/i #include <userver/components/component_context.hpp>' \
    "$CPP"

measure_build experiment

if [[ "$BUILD_PROBLEM" -eq 1 ]]; then
    echo "Измерения сохранены, но сборка завершилась с ошибкой: $RESULT_DIR" >&2
    exit 2
fi

echo "Всё готово. Результаты: $RESULT_DIR"