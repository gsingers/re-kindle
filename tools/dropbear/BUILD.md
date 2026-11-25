# Static dropbearmulti for Kindle KT3 (ARMv7, kernel 3.10.53)

## Source
- URL: https://matt.ucc.asn.au/dropbear/releases/dropbear-2026.94.tar.bz2 (latest release, 2026-07-23)
- SHA256: `e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81`
- Matches the line in the release site's signed `SHA256SUM.asc`. GPG "Good signature" on both the
  tarball (`.asc`) and `SHA256SUM.asc` from key `F734 7EF2 EE2E 07A2 6762 8CA9 4493 1494 F29C 6773`
  (Dropbear SSH Release Signing), imported from `dropbear-key-2015.asc` on the same site (not
  cross-checked against a keyserver or web of trust).

## Toolchain
- Docker `alpine:3.22` (`sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f`),
  run as `--platform linux/arm/v7` under QEMU, so it compiles natively for armv7.
- gcc 14.2.0, musl 1.2.5-r13. Output is armv7-a, Thumb-2, VFPv3-D16, hard-float EABI5, fully static.

## Build
`sh build.sh` writes `out/dropbearmulti` (stripped), `out/dropbearmulti.unstripped`, `out/configure.log`, `out/make.log`.
- configure: `ac_cv_func_getrandom=no ./configure --enable-static --disable-zlib --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx --disable-pututline --disable-pututxline`
- make: `PROGRAMS="dropbear dropbearkey scp" MULTI=1 STATIC=1`
- `getrandom` is forced off (kernel 3.10 does not have it; it arrived in 3.17). config.h: `/* #undef HAVE_GETRANDOM */`, so entropy comes from /dev/urandom.

## localoptions.h (differences from default_options.h)
| Option | Default | Here |
|---|---|---|
| DROPBEAR_SVR_PASSWORD_AUTH | 1 | 0 |
| DEFAULT_PATH | /usr/bin:/bin | /var/local/ssh:/usr/bin:/bin:/usr/sbin:/sbin:/var/local/kmc/bin |
| DEFAULT_ROOT_PATH (root sessions use this one) | /usr/sbin:/usr/bin:/sbin:/bin | same as DEFAULT_PATH |
| RSA/ECDSA/ED25519/DSS_PRIV_FILENAME | /etc/dropbear/dropbear_*_host_key | /var/local/ssh/dropbear_*_host_key |

DROPBEAR_SVR_PUBKEY_AUTH, DROPBEAR_ED25519 and DROPBEAR_ECDSA are set to 1, which is already the default.
The host key paths were changed because `-R` generates missing keys at the compiled-in paths and ignores `-r`. /var/local is persistent ext3; /mnt/us is vfat and fails the permission checks. /var/local/ssh is first in PATH because the scp symlink goes there (/var/local/kmc is chattr +i).

## authorized_keys
Default path: `<pw_dir>/.ssh/authorized_keys`, where pw_dir is the user's home from `/etc/passwd`
(getpwnam), **not** `$HOME`. If root's home there is /tmp/root, the file is `/tmp/root/.ssh/authorized_keys`.
`-D <dir>` overrides the directory and dropbear then reads `<dir>/authorized_keys`.
Every directory from the file's directory up to pw_dir (or up to `/` if the file is outside pw_dir)
must be owned by root or the user, and must not be group- or world-writable.

## Verify output
```
$ file out/dropbearmulti
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, stripped
readelf -A: Tag_CPU_arch v7, Thumb-2, Tag_FP_arch VFPv3-D16, Tag_ABI_VFP_args VFP registers
readelf -l: no INTERP / DYNAMIC segment
size 292784 bytes, sha256 2384cb9622e41a783ae72adfcb9021fbc3663a33401aba0315a5fd53465d5ef7
$ dropbearmulti dropbear -V
Dropbear v2026.94
dropbearkey -t ed25519 / -t ecdsa: generated keys under QEMU
```
`sh e2e-test.sh` (log in `out/e2e.log`) runs the server under QEMU and connects from the Mac's OpenSSH:
- `-F -E -s -g -R -p 0.0.0.0:2222`: generated `/var/local/ssh/dropbear_ed25519_host_key`, pubkey login
  via `~/.ssh/authorized_keys` succeeded, PATH as above, password-only client refused
  ("Permission denied (publickey)"), `scp -O` worked (with `/var/local/ssh/scp` symlinked to dropbearmulti).
- `-r <key> -D <dir>`: pubkey login succeeded.
- Plain `scp` (OpenSSH 9+ defaults to SFTP) failed because there is no sftp-server. Use `scp -O`.
- Log line "fexecve failed, disabling re-exec" under QEMU: this isn't fatal (dropbear stops re-execing itself).
