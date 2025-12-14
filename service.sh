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
  if command -v iptables >/dev/null 2>&1; then
    iptables -C OUTPUT -p udp --dport 443 -j DROP 2>/dev/null || iptables -I OUTPUT -p udp --dport 443 -j DROP
    iptables -C FORWARD -p udp --dport 443 -j DROP 2>/dev/null || iptables -I FORWARD -p udp --dport 443 -j DROP
    iptables -C OUTPUT -p udp --dport 8443 -j DROP 2>/dev/null || iptables -I OUTPUT -p udp --dport 8443 -j DROP
    iptables -C FORWARD -p udp --dport 8443 -j DROP 2>/dev/null || iptables -I FORWARD -p udp --dport 8443 -j DROP
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -C OUTPUT -p udp --dport 443 -j DROP 2>/dev/null || ip6tables -I OUTPUT -p udp --dport 443 -j DROP
    ip6tables -C FORWARD -p udp --dport 443 -j DROP 2>/dev/null || ip6tables -I FORWARD -p udp --dport 443 -j DROP
    ip6tables -C OUTPUT -p udp --dport 8443 -j DROP 2>/dev/null || ip6tables -I OUTPUT -p udp --dport 8443 -j DROP
    ip6tables -C FORWARD -p udp --dport 8443 -j DROP 2>/dev/null || ip6tables -I FORWARD -p udp --dport 8443 -j DROP
  fi
  WPAD_FILE="$MODDIR/wpad.dat"
  WPAD_PORT=8081
  BUSYBOX="/data/adb/magisk/busybox"
  cat >"$WPAD_FILE" <<'PAC'
function FindProxyForURL(url, host) {
  if (isPlainHostName(host) || dnsDomainIs(host, "wpad") || host === "10.10.10.10" || isInNet(host, "10.10.10.0", "255.255.255.0")) {
    return "DIRECT";
  }
  return "PROXY 10.10.10.10:8080; DIRECT";
}
PAC
  if [ -x "$BUSYBOX" ]; then
    "$BUSYBOX" httpd -p ${ALIAS_IP}:$WPAD_PORT -h "$MODDIR" -f 2>/dev/null &
  elif command -v busybox >/dev/null 2>&1; then
    busybox httpd -p ${ALIAS_IP}:$WPAD_PORT -h "$MODDIR" -f 2>/dev/null &
  else
    (
      while true; do
        LEN=$(wc -c < "$WPAD_FILE")
        {
          printf 'HTTP/1.1 200 OK\r\n'
          printf 'Content-Type: application/x-ns-proxy-autoconfig\r\n'
          printf 'Content-Length: %s\r\n' "$LEN"
          printf 'Connection: close\r\n\r\n'
          cat "$WPAD_FILE"
        } | nc -l -p $WPAD_PORT -s "$ALIAS_IP" -w 1
      done
    ) &
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -t nat -C PREROUTING -i "$IFACE" -d "$ALIAS_IP" -p tcp --dport 80 -j REDIRECT --to-port $WPAD_PORT 2>/dev/null || iptables -t nat -I PREROUTING -i "$IFACE" -d "$ALIAS_IP" -p tcp --dport 80 -j REDIRECT --to-port $WPAD_PORT
  fi
  if command -v dnsmasq >/dev/null 2>&1; then
    dnsmasq --listen-address=127.0.0.1 --port=5353 --no-resolv --no-hosts --bind-interfaces --address=/wpad/10.10.10.10 2>/dev/null || true
    iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 53 -m string --string "wpad" --algo bm -j REDIRECT --to-port 5353 2>/dev/null || iptables -t nat -I PREROUTING -i "$IFACE" -p udp --dport 53 -m string --string "wpad" --algo bm -j REDIRECT --to-port 5353
    iptables -t nat -C PREROUTING -i "$IFACE" -p tcp --dport 53 -m string --string "wpad" --algo bm -j REDIRECT --to-port 5353 2>/dev/null || iptables -t nat -I PREROUTING -i "$IFACE" -p tcp --dport 53 -m string --string "wpad" --algo bm -j REDIRECT --to-port 5353
  fi
) &
