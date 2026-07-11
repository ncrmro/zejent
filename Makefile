# Quick ways to test Zejent in different environments. `make help` lists targets.
#
# Common knobs (override like `make dev WORKSPACE=/path/to/repo`):
#   WORKSPACE    workspace directory to mount (default: this repo)
#   RUN_ARGS     extra flags for run-image.sh (e.g. RUN_ARGS=--replace)

WORKSPACE    ?= $(CURDIR)
IMAGE        ?= localhost/nix-zellij-agent:dev
REPO         ?= ncrmro/zejent
KIND_CLUSTER ?= zejent
KIND_POD     ?= zejent-kind
CODE_BIN     ?= $(shell command -v code 2>/dev/null || echo "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")
KIND_TAR     := $(if $(TMPDIR),$(TMPDIR),/tmp/)zejent-kind-image.tar

.PHONY: help image dev vscode codespace kind kind-down

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

image: ## Build the image with Nix and load it into Podman
	code/build-image.sh

dev: ## Terminal: launch/attach the workspace pod + Zellij session
	@podman image exists $(IMAGE) || $(MAKE) image
	code/run-image.sh $(RUN_ARGS) $(WORKSPACE)

# Note: `outfitter run -- -p` currently answers but does not exit afterwards,
# so the test launches it detached, polls the log for the expected reply, and
# reaps the lingering process either way.
test: ## Smoke test: Pi starts inside the pod and answers a prompt
	@podman image exists $(IMAGE) || $(MAKE) image
	code/run-image.sh --no-attach $(RUN_ARGS) $(WORKSPACE)
	@slug=$$(basename "$(WORKSPACE)" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed -E 's/^-+//; s/-+$$//; s/-+/-/g'); \
	c="zejent-$$slug"; log=/tmp/zejent-make-test.log; \
	echo "asking Pi for a reply in $$c…"; \
	podman exec "$$c" rm -f "$$log"; \
	podman exec -d --workdir "$(WORKSPACE)" "$$c" \
	  sh -lc "outfitter run --profile zejent -- --no-session -p 'Reply with exactly: ZEJENT-OK' > $$log 2>&1"; \
	pass=0; \
	for i in $$(seq 1 60); do \
	  podman exec "$$c" grep -q "ZEJENT-OK" "$$log" 2>/dev/null && { pass=1; break; }; \
	  sleep 5; \
	done; \
	podman exec "$$c" bash -c 'for d in /proc/[0-9]*; do case "$$(tr "\0" " " < "$$d/cmdline" 2>/dev/null)" in *no-session*ZEJENT-OK*) kill "$${d\#/proc/}" 2>/dev/null;; esac; done; true'; \
	podman exec "$$c" tail -3 "$$log"; \
	[ "$$pass" = "1" ] && echo "PASS: Pi responded" \
	  || { echo "FAIL: Pi did not answer within 5 minutes"; exit 1; }

vscode: ## VS Code: open this repo in its local dev container (.devcontainer, no Codespaces)
	@podman image exists ghcr.io/ncrmro/zejent:latest || \
	  { podman image exists $(IMAGE) && podman tag $(IMAGE) ghcr.io/ncrmro/zejent:latest; } || true
	@"$(CODE_BIN)" --list-extensions 2>/dev/null | grep -qi '^ms-vscode-remote.remote-containers$$' || \
	  "$(CODE_BIN)" --install-extension ms-vscode-remote.remote-containers
	@hex=$$(printf '%s' "$(CURDIR)" | xxd -p | tr -d '\n'); \
	echo "opening VS Code dev container for $(CURDIR)"; \
	echo "note: the Dev Containers extension must use podman (dev.containers.dockerPath=podman)"; \
	"$(CODE_BIN)" --folder-uri "vscode-remote://dev-container+$$hex$(CURDIR)"

codespace: ## GitHub Codespaces: reuse (or create) a codespace on $(REPO) and ssh in
	@cs=$$(gh codespace list -R $(REPO) --json name -q '.[0].name' 2>/dev/null); \
	if [ -z "$$cs" ]; then \
	  branch=$$(git rev-parse --abbrev-ref HEAD); \
	  echo "creating codespace on $(REPO)@$$branch…"; \
	  cs=$$(gh codespace create -R $(REPO) -b "$$branch"); \
	fi; \
	echo "connecting to codespace $$cs"; \
	gh codespace ssh -c "$$cs"

kind: ## kind: load the image into a local k8s cluster and attach via kubectl exec
	@command -v kind >/dev/null || { echo "kind is not installed (brew install kind)"; exit 1; }
	@podman image exists $(IMAGE) || $(MAKE) image
	@kind get clusters 2>/dev/null | grep -qx $(KIND_CLUSTER) || \
	  KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name $(KIND_CLUSTER)
	podman save $(IMAGE) -o "$(KIND_TAR)"
	KIND_EXPERIMENTAL_PROVIDER=podman kind load image-archive "$(KIND_TAR)" --name $(KIND_CLUSTER)
	rm -f "$(KIND_TAR)"
	kubectl --context kind-$(KIND_CLUSTER) apply -f code/templates/kind-test-pod.yaml
	kubectl --context kind-$(KIND_CLUSTER) wait --for=condition=Ready pod/$(KIND_POD) --timeout=180s
	kubectl --context kind-$(KIND_CLUSTER) exec -it $(KIND_POD) -- /bin/agent-zellij

# DevPod's Kubernetes driver builds the devcontainer inside the cluster
# ("dockerless"), so the pod needs pull access to ghcr.io/ncrmro/zejent. We
# mint an ephemeral docker-format credential file from `gh auth token` and
# scope it to the devpod invocation via DOCKER_CONFIG — nothing persistent.
# First `up` builds in-pod (needs a podman machine with >=8GB memory:
# `podman machine set --memory 8192`); later ups reuse the workspace volume.
devpod-kind: ## DevPod: run the devcontainer on the local kind cluster (Kubernetes provider)
	@command -v devpod >/dev/null || { echo "devpod is not installed (brew install devpod)"; exit 1; }
	@command -v kind >/dev/null || { echo "kind is not installed (brew install kind)"; exit 1; }
	@kind get clusters 2>/dev/null | grep -qx $(KIND_CLUSTER) || \
	  KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name $(KIND_CLUSTER)
	@devpod provider add kubernetes 2>/dev/null || true
	@tmpcfg=$$(mktemp -d); \
	gh auth token | podman login ghcr.io -u "$$(gh api user -q .login)" --password-stdin --authfile "$$tmpcfg/config.json" >/dev/null; \
	DOCKER_CONFIG="$$tmpcfg" devpod up . --provider kubernetes \
	  --provider-option KUBERNETES_CONTEXT=kind-$(KIND_CLUSTER) \
	  --ide none; \
	status=$$?; rm -rf "$$tmpcfg"; exit $$status
	@echo "attach: devpod ssh zejent   (then: agent-zellij)"

kind-down: ## kind: delete the test cluster
	KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name $(KIND_CLUSTER)
