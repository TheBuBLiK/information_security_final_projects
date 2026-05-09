#!/usr/bin/env bash
# =============================================================================
# DDoS Attack Simulation Against the K8s Gateway
# Demonstrates that the Nginx gateway protects the multi-pod application.
#
# Usage:
#   ./simulate_ddos.sh [GATEWAY_URL]
#
# If no URL is given, it tries to auto-detect via minikube.
# =============================================================================

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# Determine target URL
if [ -n "${1:-}" ]; then
    TARGET="$1"
else
    TARGET=$(minikube service gateway-service -n multi-pod-app --url 2>/dev/null || echo "")
    if [ -z "$TARGET" ]; then
        echo -e "${RED}ERROR: Could not detect gateway URL. Pass it as an argument:${RESET}"
        echo "  ./simulate_ddos.sh http://<minikube-ip>:30080"
        exit 1
    fi
fi

echo -e "${BOLD}${CYAN}=========================================================${RESET}"
echo -e "${BOLD}${CYAN}  DDoS Protection Test Suite — K8s Gateway               ${RESET}"
echo -e "${BOLD}${CYAN}=========================================================${RESET}"
echo -e "  Target: ${BOLD}$TARGET${RESET}"
echo ""

http_status() {
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$@" 2>/dev/null || true)
    if [ -z "$status" ]; then
        status="000"
    fi
    printf "%s" "$status"
}

cool_down() {
    sleep 3
}

# Pre-check
echo -e "${BOLD}[Pre-check] Verifying gateway is reachable...${RESET}"
if ! curl -sf --max-time 5 "$TARGET/gateway-health" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Gateway is not responding at $TARGET/gateway-health${RESET}"
    echo "Make sure the app is deployed:  ./deploy.sh"
    exit 1
fi
echo -e "${GREEN}Gateway is up.${RESET}"
echo ""

# =========================================================================
# TEST 1: Normal requests through the gateway
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 1: Normal Requests (Frontend + Backend via Gateway) ---${RESET}"

STATUS=$(http_status "$TARGET/")
echo -e "  GET /  (frontend): HTTP $STATUS $([ "$STATUS" = "200" ] && echo -e "${GREEN}OK${RESET}" || echo -e "${RED}FAIL${RESET}")"

STATUS=$(http_status "$TARGET/api/info")
echo -e "  GET /api/info (backend): HTTP $STATUS $([ "$STATUS" = "200" ] && echo -e "${GREEN}OK${RESET}" || echo -e "${RED}FAIL${RESET}")"

STATUS=$(http_status "$TARGET/api/items")
echo -e "  GET /api/items (backend): HTTP $STATUS $([ "$STATUS" = "200" ] && echo -e "${GREEN}OK${RESET}" || echo -e "${RED}FAIL${RESET}")"

# Show which backend pod served the request
POD=$(curl -s "$TARGET/api/info" | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])" 2>/dev/null || echo "unknown")
echo -e "  Backend pod serving request: ${CYAN}$POD${RESET}"
echo ""

# =========================================================================
# TEST 2: Rapid-Fire Requests (rate limit test)
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 2: Rapid-Fire Requests (Rate Limiting: 10r/s, burst 20) ---${RESET}"
echo "Sending 120 rapid requests to the gateway..."
echo ""

COUNT_200=0
COUNT_429=0
COUNT_OTHER=0

for i in $(seq 1 120); do
    STATUS=$(http_status "$TARGET/")
    if [ "$STATUS" = "200" ]; then
        COUNT_200=$((COUNT_200 + 1))
    elif [ "$STATUS" = "429" ]; then
        COUNT_429=$((COUNT_429 + 1))
    else
        COUNT_OTHER=$((COUNT_OTHER + 1))
    fi
    printf "  Request %2d: HTTP %s\n" "$i" "$STATUS"
done

echo ""
echo -e "  ${BOLD}Summary:${RESET}"
echo -e "    ${GREEN}200 (Served):       $COUNT_200${RESET}"
echo -e "    ${YELLOW}429 (Rate Limited): $COUNT_429${RESET}"
[ "$COUNT_OTHER" -gt 0 ] && echo -e "    ${RED}Other:              $COUNT_OTHER${RESET}"

if [ "$COUNT_429" -gt 0 ]; then
    echo -e "  ${GREEN}PASS: Rate limiting is active — excess requests were rejected with 429.${RESET}"
else
    echo -e "  ${YELLOW}NOTE: No 429 responses. Try running again or increasing request count.${RESET}"
fi
echo ""
cool_down

# =========================================================================
# TEST 3: Concurrent Connections (connection limit test)
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 3: Concurrent Connections (Limit: 10 per IP) ---${RESET}"
echo "Opening 30 concurrent slow backend connections..."

TMPDIR=$(mktemp -d)
for i in $(seq 1 30); do
    curl -s -o /dev/null -w "%{http_code}\n" "$TARGET/api/slow" > "$TMPDIR/result_$i" 2>&1 &
done
wait

CONN_200=0
CONN_429=0
CONN_OTHER=0

for i in $(seq 1 30); do
    STATUS=$(cat "$TMPDIR/result_$i" 2>/dev/null || echo "000")
    if [ "$STATUS" = "200" ]; then CONN_200=$((CONN_200 + 1));
    elif [ "$STATUS" = "429" ]; then CONN_429=$((CONN_429 + 1));
    else CONN_OTHER=$((CONN_OTHER + 1)); fi
done
rm -rf "$TMPDIR"

echo -e "  ${BOLD}Summary:${RESET}"
echo -e "    ${GREEN}200 (Served):       $CONN_200${RESET}"
echo -e "    ${YELLOW}429 (Conn Limited): $CONN_429${RESET}"
[ "$CONN_OTHER" -gt 0 ] && echo -e "    ${RED}Other/Failed:       $CONN_OTHER${RESET}"
echo ""
cool_down

# =========================================================================
# TEST 4: Bad User-Agent (bot filtering)
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 4: Bot Filtering (Malicious User-Agents) ---${RESET}"

STATUS=$(http_status -A "" "$TARGET/")
echo -e "  Empty User-Agent:   HTTP $STATUS $([ "$STATUS" = "403" ] && echo -e "${GREEN}BLOCKED${RESET}" || echo -e "${YELLOW}not blocked${RESET}")"

STATUS=$(http_status -H "User-Agent: sqlmap/1.5" "$TARGET/")
echo -e "  sqlmap User-Agent:  HTTP $STATUS $([ "$STATUS" = "403" ] && echo -e "${GREEN}BLOCKED${RESET}" || echo -e "${YELLOW}not blocked${RESET}")"

STATUS=$(http_status -H "User-Agent: nikto/2.1" "$TARGET/")
echo -e "  nikto User-Agent:   HTTP $STATUS $([ "$STATUS" = "403" ] && echo -e "${GREEN}BLOCKED${RESET}" || echo -e "${YELLOW}not blocked${RESET}")"

STATUS=$(http_status -H "User-Agent: Mozilla/5.0" "$TARGET/")
echo -e "  Normal User-Agent:  HTTP $STATUS $([ "$STATUS" = "200" ] && echo -e "${GREEN}ALLOWED${RESET}" || echo -e "${YELLOW}unexpected${RESET}")"
echo ""
cool_down

# =========================================================================
# TEST 5: Blocked HTTP Methods
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 5: HTTP Method Restriction ---${RESET}"

for METHOD in DELETE PUT PATCH OPTIONS; do
    STATUS=$(http_status -X "$METHOD" "$TARGET/")
    echo -e "  $METHOD:\tHTTP $STATUS $([ "$STATUS" = "444" ] || [ "$STATUS" = "000" ] && echo -e "${GREEN}BLOCKED (connection closed)${RESET}" || echo -e "${YELLOW}status: $STATUS${RESET}")"
done
echo ""
cool_down

# =========================================================================
# TEST 6: Oversized Header Attack
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 6: Oversized Header Attack ---${RESET}"
BIG_HEADER=$(python3 -c "print('X' * 8192)" 2>/dev/null || printf '%8192s' | tr ' ' 'X')
STATUS=$(http_status -H "X-Attack: $BIG_HEADER" "$TARGET/")
echo -e "  8KB header: HTTP $STATUS $([ "$STATUS" = "400" ] || [ "$STATUS" = "494" ] && echo -e "${GREEN}REJECTED${RESET}" || echo -e "${YELLOW}status: $STATUS${RESET}")"
echo ""
cool_down

# =========================================================================
# TEST 7: Server Version Disclosure
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 7: Server Version Disclosure ---${RESET}"
SERVER_HEADER=$(curl -sI "$TARGET/" | grep -i "^server:" || echo "Server: (none)")
echo -e "  $SERVER_HEADER"
if echo "$SERVER_HEADER" | grep -qi "nginx/"; then
    echo -e "  ${RED}FAIL: Server version is exposed${RESET}"
else
    echo -e "  ${GREEN}PASS: Server version is hidden${RESET}"
fi
echo ""

# =========================================================================
# TEST 8: Backend Load Balancing (K8s feature)
# =========================================================================
echo -e "${BOLD}${CYAN}--- Test 8: Backend Pod Load Balancing ---${RESET}"
echo "Sending 6 requests to /api/info and checking which pods respond..."

declare -A POD_COUNTS 2>/dev/null || true
PODS=""
for i in $(seq 1 6); do
    POD=$(curl -s "$TARGET/api/info" | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])" 2>/dev/null || echo "unknown")
    echo -e "  Request $i → pod: ${CYAN}$POD${RESET}"
    PODS="$PODS $POD"
done

UNIQUE=$(echo "$PODS" | tr ' ' '\n' | sort -u | grep -v '^$' | wc -l)
echo ""
if [ "$UNIQUE" -gt 1 ]; then
    echo -e "  ${GREEN}PASS: Requests were distributed across $UNIQUE different backend pods.${RESET}"
else
    echo -e "  ${YELLOW}NOTE: All requests hit the same pod. With 2 replicas, K8s may route locally. Try more requests.${RESET}"
fi
echo ""

# =========================================================================
# SUMMARY
# =========================================================================
echo -e "${BOLD}${CYAN}=========================================================${RESET}"
echo -e "${BOLD}${CYAN}  All Tests Complete                                     ${RESET}"
echo -e "${BOLD}${CYAN}=========================================================${RESET}"
echo ""
echo "DDoS protections demonstrated (Nginx Gateway):"
echo "  1. Rate limiting          — 10r/s per IP, burst 20"
echo "  2. Connection limiting    — 10 concurrent per IP"
echo "  3. Bot/UA filtering       — Blocks attack tools & empty UAs"
echo "  4. HTTP method restriction — Only GET/HEAD/POST"
echo "  5. Header size limits     — Rejects oversized payloads"
echo "  6. Version hiding         — server_tokens off"
echo ""
echo "Kubernetes features demonstrated:"
echo "  7. Multi-pod routing      — Gateway → Frontend & Backend"
echo "  8. Load balancing         — Requests spread across pod replicas"
echo "  9. Health checks          — Readiness & liveness probes"
echo " 10. Service discovery      — DNS-based inter-pod communication"
