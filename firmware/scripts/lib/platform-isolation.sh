# ---------------------------------------------------------------------------
# Platform isolation, shared by scripts/release.sh and scripts/run-checks.sh.
#
# The official `espressif32` platform and every URL-pinned fork (pioarduino)
# register under the SAME PlatformIO platform name ("espressif32"), and both
# install a package named `framework-arduinoespressif32`. Two such platforms in
# one PLATFORMIO_CORE_DIR therefore clobber each other -- only one framework can
# exist under that package name at a time. The failure is subtle: the
# official-platform targets still build, so the collision stays invisible until
# a fork leg runs and dies inside the platform's own build script (a
# `FRAMEWORK_DIR is None` TypeError). That is why the old CI gave the C6 env its
# own job.
#
# The rule here is one core dir PER PLATFORM SPEC, not one per family. This repo
# pins TWO distinct pioarduino releases -- 54.03.20 for env:esp32-s3-16mb and
# 55.03.311 for the C6 envs -- and those two clobber each other exactly like the
# official/fork pair, so "the fork dir" is not enough:
#
#   official envs (platform = espressif32@7.0.1) -> <base>, shared
#   each URL-pinned platform                     -> <base>-pioarduino-<tag>
#
# where <tag> is the release tag read from that env's own platform URL, so a
# custom-platform env added later is isolated automatically with no edit here.
#
# Sourced, not executed. Every function takes the firmware root explicitly, so
# there is no shared mutable state to get wrong.
# ---------------------------------------------------------------------------

# Every PlatformIO config file a firmware root loads: platformio.ini plus any
# file it names in `extra_configs` (PlatformIO merges those into the same env
# space). Emits one absolute path per line.
#
# Reading extra_configs matters, and is not speculative: if an env were declared
# only in an included file, a scan of platformio.ini alone would return an empty
# spec for it, core_dir_for_env() would fall back to the SHARED base core dir,
# and the collision this file exists to prevent would return silently.
platformio_config_files() {
  local root="$1" base
  base="${root}/platformio.ini"
  printf '%s\n' "$base"
  [ -f "$base" ] || return 0
  awk -v root="$root" '
    function emit(s,  n, parts, i) {
      n = split(s, parts, /[,[:space:]]+/)
      for (i = 1; i <= n; i++) if (parts[i] != "") print root "/" parts[i]
    }
    /^[[:space:]]*extra_configs[[:space:]]*=/ {
      line = $0
      sub(/^[^=]*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*;.*$/, "", line)
      emit(line); cont = 1; next
    }
    cont && /^[[:space:]]+[^[:space:];[]/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]*;.*$/, "", line)
      emit(line); next
    }
    { cont = 0 }
  ' "$base"
}

# The env names $2 `extends` (as bare names, `env:` stripped), one per line.
env_extends_for_env() {
  local root="$1" env="$2" f
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(platformio_config_files "$root")
  [ "${#files[@]}" -gt 0 ] || return 0
  awk -v want="$env" '
    $0 == "[env:" want "]" { inside = 1; next }
    /^\[/                 { inside = 0 }
    inside && /^[[:space:]]*extends[[:space:]]*=/ {
      sub(/^[[:space:]]*extends[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]*;.*$/, "")
      n = split($0, parts, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        p = parts[i]
        sub(/^env:/, "", p)
        if (p != "") print p
      }
      exit
    }
  ' "${files[@]}"
}

# The `platform =` value for env $2, read from every config file $1 loads. An
# env with no `platform` of its own (the `extends`-only secure/secureboot
# variants) inherits one, so the `extends` chain is walked before giving up.
# Without this, idf-secure-c6 and idf-secureboot-c6 -- which extend idf-c6, a
# fork env -- would resolve to an empty spec and silently share the base core
# dir with the official-platform envs, the very collision this file prevents.
# $3 is the recursion depth guard.
platform_spec_for_env() {
  local root="$1" env="$2" depth="${3:-0}" spec f parent
  [ "$depth" -gt 8 ] && return 0
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(platformio_config_files "$root")
  [ "${#files[@]}" -gt 0 ] || return 0
  spec="$(awk -v want="$env" '
    $0 == "[env:" want "]" { inside = 1; next }
    /^\[/                 { inside = 0 }
    inside && /^[[:space:]]*platform[[:space:]]*=/ {
      sub(/^[[:space:]]*platform[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]*;.*$/, "")
      print
      exit
    }
  ' "${files[@]}")"
  if [ -z "$spec" ]; then
    while IFS= read -r parent; do
      [ -n "$parent" ] || continue
      spec="$(platform_spec_for_env "$root" "$parent" "$((depth + 1))")"
      [ -n "$spec" ] && break
    done < <(env_extends_for_env "$root" "$env")
  fi
  printf '%s' "$spec"
}

# Short, filesystem-safe discriminator for a URL-pinned platform spec. Prefer
# the release tag from the URL:
#   .../releases/download/54.03.20/platform-espressif32.zip -> 54.03.20
# Fall back to a hash of the whole spec, so two URL platforms can never share a
# core dir even if neither is a GitHub release URL.
platform_core_tag() {
  local spec="$1" path tag
  path="${spec%%\?*}"; path="${path%%#*}"; path="${path%/}"
  tag="${path%/*}"; tag="${tag##*/}"
  tag="$(printf '%s' "$tag" | tr -c 'A-Za-z0-9._-' '-')"
  tag="${tag#-}"; tag="${tag%-}"
  if [ -z "$tag" ]; then
    tag="url$(printf '%s' "$spec" | cksum | awk '{print $1}')"
  fi
  printf '%s' "$tag"
}

# The isolated PLATFORMIO_CORE_DIR for env $2 of firmware root $1, given the base
# core dir $3. Official-platform envs get $3 unchanged; URL-pinned envs get
# $3-pioarduino-<tag>.
core_dir_for_env() {
  local root="$1" env="$2" base="$3" spec
  spec="$(platform_spec_for_env "$root" "$env")"
  case "$spec" in
    *://*) printf '%s-pioarduino-%s' "$base" "$(platform_core_tag "$spec")" ;;
    *)     printf '%s' "$base" ;;
  esac
}
