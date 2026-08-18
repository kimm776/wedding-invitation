# HTML, CSS, JS 만으로 된 청첩장

server가 없습니다. `build.sh` 를 돌리면 `dist/` 에 완성된 정적 파일이 나옵니다.
그 폴더를 정적 호스팅에 올리면 됩니다.
GitHub Pages, Cloudflare Pages, Netlify, Vercel, S3 어디든 됩니다.

**필요한 명령은 `bash`, `sed`, `awk`, `od`, `base64` 입니다.** macOS와 Linux에 기본으로 있습니다.
Windows에서는 `build.ps1` 을 씁니다.

축하 한마디를 저장할 곳이 없으므로 **입력창과 기록 목록이 나오지 않습니다.**
받은 축하를 모으시려면 [../with-guestbook](../with-guestbook) 을 참고해 주시기 바랍니다.

이 구성으로 올린 demo가 <a href="https://invitation-demo-type-a.nerd.kim/" target="_blank" rel="noopener noreferrer">invitation-demo-type-a.nerd.kim</a> 에 있습니다.
<a href="https://invitation-demo-type-a.nerd.kim/developer.html" target="_blank" rel="noopener noreferrer">developer</a> 와
<a href="https://invitation-demo-type-a.nerd.kim/terminal.html" target="_blank" rel="noopener noreferrer">terminal</a> version도 함께 올라가 있습니다.

---

## 5분 만에 띄우기

**macOS, Linux**

```bash
cp invitation.conf.example invitation.conf   # demo 데이터가 들어 있습니다
./build.sh                                   # dist/ 가 생깁니다
./startup.sh                                 # http://localhost:8080
```

**Windows (PowerShell)**

```powershell
Copy-Item invitation.conf.example invitation.conf
.\build.ps1
.\startup.ps1                                # http://localhost:8080
```

`build.ps1` 은 `build.sh` 와 같은 `invitation.conf` 를 읽어 같은 결과를 만듭니다.
실행 정책 때문에 막히면 해당 session에서만 허용해 주시기 바랍니다.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

이 세 줄로 demo 청첩장이 바로 보입니다. 그다음 `invitation.conf` 를 본인의 정보로 고치고
`./build.sh` 를 다시 돌립니다.

---

## 내 청첩장으로 바꾸기

**`invitation.conf` 한 파일만 고치면 됩니다.** 이름, 예식 일시, 예식장, 오시는 길,
사진 목록, 계좌, API key가 전부 여기 있습니다.

```ini
GROOM_NAME="김앙아"
BRIDE_NAME="최엥에"
WEDDING_AT="2026-11-14T11:00:00+09:00"
VENUE_NAME="별빛웨딩홀"
INFO_PARKING="건물 지하 주차장 이용\n무료주차 2시간"
```

`src/` 아래 HTML과 JS에는 실제 값이 하나도 없습니다. `{{GROOM_NAME}}` 같은 token만 있고
`build.sh` 가 채웁니다. 그래서 fork해도 남의 개인정보가 따라오지 않습니다.
본인의 정보가 실수로 commit되지도 않습니다. `invitation.conf` 는 `.gitignore` 대상입니다.

항목별 설명은 `invitation.conf.example` 의 주석에 전부 달려 있습니다.

### 예식 일시는 한 곳만 고치면 나머지가 따라옵니다

`WEDDING_AT` 하나만 바꾸면 아래가 전부 자동으로 다시 계산됩니다.

- 한국어 날짜와 요일: `2026년 11월 14일 토요일 오전 11시`
- D-day countdown과 달력 하이라이트
- terminal version의 `SAT 2026-11-14 11:00:00 KST` 와 LCD countdown
- developer version의 release 날짜 표시
- `og:description` 의 일자와 장소

요일은 `build.sh` 가 KST 기준으로 직접 계산합니다. `date` 명령의 GNU와 BSD 차이나
system timezone에 좌우되지 않습니다. 분이 0이면 '오전 11시', 30분이면 '오전 11시 30분' 처럼
표기도 알아서 달라집니다.

형식은 **offset을 포함한 ISO 8601** 이어야 합니다.

```ini
WEDDING_AT="2026-11-14T11:00:00+09:00"   # O
WEDDING_AT="2026-11-14 11:00"            # X, offset이 없습니다
```

`FIRST_MET_AT` 은 두 사람이 처음 만난 날입니다. terminal version의 uptime과
진행 bar 기준점으로만 쓰입니다.

### 사진

`src/photos/` 에 넣고 `invitation.conf` 의 `PHOTO_*` 에 파일 이름을 적습니다.
자세한 내용은 [src/photos/README.md](src/photos/README.md) 에 있습니다.
비워 두어도 자리 표시가 나와 화면이 깨지지 않습니다.

### 지도와 카카오 공유 key

아래 [지도와 카카오 공유 key 발급하기](#지도와-카카오-공유-key-발급하기) 에 정리해 두었습니다.
비워도 청첩장은 정상 동작합니다.

---

## 세 가지 version

같은 내용을 세 가지 version으로 보여 줍니다. `build.sh` 는 언제나 세 개를 함께 생성합니다.
화면 아래 전환 link로 서로 이동할 수 있습니다.

| 파일 | 설명 |
|---|---|
| `main.html` | 파스텔 톤. 신랑신부 프로필, gallery, 달력 |
| `developer.html` | IDE와 CI/CD 콘셉트. dark와 light mode, git log 연출 |
| `terminal.html` | 녹색과 amber phosphor CRT. neofetch, LCD countdown, ASCII 달력 |
| `release.html` | 예식 시각이 지나면 열리는 감사 인사 page |

처음 열었을 때 어느 것을 보여줄지는 `DEFAULT_VERSION` 으로 고릅니다.
그 version의 사본이 `dist/index.html` 이 됩니다.

```ini
DEFAULT_VERSION="terminal"    # main, developer, terminal 중 하나
```

`release.html` 은 예식 시각 전에는 안내만 보여 줍니다. 미리 확인하려면
`?preview=1` 을 붙입니다. 예: `http://localhost:8080/release.html?preview=1`

---

## 계좌를 어떻게 숨기는가

계좌번호가 HTML이나 JS에 평문으로 있으면 검색 engine과 scraper가 그대로 가져갑니다.
세 겹으로 막습니다.

1. **원본 분리**: 번호는 `invitation.conf` 에만 있고 그 파일은 commit되지 않습니다.
2. **난독화**: `build.sh` 가 salt와 XOR을 거친 base64 blob으로 바꿔 넣습니다.
   `dist/` 의 어느 파일을 열어도 평문 번호가 없습니다.
3. **상호작용 시에만 render**: '마음 전하실 곳' 을 펼치거나 tap할 때에만 DOM에 그립니다.

`build.sh` 는 마지막에 **결과물에 평문 번호가 남았는지 직접 검사하고, 남아 있으면 실패시킵니다.**
사람이 직접 확인하는 대신 script가 막습니다.

> **주의: 난독화는 암호화가 아닙니다.** browser가 풀어야 하므로 마음먹은 사람은 읽을 수 있습니다.
> 목적은 검색 노출과 자동수집 차단입니다. 정말 비밀로 해야 하는 값이라면 정적 사이트에 두지 않는 편이 좋습니다.

---

## 축하 한마디

이 구성에는 축하 한마디를 저장할 backend가 없습니다. 그래서 **입력창과 기록 목록을 감춥니다.**
남길 수 없는 것을 남길 수 있는 것처럼 보여 주면 하객을 속이게 되기 때문입니다.
developer version과 terminal version의 AI agent 축하는 저장이 필요 없으므로 그대로 나옵니다.

실제로 모으려면 두 가지 방법이 있습니다.

1. **[../with-guestbook](../with-guestbook) 을 통째로 씁니다.** 정적 서빙과 API를 한 container가 합니다.
2. **정적 배포는 그대로 두고 API만 따로 띄웁니다.** `with-guestbook` 을 어딘가에 올리고
   그 주소를 `invitation.conf` 에 적습니다.

```ini
GUESTBOOK_API_BASE="https://guestbook.example.com/api"
```

이 값을 비워 두면 `build.sh` 가 `window.__NO_API__` 를 넣습니다. 청첩장 JS는 그 값을 보고
입력창과 기록 목록을 감춥니다. 없는 주소로 5초마다 요청하지도 않습니다.
값을 채우면 둘 다 다시 나옵니다.

---

## directory 구조

```
static/
├── build.sh                  invitation.conf 를 읽어 src/ 를 dist/ 로 변환합니다
├── startup.sh                dist/ 를 local에서 미리 봅니다
├── build.ps1                 build.sh 의 Windows 판
├── startup.ps1               startup.sh 의 Windows 판
├── invitation.conf.example   모든 항목과 설명. 이것을 복사해 씁니다
├── invitation.conf           내 정보. gitignore 대상입니다
├── src/                      원본. 실제 값이 없고 {{TOKEN}} 만 있습니다
│   ├── main.html             main version
│   ├── developer.html        developer version
│   ├── terminal.html         terminal version
│   ├── release.html          감사 인사 page
│   ├── css/                  main.css, developer.css, terminal.css
│   ├── js/
│   │   ├── config.js         네 page가 공유하는 설정과 축하 API client
│   │   ├── main.js           main version 동작
│   │   ├── developer.js      developer version 동작
│   │   ├── terminal.js       terminal version 동작
│   │   └── private.js        계좌 난독화 해제와 render
│   ├── assets/               카카오 icon, AI brand icon
│   └── photos/               사진을 넣는 곳. gitignore 대상입니다
└── dist/                     build 결과. gitignore 대상입니다
```

---

## build.sh 가 하는 일

```
invitation.conf ──┐
                  ├──> {{TOKEN}} 을 sed 로 치환         ──> dist/*.html
src/*.html     ───┘
                  ├──> 예식 일시에서 파생값을 KST로 계산
                  ├──> window.__WEDDING__ 등을 생성      ──> dist/js/data.js
                  ├──> 계좌를 난독화해 같은 파일에 심음
                  └──> css 와 js 참조에 ?v= 를 붙임

src/{css,js,assets,photos} ──> 그대로 복사              ──> dist/
```

`build.sh` 는 `data.js` 를 `config.js` 앞에 넣습니다. 청첩장 JS가 그 값을 먼저 읽어야 하기 때문입니다.

`?v=` 는 `css` 와 `js` 내용의 checksum입니다. 내용이 바뀌면 값이 바뀌므로
하객의 browser가 이전 파일을 계속 쓰는 일이 없습니다.

### 명령 몇 가지

```bash
./build.sh                       # invitation.conf -> dist/
./build.sh -c other.conf         # 다른 conf 로 build
./build.sh -o /tmp/out           # 다른 곳에 출력
./build.sh -h                    # 도움말
./startup.sh 3000                # port 지정
```

Windows 에서는 같은 것을 이렇게 씁니다.

```powershell
.\build.ps1
.\build.ps1 -Conf other.conf
.\build.ps1 -Out C:\temp\out
.\startup.ps1 -Port 3000
```

### build.sh 가 스스로 검사하는 것

- `invitation.conf` 와 `src/` 가 있는지
- `WEDDING_AT` 이 해석 가능한 ISO 8601 인지
- 이름과 일시가 비어 있지 않은지 (비면 경고)
- 치환되지 않은 `{{TOKEN}}` 이 남았는지 (남으면 경고)
- 생성한 JSON이 유효한지 (node가 있을 때)
- **결과물에 평문 계좌번호가 남았는지 (남으면 실패)**
- `dist/` 를 비우기 전에 그것이 이 script의 산출물인지 (`-o` 로 남의 폴더를 지우지 않게)

---

## 올리기

`dist/` **안의 내용** 을 그대로 올립니다. `dist` 폴더 자체가 아닙니다.

```bash
# Cloudflare Pages
npx wrangler pages deploy dist

# Netlify
npx netlify deploy --prod --dir dist

# S3
aws s3 sync dist/ s3://my-bucket/ --delete

# GitHub Pages (gh-pages branch 를 쓰는 경우)
git subtree push --prefix static/dist origin gh-pages
```

### 올린 뒤 확인할 것

1. `SITE_ORIGIN` 이 실제 주소와 같은지. 다르면 카카오 공유 card의 사진이 안 나옵니다.
2. 네이버 지도와 카카오 앱에 그 domain을 등록했는지.
   [지도와 카카오 공유 key 발급하기](#지도와-카카오-공유-key-발급하기) 를 참고해 주시기 바랍니다.
3. 휴대폰에서 실제로 열어 보았는지. 청첩장은 거의 전부 모바일로 열립니다.

### GitHub Pages 처럼 하위 경로에 올릴 때

`https://user.github.io/repo/` 같은 하위 경로도 그대로 동작합니다.
자산 경로가 전부 상대 경로이기 때문입니다. 다만 `SITE_ORIGIN` 에는 하위 경로까지 적습니다.

```ini
SITE_ORIGIN="https://user.github.io/repo"
```

---

## 모바일에서 앱처럼 보이게 하는 장치

세 version에 공통으로 들어 있습니다. `src/js/config.js` 가 담당합니다.

- 확대(pinch, double tap, ctrl 조합) 차단. iOS Safari가 무시하는 `user-scalable=no` 를 JS로 보강합니다.
- 길게 눌러도 text가 선택되거나 iOS callout이 뜨지 않습니다. 입력창은 예외입니다.
- 사진 long press 저장 메뉴 차단. 카카오톡 in-app browser까지 세 겹으로 막습니다.
- 개발자도구 console을 열면 ASCII art 인사가 나옵니다.

---

## 지도와 카카오 공유 key 발급하기

`invitation.conf` 의 두 항목입니다.

```ini
NAVER_MAP_KEY_ID=""   # 네이버 지도를 청첩장 안에 띄웁니다
KAKAO_JS_KEY=""       # 카카오톡 공유하기를 친구 선택창까지 엽니다
```

**둘 다 비워도 청첩장은 정상 동작합니다.** 지도 자리에는 안내 문구와 길찾기 button이 나옵니다.
공유하기는 문자와 system 공유와 link 복사로 fallback합니다.
아래는 그보다 더 잘 보이게 하고 싶을 때 읽으시면 됩니다.

두 key 모두 **domain 제한 공개key** 입니다. browser에 그대로 노출되는 것이 정상입니다.
등록한 domain 밖에서는 동작하지 않아 남이 가져가도 쓸 수 없습니다.
그래서 `invitation.conf` 에 두어도 됩니다. 다만 그 파일 자체는 계좌번호 때문에 commit하지 않습니다.

### 1. 네이버 지도 (NAVER_MAP_KEY_ID)

'오시는 길' section에 지도를 띄웁니다. main version과 developer version에 나옵니다
(terminal version에는 지도가 없습니다).

#### 발급 절차

1. <a href="https://www.ncloud.com" target="_blank" rel="noopener noreferrer">NAVER Cloud Platform</a> 에 가입하고 로그인합니다.
   **결제수단 등록이 필요합니다.** 지도는 월 무료 한도가 넉넉해서 청첩장 규모로는
   요금이 나오지 않습니다. 다만 카드 등록은 해야 합니다.
2. 콘솔에서 **Services > Application Services > Maps** 로 들어갑니다.
3. **Application 등록** 을 누릅니다.
4. **Application 이름** 을 적습니다. 아무 이름이나 괜찮습니다. 예: `wedding-invitation`
5. **Service 선택** 에서 **Web Dynamic Map** 을 체크합니다.
   - Static Map, Geocoding, Directions 는 필요하지 않습니다. server용이고 청첩장은 쓰지 않습니다.
6. **Web 서비스 URL** 에 청첩장을 올릴 주소를 등록합니다. **이 단계를 빼면 지도가 표시되지 않습니다.**
   ```
   https://invitation.example.com
   http://localhost:8080
   ```
   - `http://localhost:8080` 은 local에서 미리 볼 때 필요합니다. port를 바꿔 쓰면 그 port로 적습니다.
   - 경로(`/main.html`)는 적지 않습니다. origin까지만 적습니다.
   - 나중에 domain이 정해지면 여기 와서 추가하면 됩니다. 여러 개를 등록할 수 있습니다.
7. 등록을 마치면 **인증 정보** 에서 **Client ID** 를 복사합니다.
   화면에 따라 `ncpKeyId` 라고 표시됩니다.

#### 적기

```ini
NAVER_MAP_KEY_ID="여기에_Client_ID"
VENUE_LAT="37.5662952"
VENUE_LNG="126.9779451"
VENUE_MAP_ZOOM="17"
```

좌표는 <a href="https://map.naver.com" target="_blank" rel="noopener noreferrer">네이버 지도</a> 에서 확인합니다.
예식장을 검색해 URL의 숫자를 보거나 장소를 우클릭하면 됩니다.
좌표를 안 넣으면 지도가 엉뚱한 곳을 가리킵니다.

#### 주의: Client Secret 은 넣지 않습니다

NCP는 Client ID와 Client Secret을 함께 줍니다. **Secret 은 절대 넣지 않습니다.**
server 전용 비밀이고, browser에 노출되면 남이 대신 호출해 요금을 발생시킬 수 있습니다.
청첩장은 Client ID 하나만 씁니다.

#### 지도가 표시되지 않을 때

| 증상 | 원인 |
|---|---|
| 지도 자리에 안내 문구만 나옵니다 | key가 비었거나 Web 서비스 URL에 지금 domain이 없습니다 |
| console에 인증 실패가 표시됩니다 | Web 서비스 URL과 실제 주소가 다릅니다. `www` 유무와 http, https 까지 정확히 맞춰야 합니다 |
| local에서만 표시되지 않습니다 | `http://localhost:<port>` 를 등록하지 않았습니다 |

청첩장은 인증이 실패하면 깨진 지도 대신 안내 문구를 보여 주도록 만들어 두었습니다.
그래도 길찾기 button은 동작하므로 하객이 곤란해지지는 않습니다.

---

### 2. 카카오톡 공유 (KAKAO_JS_KEY)

공유하기 button의 '카카오톡으로 공유하기' 를 제대로 동작하게 합니다.

- **key가 있으면** 친구 선택창이 바로 열립니다. 사진과 제목이 담긴 미리보기 card가 갑니다.
- **key가 없으면** system 공유(`navigator.share`)나 link 복사로 fallback합니다.
  카카오톡 in-app browser 안에서는 이 fallback이 어색하게 동작할 수 있습니다.
  하객 대부분이 카카오톡으로 청첩장을 받으므로 이 key는 넣는 편이 좋습니다.

#### 발급 절차

1. <a href="https://developers.kakao.com" target="_blank" rel="noopener noreferrer">Kakao Developers</a> 에 카카오 계정으로 로그인합니다.
   **결제수단이 필요하지 않습니다.**
2. **내 애플리케이션 > 애플리케이션 추가하기** 를 누릅니다.
3. 앱 이름과 사업자명을 적습니다. 개인이면 본인 이름을 적으면 됩니다.
4. 만들어진 앱에 들어가 **앱 키** 메뉴에서 **JavaScript 키** 를 복사합니다.
5. **도메인을 두 군데에 등록합니다.** 카카오가 목록을 둘로 나눠 두었습니다.
   한 곳만 채우면 SDK는 load되고 `Kakao.init` 도 지나가는데 마지막 공유 호출이 거절됩니다.
   - `[앱] > [플랫폼 키] > [JavaScript 키] > [JavaScript SDK 도메인]`
     `Kakao.init` 을 실행하는 쪽입니다. 카카오 문서가 "JavaScript 키는 등록된 JavaScript SDK
     도메인에서만 사용할 수 있으며, 이외에서의 요청은 거절됩니다" 라고 적어 둔 목록입니다.
   - `[앱] > [제품 링크 관리] > [웹 도메인]`
     공유 card를 눌렀을 때 이동할 쪽입니다.

   두 곳 모두에 배포 domain과 미리보기 주소를 넣습니다.

   ```
   https://invitation.example.com
   http://localhost:8080
   ```

   JavaScript 키가 여러 개면 목록도 키마다 따로입니다. 실제로 쓰는 키 아래에 넣어야 합니다.
6. 카카오 로그인은 **켜지 않아도 됩니다.** 공유하기(`Kakao.Share.sendDefault`)는 로그인이 필요 없습니다.

#### 적기

```ini
KAKAO_JS_KEY="여기에_JavaScript_키"
SITE_ORIGIN="https://invitation.example.com"
```

`SITE_ORIGIN` 을 반드시 함께 채웁니다. 공유 card의 사진(`og:image`)은 절대 URL이어야
카카오톡이 읽습니다. 이 값이 비면 사진 없는 card가 갑니다.

#### 주의: REST API 키와 Admin 키는 넣지 않습니다

앱 키 화면에는 Native, REST API, JavaScript, Admin 키가 함께 있습니다.
**JavaScript 키만** 씁니다. 나머지는 server 전용 비밀입니다.

#### 공유가 동작하지 않을 때

| 증상 | 원인 |
|---|---|
| button을 눌러도 친구 선택창이 열리지 않습니다 | `JavaScript SDK 도메인` 에 지금 주소가 없습니다 |
| 친구에게는 갔는데 눌러도 청첩장이 열리지 않습니다 | `웹 도메인` 에 지금 주소가 없습니다 |
| local에서만 안 됩니다 | 두 목록에 `http://localhost:<port>` 를 넣지 않았습니다 |

주소는 `www` 유무와 http, https 까지 정확히 맞춰야 합니다.

#### 공유 미리보기가 이전 사진으로 나올 때

카카오가 URL별로 미리보기를 cache합니다. 사진을 바꿨는데 이전 사진이 보이면
<a href="https://developers.kakao.com/tool/debugger/sharing" target="_blank" rel="noopener noreferrer">카카오 공유 디버거</a> 에서
청첩장 주소를 넣고 **초기화** 를 누릅니다.

#### 카카오 공유 점검 목록

`SITE_ORIGIN` 이 실제 주소와 같은지, 사진 파일이 그 주소로 열리는지 봅니다.

```bash
# og:image 가 절대 URL로 박혀 있는지
curl -s https://invitation.example.com/ | grep 'og:image'

# 그 URL이 실제로 열리는지 (200 이어야 합니다)
curl -s -o /dev/null -w '%{http_code}\n' https://invitation.example.com/photos/cover.jpg
```

---

### 3. 길찾기 button (key가 필요 없습니다)

지도 아래 '네이버 지도' 와 '카카오맵' button은 외부 앱을 열기만 하므로 key가 필요 없습니다.
공유 link만 넣으면 됩니다.

```ini
MAP_NAVER_URL="https://naver.me/xxxxxxxx"
MAP_KAKAO_URL="https://place.map.kakao.com/xxxxxxxxx"
```

- 네이버: <a href="https://map.naver.com" target="_blank" rel="noopener noreferrer">네이버 지도</a> 에서 예식장을 검색하고 **공유 > URL 복사** 를 누릅니다.
- 카카오: <a href="https://map.kakao.com" target="_blank" rel="noopener noreferrer">카카오맵</a> 에서 예식장을 검색하고 **공유 > URL 복사** 를 누릅니다.

이 값을 비우면 button이 지도 첫 화면으로 갑니다. 하객이 직접 검색해야 하니 채워 두는 편이 좋습니다.

---

### 4. 방문 통계 (GA_MEASUREMENT_ID)

Google Analytics 4 측정 ID입니다. GA4 속성의 데이터 스트림에서 `G-` 로 시작하는 값을 복사합니다.

```ini
GA_MEASUREMENT_ID="G-XXXXXXXXXX"
```

- **비우면 gtag script를 부르지 않습니다.** 요청도 나가지 않습니다.
- Google은 `<head>` 바로 아래 붙이라고 안내하지만, 이 청첩장은 `js/config.js` 가 넣습니다.
  네 page가 모두 그 파일을 부르므로 한 곳만 채우면 전 page에 걸립니다.
- **ID를 HTML에 직접 박지 않습니다.** 이 저장소는 fork해서 쓰는 것이라,
  박아 두면 남의 하객 방문이 내 속성으로 들어옵니다. `invitation.conf` 는 추적되지 않습니다.
- 두 구성이 각자 conf를 가지므로 static과 with-guestbook에 다른 ID를 넣어도 됩니다.
- 하객의 방문을 기록합니다. 남기실 안내가 있으면 청첩장에 함께 적어 주시기 바랍니다.

---

### 요약

| 항목 | 필수 | 비용 | 등록해야 하는 것 |
|---|---|---|---|
| `NAVER_MAP_KEY_ID` | 아니오 | 카드 등록 필요, 청첩장 규모는 무료 | Web 서비스 URL |
| `KAKAO_JS_KEY` | 아니오. 넣는 편이 좋습니다 | 없음 | JavaScript SDK 도메인과 웹 도메인 두 곳 |
| `MAP_NAVER_URL` | 아니오 | 없음 | 없음 |
| `MAP_KAKAO_URL` | 아니오 | 없음 | 없음 |
| `GA_MEASUREMENT_ID` | 아니오 | 없음 | GA4 속성과 데이터 스트림 |

key를 고친 뒤에는 `./build.sh` 를 다시 돌리고 `dist/` 를 다시 올립니다.

---

## Troubleshooting

| 증상 | 원인과 해결 |
|---|---|
| `invitation.conf 이 없습니다` | `cp invitation.conf.example invitation.conf` 를 먼저 실행해 주시기 바랍니다 |
| `생성한 window.__WEDDING__ JSON이 유효하지 않습니다` | conf 값에 따옴표나 역슬래시가 섞였습니다. 그 값을 확인해 주시기 바랍니다 |
| 화면에 이름이 표시되지 않습니다 | `GROOM_NAME` 등이 비어 있습니다. build 로그의 경고를 확인해 주시기 바랍니다 |
| 수정한 내용이 반영되지 않습니다 | `./build.sh` 를 다시 실행했는지, 올린 뒤 browser를 강제 새로고침했는지 확인해 주시기 바랍니다 |
| 지도가 표시되지 않습니다 | key 또는 domain 등록 문제입니다. 이 문서의 지도와 카카오 key 절을 확인해 주시기 바랍니다 |
| 공유 card에 사진이 나오지 않습니다 | `SITE_ORIGIN` 이 비었거나 실제 주소와 다릅니다 |
| `dist 은 이 script가 만든 곳이 아닙니다` | `-o` 로 지정한 directory에 다른 파일이 있습니다. 다른 경로를 지정해 주시기 바랍니다 |
