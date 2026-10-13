#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/clang-cache
swiftc -module-cache-path "$PWD/.build/clang-cache" Sources/ClickDiagnostic/Mapping.swift Tests/MapperTests.swift -o .build/mapper-tests
.build/mapper-tests
