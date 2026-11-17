#!/usr/bin/env bash
# Regression test for check_buildenv_floor.sh.
#
# Builds a tiny install directory out of planted objects whose symbol
# references cover every class the checker must classify, then runs the
# checker and asserts the exact set reported:
#
#   - zz_missing_probe_symbol  a symbol no host library provides -> reported,
#   - every symbol the host or a sibling object defines -> not reported,
#   - every reference that no library ships and no real link pulls
#     (exclude_by_design: linker-synthesized markers, mpg123's dead shim,
#     the dropped pthread_atfork name, Qt resource registrars) -> not
#     reported.
#
# This also exercises the provenance path: a reported symbol must come with a
# "referenced by:" line naming the object that references it.
#
# Each planted object is checked right after it is compiled: the symbol it is
# supposed to reference must in fact show up as an undefined symbol in nm, so
# an optimization that drops the reference fails loudly as a broken fixture
# instead of silently weakening the assertions.
#
# Meant to run on a normal Linux CI host (a C compiler, ldconfig, glibc and
# binutils are required, exactly what check_buildenv_floor.sh already needs).

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
checker="$here/check_buildenv_floor.sh"
[ -f "$checker" ] || { echo "checker not found: $checker" >&2; exit 2; }
command -v gcc >/dev/null 2>&1 || { echo "gcc required" >&2; exit 2; }
command -v ldconfig >/dev/null 2>&1 || { echo "ldconfig required" >&2; exit 2; }
command -v nm >/dev/null 2>&1 || { echo "nm required" >&2; exit 2; }

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT

# mkobj <out.o>: compiles the C source on stdin into a relocatable object and
# asserts that every symbol listed as an argument is an undefined reference
# in the object (a fixture that does not reference its probe is broken).
n=0
mkobj() {
    local out="$1"
    local src="$t/src.$n.c"
    n=$((n + 1))
    cat > "$src"
    gcc -c -fno-pie "$src" -o "$out"
}

check_undef() { # <object> <symbol...>
    local o="$1"; shift
    for s in "$@"; do
        if ! nm -A -u "$o" | awk -v sym="$s" '$NF == sym { ok = 1 } END { exit !ok }'; then
            echo "fixture broken: $o does not reference $s" >&2
            nm -A -u "$o" >&2 || true
            exit 1
        fi
    done
}

inst="$t/inst"
mkdir -p "$inst"

# Must be reported: referenced by no host library and by no sibling object.
# Two separate objects reference it so the provenance section must list both.
mkobj "$inst/missing.o" <<'EOF'
extern void zz_missing_probe_symbol(void);
static void f_missing(void) { zz_missing_probe_symbol(); }
void *keep_missing = (void *)&f_missing;
EOF
check_undef "$inst/missing.o" zz_missing_probe_symbol
mkobj "$inst/missing2.o" <<'EOF'
extern void zz_missing_probe_symbol(void);
static void f_missing2(void) { zz_missing_probe_symbol(); }
void *keep_missing2 = (void *)&f_missing2;
EOF
check_undef "$inst/missing2.o" zz_missing_probe_symbol

# Host libc provides strlen -> not reported.
mkobj "$inst/hostok.o" <<'EOF'
extern int strlen(const char *);
int (*keep_strlen)(const char *) = &strlen;
EOF
check_undef "$inst/hostok.o" strlen

# A symbol defined by a sibling object in the same install -> not reported.
mkobj "$inst/sibid.o" <<'EOF'
int zz_defined_by_sibling(void) { return 1; }
EOF
mkobj "$inst/sibref.o" <<'EOF'
extern int zz_defined_by_sibling(void);
int f_sib(void) { return zz_defined_by_sibling(); }
EOF
check_undef "$inst/sibref.o" zz_defined_by_sibling

# exclude_by_design classes -> never reported.
# Linker-synthesized markers.
mkobj "$inst/linkersyn.o" <<'EOF'
extern char _GLOBAL_OFFSET_TABLE_[];
char *keep_got = _GLOBAL_OFFSET_TABLE_;
extern char __start_zzfake[];
char *keep_start = __start_zzfake;
EOF
check_undef "$inst/linkersyn.o" _GLOBAL_OFFSET_TABLE_ __start_zzfake
# Package quirks: out123 shim, dropped pthread_atfork, Qt registrars.
mkobj "$inst/pkgquirk.o" <<'EOF'
extern void mpg123_output_module_info(void);
void (*keep_mpg)(void) = &mpg123_output_module_info;
extern int pthread_atfork(void);
int (*keep_ptf)(void) = &pthread_atfork;
extern void qInitResources_fixture(void);
void (*keep_qini)(void) = &qInitResources_fixture;
extern void qCleanupResources_fixture(void);
void (*keep_qcln)(void) = &qCleanupResources_fixture;
EOF
check_undef "$inst/pkgquirk.o" mpg123_output_module_info pthread_atfork \
            qInitResources_fixture qCleanupResources_fixture

set +e
output="$(bash "$checker" "$inst" 2>&1)"
rc=$?
set -e

[ "$rc" -eq 1 ] || { echo "fail: expected exit 1, got $rc" >&2; echo "$output" >&2; exit 1; }

echo "$output" | grep -q 'zz_missing_probe_symbol' \
    || { echo "fail: missing-symbol reference was not reported" >&2; echo "$output" >&2; exit 1; }

nref="$(echo "$output" | grep -c 'referenced by: .*missing.*\.o')"
[ "$nref" -ge 2 ] \
    || { echo "fail: provenance must name both referencing objects (missing.o and missing2.o), got $nref" >&2; echo "$output" >&2; exit 1; }

for safe in strlen zz_defined_by_sibling _GLOBAL_OFFSET_TABLE_ __start_zzfake \
            mpg123_output_module_info pthread_atfork qInitResources_fixture qCleanupResources_fixture; do
    echo "$output" | grep -q "$safe" \
        && { echo "fail: '$safe' must not be reported" >&2; echo "$output" >&2; exit 1; }
done

# A clean install (only host-provided and sibling-defined references) passes.
clean="$t/clean"
mkdir -p "$clean"
cp "$inst/hostok.o" "$inst/sibid.o" "$inst/sibref.o" "$clean/"
set +e
coutput="$(bash "$checker" "$clean" 2>&1)"
crc=$?
set -e
[ "$crc" -eq 0 ] || { echo "fail: clean install must pass, got rc=$crc" >&2; echo "$coutput" >&2; exit 1; }
echo "$coutput" | grep -q 'buildenv meets' \
    || { echo "fail: clean install must say 'buildenv meets', got:" >&2; echo "$coutput" >&2; exit 1; }

echo "test_buildenv_floor: all assertions passed"