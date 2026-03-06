#!/bin/bash
# OpenViking client library for OMK hooks
# Communicates with ov-daemon via Unix socket

OV_AVAILABLE=0
OV_SOCKET="${OV_SOCKET:-/tmp/omk-ov.sock}"

_ov_check_overlay() {
  local overlay=".omk-overlay.json"
  [ -f "$overlay" ] || return 1
  python3 -c "
import json,sys
d=json.load(open('$overlay'))
sys.exit(0 if d.get('knowledge_backend')=='openviking' else 1)
" 2>/dev/null
}

ov_init() {
  _ov_check_overlay || return 1
  [ -S "$OV_SOCKET" ] || return 1
  local resp
  resp=$(ov_call '{"cmd":"health"}')
  echo "$resp" | grep -q '"ok"' && OV_AVAILABLE=1 || return 1
}

ov_call() {
  python3 -c "
import socket,json,sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
s.settimeout(8)
s.connect('$OV_SOCKET')
s.sendall(sys.argv[1].encode())
d=s.recv(65536)
s.close()
print(d.decode())
" "$1" 2>/dev/null
}

ov_search() {
  ov_call "{\"cmd\":\"search\",\"query\":\"$1\",\"limit\":${2:-3}}"
}

ov_add() {
  ov_call "{\"cmd\":\"add_resource\",\"path\":\"$1\",\"reason\":\"$2\"}"
}

ov_session_commit() {
  ov_call "{\"cmd\":\"session_commit\",\"session_id\":\"$1\",\"message\":\"$2\"}"
}
