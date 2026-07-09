#!/usr/bin/env bash
set -euo pipefail

# Ensure a per-workspace Podman pod exists from generated Kubernetes YAML, then
# attach to the workspace's Zellij session inside the prebuilt tagged image.
#
# Runtime orchestration intentionally lives here instead of in flake.nix. Build
# and load localhost/nix-zellij-agent:dev first with ./build-image.sh.
#
# Usage:
#   ./run-image.sh [--update] [--outfitter-version VERSION] [--replace] [workspace]
#
# Options:
#   --update  Update flake inputs, bump/rebuild the Outfitter-containing image,
#             reload localhost/nix-zellij-agent:dev, and recreate this workspace pod.
#   --outfitter-version VERSION
#             Pin @ai-outfitter/outfitter to VERSION during --update instead of latest.
#   --replace Recreate this workspace pod before attaching.
#   --replace-secret Replace the Podman GitHub token secret before attaching.
#
# Optional environment:
#   AGENT_ZELLIJ_SESSION_NAME=notes
#   CONTAINER_NAME=zejent-notes
#   POD_NAME=zejent-notes
#   ZEJENT_IMAGE_REF=localhost/nix-zellij-agent:dev
#   ZEJENT_STATE_DIR=$HOME/.local/state/zejent
#   OUTFITTER_ROOT_DIR=$HOME/.outfitter/zejent/root
#   GITHUB_TOKEN_SECRET=nix-zellij-agent-github-token
#   GITHUB_TOKEN=... or GH_TOKEN=...  # optional; otherwise prompts on first run
#   PI_HOME_DIR=$HOME/.pi             # host Pi state mounted read-only at /root/.pi
#   TMP_VOLUME_NAME=zejent-notes-tmp   # Podman named volume mounted at /tmp
#   PI_SESSION_ID=zejent-notes         # stable Pi session id for leader-agent
#   PI_SESSION_NAME=notes              # human-readable Pi session name
#   PI_SESSION_DIR=/tmp/pi-sessions    # writable Pi session dir inside persistent /tmp
#   LEADER_AGENT_CMD='outfitter run --profile zejent'

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
TEMPLATE_FILE="$SCRIPT_DIR/templates/pod.yaml.tpl"
OUTFITTER_SOURCE_DIR="${ZEJENT_OUTFITTER_SOURCE_DIR:-$SCRIPT_DIR/.outfitter}"
LINK_OUTFITTER_DIR="${ZEJENT_LINK_OUTFITTER_DIR:-${HOME:-$PWD}/repos/unsupervised/link/.outfitter}"
WORKSPACE_INPUT="$PWD"
IMAGE_REF="${ZEJENT_IMAGE_REF:-localhost/nix-zellij-agent:dev}"
ZEJENT_UPDATE=0
FORCE_RECREATE=0
REPLACE_SECRET=0
SYNC_ONLY=0
NO_ATTACH=0
OUTFITTER_VERSION=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--update] [--outfitter-version VERSION] [--replace] [--replace-secret] [workspace]

Launch or attach to the Zejent Podman/Zellij workspace.

Options:
  --update                    Update the Nix flake inputs, bump @ai-outfitter/outfitter, rebuild/load
                              $IMAGE_REF, and recreate the workspace pod so the new image is used.
  --outfitter-version VERSION Pin @ai-outfitter/outfitter to VERSION during --update instead of latest.
  --replace                   Recreate this workspace pod before attaching.
  --replace-secret            Replace the Podman GitHub token secret before attaching.
  --sync-only                 Materialize Outfitter profiles/prompts and exit without
                              touching the pod or attaching (running panes pick up the
                              files through the /root/.outfitter mount).
  --no-attach                 Ensure the pod is running, then exit instead of attaching
                              (for editors/automation that connect on their own).
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      ZEJENT_UPDATE=1
      shift
      ;;
    --outfitter-version)
      if [[ -z "${2:-}" ]]; then
        echo "error: --outfitter-version requires a version" >&2
        exit 1
      fi
      OUTFITTER_VERSION="$2"
      shift 2
      ;;
    --outfitter-version=*)
      OUTFITTER_VERSION="${1#*=}"
      shift
      ;;
    --replace)
      FORCE_RECREATE=1
      shift
      ;;
    --replace-secret)
      REPLACE_SECRET=1
      shift
      ;;
    --sync-only)
      SYNC_ONLY=1
      shift
      ;;
    --no-attach)
      NO_ATTACH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      if [[ $# -gt 0 ]]; then
        WORKSPACE_INPUT="$1"
        shift
      fi
      ;;
    -* )
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      WORKSPACE_INPUT="$1"
      shift
      if [[ $# -gt 0 ]]; then
        printf 'error: unexpected extra argument: %s\n' "$1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ "$ZEJENT_UPDATE" == "1" ]]; then
  build_args=(--update)
  if [[ -n "$OUTFITTER_VERSION" ]]; then
    build_args+=(--outfitter-version "$OUTFITTER_VERSION")
  fi
  "$SCRIPT_DIR/build-image.sh" "${build_args[@]}"
  FORCE_RECREATE=1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "error: missing pod template: $TEMPLATE_FILE" >&2
  exit 1
fi

if ! podman image exists "$IMAGE_REF"; then
  cat >&2 <<EOF
error: image $IMAGE_REF is not loaded in local Podman.
Run: $SCRIPT_DIR/build-image.sh
EOF
  exit 1
fi
IMAGE_ID="$(podman image inspect -f '{{.Id}}' "$IMAGE_REF")"

WORKSPACE="$(cd -- "$WORKSPACE_INPUT" && pwd -P)"
workspace_base="${WORKSPACE##*/}"
slugify() {
  local value="$1"
  value="$(printf '%s' "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9-' '-' \
    | sed -E 's/^-+//; s/-+$//; s/-+/-/g')"
  value="${value:0:40}"
  if [[ -z "$value" ]]; then
    value="workspace"
  fi
  printf '%s' "$value"
}

workspace_slug="$(slugify "${workspace_base:-workspace}")"

read_task_title() {
  local task_file="$WORKSPACE/TASK.md"
  local line
  [[ -f "$task_file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*#{1,6}[[:space:]]*//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    if [[ -n "${line//[[:space:]]/}" ]]; then
      printf '%s' "$line"
      return 0
    fi
  done < "$task_file"
  return 1
}

resolve_work_context_slug() {
  local task_title branch
  if task_title="$(read_task_title)"; then
    slugify "$task_title"
    return 0
  fi

  if command -v git >/dev/null 2>&1 && git -C "$WORKSPACE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch="$(git -C "$WORKSPACE" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
      branch="$(basename -- "$(git -C "$WORKSPACE" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$WORKSPACE")")"
    fi
    slugify "$branch"
    return 0
  fi

  slugify "${workspace_base:-workspace}"
}

WORK_CONTEXT_SLUG="${ZEJENT_WORK_CONTEXT_SLUG:-$(resolve_work_context_slug)}"
if [[ "$WORK_CONTEXT_SLUG" == "workspace" && "$workspace_slug" != "workspace" ]]; then
  WORK_CONTEXT_SLUG="$workspace_slug"
fi

DEFAULT_CONTAINER_NAME="zejent-$workspace_slug"
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
POD_NAME="${POD_NAME:-$CONTAINER_NAME}"
SESSION_NAME="${AGENT_ZELLIJ_SESSION_NAME:-$WORK_CONTEXT_SLUG}"
LEADER_AGENT_CMD="${LEADER_AGENT_CMD:-}"
GITHUB_TOKEN_SECRET="${GITHUB_TOKEN_SECRET:-nix-zellij-agent-github-token}"
GITHUB_TOKEN_FILE="/run/secrets/github-token"
PI_HOME_DIR="${PI_HOME_DIR:-${HOME:-$PWD}/.pi}"
TMP_VOLUME_NAME="${TMP_VOLUME_NAME:-zejent-$workspace_slug-tmp}"
PI_SESSION_DIR="${PI_SESSION_DIR:-/tmp/pi-sessions}"
if [[ "$WORK_CONTEXT_SLUG" == "$workspace_slug" ]]; then
  default_pi_session_id="zejent-$workspace_slug"
else
  default_pi_session_id="zejent-$workspace_slug-$WORK_CONTEXT_SLUG"
fi
PI_SESSION_ID="${PI_SESSION_ID:-$default_pi_session_id}"
PI_SESSION_NAME="${PI_SESSION_NAME:-$SESSION_NAME}"

if [[ -n "${ZEJENT_STATE_DIR:-}" ]]; then
  STATE_ROOT="$ZEJENT_STATE_DIR"
elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
  STATE_ROOT="$XDG_STATE_HOME/zejent"
elif [[ -n "${HOME:-}" ]]; then
  STATE_ROOT="$HOME/.local/state/zejent"
else
  STATE_ROOT="$PWD/.zejent/state"
fi
POD_STATE_DIR="$STATE_ROOT/$POD_NAME"
POD_YAML="$POD_STATE_DIR/pod.yaml"

if [[ -n "${OUTFITTER_ROOT_DIR:-}" ]]; then
  outfitter_root_dir="$OUTFITTER_ROOT_DIR"
elif [[ -n "${HOME:-}" ]]; then
  outfitter_root_dir="$HOME/.outfitter/zejent/root"
else
  outfitter_root_dir="$PWD/.outfitter/zejent/root"
fi
outfitter_settings_file="$outfitter_root_dir/settings.yml"

if [[ ! -d "$OUTFITTER_SOURCE_DIR" ]]; then
  echo "error: missing Zejent Outfitter profile source: $OUTFITTER_SOURCE_DIR" >&2
  exit 1
fi
if [[ ! -f "$OUTFITTER_SOURCE_DIR/profiles/zejent.yml" ]]; then
  echo "error: missing Zejent profile: $OUTFITTER_SOURCE_DIR/profiles/zejent.yml" >&2
  exit 1
fi
if [[ ! -f "$OUTFITTER_SOURCE_DIR/prompts/zejent/SYSTEM.md" ]]; then
  echo "error: missing Zejent system prompt: $OUTFITTER_SOURCE_DIR/prompts/zejent/SYSTEM.md" >&2
  exit 1
fi

mkdir -p "$POD_STATE_DIR" "$outfitter_root_dir/profiles" "$outfitter_root_dir/prompts/zejent" "$PI_HOME_DIR"
PI_HOME_DIR="$(cd -- "$PI_HOME_DIR" && pwd -P)"

# Prefer the already-cloned Link profile catalog on the host so startup does not
# depend on cloning the private ai-outfitter/link repository from inside the
# container. This also avoids requiring broad GitHub token permissions for the
# common local workflow. The remote Link source can still be used by pointing
# ZEJENT_LINK_OUTFITTER_DIR at another checkout before launch.
install_flat_profiles() {
  local source_dir="$1"
  local profile_file profile_id profile_dir
  if [[ ! -d "$source_dir" ]]; then
    return 0
  fi
  for profile_file in "$source_dir"/*.yml "$source_dir"/*.yaml; do
    [[ -e "$profile_file" ]] || continue
    profile_id="$(basename -- "$profile_file")"
    profile_id="${profile_id%.yml}"
    profile_id="${profile_id%.yaml}"
    profile_dir="$outfitter_root_dir/profiles/$profile_id"
    mkdir -p "$profile_dir"
    cp "$profile_file" "$profile_dir/profile.yml"
  done
}

if [[ -d "$LINK_OUTFITTER_DIR" ]]; then
  for dir in prompts skills deepwork; do
    if [[ -d "$LINK_OUTFITTER_DIR/$dir" ]]; then
      mkdir -p "$outfitter_root_dir/$dir"
      cp -R "$LINK_OUTFITTER_DIR/$dir/." "$outfitter_root_dir/$dir/"
    fi
  done
  install_flat_profiles "$LINK_OUTFITTER_DIR/profiles"
else
  echo "warning: Link Outfitter checkout not found at $LINK_OUTFITTER_DIR; zejent profile inheritance may fail unless profiles are already present in $outfitter_root_dir" >&2
fi

install_flat_profiles "$OUTFITTER_SOURCE_DIR/profiles"
if [[ -d "$OUTFITTER_SOURCE_DIR/profiles/zejent" ]]; then
  mkdir -p "$outfitter_root_dir/profiles/zejent"
  cp -R "$OUTFITTER_SOURCE_DIR/profiles/zejent/." "$outfitter_root_dir/profiles/zejent/"
fi
cp "$OUTFITTER_SOURCE_DIR/prompts/zejent/SYSTEM.md" "$outfitter_root_dir/prompts/zejent/SYSTEM.md"

# The local Link checkout can temporarily reference deleted feature branches.
# Keep Zejent startup resilient by using Pi's fragment-style git ref syntax
# instead of treating @main as part of the GitHub repository path.
find "$outfitter_root_dir/profiles" -name profile.yml -type f -print0 \
  | xargs -0 -r perl -pi -e \
      's|git:github\.com/ai-outfitter/deepwork\@fix/post-commit-review-reminder|git:github.com/ai-outfitter/deepwork#main|g; s|git:github\.com/ai-outfitter/deepwork\@main|git:github.com/ai-outfitter/deepwork#main|g'

# Outfitter 0.7+ treats raw append_system_prompt strings as literal text and
# warns when they look like paths. Convert Link/Zejent path-style prompt entries
# to typed file includes in the materialized runtime profiles without modifying
# the upstream Link checkout.
find "$outfitter_root_dir/profiles" -name profile.yml -type f -print0 \
  | xargs -0 -r perl -0pi -e 's{^(\s*)-\s*\.outfitter/([^\n{}]+\.md)\s*$}{$1- file: /root/.outfitter/$2}mg; s{^(\s*)-\s*(/root/\.outfitter/[^\n{}]+\.md)\s*$}{$1- file: $2}mg'

cat > "$outfitter_settings_file" <<'OUTFITTER_SETTINGS'
default_profile: zejent
default_agent: pi
profile_export: true

profile_sources:
  - path: /root/.outfitter/profiles
OUTFITTER_SETTINGS

if [[ "$SYNC_ONLY" == "1" ]]; then
  printf 'synced Outfitter profiles/prompts to %s\n' "$outfitter_root_dir" >&2
  exit 0
fi

read_secret_from_tty() {
  local prompt="$1"
  local value
  printf '%s' "$prompt" > /dev/tty
  IFS= read -r -s value < /dev/tty
  printf '\n' > /dev/tty
  printf '%s' "$value"
}

print_github_token_help() {
  cat > /dev/tty <<'GITHUB_HELP'

GitHub token setup
------------------
The agent container uses this token for gh, Git HTTPS, and Outfitter profile sync.
The token is stored as a Podman secret and is not written to the rendered pod YAML.

Create a fine-grained personal access token:
  https://github.com/settings/personal-access-tokens/new

Recommended repository access:
  - ai-outfitter/link
  - any private repositories this workspace needs to clone or sync

Minimum fine-grained permissions:
  - Repository permissions: Contents = Read-only
  - Repository permissions: Metadata = Read-only

If fine-grained tokens do not work for your private repo workflow, use a classic
PAT with the repo scope:
  https://github.com/settings/tokens/new?scopes=repo

GITHUB_HELP
}

create_github_secret() {
  local secret_name="$1"
  local token="$2"
  local encoded_token
  encoded_token="$(printf '%s' "$token" | base64 | tr -d '\n')"

  podman secret create "$secret_name" - >/dev/null <<SECRET_YAML
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
type: Opaque
data:
  github-token: $encoded_token
SECRET_YAML
}

resolve_github_token() {
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [[ -n "$token" ]]; then
    printf '%s' "$token"
    return 0
  fi

  print_github_token_help
  token="$(read_secret_from_tty 'Paste GitHub token (empty to continue without GitHub auth): ')"
  printf '%s' "$token"
}

github_secret_available=0
host_github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if podman secret exists "$GITHUB_TOKEN_SECRET"; then
  if [[ "$REPLACE_SECRET" == "1" ]]; then
    host_github_token="$(resolve_github_token)"
    if [[ -z "$host_github_token" ]]; then
      echo "error: cannot replace $GITHUB_TOKEN_SECRET without a GitHub token" >&2
      exit 1
    fi
    podman secret rm "$GITHUB_TOKEN_SECRET" >/dev/null
    create_github_secret "$GITHUB_TOKEN_SECRET" "$host_github_token"
    echo "replaced Podman secret: $GITHUB_TOKEN_SECRET" >&2
  fi
  github_secret_available=1
else
  host_github_token="$(resolve_github_token)"
  if [[ -n "$host_github_token" ]]; then
    create_github_secret "$GITHUB_TOKEN_SECRET" "$host_github_token"
    github_secret_available=1
    echo "created Podman secret: $GITHUB_TOKEN_SECRET" >&2
  else
    echo "continuing without GitHub auth; gh, private GitHub sync, and private Outfitter sync may fail." >&2
  fi
fi


yaml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}

WORKSPACE_Q="$(yaml_quote "$WORKSPACE")"
OUTFITTER_ROOT_DIR_Q="$(yaml_quote "$outfitter_root_dir")"
PI_HOME_DIR_Q="$(yaml_quote "$PI_HOME_DIR")"
IMAGE_REF_Q="$(yaml_quote "$IMAGE_REF")"

secret_fingerprint="none"
if [[ "$github_secret_available" == "1" ]]; then
  secret_fingerprint="$GITHUB_TOKEN_SECRET"
fi
template_hash="$(sha256sum "$TEMPLATE_FILE" | awk '{print $1}')"
CONFIG_HASH="$(printf '%s\0' "$IMAGE_REF" "$IMAGE_ID" "$WORKSPACE" "$CONTAINER_NAME" "$outfitter_settings_file" "$secret_fingerprint" "$PI_HOME_DIR" "$TMP_VOLUME_NAME" "$PI_SESSION_DIR" "$PI_SESSION_ID" "$PI_SESSION_NAME" "$OUTFITTER_SOURCE_DIR" "$template_hash" \
  | sha256sum \
  | awk '{print $1}')"

if [[ "$github_secret_available" == "1" ]]; then
  GITHUB_TOKEN_VOLUME_MOUNT='        - name: github-token
          mountPath: /run/secrets
          readOnly: true'
  GITHUB_TOKEN_VOLUME="    - name: github-token
      secret:
        secretName: $GITHUB_TOKEN_SECRET
        items:
          - key: github-token
            path: github-token"
else
  GITHUB_TOKEN_VOLUME_MOUNT=''
  GITHUB_TOKEN_VOLUME=''
fi

render_template() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      *__GITHUB_TOKEN_VOLUME_MOUNT__*)
        if [[ -n "$GITHUB_TOKEN_VOLUME_MOUNT" ]]; then
          printf '%s\n' "$GITHUB_TOKEN_VOLUME_MOUNT"
        fi
        ;;
      *__GITHUB_TOKEN_VOLUME__*)
        if [[ -n "$GITHUB_TOKEN_VOLUME" ]]; then
          printf '%s\n' "$GITHUB_TOKEN_VOLUME"
        fi
        ;;
      *)
        line="${line//__POD_NAME__/$POD_NAME}"
        line="${line//__CONTAINER_NAME__/$CONTAINER_NAME}"
        line="${line//__WORKSPACE_SLUG__/$workspace_slug}"
        line="${line//__WORKSPACE_Q__/$WORKSPACE_Q}"
        line="${line//__OUTFITTER_ROOT_DIR_Q__/$OUTFITTER_ROOT_DIR_Q}"
        line="${line//__PI_HOME_DIR_Q__/$PI_HOME_DIR_Q}"
        line="${line//__TMP_VOLUME_NAME__/$TMP_VOLUME_NAME}"
        line="${line//__IMAGE_REF__/$IMAGE_REF_Q}"
        line="${line//__CONFIG_HASH__/$CONFIG_HASH}"
        printf '%s\n' "$line"
        ;;
    esac
  done < "$TEMPLATE_FILE"
}

render_template > "$POD_YAML"

normalize_inspect_value() {
  local value="$1"
  if [[ "$value" == "<no value>" ]]; then
    printf ''
  else
    printf '%s' "$value"
  fi
}

inspect_pod_label() {
  podman pod inspect -f "{{ index .Labels \"$1\" }}" "$POD_NAME" 2>/dev/null || true
}

inspect_container_annotation() {
  podman inspect --type container -f "{{ index .Config.Annotations \"$1\" }}" "$CONTAINER_NAME" 2>/dev/null || true
}

play_pod() {
  if ! podman play kube --quiet --no-pod-prefix "$POD_YAML"; then
    cat >&2 <<EOF
error: podman play kube failed for $POD_YAML.
If $GITHUB_TOKEN_SECRET was created by the older podman-run launcher, remove it
or rerun with --replace-secret so it can be stored in Kubernetes Secret format
for podman play kube.
EOF
    exit 1
  fi
}

if podman pod exists "$POD_NAME"; then
  existing_kind="$(normalize_inspect_value "$(inspect_pod_label 'dev.ncrmro.agent.kind')")"
  existing_workspace="$(normalize_inspect_value "$(inspect_container_annotation 'dev.ncrmro.agent.workspace')")"
  existing_hash="$(normalize_inspect_value "$(inspect_container_annotation 'dev.ncrmro.agent.config-hash')")"

  if [[ "$existing_kind" != "nix-zellij" || "$existing_workspace" != "$WORKSPACE" ]]; then
    printf 'error: pod %s already exists for workspace %s (kind=%s). Set POD_NAME/CONTAINER_NAME or remove the pod.\n' \
      "$POD_NAME" "${existing_workspace:-unknown}" "${existing_kind:-unknown}" >&2
    exit 1
  fi

  if [[ "$FORCE_RECREATE" == "1" ]]; then
    podman kube down "$POD_YAML" >/dev/null 2>&1 || podman pod rm -f "$POD_NAME" >/dev/null
    play_pod
  elif [[ "$existing_hash" != "$CONFIG_HASH" ]]; then
    printf 'warning: generated pod YAML differs from existing pod %s; keeping existing pod. Re-run with --replace to recreate it.\n' "$POD_NAME" >&2
  fi
else
  if podman container exists "$CONTAINER_NAME"; then
    printf 'error: container %s already exists outside pod %s. Set CONTAINER_NAME/POD_NAME or remove the container.\n' \
      "$CONTAINER_NAME" "$POD_NAME" >&2
    exit 1
  fi
  play_pod
fi

pod_state="$(podman pod inspect -f '{{.State}}' "$POD_NAME")"
if [[ "$pod_state" != "Running" ]]; then
  podman pod start "$POD_NAME" >/dev/null
fi

if ! podman container exists "$CONTAINER_NAME"; then
  printf 'error: expected container %s was not created by pod %s. Inspect %s.\n' \
    "$CONTAINER_NAME" "$POD_NAME" "$POD_YAML" >&2
  exit 1
fi

exec_env_args=(
  --env "AGENT_ZELLIJ_SESSION_NAME=$SESSION_NAME"
  --env "LEADER_AGENT_CMD=$LEADER_AGENT_CMD"
  --env "PI_SESSION_ID=$PI_SESSION_ID"
  --env "PI_SESSION_NAME=$PI_SESSION_NAME"
  --env "PI_CODING_AGENT_SESSION_DIR=$PI_SESSION_DIR"
  --env "GITHUB_TOKEN_FILE=$GITHUB_TOKEN_FILE"
  --env "GIT_ASKPASS=/bin/github-token-askpass"
  --env "GIT_TERMINAL_PROMPT=0"
)

printf 'workspace: %s\nwork context: %s\npod: %s\ncontainer: %s\nzellij session: %s\nkube yaml: %s\noutfitter root: %s -> %s\nzejent profile: %s -> %s\ngithub secret: %s\npi home: %s -> %s (read-only)\ntmp volume: %s -> %s\npi session dir: %s\npi session id: %s\npi session name: %s\n' \
  "$WORKSPACE" "$WORK_CONTEXT_SLUG" "$POD_NAME" "$CONTAINER_NAME" "$SESSION_NAME" "$POD_YAML" "$outfitter_root_dir" "/root/.outfitter" "$OUTFITTER_SOURCE_DIR/profiles/zejent.yml" "/root/.outfitter/profiles/zejent.yml" "$GITHUB_TOKEN_SECRET" "$PI_HOME_DIR" "/root/.pi" "$TMP_VOLUME_NAME" "/tmp" "$PI_SESSION_DIR" "$PI_SESSION_ID" "$PI_SESSION_NAME" >&2

if [[ "$NO_ATTACH" == "1" ]]; then
  printf 'pod %s is running; attach later with: %s %s\n' "$POD_NAME" "$0" "$WORKSPACE" >&2
  exit 0
fi

saved_tty=""
if [[ -t 0 ]]; then
  saved_tty="$(stty -g 2>/dev/null || true)"
fi

cleanup_tty() {
  local exit_code=$?

  # podman exec -it + zellij can leave the host terminal in raw/alternate-screen
  # mode when interrupted. Restore the saved tty mode and emit conservative ANSI
  # resets before returning control to the caller's shell.
  if [[ -n "${saved_tty:-}" ]]; then
    stty "$saved_tty" 2>/dev/null || stty sane 2>/dev/null || true
  else
    stty sane 2>/dev/null || true
  fi
  printf '\033[?1049l\033[?25h\033[0m' >&2

  trap - EXIT INT TERM
  exit "$exit_code"
}
trap cleanup_tty EXIT INT TERM

podman exec -it \
  --workdir "$WORKSPACE" \
  "${exec_env_args[@]}" \
  "$CONTAINER_NAME" \
  /bin/agent-zellij
