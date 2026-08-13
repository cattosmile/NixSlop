# Architecture

## Why NixSlop is a modular monorepo now

NixSlop has one consumer-facing job: expose a coherent set of fast-moving tools
through stable Home Manager and NixOS interfaces. Keeping that public flake in
one repository currently gives three concrete guarantees:

1. A package update and every module default that refers to it can be validated
   atomically.
2. Cross-package dependencies stay visible. For example, the `oh-my-codex`
   wrapper embeds the NixSlop Codex package in its executable path, so a Codex
   pin update must also rebuild and smoke-test OMX.
3. Compatibility checks can evaluate all public packages, modules, generated
   files, and supported systems against one lock file before a pull request is
   merged.

The monorepo is modular rather than monolithic: `flake.nix` assembles components
but package construction, modules, checks, development tooling, and automation
each have their own ownership boundary.

## Component boundaries

| Area | Owned files | Responsibility |
| --- | --- | --- |
| Flake assembly | `flake.nix`, `flake.lock` | Inputs and stable public output names |
| Packages | `packages/` | Package derivations, source pins, desktop package, updater scripts |
| Home Manager | `modules/home-manager/` | Aggregate, program integrations, and user-session services |
| NixOS | `modules/nixos/` | Optional Computer Use system-service fallback |
| Checks | `nix/checks.nix`, `tests/` | Output, module, generated-file, updater, and workflow contracts |
| Development shell | `nix/dev-shells.nix` | Repository maintenance tools |
| Automation | `.github/workflows/`, `scripts/validate_update.py` | Fixed-target updates, PR lifecycle, health sentinel |

Package modules may select NixSlop package outputs as defaults, but consumer
configuration and secrets stay outside this repository. The Home Manager
modules own user packages, generated files, and user-session services. The
NixOS module is retained only as a legacy fallback for systems that need a
system-level ydotool daemon or device/group integration. The official ChatGPT
Desktop package is also exposed as an opt-in NixSlop Computer Use variant. That
variant keeps OpenAI's official executable, Electron runtime, native modules,
and FHS layout intact, then stages the community Linux plugin and its feature
patches into the official app while replacing only the native helper with
NixSlop's Hyprland-first and grim-enabled backend. The Hyprland adapter changes
only the virtual ydotool device, not physical keyboard layouts. When the UI
variant is enabled, the Home Manager activation also registers the local
`computer-use@openai-bundled` plugin in Codex's mutable plugin configuration;
the immutable package alone only makes that plugin available in the bundled
marketplace.

## Public compatibility boundary

The following are intentionally stable:

- The package outputs `codex`, `chatgpt-desktop`, and `oh-my-codex`.
- The historical `codex-desktop` and `codex-computer-use-linux` outputs remain
  aliases of `chatgpt-desktop`; `codex-desktop-computer-use-ui` is the explicit
  patched variant.
- Aggregate Home Manager modules `default` and `nixslop`.
- Individual Home Manager module names and their historical option paths.
- NixOS modules `default` and `codexComputerUse`.
- `programs.codexDesktopLinux.computerUseUi.enable` selects the official-app
  Linux Computer Use variant; historical package override arguments remain
  accepted for compatibility.
- The isolated US mapping for `ydotoold-virtual-device` and its explicit
  Home Manager opt-out.

The desktop contract verifies the pinned official package, its launcher and
desktop entry, and the bundled native Linux Computer Use helper. Feature
availability is owned by the official application rather than by NixSlop patch
reports.

Regression checks evaluate this boundary on every pull request and push to
`main`. Moving implementation files does not authorize a public rename.

## Configuration ownership

The aggregate module exposes the central `programs.nixslop` convenience facade
and composes the Codex Desktop, Computer Use, and OMX integrations without
owning their implementation. Its options project weak defaults onto the
historical module paths, so explicit legacy settings still win. Native Home
Manager modules remain the canonical owners of
Codex files:

- `programs.codex` owns declarative Codex settings and context when
  `programs.codexOmx.setupPlugin = false`.
- Mutable `omx setup --plugin` owns Codex configuration when
  `programs.codexOmx.setupPlugin = true`; the module rejects simultaneous
  native Codex file generation.
- `programs.codexOmx.restoreDefaultPlugins` owns the additive registration of
  Codex's shipped default plugin IDs and repairs the NixSlop-managed Computer
  Use cache wrapper when it points at an older helper. It invokes the Codex CLI
  after OMX, skips unavailable runtime marketplaces, and never owns
  authentication, account slots, skills, or unrelated plugin entries. Native
  Home Manager Codex configuration is left to its declarative plugin options
  instead.
- `programs.codexComputerUse` owns the legacy user-space Computer Use runtime: the
  AT-SPI D-Bus and systemd user units, the ydotool client, the per-user
  `ydotoold` service, and `YDOTOOL_SOCKET`. When the legacy NixOS module is
  present, it reuses that module's system socket instead of starting a second
  daemon.
- `programs.nixslop` is the consumer-facing setup facade. Its `codex` and
  `omx` selectors target the current combined Codex/OMX module; `desktop` selects
  the official ChatGPT Desktop package, `desktop.computerUseUi` selects the
  patched Linux Computer Use variant, and `computerUse` provides its optional
  ydotool/AT-SPI fallback integration. The historical option paths remain
  public for advanced configuration and compatibility.
- `nixosModules.codexComputerUse` remains a compatibility boundary for systems
  that need a system-level `ydotoold` service or NixOS-wide device/group
  integration. It is not required for the normal Home Manager setup.
This single-owner rule prevents two activation paths from rewriting the same
file with different models of state.

## Future repository split boundary

A split becomes useful when a component needs independent maintainers, release
cadence, CI capacity, or binary-cache policy. The natural candidates are
package-source repositories, not the consumer interface.

If a split happens, this repository should remain the compatibility facade:

1. External package flakes expose versioned package outputs.
2. NixSlop follows those inputs and preserves its existing package and module
   names.
3. Home Manager and NixOS modules remain here while they coordinate multiple
   packages or shared system integration.
4. Contract tests run against the composed external inputs before any lock
   update merges.

No external repository is required for the current design. Splitting files
without independent ownership would add cross-repository coordination while
removing the atomic validation that the update workflows rely on.
