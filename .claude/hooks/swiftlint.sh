#!/bin/bash
# PostToolUse hook: lint Swift files after Edit/Write

FILE_PATH=$(jq -r '.tool_input.file_path // empty')

# Skip non-Swift files
[[ "$FILE_PATH" != *.swift ]] && exit 0

# Skip files outside Sources/
[[ "$FILE_PATH" != *Sources/* ]] && exit 0

TOOLCHAIN_DIR=$(dirname "$(dirname "$(xcrun --find swiftc)")")
OUTPUT=$(DYLD_FRAMEWORK_PATH="$TOOLCHAIN_DIR/lib" swiftlint lint --quiet --strict "$FILE_PATH" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "$OUTPUT" >&2
  exit $EXIT_CODE
fi
