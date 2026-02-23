#!/bin/bash
# patterns.sh — Shared regex patterns for security hooks

# Case-sensitive patterns (exact case matters, e.g. git flags)
DANGEROUS_BASH_PATTERNS=(
  '\brm[[:space:]]+(-[rRf]|--recursive|--force)'
  '\brmdir\b'
  '\bmkfs\b'
  '\bshred\b'
  '\bdd[[:space:]]+.*of=/'
  '\bgit[[:space:]]+push[[:space:]]+.*--force'
  '\bgit[[:space:]]+push[[:space:]]+.*-f\b'
  '\bgit[[:space:]]+reset[[:space:]]+--hard'
  '\bgit[[:space:]]+clean[[:space:]]+-f'
  '\bgit[[:space:]]+stash[[:space:]]+drop'
  '\bgit[[:space:]]+branch[[:space:]]+-D\b'
  '\bchmod[[:space:]]+(-R[[:space:]]+)?777'
  '\bchown[[:space:]]+-R'
  'curl.*\|[[:space:]]*(ba)?sh'
  'wget.*\|[[:space:]]*(ba)?sh'
  '\bshutdown\b'
  '\breboot\b'
  '\bsystemctl[[:space:]]+(stop|disable|mask)'
  '\bdocker[[:space:]]+system[[:space:]]+prune[[:space:]]+-a'
  '\bdocker[[:space:]]+rm[[:space:]]+-f'
  '\bdocker[[:space:]]+rmi[[:space:]]+-f'
  '\bfind\b[[:space:]]+(/etc|/usr|/var|/sys|/boot)(/[^[:space:]]*)?[[:space:]].*-delete'
  '\bfind\b[[:space:]]+(/etc|/usr|/var|/sys|/boot)(/[^[:space:]]*)?[[:space:]].*-exec[[:space:]]+rm'
)

# Case-insensitive patterns (SQL keywords may appear in any case)
DANGEROUS_BASH_PATTERNS_NOCASE=(
  '\bDROP[[:space:]]+(DATABASE|TABLE|SCHEMA)\b'
  '\bTRUNCATE\b'
)

INJECTION_PATTERNS='(curl.*\|[[:space:]]*(ba)?sh|wget.*\|[[:space:]]*(ba)?sh|SECRET[[:space:]]+INSTRUCTIONS|hidden[[:space:]]+instructions|ignore[[:space:]]+(all[[:space:]]+)?previous|system[[:space:]]+prompt|<script)'

SECRET_PATTERNS='(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|-----BEGIN[[:space:]]+(RSA[[:space:]]+)?PRIVATE[[:space:]]+KEY|xox[bpras]-[0-9a-zA-Z-]{10,}|sk_live_[0-9a-zA-Z]{10,}|pk_live_[0-9a-zA-Z]{10,}|npm_[a-zA-Z0-9]{10,}|pypi-[a-zA-Z0-9]{10,}|glpat-[a-zA-Z0-9_-]{20,}|hf_[a-zA-Z0-9]{20,})'
