#!/usr/bin/env bash
# Install Agent Orchestrator (ao CLI + desktop app) from a local checkout.
#
#   scripts/install-local.sh [--mode package|dev|daemon|deb] [--prefix DIR]
#                            [--app-dir DIR] [--skip-deps] [--skip-prepare]
#                            [--update-desktop] [--no-dpkg]
#
#   package  (default) builds the packaged Electron app + Go daemon, installs
#                      the app bundle under ~/.local/share/agent-orchestrator,
#                      installs `ao` and an `agent-orchestrator` wrapper under
#                      ~/.local/bin. No sudo required.
#   dev                warms frontend deps/helpers and installs a source-linked
#                      `agent-orchestrator` launcher (`electron-forge start`) +
#                      `ao` CLI. Edits are live.
#   daemon             fast path: builds and installs only the Go `ao` binary.
#   deb                builds a Linux .deb via electron-forge make and installs
#                      it with `sudo dpkg -i` (pass --no-dpkg to only build).
#
# Run from anywhere; the script locates the repository through its own path.
# See FORK.md for prerequisites and workflow details.
set -euo pipefail

MODE="package"
PREFIX="${HOME}/.local/bin"
APP_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/agent-orchestrator"
SKIP_DEPS=0
SKIP_PREPARE=0
UPDATE_DESKTOP=0
NO_DPKG=0

usage() {
	cat <<'EOF'
Install Agent Orchestrator from this repository.

Usage: scripts/install-local.sh [options]

Options:
  --mode package|dev|daemon|deb  Install mode (default: package).
  --prefix DIR                   Bin directory for `ao` and `agent-orchestrator`
                                 (default: ~/.local/bin).
  --app-dir DIR                  Package mode: app bundle install directory
                                 (default: ~/.local/share/agent-orchestrator).
  --skip-deps                    Skip frontend dependency install (`npm ci` / `dev:warm`).
  --skip-prepare                 Skip prepackage/premake/dev-prepare asset builds.
  --update-desktop               Update ~/.local/share/applications/agent-orchestrator.desktop
                                 to launch the installed wrapper.
  --no-dpkg                      Deb mode: build .deb without running `sudo dpkg -i`.
  -h, --help                     Show this help.

Modes:
  package   Builds the Go daemon and packaged Electron app (no sudo). Installs
            the bundle into --app-dir and wrappers into --prefix.
  dev       Runs `npm run dev:warm` and installs a wrapper that runs
            `electron-forge start` directly from this checkout.
  daemon    Builds only the Go `ao` CLI/daemon and installs it into --prefix.
  deb       Builds a Debian package and installs it system-wide via dpkg.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--mode)
			if [ $# -lt 2 ] || [ -z "$2" ]; then
				printf 'install-local: --mode needs a value\n' >&2
				exit 2
			fi
			MODE="$2"
			shift 2
			;;
		--mode=*)
			MODE="${1#*=}"
			shift
			;;
		--prefix)
			if [ $# -lt 2 ] || [ -z "$2" ]; then
				printf 'install-local: --prefix needs a value\n' >&2
				exit 2
			fi
			PREFIX="$2"
			shift 2
			;;
		--prefix=*)
			PREFIX="${1#*=}"
			shift
			;;
		--app-dir)
			if [ $# -lt 2 ] || [ -z "$2" ]; then
				printf 'install-local: --app-dir needs a value\n' >&2
				exit 2
			fi
			APP_DIR="$2"
			shift 2
			;;
		--app-dir=*)
			APP_DIR="${1#*=}"
			shift
			;;
		--skip-deps)
			SKIP_DEPS=1
			shift
			;;
		--skip-prepare)
			SKIP_PREPARE=1
			shift
			;;
		--update-desktop)
			UPDATE_DESKTOP=1
			shift
			;;
		--no-dpkg)
			NO_DPKG=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			printf 'install-local: unknown argument: %s\n\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
done

case "$MODE" in
	package | dev | daemon | deb) ;;
	*)
		printf 'install-local: --mode must be "package", "dev", "daemon", or "deb", got "%s"\n' "$MODE" >&2
		exit 2
		;;
esac

while [[ "$PREFIX" == */ && "$PREFIX" != "/" ]]; do PREFIX="${PREFIX%/}"; done
while [[ "$APP_DIR" == */ && "$APP_DIR" != "/" ]]; do APP_DIR="${APP_DIR%/}"; done
if [ -z "$PREFIX" ] || [ "$PREFIX" = "/" ]; then
	printf 'install-local: invalid --prefix "%s"\n' "$PREFIX" >&2
	exit 2
fi
if [ -z "$APP_DIR" ] || [ "$APP_DIR" = "/" ]; then
	printf 'install-local: invalid --app-dir "%s"\n' "$APP_DIR" >&2
	exit 2
fi

step() { printf '\n▶ %s\n' "$1"; }
done_step() { printf '✓ %s\n' "$1"; }

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		printf 'install-local: "%s" not found on PATH\n' "$1" >&2
		exit 1
	}
}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$REPO_ROOT"

install_ao_binary() {
	local src="$1"
	[ -f "$src" ] || {
		printf 'install-local: built ao binary missing at %s\n' "$src" >&2
		exit 1
	}
	step "install ao binary into $PREFIX/ao"
	mkdir -p "$PREFIX"
	# Remove first so a symlink target is replaced rather than followed.
	rm -f "$PREFIX/ao"
	install -m 755 "$src" "$PREFIX/ao"
}

write_launcher_wrapper() {
	local target_cmd="$1"
	local wrapper="$PREFIX/agent-orchestrator"
	step "install desktop launcher wrapper into $wrapper"
	mkdir -p "$PREFIX"
	rm -f "$wrapper"
	cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Work around modernc.org/sqlite failing to scan Go timestamps written in
# numeric-abbreviation timezones (e.g. Asia/Tehran "+0330 +0330") and allow
# Electron's Node fetch() to honor HTTP_PROXY/HTTPS_PROXY.
export TZ="\${AO_TZ:-UTC}"
export NODE_USE_ENV_PROXY="\${NODE_USE_ENV_PROXY:-1}"

${target_cmd}
EOF
	chmod 755 "$wrapper"
}

update_desktop_entry() {
	local desktop_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
	local desktop_file="${desktop_dir}/agent-orchestrator.desktop"
	local icon_dest="${XDG_DATA_HOME:-${HOME}/.local/share}/icons/hicolor/1024x1024/apps/agent-orchestrator.png"
	local icon_src="${REPO_ROOT}/frontend/assets/icon.png"

	step "update desktop entry ($desktop_file)"
	mkdir -p "$desktop_dir"
	if [ -f "$icon_src" ]; then
		mkdir -p "$(dirname -- "$icon_dest")"
		cp "$icon_src" "$icon_dest"
	fi

	local proxy_args=""
	if [ -n "${HTTPS_PROXY:-${HTTP_PROXY:-}}" ]; then
		local proxy_url="${HTTPS_PROXY:-${HTTP_PROXY}}"
		proxy_args=" --proxy-server=${proxy_url} \"--proxy-bypass-list=localhost;127.0.0.1;::1\""
	fi

	cat >"$desktop_file" <<EOF
[Desktop Entry]
Name=Orchestrator
Comment=Agent Orchestrator (local fork build)
GenericName=Orchestrator
Exec=${PREFIX}/agent-orchestrator${proxy_args} %U
Icon=${icon_dest}
Type=Application
StartupNotify=true
StartupWMClass=Orchestrator
Categories=Development;Utility;
MimeType=x-scheme-handler/ao-app;
EOF
	if command -v update-desktop-database >/dev/null 2>&1; then
		update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
	fi
}

ensure_frontend_deps() {
	if [ "$SKIP_DEPS" -eq 0 ]; then
		step "install frontend dependencies (npm ci)"
		(cd "$REPO_ROOT/frontend" && npm ci)
	fi
}

verify_ao() {
	step "verify ao"
	if command -v ao >/dev/null 2>&1; then
		local found
		found=$(command -v ao)
		if [ "$found" != "$PREFIX/ao" ]; then
			printf 'install-local: note: "ao" on PATH resolves to %s, not %s (check PATH order)\n' "$found" "$PREFIX/ao" >&2
		fi
	fi
	"$PREFIX/ao" version
}

require_cmd go

case "$MODE" in
	daemon)
		require_cmd node
		step "build Go daemon + CLI (frontend/scripts/build-daemon.mjs)"
		(cd "$REPO_ROOT/frontend" && node ./scripts/build-daemon.mjs)
		install_ao_binary "$REPO_ROOT/frontend/daemon/ao"
		verify_ao
		done_step "installed (daemon) → $PREFIX/ao"
		;;

	dev)
		require_cmd node
		require_cmd npm
		if [ "$SKIP_DEPS" -eq 0 ]; then
			warm_args=()
			[ "$SKIP_PREPARE" -eq 1 ] && warm_args+=(--skip-prepare)
			step "warm frontend workspace (npm run dev:warm ${warm_args[*]:-})"
			(cd "$REPO_ROOT/frontend" && npm run dev:warm -- ${warm_args[@]+"${warm_args[@]}"})
		elif [ "$SKIP_PREPARE" -eq 0 ]; then
			step "prepare dev assets (node ./scripts/dev-prepare.mjs)"
			(cd "$REPO_ROOT/frontend" && node ./scripts/dev-prepare.mjs)
		fi
		if [ -f "$REPO_ROOT/frontend/daemon/ao" ]; then
			install_ao_binary "$REPO_ROOT/frontend/daemon/ao"
		else
			step "build Go daemon + CLI"
			(cd "$REPO_ROOT/frontend" && node ./scripts/build-daemon.mjs --dev)
			install_ao_binary "$REPO_ROOT/frontend/daemon/ao"
		fi
		write_launcher_wrapper "cd \"$REPO_ROOT/frontend\" && exec ./node_modules/.bin/electron-forge start -- \"\$@\""
		[ "$UPDATE_DESKTOP" -eq 1 ] && update_desktop_entry
		verify_ao
		done_step "installed (dev) → $PREFIX/agent-orchestrator + $PREFIX/ao"
		;;

	package)
		require_cmd node
		require_cmd npm
		ensure_frontend_deps
		if [ "$SKIP_PREPARE" -eq 0 ]; then
			step "build packaged Electron app (npm run package)"
			(cd "$REPO_ROOT/frontend" && npm run package)
		else
			step "package Electron app without prepackage (electron-forge package)"
			(cd "$REPO_ROOT/frontend" && ./node_modules/.bin/electron-forge package)
		fi

		packaged_dir=$(find "$REPO_ROOT/frontend/out" -maxdepth 1 -mindepth 1 -type d -name 'Agent Orchestrator-linux-*' | head -n 1 || true)
		if [ -z "$packaged_dir" ] || [ ! -x "$packaged_dir/agent-orchestrator" ]; then
			printf 'install-local: packaged app missing under %s/frontend/out\n' "$REPO_ROOT" >&2
			exit 1
		fi

		step "install packaged app bundle into $APP_DIR"
		mkdir -p "$(dirname -- "$APP_DIR")"
		rm -rf "${APP_DIR}.new" "${APP_DIR}.old"
		cp -a "$packaged_dir" "${APP_DIR}.new"
		if [ -e "$APP_DIR" ]; then
			mv "$APP_DIR" "${APP_DIR}.old"
		fi
		mv "${APP_DIR}.new" "$APP_DIR"
		rm -rf "${APP_DIR}.old"

		if [ -f "$APP_DIR/resources/daemon/ao" ]; then
			install_ao_binary "$APP_DIR/resources/daemon/ao"
		elif [ -f "$REPO_ROOT/frontend/daemon/ao" ]; then
			install_ao_binary "$REPO_ROOT/frontend/daemon/ao"
		fi
		write_launcher_wrapper "exec \"$APP_DIR/agent-orchestrator\" \"\$@\""
		[ "$UPDATE_DESKTOP" -eq 1 ] && update_desktop_entry
		verify_ao
		done_step "installed (package) → $APP_DIR (wrappers in $PREFIX)"
		;;

	deb)
		require_cmd node
		require_cmd npm
		ensure_frontend_deps
		if [ "$SKIP_PREPARE" -eq 0 ]; then
			step "prepare assets for .deb (npm run premake)"
			(cd "$REPO_ROOT/frontend" && npm run premake)
		fi
		step "build Linux .deb package (electron-forge make --targets=@electron-forge/maker-deb)"
		(cd "$REPO_ROOT/frontend" && ./node_modules/.bin/electron-forge make --targets=@electron-forge/maker-deb)

		deb_file=$(find "$REPO_ROOT/frontend/out/make/deb" -type f -name '*.deb' | sort | tail -n 1 || true)
		if [ -z "$deb_file" ]; then
			printf 'install-local: .deb artifact missing under %s/frontend/out/make/deb\n' "$REPO_ROOT" >&2
			exit 1
		fi

		if [ "$NO_DPKG" -eq 0 ]; then
			step "install $deb_file via sudo dpkg -i"
			sudo dpkg -i "$deb_file"
		else
			printf 'note: --no-dpkg set; skipping dpkg install of %s\n' "$deb_file"
		fi
		if [ -f "$REPO_ROOT/frontend/daemon/ao" ]; then
			install_ao_binary "$REPO_ROOT/frontend/daemon/ao"
			verify_ao
		fi
		done_step "built (deb) → $deb_file"
		;;
esac
