#!/usr/bin/env bash
# Drive vordi-mcp over stdio and pretty-print results. No agent needed.
# Usage:  ./smoke-test.sh [search-query]
set -euo pipefail
cd "$(dirname "$0")"

BIN=".build/release/vordi-mcp"
[ -x "$BIN" ] || { echo "Building release binary..."; swift build -c release; }

QUERY="${1:-claude}"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"vordi_list_runs","arguments":{"limit":5}}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"vordi_search_transcripts\",\"arguments\":{\"query\":\"$QUERY\",\"limit\":5}}}" \
  | "$BIN" 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    m=json.loads(line)
    i=m.get('id')
    if i==1: print('✅ initialize →', m['result']['serverInfo'])
    elif i==2: print('✅ tools/list →', [t['name'] for t in m['result']['tools']])
    elif i==3:
        runs=json.loads(m['result']['content'][0]['text'])
        print(f'✅ vordi_list_runs → {len(runs)} runs')
        for r in runs: print('   •', r.get('date'),'|',r.get('app'),'|',repr(r.get('text','')[:55]))
    elif i==4:
        runs=json.loads(m['result']['content'][0]['text'])
        print(f'✅ search → {len(runs)} hits')
        for r in runs: print('   •', repr(r.get('text','')[:60]))
"
