#!/bin/sh
# End-to-end test: run out/dropbearmulti under QEMU (linux/arm/v7) and log in from the host.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
E=$HERE/e2e; mkdir -p "$E"
[ -f "$E/client" ] || ssh-keygen -q -t ed25519 -N '' -f "$E/client" -C e2e
SSHO="-i $E/client -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o LogLevel=ERROR"
IMG=alpine:3.22
PREP='mkdir -p /var/local/ssh && chmod 700 /var/local/ssh && ln -s /w/dropbearmulti /var/local/ssh/scp'

echo "=== A: -R (keys generated at compiled default /var/local/ssh/...), ~/.ssh/authorized_keys"
docker run -d --name dbtestA --platform linux/arm/v7 -p 127.0.0.1:2222:2222 -v "$HERE/out":/w:ro -v "$E":/e:ro $IMG sh -c "$PREP"' && mkdir -p /root/.ssh && cp /e/client.pub /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && exec /w/dropbearmulti dropbear -F -E -s -g -R -p 0.0.0.0:2222' >/dev/null
sleep 4
ssh $SSHO -p 2222 root@127.0.0.1 'echo "login ok; PATH=$PATH; uid=$(id -u); HOME=$HOME"; ls -l /var/local/ssh'
echo "-- password-only attempt (expect publickey-only denial):"
ssh -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -p 2222 root@127.0.0.1 true 2>&1 | tail -1
echo "-- scp -O (legacy scp protocol):"
scp -O $SSHO -P 2222 "$E/client.pub" root@127.0.0.1:/tmp/x && ssh $SSHO -p 2222 root@127.0.0.1 'cmp /tmp/x /e/client.pub && echo "scp -O ok"'
echo "-- scp default (SFTP protocol, expect failure: no sftp-server):"
scp $SSHO -P 2222 "$E/client.pub" root@127.0.0.1:/tmp/y 2>&1 | tail -1
docker logs dbtestA 2>&1 | tail -4
docker rm -f dbtestA >/dev/null

echo "=== B: pre-made key via -r, authorized_keys via -D"
docker run -d --name dbtestB --platform linux/arm/v7 -p 127.0.0.1:2222:2222 -v "$HERE/out":/w:ro -v "$E":/e:ro $IMG sh -c 'mkdir -p /hk /k && /w/dropbearmulti dropbearkey -t ed25519 -f /hk/ed >/dev/null 2>&1 && cp /e/client.pub /k/authorized_keys && chmod 600 /k/authorized_keys && exec /w/dropbearmulti dropbear -F -E -s -g -r /hk/ed -D /k -p 0.0.0.0:2222' >/dev/null
sleep 4
ssh $SSHO -p 2222 root@127.0.0.1 'echo "B login ok"'
docker logs dbtestB 2>&1 | tail -2
docker rm -f dbtestB >/dev/null
