/* Kindle (KT3, fw 5.16.x) embedded, key-only dropbear. */
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DROPBEAR_ED25519 1
#define DROPBEAR_ECDSA 1
/* The Kindle runs everything as root, and root sessions get DEFAULT_ROOT_PATH.
 * /var/local/ssh comes first: it holds the scp symlink (/var/local/kmc is chattr +i). */
#define DEFAULT_PATH "/var/local/ssh:/usr/bin:/bin:/usr/sbin:/sbin:/var/local/kmc/bin"
#define DEFAULT_ROOT_PATH "/var/local/ssh:/usr/bin:/bin:/usr/sbin:/sbin:/var/local/kmc/bin"
/* Default host key paths. -R generates missing keys at THESE paths (it ignores -r).
 * /var/local is persistent ext3; /mnt/us is vfat and fails permission checks. */
#define RSA_PRIV_FILENAME "/var/local/ssh/dropbear_rsa_host_key"
#define ECDSA_PRIV_FILENAME "/var/local/ssh/dropbear_ecdsa_host_key"
#define ED25519_PRIV_FILENAME "/var/local/ssh/dropbear_ed25519_host_key"
#define DSS_PRIV_FILENAME "/var/local/ssh/dropbear_dss_host_key"
