#!/usr/bin/env python3
"""Build grpc-java 1.72's code generator natively on Apple Silicon."""
import platform
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
if platform.system() != 'Darwin' or platform.machine() != 'arm64':
    raise SystemExit(0)
output = root / 'toolchains/protoc-gen-grpc-java'
if output.exists():
    raise SystemExit(0)
source = root / 'toolchains/grpc-java-source'
archive = root / 'toolchains/grpc-java-1.72.0.tar.gz'
source.mkdir(parents=True, exist_ok=True)
if not (source / 'compiler/src/java_plugin/cpp/java_plugin.cpp').exists():
    subprocess.run(['curl', '-fL', '--retry', '2', 'https://github.com/grpc/grpc-java/archive/refs/tags/v1.72.0.tar.gz', '-o', str(archive)], check=True)
    subprocess.run(['tar', '-xzf', str(archive), '-C', str(source), '--strip-components=1'], check=True)
protobuf = Path(subprocess.check_output(['brew', '--prefix', 'protobuf'], text=True).strip())
abseil = Path(subprocess.check_output(['brew', '--prefix', 'abseil'], text=True).strip())
cpp = source / 'compiler/src/java_plugin/cpp'
subprocess.run(['c++', '-std=c++17', '-I' + str(protobuf / 'include'), '-I' + str(abseil / 'include'),
                str(cpp / 'java_plugin.cpp'), str(cpp / 'java_generator.cpp'), '-o', str(output),
                '-L' + str(protobuf / 'lib'), '-lprotobuf', '-lprotoc',
                *map(str, sorted((abseil / 'lib').glob('libabsl_*.dylib')))], check=True)
