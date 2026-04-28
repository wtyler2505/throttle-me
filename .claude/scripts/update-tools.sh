#!/bin/bash
# update-tools.sh - Re-scan MCP servers and CLI tools, update documentation

set -e

echo "🔍 Updating tool documentation..."

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Backup existing docs
echo "📦 Backing up existing documentation..."
cp .claude/core/tools-mcp.md .claude/core/tools-mcp.md.bak
cp .claude/core/tools-cli.md .claude/core/tools-cli.md.bak

# Check MCP config
echo "🔧 Scanning MCP servers..."
if [ -f .mcp.json ]; then
  MCP_COUNT=$(jq '.mcpServers | length' .mcp.json 2>/dev/null || echo "0")
  echo "   Found $MCP_COUNT MCP servers in .mcp.json"
elif [ -f ~/.mcp.json ]; then
  MCP_COUNT=$(jq '.mcpServers | length' ~/.mcp.json 2>/dev/null || echo "0")
  echo "   Found $MCP_COUNT MCP servers in ~/.mcp.json"
else
  echo "   ⚠️  No .mcp.json found"
  MCP_COUNT=0
fi

# Check CLI tools
echo "🛠️  Scanning CLI tools..."
TOOLS=("bash" "dialog" "iptables" "git" "node" "npm" "python3" "grep" "awk" "sed" "ip" "sudo" "chattr")
FOUND_COUNT=0

for tool in "${TOOLS[@]}"; do
  if command -v "$tool" &>/dev/null; then
    ((FOUND_COUNT++))
  fi
done

echo "   Found $FOUND_COUNT/$${#TOOLS[@]} CLI tools"

# Timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo ""
echo "✅ Tool documentation updated at $TIMESTAMP"
echo ""
echo "Summary:"
echo "  - MCP Servers: $MCP_COUNT"
echo "  - CLI Tools: $FOUND_COUNT"
echo ""
echo "Backups saved to:"
echo "  - .claude/core/tools-mcp.md.bak"
echo "  - .claude/core/tools-cli.md.bak"
echo ""
echo "💡 Re-run this script after installing new MCP servers or CLI tools"
