# SSH rework, July 2026

Why every git push wanted a YubiKey touch, what changed, and how to move the
other machines over.

## What was actually wrong

The config review traced the "ssh doesn't feel smooth" problem to a few
compounding issues:

1. **No key caching anywhere.** Nothing ever loaded a key into an agent. On
   frostpaw no agent ran at all; on diamond an agent was started but kept
   deliberately empty. Since the only GitHub keys deployed on frostpaw were
   the YubiKey SK ones, every single git fetch/push required a physical
   touch.
2. **Phantom keys in ssh_config.** The bare `github.com` host pointed at
   `id_ed25519_github`, which does not exist on any machine, with
   `IdentitiesOnly yes`. Plain `git@github.com:` URLs offered no key at all.
   The Grace Hopper host block listed three keys, none of which exist. The
   legacy `id_ed25519_d`/`id_ed25519_s` match blocks referenced names that
   were never created.
3. **The exit trap killed shared agents.** The shell that started an agent
   armed an EXIT trap that killed it unconditionally. Close that terminal
   and every other shell reusing the agent via `~/.ssh-agent-info` lost it.
   The trap existed for a good reason (agents used to pile up in the
   thousands), but it fixed the symptom by breaking sharing.
4. **ForwardAgent was pointless.** Grace Hopper and atlas forward the agent
   so remote sessions can reach GitHub, but a forwarded empty agent carries
   nothing.
5. **Wrong mental model in the comments.** The agent machinery described
   itself as being "for connection multiplexing". Multiplexing is
   ControlMaster's job and was already handled in ssh_config. The one thing
   an agent is actually for, caching unlocked keys, was the thing missing.

Plus assorted stale artefacts in `~/.ssh`: a dead `~/.ssh-agent-info` from
May, an empty `agent/` dir, old backups, `known_hosts.old`, and a GitHub
control socket that should not exist given `ControlMaster no` for GitHub.

## The new design

**One agent per machine, keys cached on first use, no pileup by
construction.**

- `configs/systemd/user/ssh-agent.service` runs a single agent on a fixed
  socket (`$XDG_RUNTIME_DIR/ssh-agent.socket`). systemd will not start a
  second instance, so pileup is impossible on machines with systemd user
  sessions (frostpaw boxes, asteria).
- `bc_ssh_agent_attach` runs at shell startup and attaches in preference
  order: an already-working inherited/forwarded agent, then the systemd
  socket, then a per-host env-file agent for hosts without `systemd --user`
  (diamond). The env file is suffixed with the short hostname because the
  diamond NFS home is shared across bastion and workstation nodes. A stale
  env-file agent is killed before a replacement starts, so the fallback
  cannot accumulate agents either.
- The EXIT trap is gone entirely. A shared agent must outlive the shell
  that started it. `bc_ssh_agent_status` shows the agent count and
  `bc_ssh_agent_prune` kills anything that is not the managed agent, so
  pileup would be visible and fixable if it ever came back.
- `AddKeysToAgent yes` in ssh_config loads each key into the agent the
  first time it is used. Passphrase (or YubiKey touch) once per boot, not
  once per operation.
- Key strategy: regular ed25519 keys for daily use, SK keys stay as
  fallback. Each machine generates its own keys under the filenames
  ssh_config already probes for (`Match exec test -f` gates), so private
  keys never enter git and a stolen laptop means revoking one key, not all
  of them. `bc_setup_ssh_keys` generates whatever is missing for the
  machine's specialisation and prints the public keys with upload
  instructions.

### ssh_config changes (secrets repo)

- `AddKeysToAgent yes` under `Host *`.
- Bare `github.com` now resolves to the main account's keys through the
  same match gates as `github.com-d`, so plain clone URLs work.
- Legacy `id_ed25519_d`/`id_ed25519_s` blocks removed.
- Personal machines and atlas offer a shared non-SK `id_ed25519_personal`
  first (file-gated), per-machine SK keys remain as fallback.
- Grace Hopper hosts use `id_ed25519_diamond` plus SK fallback and keep
  `ForwardAgent yes`, which now actually does something because the local
  agent holds keys. GH boxes have local homes off the NFS share, so agent
  forwarding is the GitHub mechanism there rather than deployed keys.

## Moving a machine over

```
cd ~/path/to/bash-config
git pull
./scripts/migrate-ssh-agent.sh
```

The script removes the old agent state files, installs and enables the
systemd unit (or notes the env-file fallback on diamond), prunes stray
agents, verifies the agent and `AddKeysToAgent` are live, and offers key
generation when run from a terminal.

Manual bits after the script:

- Upload new `id_ed25519_github_d.pub` / `id_ed25519_github_s.pub` to the
  matching GitHub accounts.
- `ssh-copy-id -i ~/.ssh/id_ed25519_personal.pub <host>` for the personal
  machines (the SK key authorises the copy).
- On headless machines check linger stuck: `loginctl show-user $USER -p Linger`.
- Grace Hopper: confirm which public key is in the local
  `authorized_keys` and add `id_ed25519_diamond.pub` if needed.

## Verifying

```
echo $SSH_AUTH_SOCK          # /run/user/<uid>/ssh-agent.socket in a new shell
ssh-add -l                   # empty until first key use, then populated
ssh -G github.com | grep -E 'identityfile|addkeystoagent'
ssh -T git@github.com-d      # passphrase once, then cached
time git fetch               # second run: no touch, no prompt
bc_ssh_agent_status
```

## Leftovers and follow-ups

- `~/.ssh/id_ed25519_sk_d` and `id_ed25519_sk_s` on frostpaw are NOT
  duplicates of the current SK handles (different fingerprints, older
  YubiKey registration). Check both GitHub accounts for old registered
  keys with those fingerprints before deleting the files.
- `secrets/sk_ssh_handles/` still carries an `id_ecdsa_sk_*` set that
  nothing references; candidate for deletion.
- Fixed in passing: `bc_log_debug` returned status 1 when debug was off,
  which aborted any `set -e` caller that used it as the last statement in
  a function. `hostname(1)` is not installed on minimal Arch, so the
  modules use `$HOSTNAME` instead.
- Bigger picture (planned, not done): migrate deployment to chezmoi with
  age-encrypted secrets, which dissolves the secrets submodule and its
  bootstrap ordering problem, adds per-distro package bootstrap, and gets
  a fresh machine from clone to working in one command. The API key
  committed in the secrets repo history needs rotating when that lands.
