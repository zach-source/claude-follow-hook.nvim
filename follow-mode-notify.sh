#!/usr/bin/env bash
# Claude hook: Send file paths to NeoVim follow mode socket
# Event: PostToolUse (after Write/Edit/MultiEdit)

set -euo pipefail

# Debug logging (always enabled for troubleshooting)
DEBUG_LOG="/tmp/claude-follow-mode-debug.log"

log_debug() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$DEBUG_LOG"
}

# Get current working directory for socket name
CWD=$(pwd)

# Generate socket path (same logic as nvim: hash CWD)
HASH=$(echo -n "$CWD" | shasum -a 256 | cut -c1-12)
SOCKET="/tmp/nvim-follow-$USER-$HASH.sock"

log_debug "===== Follow Mode Hook Triggered ====="
log_debug "CWD: $CWD"
log_debug "Hash: $HASH"
log_debug "Socket: $SOCKET"

# Check if socket exists (follow mode enabled in nvim for this workspace)
if [[ ! -S "$SOCKET" ]]; then
	# Follow mode not enabled for this workspace, exit silently
	log_debug "Socket not found, exiting"
	exit 0
fi

log_debug "Socket exists"

# Read stdin (tool use JSON from Claude) and save to temp file
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON"

log_debug "Stdin saved to: $TEMP_JSON"
log_debug "Stdin size: $(wc -c < "$TEMP_JSON") bytes"
log_debug "Stdin preview: $(head -c 500 "$TEMP_JSON")"

# Extract file path from tool parameters (check both tool_input and parameters)
FILE_PATH=$(jq -r '.tool_input.file_path // .parameters.file_path // .tool_input.path // .parameters.path // empty' "$TEMP_JSON" 2>>"$DEBUG_LOG")

log_debug "Extracted file_path: '$FILE_PATH'"

# Also try tool_response for Write operations
if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
	FILE_PATH=$(jq -r '.tool_response.file_path // .tool_response.filePath // empty' "$TEMP_JSON" 2>>"$DEBUG_LOG")
	log_debug "Tried tool_response, got: '$FILE_PATH'"
fi

# Debug: dump full JSON structure
log_debug "Full JSON keys: $(jq 'keys' "$TEMP_JSON" 2>&1)"
log_debug "tool_input keys: $(jq '.tool_input | keys' "$TEMP_JSON" 2>&1)"

# Exit if no file path found
if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
	log_debug "No file path found, exiting"
	# Save JSON for manual inspection
	cp "$TEMP_JSON" "/tmp/claude-hook-last-payload.json"
	log_debug "Saved payload to /tmp/claude-hook-last-payload.json for inspection"
	rm -f "$TEMP_JSON"
	exit 0
fi

# Clean up temp file when done
trap 'rm -f "$TEMP_JSON"' EXIT

# Get tool name to determine operation type
TOOL_NAME=$(jq -r '.tool_name // "unknown"' "$TEMP_JSON" 2>>"$DEBUG_LOG")

# Extract old_string to count how many lines were affected (for Edit)
OLD_STRING=$(jq -r '.tool_input.old_string // .parameters.old_string // empty' "$TEMP_JSON" 2>>"$DEBUG_LOG")
NEW_STRING=$(jq -r '.tool_input.new_string // .parameters.new_string // empty' "$TEMP_JSON" 2>>"$DEBUG_LOG")

# For Edit operations, find the line number by searching for old_string in the file
LINE_NUM=1
if [[ "$TOOL_NAME" == "Edit" && -n "$OLD_STRING" && "$OLD_STRING" != "null" && -f "$FILE_PATH" ]]; then
	# Get first line of old_string to search
	SEARCH_LINE=$(echo "$OLD_STRING" | head -1)
	log_debug "Searching for line: $SEARCH_LINE"
	# Find line number in file
	FOUND_LINE=$(grep -n -F "$SEARCH_LINE" "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1)
	if [[ -n "$FOUND_LINE" ]]; then
		LINE_NUM=$FOUND_LINE
		log_debug "Found edit at line $LINE_NUM"
	fi
fi

# Count lines changed (estimate based on new_string line count)
if [[ -n "$NEW_STRING" && "$NEW_STRING" != "null" ]]; then
	LINE_COUNT=$(echo "$NEW_STRING" | wc -l)
else
	LINE_COUNT=1
fi

log_debug "Tool: $TOOL_NAME, Line: $LINE_NUM, Count: $LINE_COUNT"

# Escape single quotes for Lua string
FILE_PATH_ESCAPED="${FILE_PATH//\'/\\\'}"

log_debug "Sending to nvim: $FILE_PATH_ESCAPED:$LINE_NUM"

# Send to socket using nvim --remote-expr
if command -v nvim >/dev/null 2>&1; then
	# Use nvim --remote-expr to call the follow-mode function with highlighting info
	if nvim --server "$SOCKET" --remote-expr "luaeval(\"require('claude-follow').open_file('$FILE_PATH_ESCAPED', $LINE_NUM, $LINE_COUNT, '$TOOL_NAME')\")" 2>&1 | tee -a "$DEBUG_LOG"; then
		log_debug "✓ Successfully sent to nvim"
	else
		log_debug "✗ Failed to send to nvim"
	fi
fi

log_debug "Hook completed"
exit 0
