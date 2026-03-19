#!/bin/bash
set -e

HOST="${1:-localhost}"
PORT="${2:-8511}"
BASE_URL="http://${HOST}:${PORT}"

echo "=== GLM-OCR 배포 테스트 ==="
echo "Target: ${BASE_URL}"
echo ""

# 1. Health check
echo "[1/4] Health check..."
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health")
if [ "$HEALTH" = "200" ]; then
  echo "  OK (200)"
else
  echo "  FAIL (${HEALTH}) - 서버가 실행 중인지 확인하세요"
  exit 1
fi
echo ""

# 2. Ollama 연결 확인
echo "[2/4] Ollama 모델 확인..."
MODELS=$(docker exec glm-ocr-ollama ollama list 2>/dev/null || echo "FAIL")
if echo "$MODELS" | grep -q "glm-ocr"; then
  echo "  OK - glm-ocr 모델 존재"
else
  echo "  모델 없음 - 다운로드 중..."
  docker exec glm-ocr-ollama ollama pull glm-ocr:latest
  echo "  다운로드 완료"
fi
echo ""

# 3. OCR 테스트 (URL 이미지)
echo "[3/4] OCR 테스트 (URL 이미지)..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/glmocr/parse" \
  -H "Content-Type: application/json" \
  -d '{"images": ["https://raw.githubusercontent.com/zai-org/GLM-OCR/main/examples/source/code.png"]}')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
  echo "  OK (200)"
  echo "  응답 미리보기:"
  echo "$BODY" | python3 -m json.tool 2>/dev/null | head -20
else
  echo "  FAIL (${HTTP_CODE})"
  echo "$BODY"
fi
echo ""

# 4. OCR 테스트 (로컬 이미지 base64) - 테스트 이미지가 있는 경우
echo "[4/4] OCR 테스트 (Base64 이미지)..."
TEST_IMG=""
for candidate in test.png test.jpg examples/source/code.png; do
  if [ -f "$candidate" ]; then
    TEST_IMG="$candidate"
    break
  fi
done

if [ -n "$TEST_IMG" ]; then
  BASE64_IMG=$(base64 -w 0 "$TEST_IMG" 2>/dev/null || base64 -i "$TEST_IMG" 2>/dev/null)
  EXT="${TEST_IMG##*.}"
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/glmocr/parse" \
    -H "Content-Type: application/json" \
    -d "{\"images\": [\"data:image/${EXT};base64,${BASE64_IMG}\"]}")
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  OK (200) - ${TEST_IMG}"
    echo "  응답 미리보기:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null | head -20
  else
    echo "  FAIL (${HTTP_CODE})"
    echo "$BODY"
  fi
else
  echo "  SKIP - 로컬 테스트 이미지 없음 (test.png 등을 배치하면 테스트됩니다)"
fi

echo ""
echo "=== 테스트 완료 ==="
