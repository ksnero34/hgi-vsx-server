# VSCode Extension Migration Guide

이 가이드는 인터넷 환경에서 VSCode extension들을 다운로드하고, 폐쇄망 환경의 OpenVSX 레지스트리에 업로드하는 방법을 설명합니다.

## 전체 워크플로우

```
[인터넷 환경]                    [USB]                [폐쇄망 환경]
    |                             |                         |
    | 1. Extension 다운로드        |                         |
    | download-extensions.sh      |                         |
    |                             |                         |
    | 2. USB로 복사      -------> | 3. USB 마운트 --------> |
    |                             |                         |
    |                             |              4. Extension 업로드
    |                             |              upload-extensions.sh
    |                             |                         |
    |                             |                    OpenVSX Registry
```

---

## 1단계: 인터넷 환경에서 Extension 다운로드

### 사전 요구사항
- Node.js (v16 이상)
- npm

### 1.1 Extension 목록 작성

`extensions.txt` 파일을 편집하여 필요한 extension들을 추가합니다:

```bash
vim extensions.txt
```

#### 기본 포맷
```
publisher.extension-name[@version][@target-platform]
```

#### 예시
```bash
# Latest version (버전 생략)
ms-python.python
dbaeumer.vscode-eslint

# 특정 버전 지정
ms-python.python@2024.0.0
dbaeumer.vscode-eslint@2.4.4
eamodio.gitlens@14.7.0

# 특정 플랫폼용
ms-python.python@2024.0.0@linux-x64
ms-python.python@2024.0.0@win32-x64
ms-python.python@2024.0.0@darwin-arm64

# Latest 버전의 특정 플랫폼
ms-python.python@@linux-x64
rust-lang.rust-analyzer@@darwin-arm64
```

#### 지원하는 Target Platforms
- `win32-x64` - Windows 64-bit
- `win32-ia32` - Windows 32-bit
- `win32-arm64` - Windows ARM64
- `linux-x64` - Linux 64-bit
- `linux-arm64` - Linux ARM64
- `linux-armhf` - Linux ARM 32-bit
- `darwin-x64` - macOS Intel
- `darwin-arm64` - macOS Apple Silicon (M1/M2)
- `alpine-x64` - Alpine Linux 64-bit
- `alpine-arm64` - Alpine Linux ARM64

#### Extension ID 찾는 방법
- **VSCode Marketplace**: `https://marketplace.visualstudio.com/vscode`
- **Open VSX**: `https://open-vsx.org/`
- **VSCode에서**: Extension 상세 페이지의 "Extension ID" 확인
- **VSCode에서**: Extension 우클릭 > "Copy Extension ID"

#### 버전 번호 찾는 방법
- **VSCode Marketplace**: Extension 페이지의 "Version History" 탭
- **Open VSX**: Extension 페이지의 버전 드롭다운
- **VSCode에서**: 설치된 extension의 버전 확인

### 1.2 다운로드 스크립트 실행

#### 옵션 A: 기본 다운로드 (빠름)

```bash
# 실행 권한 부여
chmod +x scripts/download-extensions.sh

# Extension 다운로드
./scripts/download-extensions.sh extensions.txt
```

#### 옵션 B: Dependencies 자동 해결 (권장)

```bash
# 실행 권한 부여
chmod +x scripts/download-extensions-with-deps.sh

# Extension과 모든 dependencies 다운로드
./scripts/download-extensions-with-deps.sh extensions.txt
```

**Dependencies 스크립트의 추가 기능:**
1. 자동으로 extension dependencies 탐지
2. Pre-release와 stable 버전 모두 다운로드
3. 재귀적으로 모든 dependencies 다운로드
4. 중복 다운로드 방지
5. Open VSX와 VS Marketplace 모두 지원

**예시 출력:**
```
[1] Processing: ms-kubernetes-tools.vscode-kubernetes-tools
  → Downloading stable version...
    ✓ Downloaded stable from Open VSX
  → Downloading pre-release version...
    ✓ Downloaded pre-release from Open VSX
  → Checking dependencies...
  ✓ Found 2 dependencies
    + redhat.vscode-yaml
    + ms-kubernetes-tools.vscode-kubernetes-tools-core

Phase 2: Downloading dependencies
...
```

### 1.3 다운로드 결과 확인

```bash
# 다운로드된 extension 확인
tree extensions/

# 예상 구조:
# extensions/
# ├── ms-python/
# │   └── python/
# │       ├── ms-python.python-2024.0.0.vsix
# │       └── metadata.json
# ├── dbaeumer/
# │   └── vscode-eslint/
# │       └── dbaeumer.vscode-eslint-3.0.0.vsix
# └── ...
```

### 1.4 USB로 복사

```bash
# USB 마운트 (Linux 예시)
sudo mount /dev/sdb1 /mnt/usb

# Extensions 복사
cp -r extensions /mnt/usb/

# 안전하게 언마운트
sudo umount /mnt/usb
```

---

## 2단계: 폐쇄망 환경에서 Extension 업로드

### 사전 요구사항
- OpenVSX 서버 실행 중
- Personal Access Token (PAT)

### 2.1 Personal Access Token 생성

1. 브라우저에서 OpenVSX에 접속: `http://vsx.hgi.com:28080`
2. OIDC로 로그인
3. 우측 상단 프로필 > "User Settings" 클릭
4. "Access Tokens" 탭으로 이동
5. "Create new token" 클릭
   - Description: `Extension Publishing`
   - 생성된 토큰을 복사하여 안전하게 보관

### 2.2 환경 변수 설정

```bash
# PAT 설정 (매번 실행 시 필요)
export OVSX_PAT="your-personal-access-token-here"

# Registry URL 설정 (기본값: http://vsx.hgi.com:28080)
export OVSX_REGISTRY_URL="http://vsx.hgi.com:28080"
```

또는 `.env` 파일에 추가:
```bash
echo "OVSX_PAT=your-token" >> ~/.bashrc
echo "OVSX_REGISTRY_URL=http://vsx.hgi.com:28080" >> ~/.bashrc
source ~/.bashrc
```

### 2.3 USB에서 Extensions 복사

```bash
# USB 마운트
sudo mount /dev/sdb1 /mnt/usb

# Extensions 복사
cp -r /mnt/usb/extensions ~/hgi-vsx-server/

# USB 언마운트
sudo umount /mnt/usb
```

### 2.4 업로드 스크립트 실행

```bash
# 실행 권한 부여
chmod +x scripts/upload-extensions.sh

# Extensions 업로드
./scripts/upload-extensions.sh extensions/
```

스크립트는 다음을 수행합니다:
1. 각 extension의 namespace 생성 (없는 경우)
2. Extension을 OpenVSX에 업로드
3. 버전, 메타데이터 등 모든 정보가 함께 등록됨
4. 이미 등록된 extension은 스킵

### 2.5 업로드 결과 확인

```bash
# 브라우저에서 확인
# http://vsx.hgi.com:28080

# 또는 CLI로 확인
curl http://vsx.hgi.com:28080/api/-/search?query=python
```

---

## Docker 컨테이너 사용 (권장)

Node.js가 설치되어 있지 않은 경우, CLI 컨테이너를 사용할 수 있습니다:

### 다운로드 (인터넷 환경)

```bash
# 임시 컨테이너로 실행
docker run --rm -it \
  -v $(pwd)/extensions.txt:/workspace/extensions.txt \
  -v $(pwd)/extensions:/workspace/extensions \
  -v $(pwd)/scripts:/workspace/scripts \
  node:18 bash

# 컨테이너 내부에서
cd /workspace
npm install -g ovsx
./scripts/download-extensions.sh extensions.txt
exit
```

### 업로드 (폐쇄망 환경)

```bash
# CLI 서비스 사용
docker compose run --rm cli bash

# 컨테이너 내부에서
export OVSX_PAT="your-token"
export OVSX_REGISTRY_URL="http://server:8080"
/workspace/scripts/upload-extensions.sh /workspace/extensions/
exit
```

---

## 트러블슈팅

### Extension 다운로드 실패

```bash
# 특정 extension만 재시도
ovsx get ms-python.python -o ./extensions/ms-python/python/

# VS Marketplace에서 직접 다운로드
curl -L "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-python/vsextensions/python/latest/vspackage" \
  -o ms-python.python.vsix
```

### 업로드 권한 에러

```bash
# PAT 확인
echo $OVSX_PAT

# 새로운 PAT 생성
# 브라우저에서 User Settings > Access Tokens

# Namespace 수동 생성
ovsx create-namespace ms-python -p $OVSX_PAT -r $OVSX_REGISTRY_URL
```

### 중복 버전 에러

스크립트는 자동으로 `--skip-duplicate` 옵션을 사용하여 중복을 건너뜁니다.
수동으로 업로드할 때도 이 옵션을 사용하세요:

```bash
ovsx publish extension.vsix -p $OVSX_PAT -r $OVSX_REGISTRY_URL --skip-duplicate
```

### 네트워크 연결 문제

```bash
# Registry 연결 확인
curl http://vsx.hgi.com:28080/api/version

# 서버 로그 확인
docker compose logs -f server
```

---

## 고급 사용법

### 특정 버전 다운로드

```bash
# ovsx CLI 직접 사용
ovsx get ms-python.python --version 2023.20.0

# 또는 extensions.txt에 추가
echo "ms-python.python@2023.20.0" >> extensions.txt
./scripts/download-extensions.sh
```

### Platform-specific Extensions

일부 extension은 플랫폼별로 제공됩니다:

```bash
# ovsx CLI 직접 사용
ovsx get ms-python.python --target linux-x64
ovsx get ms-python.python --target win32-x64
ovsx get ms-python.python --target darwin-arm64

# 또는 extensions.txt에 추가
cat >> extensions.txt << EOF
ms-python.python@@linux-x64
ms-python.python@@win32-x64
ms-python.python@@darwin-arm64
EOF
./scripts/download-extensions.sh
```

### 여러 버전 동시 다운로드

동일한 extension의 여러 버전을 다운로드할 수 있습니다:

```bash
# extensions.txt
ms-python.python@2024.0.0
ms-python.python@2023.22.0
ms-python.python@2023.20.0

# 각 버전은 별도 디렉토리에 저장됩니다:
# extensions/ms-python/python/2024.0.0/
# extensions/ms-python/python/2023.22.0/
# extensions/ms-python/python/2023.20.0/
```

### Batch 다운로드

```bash
# 여러 버전 동시 다운로드
cat << EOF > download-all.sh
#!/bin/bash
ovsx get ms-python.python -o extensions/ &
ovsx get dbaeumer.vscode-eslint -o extensions/ &
ovsx get esbenp.prettier-vscode -o extensions/ &
wait
EOF
chmod +x download-all.sh
./download-all.sh
```

### Extension 메타데이터 확인

```bash
# JSON 메타데이터 보기
ovsx get ms-python.python --metadata | jq .

# 특정 필드만 추출
ovsx get ms-python.python --metadata | jq '.version, .displayName'
```

---

## 참고 자료

- OpenVSX Documentation: https://github.com/eclipse/openvsx/wiki
- OVSX CLI: https://github.com/eclipse/openvsx/tree/master/cli
- VSCode Extension API: https://code.visualstudio.com/api
- Extension Marketplace: https://marketplace.visualstudio.com/vscode


## Extension pack 만드는법
기본 구조(최소):

package.json에 categories: ["Extension Packs"]
extensionPack 배열에 묶을 확장 ID들
아이콘/README/CHANGELOG는 선택이지만 보통 포함
예시(핵심만):

{
  "name": "my-pack",
  "displayName": "My Extension Pack",
  "version": "0.0.1",
  "publisher": "myorg",
  "engines": { "vscode": "^1.90.0" },
  "categories": ["Extension Packs"],
  "extensionPack": [
    "ms-python.python",
    "esbenp.prettier-vscode"
  ]
}
VSIX 패키징:

폴더 준비: package.json, README.md, LICENSE (선택)
vsce로 패키징
npm i -g @vscode/vsce
cd hgi-extension-pack
vsce package