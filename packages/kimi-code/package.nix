{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeWrapper,
  fd,
  ripgrep,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version;

  releasePlatform =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "Unsupported Kimi Code platform: ${stdenv.hostPlatform.system}");

  src = fetchurl {
    url = "https://github.com/MoonshotAI/kimi-code/releases/download/%40moonshot-ai/kimi-code%40${version}/kimi-code-${releasePlatform}.zip";
    hash = versionData.hashes.${stdenv.hostPlatform.system};
  };
in
stdenv.mkDerivation {
  pname = "kimi-code";
  inherit version src;

  dontUnpack = true;
  # The release binary embeds a Node SEA blob. Stripping rewrites ELF metadata
  # used by the embedded payload and makes the executable crash at startup.
  dontStrip = true;

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    unzip "$src"
    install -Dm755 kimi "$out/bin/kimi"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/kimi" \
      --prefix PATH : ${
        lib.makeBinPath [
          ripgrep
          fd
        ]
      }
  '';

  meta = {
    description = "Kimi Code CLI - terminal coding agent from Moonshot AI";
    homepage = "https://github.com/MoonshotAI/kimi-code";
    changelog = "https://github.com/MoonshotAI/kimi-code/releases/tag/%40moonshot-ai%2Fkimi-code%40${version}";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.mit;
    mainProgram = "kimi";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
