{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
  rustPlatform,
  codex,
  git,
  tmux,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash npmDepsHash;

  src = fetchFromGitHub {
    owner = "Yeachan-Heo";
    repo = "oh-my-codex";
    rev = "v${version}";
    inherit hash;
  };

  nativeTools = rustPlatform.buildRustPackage {
    pname = "oh-my-codex-native-tools";
    inherit version src;

    cargoLock.lockFile = ./Cargo.lock;
    cargoBuildFlags = [
      "--workspace"
      "--bins"
    ];

    doCheck = false;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      for bin in omx-api omx-explore-harness omx-runtime omx-sparkshell; do
        candidate="$(find target -type f -path "*/release/$bin" -perm -0100 | head -n 1)"
        if [ -z "$candidate" ]; then
          echo "missing expected native OMX binary: $bin" >&2
          find target -maxdepth 4 -type f -path '*/release/*' >&2 || true
          exit 1
        fi
        cp "$candidate" "$out/bin/$bin"
      done

      runHook postInstall
    '';

    meta = {
      description = "Native helper binaries for oh-my-codex";
      homepage = "https://github.com/Yeachan-Heo/oh-my-codex";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };
in
buildNpmPackage {
  pname = "oh-my-codex";
  inherit
    version
    src
    npmDepsHash
    nodejs
    ;

  npmFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build";

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
        substituteInPlace src/cli/plugin-marketplace.ts \
          --replace-fail 'import { cp, readdir, readFile, rm, writeFile } from "fs/promises";' \
            'import { chmod, cp, readdir, readFile, rm, writeFile } from "fs/promises";' \
          --replace-fail 'async function applyTeamModeToPluginCache' \
            'async function makePluginCacheWritable(cacheDir: string): Promise<void> {
      async function visit(dir: string): Promise<void> {
        await chmod(dir, 0o755).catch(() => undefined);
        const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
        for (const entry of entries) {
          const path = join(dir, entry.name);
          if (entry.isDirectory()) {
            await visit(path);
          } else {
            await chmod(path, 0o644).catch(() => undefined);
          }
        }
      }
      await visit(cacheDir);
    }

    async function applyTeamModeToPluginCache' \
          --replace-fail 'await cp(packagedMarketplace.pluginRoot, cacheDir, { recursive: true });
    		await applyTeamModeToPluginCache(cacheDir, options.teamMode);' \
            'await cp(packagedMarketplace.pluginRoot, cacheDir, { recursive: true });
    		await makePluginCacheWritable(cacheDir);
    		await applyTeamModeToPluginCache(cacheDir, options.teamMode);'
  '';

  postInstall = ''
    wrapProgram "$out/bin/omx" \
      --set OMX_EXPLORE_BIN "${nativeTools}/bin/omx-explore-harness" \
      --set OMX_SPARKSHELL_BIN "${nativeTools}/bin/omx-sparkshell" \
      --set OMX_API_BIN "${nativeTools}/bin/omx-api" \
      --set OMX_RUNTIME_BINARY "${nativeTools}/bin/omx-runtime" \
      --prefix PATH : "${
        lib.makeBinPath [
          codex
          git
          tmux
        ]
      }"
  '';

  passthru = {
    inherit nativeTools;
  };

  meta = {
    description = "Workflow layer for OpenAI Codex CLI";
    homepage = "https://github.com/Yeachan-Heo/oh-my-codex";
    license = lib.licenses.mit;
    mainProgram = "omx";
    platforms = lib.platforms.unix;
  };
}
