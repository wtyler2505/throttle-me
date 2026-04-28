# MCP Servers

## Installed Servers (10 total)

### 1. taskmaster-ai
**Purpose:** AI-powered task management and workflow automation
**Command:** node → /usr/local/lib/node_modules/task-master-ai/dist/mcp-server.js

**Key Tools:**
- `mcp__taskmaster-ai__get_tasks()` - List all tasks with filtering
- `mcp__taskmaster-ai__get_task(id)` - Get specific task details
- `mcp__taskmaster-ai__next_task()` - Get next actionable task
- `mcp__taskmaster-ai__set_task_status(id, status)` - Update task status
- `mcp__taskmaster-ai__add_task(prompt)` - AI-generated task creation
- `mcp__taskmaster-ai__expand_task(id)` - Break task into subtasks
- `mcp__taskmaster-ai__parse_prd(input)` - Generate tasks from PRD
- `mcp__taskmaster-ai__update_task(id, prompt)` - AI-powered task updates
- `mcp__taskmaster-ai__analyze_project_complexity()` - Complexity analysis

**Usage Pattern:**
```javascript
// Get next task to work on
await mcp__taskmaster-ai__next_task({projectRoot: "/home/wtyler/throttle-me"})

// Parse PRD to generate initial tasks
await mcp__taskmaster-ai__parse_prd({
  projectRoot: "/home/wtyler/throttle-me",
  input: "/home/wtyler/throttle-me/PRD.md"
})
```

**API Keys Required:** ANTHROPIC_API_KEY, PERPLEXITY_API_KEY, OPENAI_API_KEY

---

### 2. desktop-commander
**Purpose:** Advanced file operations and process management
**Command:** node → /usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/dist/index.js

**Key Tools:**
- `mcp__desktop-commander__read_file(path)` - Read files with offset/length
- `mcp__desktop-commander__write_file(path, content, mode)` - Write/append files
- `mcp__desktop-commander__edit_block(filePath, oldString, newString)` - Surgical edits
- `mcp__desktop-commander__list_directory(path)` - List directory contents
- `mcp__desktop-commander__start_search(path, pattern, searchType)` - Streaming search
- `mcp__desktop-commander__start_process(command)` - Start terminal process with smart detection
- `mcp__desktop-commander__interact_with_process(pid, input)` - Send input to REPL
- `mcp__desktop-commander__read_process_output(pid)` - Read process output

**Usage Pattern:**
```bash
# Preferred for file operations (use instead of bash cat/echo)
read_file({path: "/home/wtyler/throttle-me/throttle-me"})
write_file({path: "/home/wtyler/test.sh", content: "#!/bin/bash\necho hello"})
edit_block({filePath: "/home/wtyler/script.sh", oldString: "old", newString: "new"})

# CRITICAL: Use for ALL local file analysis (not analysis tool)
start_process({command: "python3 -i", timeout_ms: 30000})
interact_with_process({pid: 1234, input: "import pandas as pd"})
```

**API Keys:** None required

---

### 3. FileScopeMCP
**Purpose:** File importance ranking and dependency analysis
**Command:** node → /home/wtyler/FileScopeMCP/dist/mcp-server.js
**Base Directory:** /home/wtyler/multi-controller-app

**Key Tools:**
- `mcp__FileScopeMCP__create_file_tree(filename, baseDirectory)` - Create file tree
- `mcp__FileScopeMCP__list_files()` - List all files with importance
- `mcp__FileScopeMCP__find_important_files(limit, minImportance)` - Find key files
- `mcp__FileScopeMCP__get_file_summary(filepath)` - Get file summary
- `mcp__FileScopeMCP__set_file_importance(filepath, importance)` - Manual ranking
- `mcp__FileScopeMCP__generate_diagram(style, outputPath)` - Mermaid diagrams

**Usage Pattern:**
```javascript
// Find most important files in project
await mcp__FileScopeMCP__find_important_files({limit: 10, minImportance: 7})

// Generate architecture diagram
await mcp__FileScopeMCP__generate_diagram({
  style: "dependency", 
  outputPath: "docs/architecture.mmd"
})
```

**Environment:** FILE_WATCHING_ENABLED=false, MIN_IMPORTANCE_SCORE=6

---

### 4. clear-thought
**Purpose:** Advanced reasoning and problem-solving frameworks
**Command:** node → /usr/local/lib/node_modules/@waldzellai/clear-thought/dist/index.js

**Key Tools:**
- `mcp__clear-thought__sequentialthinking()` - Chain of thought reasoning
- `mcp__clear-thought__mentalmodel()` - Apply mental models (first principles, etc.)
- `mcp__clear-thought__debuggingapproach()` - Systematic debugging methods
- `mcp__clear-thought__collaborativereasoning()` - Multi-persona analysis
- `mcp__clear-thought__decisionframework()` - Structured decision analysis
- `mcp__clear-thought__scientificmethod()` - Hypothesis testing workflow

**Usage Pattern:**
```javascript
// Use for complex problem-solving
await mcp__clear-thought__sequentialthinking({
  thought: "Breaking down the TTL bypass mechanism...",
  thoughtNumber: 1,
  totalThoughts: 5,
  nextThoughtNeeded: true
})
```

---

### 5. context7
**Purpose:** Up-to-date library documentation retrieval
**Command:** node → /usr/local/lib/node_modules/@upstash/context7-mcp/dist/index.js

**Key Tools:**
- `mcp__context7__resolve-library-id(libraryName)` - Find library ID
- `mcp__context7__get-library-docs(context7CompatibleLibraryID, topic)` - Fetch docs

**Usage Pattern:**
```javascript
// Get latest documentation
const lib = await mcp__context7__resolve-library-id({libraryName: "react"})
const docs = await mcp__context7__get-library-docs({
  context7CompatibleLibraryID: "/facebook/react",
  topic: "hooks"
})
```

---

### 6. perplexity-ask
**Purpose:** Real-time web search and research
**Command:** node → /usr/local/lib/node_modules/server-perplexity-ask/dist/index.js

**Key Tools:**
- `mcp__perplexity-ask__perplexity_ask(messages)` - Sonar API conversation

**Usage Pattern:**
```javascript
await mcp__perplexity-ask__perplexity_ask({
  messages: [
    {role: "user", content: "Latest iptables TTL bypass techniques?"}
  ]
})
```

**API Keys Required:** PERPLEXITY_API_KEY

---

### 7. memory
**Purpose:** Knowledge graph for entity/relation tracking
**Command:** node → /usr/local/lib/node_modules/@modelcontextprotocol/server-memory/dist/index.js

**Key Tools:**
- `mcp__memory__create_entities(entities)` - Create knowledge entities
- `mcp__memory__create_relations(relations)` - Link entities
- `mcp__memory__add_observations(observations)` - Add entity details
- `mcp__memory__search_nodes(query)` - Search knowledge graph
- `mcp__memory__read_graph()` - Get entire graph
- `mcp__memory__delete_entities(entityNames)` - Remove entities

**Usage Pattern:**
```javascript
// Track project entities
await mcp__memory__create_entities({
  entities: [{
    name: "throttle-me",
    entityType: "project",
    observations: ["Bash TUI for carrier bypass", "Uses iptables TTL modification"]
  }]
})
```

---

### 8. time-server
**Purpose:** Time/date utilities and timezone conversions
**Command:** npx -y time-mcp

**Key Tools:**
- `mcp__time-server__current_time(format, timezone)` - Get current time
- `mcp__time-server__convert_time(sourceTimezone, targetTimezone, time)` - Convert zones
- `mcp__time-server__relative_time(time)` - Relative time from now
- `mcp__time-server__get_timestamp(time)` - Get Unix timestamp

---

### 9. arduino-cli-mcp
**Purpose:** Arduino board management and compilation
**Command:** python3 → /home/wtyler/arduino-cli-mcp/main.py
**Work Directory:** /home/wtyler/multi-controller-app

*Not applicable to this project (no Arduino code)*

---

### 10. computer-use
**Purpose:** GUI automation (mouse/keyboard control, screenshots)
**Command:** node → computer-use-mcp/dist/index.js

**Key Tools:**
- `mcp__computer-use__computer(action)` - Control desktop GUI
  - Actions: get_screenshot, mouse_move, left_click, type, key

**Usage Pattern:**
```javascript
// Take screenshot to debug dialog TUI
await mcp__computer-use__computer({action: "get_screenshot"})
```

**Environment:** DISPLAY=:0

---

## MCP Server Selection Guide

**For file operations:** Use `desktop-commander` (not bash cat/echo)
**For AI tasks:** Use `taskmaster-ai` (task management, PRD parsing)
**For research:** Use `perplexity-ask` (web search) or `context7` (docs)
**For reasoning:** Use `clear-thought` (complex problem-solving)
**For knowledge:** Use `memory` (entity tracking across sessions)
**For architecture:** Use `FileScopeMCP` (dependency analysis, diagrams)
