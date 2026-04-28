# Claude Notes — throttle-me Iteration

Rolling notebook of design decisions, review findings, and surprises discovered during the Claude+Codex collaborative iteration. Persists across rounds. Plan reference: `~/.claude/plans/ai-ensemble-lexical-kurzweil.md`.

## Round Log

### Round 0 — Codex dashboard rebuild (pre-existing, archived)
See `coordination/round-0-dashboard-rebuild-DONE.md`. Commits `7216dcd` → `d339017`. Outcome: Textual TUI command center, 12 passing pytests, ultra-wide cap at 224 cols, queued 3 follow-ups (A/B/C).

### Round 1 — Stream A: Owned chains + transactional rollback (in progress)

**Why iptables, not nftables (decision):** Existing scripts are iptables-native, the codebase has no nft tooling, and a port doubles scope. Document migration path here, defer to a later round.

**The 3 silent failures (CLAUDE.md rules #4, #5, plus implicit MSS):**
1. `chattr +i /etc/resolv.conf` is a silent no-op when the file is a symlink to systemd-resolved's stub. Detect with `[[ -L /etc/resolv.conf ]]` and refuse silently — log warning loudly instead.
2. IPv6 DNS DNAT silently fails when `nf_nat_ipv6` kernel module isn't loaded. Detect with `lsmod | grep nf_nat_ipv6` (or `modprobe`), fail loudly if missing.
3. MSS clamping is missing entirely from the bypass. Without it, large packets fragment and stall over carrier paths. Add to owned mangle chain.

**Owned-chain design:**
- New chains: `THROTTLE_ME_POSTROUTING` (mangle) and `THROTTLE_ME_OUTPUT` (nat).
- Jump rules from main chains to owned chains (idempotent).
- All flushing operates on owned chains only — never `-F POSTROUTING`/`-F OUTPUT`.
- `lib/iptables.sh` checks must look at owned chains directly (since `iptables -L POSTROUTING` won't show the rules anymore — only the jump).

**Transactional verify+rollback pattern:**
- `enable_bypass` invokes `bypass-tethering`, then calls a new `iptables_verify_active` from `lib/iptables.sh` which checks every expected rule.
- If verify fails: invoke `disable-bypass-tethering` immediately to clean up partial state; return error.
- The disable script must itself be idempotent (already mostly is).

**Sudo TTY rule:** The disable script (`disable-bypass-tethering`) calls bare `sudo` without `-S`. Over non-TTY pipes it hangs. Pre-cache via `start_sudo_cache` from `lib/utils.sh:11` before invoking, OR add `sudo -v` priming inside `lib/core.sh:disable_bypass`. Choose the latter so pre-caching isn't required for the CLI path.

## Open Questions / Future Rounds

- nftables migration timing — when iptables-nft becomes default in more distros, this becomes worth doing.
- Should owned chains also wrap `INPUT` for DNS port hardening (block leaks from non-NAT'd processes)? Not in scope for Round 1; consider for a later D-stream item.
- The 30-day session retention policy in `lib/retention.sh` — verify it still works after Stream A reshuffles enable/disable timing.

## Review Findings Log

(Populated after each Codex round.)
