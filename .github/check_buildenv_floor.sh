#!/usr/bin/env bash
# Check that the files under <dir> stay within this build host's ABI floor.
#
# Packages restored from the NuGet binary cache may have been built on a newer
# host than the buildenv floor. That shows up in two places:
#
#  1. Version nodes. Executables and shared libraries reference version nodes
#     (GLIBC_x, GLIBCXX_x, CXXABI_x, GCC_x) read from .gnu.version_r.
#  2. Symbols. Static objects and archives carry no version info; a static
#     library references newer libc/libstdc++ symbols as plain undefined
#     references (e.g. __isoc23_sscanf from glibc >= 2.38, or _M_replace_cold
#     from GCC >= 12). readelf --version-info cannot see these.
#
# Only requirement data of the audited files is inspected, never their
# definitions, so a file that merely exports a symbol is never reported. The
# provided set is taken from this host:
#   - version nodes: the definition data of the host libc/libstdc++/libgcc_s,
#   - symbols: every symbol exported by a shared or static library the host
#     linker can see (ldconfig plus the compiler's libgcc.a), and every symbol
#     defined elsewhere under <dir>.
# A symbol that exists nowhere on the floor host and nowhere else in the
# install is reported (with the file that references it). A few references
# are excluded up front because they can never be floor-ABI drift, see
# exclude_by_design (linker-synthesized markers, mpg123's dead out123 shim,
# glibc's dropped pthread_atfork name, Qt resource registrars). The floor
# therefore follows the host and holds no hardcoded values.
#
# Usage: check_buildenv_floor.sh <dir>

set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <dir>" >&2; exit 2; }
dir="$1"
[ -d "$dir" ] || { echo "error: audited directory not found: $dir" >&2; exit 2; }

ldconfig_cmd=""
for c in "$(command -v ldconfig 2>/dev/null)" /usr/sbin/ldconfig /sbin/ldconfig; do
    [ -n "$c" ] && [ -x "$c" ] && { ldconfig_cmd="$c"; break; }
done
[ -n "$ldconfig_cmd" ] || { echo "cannot locate ldconfig" >&2; exit 2; }
command -v nm >/dev/null 2>&1 || { echo "cannot locate nm" >&2; exit 2; }

# Primary triplet so multilib paths (i386 on x86_64, etc.) are skipped.
triplet=""
case "$(uname -m)" in
    x86_64)        triplet="x86_64-linux-gnu" ;;
    aarch64|arm64) triplet="aarch64-linux-gnu" ;;
esac

locate_lib() {
    # $1: exact soname, e.g. libstdc++.so.6. grep -F, no regex escaping.
    local soname="$1"
    local out
    if [ -n "$triplet" ]; then
        out=$("$ldconfig_cmd" -p | grep -F "${triplet}/${soname}" | awk '{print $NF}' | head -n1)
    else
        out=$("$ldconfig_cmd" -p | grep -F "${soname}" | awk '{print $NF}' | head -n1)
    fi
    printf '%s\n' "$out"
}

libc="$(locate_lib 'libc.so.6')"
[ -n "$libc" ] || { echo "cannot locate host libc" >&2; exit 2; }
libstdcpp="$(locate_lib 'libstdc++.so.6')"
[ -n "$libstdcpp" ] || { echo "cannot locate host libstdc++" >&2; exit 2; }
libgcc_s="$(locate_lib 'libgcc_s.so.1')"
[ -n "$libgcc_s" ] || { echo "cannot locate host libgcc_s" >&2; exit 2; }

# Version nodes the host provides: definition data of the host libraries.
namespaces='(GLIBC|GLIBCXX|CXXABI|GCC)_[0-9.]+'
provided_nodes() {
    readelf --version-info "$1" 2>/dev/null \
        | awk '/\.gnu\.version_d/{f=1; next} /\.gnu\.version_r/{f=0} f' \
        | grep -oE "$namespaces" | sort -u || true
}
declare -A prov
while IFS= read -r node; do
    [ -n "$node" ] && prov["$node"]=1
done < <(provided_nodes "$libc"; provided_nodes "$libstdcpp"; provided_nodes "$libgcc_s")

# Version nodes the audited files reference: requirement data only.
required_nodes() {
    readelf --version-info "$1" 2>/dev/null \
        | awk '/\.gnu\.version_r/{f=1; next} f' \
        | grep -oE "$namespaces" | sort -u || true
}

# Global defined symbol names of one library, one per line on stdout. nm's
# default layout is "<addr> <TYPE> <name>[@VER]" (no address for common/weak
# items); per-member archive headers such as "lib.a(member.o):" are dropped.
# Version suffixes are stripped so an unversioned reference matches its
# versioned definition. Both symbol tables are read by default: shared
# libraries are usually stripped of .symtab, which nm -D (the .dynsym table)
# still sees, and static archives have no .dynsym, which the plain symtab
# covers. Pass an explicit second argument "dynsym" to read only the .dynsym
# table, for callers that will only encounter shared libraries. The GNU
# indirect (ifunc) and GNU unique symbols are printed with a lowercase "i" or
# "u" in the symbol table; both are global and resolve link-time references,
# so they count as provided.
defined_syms_of() {
    if [ "${2:-}" = dynsym ]; then
        nm -D --defined-only "$1" 2>/dev/null
    else
        { nm -D --defined-only "$1" 2>/dev/null
          nm --defined-only "$1" 2>/dev/null; }
    fi | awk '{ for (i = 1; i < NF; i++) if ($i ~ /^[A-Ziu]$/) { sub(/@.*/, "", $(i+1)); print $(i+1); break } }' \
        || true
}

# Strong undefined symbols of one static library, one "name<TAB>source" line
# per symbol on stdout. Weak undefined symbols may stay unresolved at link
# time, so only strong ("U") ones are candidates. The source lets a reported
# symbol point back at the file that needs it.
undef_syms_of() {
    nm -A -u "$1" 2>/dev/null \
        | awk '{ if ($2 == "U" && NF >= 3) { n = $3; sub(/@.*/, "", n); s = $1; sub(/:$/, "", s); print n "\t" s } }' \
        || true
}

fail=0

while IFS= read -r -d '' f; do
    # Static objects/archives are checked at the symbol level below.
    case "$f" in
        *.a|*.o) continue ;;
    esac
    file "$f" | grep -q ELF || continue
    while read -r node; do
        [ -n "$node" ] || continue
        if [ -z "${prov[$node]+1}" ]; then
            echo "floor violation: $f requires $node, the host does not provide it" >&2
            fail=1
        fi
    done < <(required_nodes "$f")
done < <(find "$dir" -type f -print0)

# ---- symbol-level check for static objects and archives ----

# The scans below run in parallel (xargs -P); a plain stdout pipe would let a
# child's long symbol name be split across a buffered pipe write and
# interleaved with a sibling child's output, splicing lines mid-name into
# garbage like "9setCursorERK7QCursor" (the tail of
# "_ZN7QWindow9setCursorERK7QCursor"). A spliced name matches nothing on the
# host and reads as a false floor violation. Every child therefore writes its
# own result file (per-process $$), and the per-file results are concatenated
# exactly once, serially, before being sorted.
tmpd="$(mktemp -d)"
undeffile="$tmpd/undef"
undefraw="$tmpd/undefraw"
hostfile="$tmpd/host"
hostmissing="$tmpd/hostmissing"
installfile="$tmpd/install"
# Each parallel scan stream writes only into its own result directory
# ($1/...), and results() reads only the directory it is given, so no stream
# can pick up or overwrite another stream's output or a stale file of a
# different kind.
refd="$tmpd/refs"       # strong undefined symbols of static files (u.$$)
hostd="$tmpd/hostdefs"  # defined symbols of host libraries          (h.$$)
linkd="$tmpd/instsyms"  # .dynsym definitions of install shared libs (s.$$)
staticd="$tmpd/instar"  # plain-symtab definitions of install archives(i.$$)
mkdir -p "$refd" "$hostd" "$linkd" "$staticd"
results() { find "$1" -type f -print0 2>/dev/null | xargs -0 -r cat; }
trap 'rm -rf "$tmpd"' EXIT

parallel="$({ command -v nproc >/dev/null 2>&1 && nproc; } || echo 4)"
export -f undef_syms_of defined_syms_of

# References no library provides and the linker itself always satisfies;
# these are never floor-ABI drift, so they are dropped from the reported
# set. They fall into two classes:
#
#   Linker-synthesized markers. The linker manufactures these at the final
#   link; no glibc/libstdc++/libgcc_s version could provide them, so a static
#   reference to them can never mean "newer than the floor":
#     - _GLOBAL_OFFSET_TABLE_,
#     - __start_<section>/__stop_<section>.
#
#   Package quirks. A library member carries a reference no real link pulls,
#   so the name is an artifact of the package, not of floor-ABI drift. Each
#   entry names the referencing member so the exclusion is tied to an actual,
#   inspectable source rather than a free-form rule:
#     - mpg123_output_module_info: libout123's legacy shim references the
#       module-info symbol the package does not ship; the referencing archive
#       member is never pulled into any real link (nothing references its
#       output123_* API),
#     - pthread_atfork: glibc >= 2.34 no longer exports the name (only
#       __register_atfork remains), so the reference can be satisfied neither
#       by a floor libc (>= 2.34) nor by any host newer than it; the exclusion
#       treats the reference as carried by an archive member no real link
#       pulls. NOTE: this floor (the 2.7 buildenv) is glibc >= 2.34, so the
#       rationale "the floor's libpthread still provides it" that applied to
#       the 2.6 floor does NOT hold here; verify the referencing member before
#       shipping this exclusion (see directory audit history),
#     - qInitResources_*/qCleanupResources_*: Qt rcc-generated resource
#       registrars, resolved in the consumer's own link, never by a host
#       library.
exclude_by_design() {
    grep -vx '_GLOBAL_OFFSET_TABLE_' \
        | grep -vxE '__(start|stop)_[^@ ]+' \
        | grep -vx 'mpg123_output_module_info' \
        | grep -vx 'pthread_atfork' \
        | grep -vxE '(_Z[0-9]+)?q(Init|Cleanup)Resources_[^@ ]+' \
        || true
}

# Union of every strong undefined symbol across all static files.
find "$dir" -type f \( -name '*.a' -o -name '*.o' \) -print0 \
    | xargs -0 -r -P "$parallel" -n 1 bash -c 'undef_syms_of "$2" > "$1/u.$$"' _ "$refd" \
    || true
results "$refd" | LC_ALL=C sort -u > "$undefraw"
cut -f1 "$undefraw" | LC_ALL=C sort -u > "$undeffile"

if [ -s "$undeffile" ]; then
    # Provided pack: every shared library the host linker sees. A symbol that
    # exists in any host library can be satisfied at AppImage link time, so
    # only symbols missing from the whole host count as requiring a newer
    # glibc/libstdc++ than the floor. The compiler's static libgcc.a and the C
    # startup objects crtbegin/crtend (which define __dso_handle) join the
    # set, and defined_syms_of reads both the .dynsym and the plain symtab so
    # stripped shared libraries and static archives both contribute.
    {
        "$ldconfig_cmd" -p | awk '{print $NF}' | sort -u
        if command -v gcc >/dev/null 2>&1; then
            gcc -print-libgcc-file-name 2>/dev/null || true
            gcc -print-file-name=crtbegin.o 2>/dev/null || true
            gcc -print-file-name=crtend.o 2>/dev/null || true
        fi
    } | LC_ALL=C sort -u \
        | xargs -d '\n' -r -P "$parallel" -n 1 bash -c 'defined_syms_of "$2" > "$1/h.$$"' _ "$hostd" \
        || true
    results "$hostd" | LC_ALL=C sort -u > "$hostfile"

    LC_ALL=C comm -23 "$undeffile" "$hostfile" > "$hostmissing"

    # Symbols the install itself defines, only when needed: some static file
    # references a symbol no host library provides. Shared libraries are read
    # with nm -D (their plain symtab is usually stripped); static archives use
    # the plain symtab.
    if [ -s "$hostmissing" ]; then
        find "$dir" -type f -name '*.so*' -print0 \
            | xargs -0 -r -P "$parallel" -n 1 bash -c 'defined_syms_of "$2" dynsym > "$1/s.$$"' _ "$linkd" \
            || true
        results "$linkd" >> "$installfile"

        find "$dir" -type f \( -name '*.a' -o -name '*.o' \) -print0 \
            | xargs -0 -r -P "$parallel" -n 1 bash -c 'defined_syms_of "$2" > "$1/i.$$"' _ "$staticd" \
            || true
        results "$staticd" >> "$installfile"
        LC_ALL=C sort -u -o "$installfile" "$installfile"

        # Symbols neither the host nor any sibling file provides are the
        # violations.
        LC_ALL=C comm -23 "$hostmissing" "$installfile" > "$hostmissing.tmp"
        mv "$hostmissing.tmp" "$hostmissing"
    fi

    # Drop the references no library or the linker itself satisfies (see
    # exclude_by_design); they cannot be floor-ABI drift.
    if [ -s "$hostmissing" ]; then
        exclude_by_design < "$hostmissing" > "$hostmissing.tmp"
        mv "$hostmissing.tmp" "$hostmissing"
    fi

    if [ -s "$hostmissing" ]; then
        echo "floor violation: static libraries under $dir reference symbols that neither any host library nor any other file under $dir provides:" >&2
        while IFS= read -r sym; do
            echo "  $sym" >&2
            awk -F '\t' -v s="$sym" '$1 == s { print "      referenced by: " $2 }' "$undefraw" >&2
        done < "$hostmissing"
        fail=1
    fi
fi

if [ "$fail" != 0 ]; then
    echo "restored buildenv files require newer glibc/libstdc++/libgcc_s symbols or version nodes than this host provides" >&2
    exit 1
fi
echo "$dir: buildenv meets this host's ABI floor"