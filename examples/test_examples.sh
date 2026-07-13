#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDS=""
FAIL=0
PASS=0

cleanup() {
    for p in $PIDS; do kill "$p" 2>/dev/null || true; done
    wait 2>/dev/null || true
}
trap cleanup EXIT

run_test() {
    local name="$1" port="$2" desc="$3" cmd="$4"
    printf "  %-30s " "$desc"
    local code body
    body=$(eval "$cmd" 2>/dev/null) || true
    if [ $? -eq 0 ] && [ -n "$body" ]; then
        PASS=$((PASS+1))
        echo "PASS"
    else
        FAIL=$((FAIL+1))
        echo "FAIL (unexpected)"
    fi
}

run_status_test() {
    local name="$1" port="$2" desc="$3" url="$4" expect="$5" extra="${6:-}"
    printf "  %-30s " "$desc"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" $extra "http://localhost:$port$url" 2>/dev/null || true)
    if [ "$code" = "$expect" ]; then
        PASS=$((PASS+1))
        echo "PASS (HTTP $code)"
    else
        FAIL=$((FAIL+1))
        echo "FAIL (expected HTTP $expect, got $code)"
    fi
}

run_header_test() {
    local name="$1" port="$2" desc="$3" url="$4" header="$5" expect="$6"
    printf "  %-30s " "$desc"
    local val
    val=$(curl -sI "http://localhost:$port$url" 2>/dev/null | grep -i "^$header:" | tr -d '\r' | sed 's/[^:]*: *//' || true)
    if echo "$val" | grep -qi "$expect"; then
        PASS=$((PASS+1))
        echo "PASS ($header: $val)"
    else
        FAIL=$((FAIL+1))
        echo "FAIL (expected $header containing '$expect', got '$val')"
    fi
}

echo "=== Building examples ==="
cd "$ROOT"
zig build 2>&1 | sed 's/^/  /'

echo ""
echo "=== Starting servers ==="

start_svr() {
    local name="$1" port="$2"
    zig build "$name" -- --listen "0.0.0.0:$port" &
    local pid=$!
    PIDS="$PIDS $pid"
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "  FAILED to start $name on port $port"
        exit 1
    fi
    echo "  $name -> port $port (PID $pid)"
}

start_svr ex-resource      8001
start_svr ex-mount         8002
start_svr ex-middleware    8003
start_svr ex-cors          8004
start_svr ex-rate-limit    8005
start_svr ex-version       8006
start_svr ex-comprehensive 8007

echo ""
echo "=== Running tests ==="

echo "  01_resource ($1)"
run_status_test 01 8001 "GET /posts 200" "/posts" 200
run_status_test 01 8001 "GET /posts/42 200" "/posts/42" 200
run_status_test 01 8001 "POST /posts 201" "/posts" 201 "-X POST -d '{\"t\":1}'"
run_status_test 01 8001 "PUT /posts/1 200" "/posts/1" 200 "-X PUT -d '{\"t\":1}'"
run_status_test 01 8001 "DELETE /posts/1 200" "/posts/1" 200 "-X DELETE"
run_status_test 01 8001 "PATCH /posts/1 404" "/posts/1" 404 "-X PATCH"

echo "  02_mount ($2)"
run_status_test 02 8002 "GET /admin/dashboard 200" "/admin/dashboard" 200
run_status_test 02 8002 "GET /admin/settings 200" "/admin/settings" 200
run_status_test 02 8002 "GET /api/users 200" "/api/users" 200
run_status_test 02 8002 "GET /api/posts 200" "/api/posts" 200
run_status_test 02 8002 "GET /api/posts/5 200" "/api/posts/5" 200
run_status_test 02 8002 "GET /admin 404" "/admin" 404

echo "  03_middleware ($3)"
run_status_test 03 8003 "GET /public 200" "/public" 200
run_status_test 03 8003 "GET /admin (no auth) 403" "/admin" 403
run_status_test 03 8003 "GET /admin (bad token) 403" "/admin" 403 "-H 'Authorization: Bearer wrong'"
run_status_test 03 8003 "GET /admin (valid auth) 200" "/admin" 200 "-H 'Authorization: Bearer secret-token'"

echo "  04_cors ($4)"
run_status_test 04 8004 "GET /public (no CORS) 200" "/public" 200
run_header_test 04 8004 "GET /api/posts (CORS myapp)" "/api/posts" "access-control-allow-origin" "https://myapp.com"
run_header_test 04 8004 "POST /api/login (CORS dashboard)" "/api/login" "access-control-allow-origin" "dashboard"

echo "  05_rate_limit ($5)"
run_status_test 05 8005 "POST /login #1 200" "/login" 200 "-X POST"
run_status_test 05 8005 "POST /login #2 200" "/login" 200 "-X POST"
run_status_test 05 8005 "POST /login #3 200" "/login" 200 "-X POST"
run_status_test 05 8005 "POST /login #4 429" "/login" 429 "-X POST"
run_status_test 05 8005 "GET /posts (no limit) 200" "/posts" 200

echo "  06_version ($6)"
run_status_test 06 8006 "GET /api/v1/users 200" "/api/v1/users" 200
run_status_test 06 8006 "GET /api/v2/users 200" "/api/v2/users" 200
run_status_test 06 8006 "GET /api/v2/posts 200" "/api/v2/posts" 200
run_status_test 06 8006 "POST /api/v2/posts 201" "/api/v2/posts" 201 "-X POST"
run_status_test 06 8006 "GET /api/v3/users 404" "/api/v3/users" 404

echo "  07_comprehensive ($7)"
run_status_test 07 8007 "GET /healthz 200" "/healthz" 200
run_status_test 07 8007 "GET /admin/users (no auth) 403" "/admin/users" 403
run_status_test 07 8007 "GET /admin/users (auth) 200" "/admin/users" 200 "-H 'Authorization: Bearer admin-secret'"
run_status_test 07 8007 "POST /admin/users (auth+body) 201" "/admin/users" 201 "-H 'Authorization: Bearer admin-secret' -X POST -d '{}'"
run_status_test 07 8007 "GET /api/v2/data 200" "/api/v2/data" 200
run_status_test 07 8007 "POST /api/v2/posts (CORS+limit) 201" "/api/v2/posts" 201 "-X POST -d '{}'"
run_header_test 07 8007 "POST /api/v2/posts CORS header" "/api/v2/posts" "access-control-allow-origin" "blog.example.com"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
