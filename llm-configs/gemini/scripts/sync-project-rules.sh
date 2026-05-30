#!/bin/bash
WORKSPACE_DIR="$HOME/Workspace"
projects=$(find "$WORKSPACE_DIR" -maxdepth 2 -name "CLAUDE.md")

for claude_md in $projects; do
    project_dir=$(dirname "$claude_md")
    gemini_md="$project_dir/GEMINI.md"
    
    if [ ! -f "$gemini_md" ] || [ "$claude_md" -nt "$gemini_md" ]; then
        cp "$claude_md" "$gemini_md"
        echo "✓ $project_dir: GEMINI.md 갱신 완료"
    fi
done
