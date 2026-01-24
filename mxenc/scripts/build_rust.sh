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

# iOS target (Requires rustup target add aarch64-apple-ios)
echo "[mxenc] Building for iOS (arm64)..."
cargo build --release --target aarch64-apple-ios

echo "[mxenc] Artifacts at: target/release"
echo "- Linux: libmxenc_core.so"
echo "- macOS: libmxenc_core.dylib"
echo "- Windows: mxenc_core.dll"
echo "- iOS: target/aarch64-apple-ios/release/libmxenc_core.a"

# Copy for iOS linkage (Helper)
mkdir -p "$PROJECT_ROOT/ios/libs"
cp "target/aarch64-apple-ios/release/libmxenc_core.a" "$PROJECT_ROOT/ios/libs/"

popd >/dev/null

echo "[mxenc] Done. 请将对应平台产物拷贝到 Flutter 可加载的位置。"
echo "iOS 注意：已拷贝 libmxenc_core.a 到 ios/libs，请在 Xcode 中手动点击 'Add' 并链接它。"


