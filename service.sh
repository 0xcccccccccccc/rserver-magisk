#!/system/bin/sh
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 1; done
"$MODDIR/bin/rserver" -h 0.0.0.0 -p 8080 &
(
  i=0
  IFACE=""
  while [ $i -lt 30 ]; do
    IFACE=$(ip -o link 2>/dev/null | awk -F': ' '/state UP/{print $2}' | cut -d: -f1 | awk '/^(ap|wlan|softap)[0-9]+$/{print; exit}')
    if [ -n "$IFACE" ]; then
      if ip -o addr show dev "$IFACE" 2>/dev/null | grep -q ' inet '; then
        break
      fi
    fi
    sleep 2
    i=$((i+1))
  done
  if [ -n "$IFACE" ]; then
    ALIAS_IP="10.10.10.10"
    if command -v ip >/dev/null 2>&1; then
      ip addr add ${ALIAS_IP}/32 dev "$IFACE" 2>/dev/null || true
      ip link set "$IFACE" up 2>/dev/null || true
    elif command -v ifconfig >/dev/null 2>&1; then
      ifconfig "$IFACE" ${ALIAS_IP} up 2>/dev/null || true
    fi
  fi
) &
