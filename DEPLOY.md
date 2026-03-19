# GLM-OCR Docker 배포 가이드

## 아키텍처

```
┌─────────────────────────────────────────────────┐
│  Client                                         │
│  POST /glmocr/parse  {"images": ["url", ...]}   │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  glm-ocr-server (Flask, port 8511)               │
│  - Layout 감지 (PP-DocLayoutV3)                   │
│  - 결과 조합 및 Markdown 변환                      │
└──────────────────────┬───────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  OCR 모델 서버                                    │
│  - CPU: Ollama (port 11434)                      │
│  - GPU: vLLM  (port 8000)                        │
└──────────────────────────────────────────────────┘
```

---

## 사전 요구사항

- Docker >= 24.0
- Docker Compose >= 2.20
- (GPU 버전) NVIDIA Driver >= 535, nvidia-container-toolkit 설치

---

## 1. CPU 버전 (Ollama)

GPU 없이 로컬에서 전체 파이프라인을 실행합니다.

### 파일 구성

| 파일 | 설명 |
|------|------|
| `Dockerfile` | Flask 서버 이미지 (CPU torch) |
| `config-ollama.yaml` | Ollama 연동 설정 |
| `docker-compose.yaml` | Flask + Ollama 통합 |

### 빌드 및 실행

```bash
# 빌드 & 실행
docker compose up -d

# Ollama에 GLM-OCR 모델 다운로드 (최초 1회, 약 1GB)
docker exec glm-ocr-ollama ollama pull glm-ocr:latest
```

### 로그 확인

```bash
# 전체 로그
docker compose logs -f

# 개별 컨테이너
docker logs -f glm-ocr-ollama
docker logs -f glm-ocr-server
```

### 종료 및 정리

```bash
# 종료
docker compose down

# 볼륨(모델 캐시)까지 삭제
docker compose down -v
```

---

## 2. GPU 버전 (vLLM)

NVIDIA GPU를 활용하여 고성능으로 서빙합니다.

### 파일 구성

| 파일 | 설명 |
|------|------|
| `Dockerfile.gpu` | Flask 서버 이미지 (GPU torch) |
| `config-vllm.yaml` | vLLM 연동 설정 |
| `docker-compose.gpu.yaml` | Flask + vLLM 통합 |

### 빌드 및 실행

```bash
# 빌드 & 실행 (모델 다운로드 포함, 최초 실행 시 시간 소요)
docker compose -f docker-compose.gpu.yaml up -d
```

vLLM이 `THUDM/GLM-OCR` 모델을 HuggingFace에서 자동 다운로드합니다.
모델 로딩이 완료될 때까지 health check가 대기합니다 (최대 약 2분).

### 로그 확인

```bash
# 전체 로그
docker compose -f docker-compose.gpu.yaml logs -f

# vLLM 로딩 상태 확인
docker logs -f glm-ocr-vllm

# Flask 서버 확인
docker logs -f glm-ocr-server
```

### GPU 사용량 모니터링

```bash
watch -n 1 nvidia-smi
```

### 종료 및 정리

```bash
# 종료
docker compose -f docker-compose.gpu.yaml down

# 볼륨(모델 캐시)까지 삭제
docker compose -f docker-compose.gpu.yaml down -v
```

---

## 3. 테스트

### Health Check

```bash
curl http://localhost:8511/health
# 응답: {"status": "ok"}
```

### OCR API 호출 (URL 이미지)

```bash
curl -X POST http://localhost:8511/glmocr/parse \
  -H "Content-Type: application/json" \
  -d '{"images": ["https://example.com/document.png"]}'
```

### OCR API 호출 (Base64 이미지)

```bash
# 로컬 이미지를 base64로 인코딩하여 전송
BASE64_IMG=$(base64 -i test.png)

curl -X POST http://localhost:8511/glmocr/parse \
  -H "Content-Type: application/json" \
  -d "{\"images\": [\"data:image/png;base64,${BASE64_IMG}\"]}"
```

### 복수 이미지 요청

```bash
curl -X POST http://localhost:8511/glmocr/parse \
  -H "Content-Type: application/json" \
  -d '{
    "images": [
      "https://example.com/page1.png",
      "https://example.com/page2.png"
    ]
  }'
```

### 응답 형식

```json
{
  "json_result": { ... },
  "markdown_result": "# 문서 제목\n\n본문 내용..."
}
```

### Python으로 테스트

```python
import requests

resp = requests.post(
    "http://localhost:8511/glmocr/parse",
    json={"images": ["https://example.com/document.png"]},
)
result = resp.json()
print(result["markdown_result"])
```

---

## 4. 설정 커스터마이징

### 환경변수로 설정 변경

```bash
# docker-compose.yaml의 glm-ocr 서비스에 environment 추가
environment:
  - GLMOCR_LOG_LEVEL=DEBUG
  - GLMOCR_ENABLE_LAYOUT=false
```

### config 파일 직접 수정

호스트에서 `config-ollama.yaml` 또는 `config-vllm.yaml`을 수정한 뒤 재시작:

```bash
# CPU 버전
docker compose restart glm-ocr

# GPU 버전
docker compose -f docker-compose.gpu.yaml restart glm-ocr
```

### Layout 감지 끄기

빠른 테스트가 필요하면 layout 감지를 비활성화할 수 있습니다:

```yaml
# config 파일에서
pipeline:
  enable_layout: false
```

---

## 5. 트러블슈팅

### Ollama 모델이 없다는 오류

```bash
docker exec glm-ocr-ollama ollama list
# glm-ocr:latest 가 없으면 다시 pull
docker exec glm-ocr-ollama ollama pull glm-ocr:latest
```

### vLLM이 OOM으로 죽는 경우

`docker-compose.gpu.yaml`의 vLLM command에 GPU 메모리 제한 추가:

```yaml
command:
  - --model
  - THUDM/GLM-OCR
  - --gpu-memory-utilization
  - "0.8"
  # ... 나머지 옵션
```

### Flask 서버가 OCR 서버에 연결 실패

```bash
# OCR 서버가 정상 동작하는지 확인
# Ollama
curl http://localhost:11434/

# vLLM
curl http://localhost:8000/health
```

### 컨테이너 간 네트워크 문제

```bash
# docker compose 네트워크 확인
docker network ls
docker network inspect glm-ocr_default
```

---

## 6. CPU vs GPU 비교

| 항목 | CPU (Ollama) | GPU (vLLM) |
|------|-------------|------------|
| 하드웨어 | CPU만 필요 | NVIDIA GPU 필요 |
| 처리 속도 | 느림 | 빠름 |
| 동시 처리 | 제한적 (`max_workers: 1`) | 높음 (`max_workers: 32`) |
| Layout batch | 1 | 8 |
| 적합 용도 | 개발/테스트/소량 처리 | 프로덕션/대량 처리 |
| 모델 다운로드 | `ollama pull` 수동 실행 | vLLM 자동 다운로드 |
