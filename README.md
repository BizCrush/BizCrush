# BizCrush Desktop Release Guide

로컬에서 macOS 빌드하고 GitHub Pages에 배포하는 방법입니다.

## 사전 준비

### 1. Sparkle Private Key 설정

처음 한 번만 설정하면 됩니다:

```bash
mkdir -p ~/.bizcrush
echo 'MC4CAQAwBQYDK2VwBCIEIL9xssdU1DtxyhWKoRrcjsl235gFKjTibAwQv9UoRURE' > ~/.bizcrush/sparkle_private_key.pem
chmod 600 ~/.bizcrush/sparkle_private_key.pem
```

### 2. GitHub CLI 설치 및 인증

**로컬에서 배포하려면 필수:**

```bash
brew install gh
gh auth login
```

GitHub CLI로 인증하면 BizCrush/BizCrush GitHub Pages에 자동으로 배포할 수 있습니다.

### 3. GitHub Actions 자동화 설정 (선택사항)

태그를 푸시하면 자동으로 빌드 및 배포하려면:

1. Personal Access Token 생성: https://github.com/settings/tokens
   - Scopes: `repo`, `workflow`

2. adelab-inc/biz-crush에 Secret 추가: https://github.com/adelab-inc/biz-crush/settings/secrets/actions
   - Name: `GH_PAGES_TOKEN`
   - Value: 위에서 생성한 토큰

이후 태그를 푸시하면 자동으로 BizCrush/BizCrush GitHub Pages에 배포됩니다.

## 릴리스 방법

### 빠른 실행

```bash
cd desktop
./release-macos.sh 0.21.0
```

버전 번호만 입력하면 자동으로:
1. ✅ Flutter 앱 빌드
2. ✅ DMG 생성
3. ✅ Sparkle 서명
4. ✅ appcast.xml 생성
5. ✅ BizCrush/BizCrush 저장소에 배포
6. ✅ Git 태그 생성
7. ✅ GitHub Release 생성 (gh CLI 있는 경우)

## 배포 확인

다음 URL에서 확인:

- 다운로드 페이지: https://bizcrush.github.io/BizCrush/
- DMG 직접 링크: https://bizcrush.github.io/BizCrush/BizCrush-v0.21.0.dmg
- 업데이트 피드: https://bizcrush.github.io/BizCrush/appcast.xml
