{
  description = "Minimal Podman agent image with Zellij, lazygit, Pi, and Outfitter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          # Flake-owned npm CLI installation. There is intentionally no
          # repo-local package.json/package-lock.json: npm packages are pinned
          # here and materialized by Nix. The fixed-output derivation fetches
          # npm contents only; the normal derivation adds wrappers that refer to
          # Nix store paths.
          npmGlobal = pkgs.stdenvNoCC.mkDerivation {
            pname = "agent-container-node-tools-npm-global";
            version = "0.0.0";

            nativeBuildInputs = [ pkgs.nodejs_22 pkgs.cacert ];

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = "sha256-BEIk2RCvCp64BTKUrvF55vSzByt5eu9kXNae4io+3rE=";

            buildCommand = ''
              export HOME="$TMPDIR/home"
              export npm_config_cache="$TMPDIR/npm-cache"
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              mkdir -p "$HOME" "$out"

              npm install --global --prefix "$out" --ignore-scripts \
                @earendil-works/pi-coding-agent@0.80.2 \
                @ai-outfitter/outfitter@0.7.2 \
                ajv@8.17.1 \
                yaml@2.8.1

              # Fixed-output derivations cannot contain references to arbitrary
              # Nix store paths. Keep this output as npm material only; wrappers
              # are created in nodeTools below.
              rm -rf "$out/bin"
            '';
          };

          nodeTools = pkgs.stdenvNoCC.mkDerivation {
            pname = "agent-container-node-tools";
            version = "0.0.0";
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontUnpack = true;
            installPhase = ''
              mkdir -p "$out/lib" "$out/bin"
              cp -R ${npmGlobal}/lib/node_modules "$out/lib/"
              chmod -R u+w "$out/lib/node_modules"

              makeWrapper ${pkgs.nodejs_22}/bin/node "$out/bin/pi" \
                --add-flags "$out/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
                --set NODE_PATH "$out/lib/node_modules" \
                --prefix PATH : ${lib.makeBinPath [ pkgs.bashInteractive pkgs.coreutils pkgs.git pkgs.ripgrep pkgs.zsh ]}
              makeWrapper ${pkgs.nodejs_22}/bin/node "$out/bin/outfitter" \
                --add-flags "$out/lib/node_modules/@ai-outfitter/outfitter/dist/cli.js" \
                --set NODE_PATH "$out/lib/node_modules" \
                --prefix PATH : ${lib.makeBinPath [ pkgs.bashInteractive pkgs.coreutils pkgs.git pkgs.ripgrep pkgs.zsh ]}
            '';
          };

          containerFiles = pkgs.stdenvNoCC.mkDerivation {
            pname = "agent-container-files";
            version = "0.0.0";
            src = ./container;
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              mkdir -p "$out"
              cp -R . "$out/"
              if [ -d "$out/bin" ]; then
                find "$out/bin" -type f -exec chmod 0755 {} +
              fi
            '';
          };

          # The image ships a source-controlled /bin/gh wrapper that injects a
          # token from /run/secrets/github-token. Expose the real gh binary under
          # a different name to avoid a /bin/gh collision in buildEnv.
          ghReal = pkgs.runCommand "agent-gh-real" { } ''
            mkdir -p "$out/bin"
            ln -s ${pkgs.gh}/bin/gh "$out/bin/gh-real"
          '';

          imagePackages = [
            pkgs.bashInteractive
            pkgs.cacert
            pkgs.coreutils
            pkgs.curl
            pkgs.findutils
            pkgs.git
            pkgs.helix
            ghReal
            pkgs.gnugrep
            pkgs.gnused
            pkgs.gnutar
            pkgs.gzip
            pkgs.less
            pkgs.lazygit
            pkgs.bash-language-server
            pkgs.docker-compose-language-service
            pkgs.dockerfile-language-server
            pkgs.harper
            pkgs.helm-ls
            pkgs.marksman
            pkgs.nil
            pkgs.nixfmt-rfc-style
            pkgs.nodejs_22
            pkgs.nix
            pkgs.openssh
            pkgs.pandoc
            pkgs.prettier
            pkgs.ripgrep
            pkgs.ruby-lsp
            pkgs.solargraph
            pkgs.typescript
            pkgs.typescript-language-server
            pkgs.vscode-langservers-extracted
            pkgs.which
            pkgs.wl-clipboard
            pkgs.xdg-utils
            pkgs.yaml-language-server
            pkgs.zk
            pkgs.zellij
            pkgs.zsh
            nodeTools
            containerFiles
          ];

          imageRoot = pkgs.buildEnv {
            name = "agent-image-root";
            paths = imagePackages ++ [ pkgs.dockerTools.fakeNss ];
            pathsToLink = [ "/bin" "/etc" ];
          };

          imageName = "localhost/nix-zellij-agent";
          imageTag = "dev";

          image = pkgs.dockerTools.buildLayeredImage {
            name = imageName;
            tag = imageTag;
            contents = [ imageRoot ];
            extraCommands = ''
              # Nixpkgs zsh ships a compiled /etc/zshenv.zwc that re-sources
              # /etc/zshenv in non-NixOS containers, causing recursion when we
              # provide our own /etc/zshenv. Remove the compiled companion so
              # zsh reads the plain text file from container/etc/zshenv.
              rm -f etc/zshenv.zwc etc/zshenv_zwc_is_used

              mkdir -p tmp root/.config/gh root/.outfitter workspace
              if [ -d ${containerFiles}/root ]; then
                cp -R ${containerFiles}/root/. root/
              fi
              chmod 1777 tmp
            '';
            config = {
              Cmd = [ "/bin/agent-zellij" ];
              WorkingDir = "/workspace";
              Env = [
                "PATH=/bin:${lib.makeBinPath imagePackages}"
                "HOME=/root"
                "EDITOR=hx"
                "VISUAL=hx"
                "XDG_CONFIG_HOME=/root/.config"
                "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "GITHUB_TOKEN_FILE=/run/secrets/github-token"
                "GIT_ASKPASS=/bin/github-token-askpass"
                "GIT_TERMINAL_PROMPT=0"
                "NODE_PATH=${nodeTools}/lib/node_modules"
                "TERM=xterm-256color"
              ];
            };
          };
        in
        {
          default = image;
          image = image;
          node-tools = nodeTools;
          container-files = containerFiles;
        });
    };
}
