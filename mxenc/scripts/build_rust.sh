#!/usr/bin/env bash
set -euo pipefail

# 构建 Rust 原生库以供 Flutter 使用
# 需在 rust_core 目录下执行 cargo 构建

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$PROJECT_ROOT/rust_core"

echo "[mxenc] Building Rust core..."
pushd "$RUST_DIR" >/dev/null

# Desktop targets
cargo build --release

echo "[mxenc] Artifacts at: target/release"
echo "- Linux: libmxenc_core.so"
echo "- macOS: libmxenc_core.dylib"
echo "- Windows: mxenc_core.dll"

popd >/dev/null

echo "[mxenc] Done. 请将对应平台产物拷贝到 Flutter 可加载的位置（如 windows\runner 或通过 flutter_rust_bridge 生成绑定）。"


