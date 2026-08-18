# 축하 한마디까지 받는 청첩장

정적 청첩장에 **하객이 남긴 축하 한마디를 실제로 모으는 기능** 을 더한 구성입니다.

```bash
cp invitation.conf.example invitation.conf
docker compose up -d          # http://localhost:8080
```

두 줄입니다. `npm install` 이 없고, build 단계도 없습니다.

이 구성으로 올린 demo가 <a href="https://invitation-demo-type-b.nerd.kim/" target="_blank" rel="noopener noreferrer">invitation-demo-type-b.nerd.kim</a> 에 있습니다.
<a href="https://invitation-demo-type-b.nerd.kim/developer" target="_blank" rel="noopener noreferrer">developer</a> 와
<a href="https://invitation-demo-type-b.nerd.kim/terminal" target="_blank" rel="noopener noreferrer">terminal</a> version도 함께 올라가 있습니다.
남기신 축하는 모두에게 보입니다.

---

## 구성

```
[Node app] -> [guestbook.db]
```

축하 한마디를 SQLite 파일에 담습니다. 별도 database container가 없습니다.

### 필요한 것

- **docker** 로 띄우면 이것만 있으면 됩니다. image가 `node:24-alpine` 입니다.
- **docker 없이** 직접 돌리려면 **Node 24 이상** 이 필요합니다.
  server가 `node:sqlite` 를 쓰는데 Node 20과 22에는 그 module이 없습니다.

`package.json` 이 없어 `npm install` 을 하지 않습니다.

### SQLite 하나면 되는 이유

축하 한마디 기능이 담을 곳에 요구하는 것은 세 가지입니다.

| 필요한 것 | 왜 필요한가 | SQLite의 무엇이 맡는가 |
|---|---|---|
| 단조 증가하는 ID | 동시에 축하를 눌러도 순서가 어긋나지 않습니다 | `INTEGER PRIMARY KEY AUTOINCREMENT` |
| 재시작해도 남는 영속성 | container를 다시 띄워도 축하가 남습니다 | WAL mode의 DB 파일 |
| 만료되는 rate limit 창 | 같은 사람의 연타를 막습니다 | `exp` 열을 두고 지날 때 지웁니다 |

**여러 청첩장을 한 platform에서 돌리거나, 여러 server가 같은 자료를 함께 읽고 써야 한다면**
파일 하나로는 부족합니다. 그때는 Redis나 관계형 database를 두는 편이 맞습니다.

---

## static 구성과 무엇이 다른가

| | static | with-guestbook |
|---|---|---|
| 축하 한마디 | 입력창이 없습니다 | **모두가 함께 보는 실제 기록이 남습니다** |
| 필요한 것 | bash, sed, awk | docker (또는 Node 24) |
| 배포 | 정적 호스팅에 폴더를 올립니다 | container를 돌릴 곳이 필요합니다 |
| 내용을 고친 뒤 | `./build.sh` 를 다시 돌리고 재배포합니다 | `docker compose restart` 를 합니다 |
| 계좌 난독화 salt | build 시점에 한 번 | **요청마다 새로** |
| 비용 | 대개 무료 | server 비용 |

**`invitation.conf` 형식이 같습니다.** static에서 쓰던 파일을 그대로 복사해 오면 됩니다.
반대 방향도 됩니다.

정적 배포는 그대로 두고 이 server의 API만 쓸 수도 있습니다.
static 쪽 `invitation.conf` 에 이 server 주소를 적으면 됩니다.

```ini
GUESTBOOK_API_BASE="https://guestbook.example.com/api"
```

---

## 쓰는 방법

```bash
cp invitation.conf.example invitation.conf   # 그다음 본인의 정보로 고칩니다
docker compose up -d                         # http://localhost:8080

docker compose logs -f                       # log를 봅니다
docker compose restart                       # invitation.conf 를 고친 뒤 반영합니다
docker compose down                          # 멈춥니다. 축하는 volume에 남습니다
```

port를 바꾸려면 `INVITATION_PORT=3000 docker compose up -d` 로 띄웁니다.

### docker 없이 직접 돌리기

```bash
node server/server.mjs        # Node 24 이상
PORT=3000 node server/server.mjs
```

### 무엇을 고치면 어떻게 반영되는가

| 고친 것 | 필요한 조치 |
|---|---|
| `invitation.conf` | `docker compose restart` |
| `src/` 의 css, js, html | browser만 새로고침하면 됩니다 (bind mount입니다) |
| `server/server.mjs` | `docker compose restart` |
| `Dockerfile` | `docker compose up -d --build` |

`src/` 와 `invitation.conf` 가 읽기 전용 bind mount이므로 내용을 고쳐도 image를 다시 build하지 않습니다.

---

## 받은 축하 백업하기

받은 축하는 `guestbook-data` 라는 docker named volume에 있습니다.

```bash
docker compose down       # 안전합니다. volume이 남습니다
docker compose down -v    # 위험합니다. 받은 축하가 모두 사라집니다
```

**예식이 끝나면 백업해 두시기 바랍니다.** 오래 두고 볼 기록입니다.

```bash
# DB 파일을 그대로 꺼냅니다
docker compose cp invitation:/app/data/guestbook.db ./guestbook-backup.db

# 사람이 읽을 형태로 뽑습니다 (sqlite3 가 있을 때)
sqlite3 -header -csv guestbook-backup.db \
  'SELECT ts, msg FROM approvals ORDER BY seq' > guestbook.csv

# API로도 받을 수 있습니다
curl -s http://localhost:8080/api/approvals | node -e \
  'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
     for(const r of JSON.parse(d).recent) console.log(r.ts, r.msg)})'
```

되돌릴 때는 `docker compose down` 을 한 뒤 volume에 파일을 넣고 다시 띄웁니다.

```bash
docker compose cp ./guestbook-backup.db invitation:/app/data/guestbook.db
docker compose restart
```

---

## 주소

page 주소에 확장자가 없습니다.

| 주소 | 내용 |
|---|---|
| `/` | `DEFAULT_VERSION` 으로 고른 version |
| `/main` | main version |
| `/developer` | developer version |
| `/terminal` | terminal version |
| `/release` | 감사 인사 page. 예식 전에는 안내만 나옵니다. `/release?preview=1` 로 미리 볼 수 있습니다 |

`/developer.html` 처럼 확장자를 붙여 들어오면 확장자 없는 같은 주소로 301 응답합니다.
밖에서 받은 이전 link와 북마크도 그대로 열립니다.
이 301에는 `Cache-Control: no-store` 를 붙여 두어서, 나중에 되돌려도 하객의 browser가
이전 redirect를 계속 쓰지 않습니다.

`src/` 의 HTML은 서로를 `developer.html` 로 가리킵니다. server가 응답을 만들 때 그 link에서
확장자를 떼므로, 하객이 version을 오갈 때 redirect를 한 번 더 타지 않습니다.
`static` 구성에는 server가 없어 `developer.html` 을 그대로 씁니다.

---

## API

하객이 인증 없이 부르는 공개 경로입니다.

| method | 경로 | 응답 |
|---|---|---|
| `GET` | `/api/approvals` | `{count, recent: [{id, ts, msg}]}` 최신 20건 |
| `GET` | `/api/approvals?before=<id>` | 그보다 오래된 20건 ('더보기') |
| `POST` | `/api/approvals` `{message}` | `{count}` |
| `GET` | `/healthz` | `ok` |

- `id` 는 `<밀리초>-<순번>` 입니다. client가 '더보기' cursor와 중복 판별 key로 씁니다.
  **이 형식을 바꾸면 청첩장 세 version의 `js/config.js` 를 모두 고쳐야 합니다.**
- 메시지는 **50자** 까지입니다. 넘으면 server가 자릅니다.
- 메시지가 비어 있어도 됩니다. 그때는 version마다 정해 둔 문구 중에서 하나를 골라 보여 줍니다.

### server가 지키는 것

client를 신뢰하지 않고 server에서 다시 검사합니다.

- **태그 문자 제거**: `<` 와 `>` 를 없앱니다. `<script>alert(1)</script>` 는 `scriptalert(1)/script` 가 됩니다.
- **한 줄 보장**: tab과 줄바꿈을 공백으로 바꿉니다.
- **깨진 기호 제거**: 결합문자(Zalgo), 제어문자, zero-width, 방향제어(BIDI) 문자를 없앱니다.
  한글과 영문, emoji, 일반 문장부호는 그대로 둡니다.
- **연타 차단**: 같은 IP는 50초에 한 번입니다. 화면은 60초 cooldown을 보여 주고
  server는 조금 짧은 50초로 최종 차단합니다. 60초 직후 요청이 경계 race로 거절되지 않게 일부러 더 짧습니다.
- **본문 크기 제한**: 4KB를 넘으면 연결을 끊습니다.
- **경로 이탈 차단**: `src/` 밖의 파일을 요청하면 거부합니다.

부적절한 메시지를 지우려면 DB에서 직접 지웁니다.

```bash
docker compose exec invitation node -e '
  const {DatabaseSync}=require("node:sqlite");
  const db=new DatabaseSync("/app/data/guestbook.db");
  console.log(db.prepare("SELECT seq, ts, msg FROM approvals ORDER BY seq DESC LIMIT 20").all());
'
# seq 를 확인한 뒤
docker compose exec invitation node -e '
  const {DatabaseSync}=require("node:sqlite");
  const db=new DatabaseSync("/app/data/guestbook.db");
  db.prepare("DELETE FROM approvals WHERE seq = ?").run(Number(process.argv[1]));
' 123
```

---

## directory 구조

```
with-guestbook/
├── docker-compose.yml        service 하나. volume 하나
├── Dockerfile                node:24-alpine 한 단계. build stage가 없습니다
├── invitation.conf.example   모든 항목과 설명. 이것을 복사해 씁니다
├── invitation.conf           내 정보. gitignore 대상입니다
├── server/
│   └── server.mjs            정적 서빙 + SSR + 축하 API
└── src/                      청첩장 원본. static/src 와 같은 내용입니다
    ├── main.html developer.html terminal.html release.html
    ├── css/  js/  assets/
    └── photos/               사진을 넣는 곳. gitignore 대상입니다
```

축하 DB는 저장소에 없습니다. docker volume `guestbook-data` 안에 있습니다.

---

## server.mjs 가 요청마다 하는 일

static 구성은 build 시점에 한 번 치환하지만, 이쪽은 **요청마다** 생성합니다.

```
GET /developer ──> src/developer.html 을 읽어
                   1) 계좌를 난독화해 주입          (salt가 매 요청 달라집니다)
                   2) window.__WEDDING__ 등을 주입   (config.js 보다 먼저)
                   3) css 와 js 참조에 ?v= 를 붙임
                   4) page 사이 link에서 .html 을 뗌
                   5) {{TOKEN}} 을 치환
                   6) 사진이 없으면 og:image meta 제거
               ──> HTML 응답 (Cache-Control: no-store)

GET /                   ──> DEFAULT_VERSION 의 page를 같은 방식으로
GET /developer.html     ──> 301 /developer
GET /css/main.css       ──> 그대로 응답 (immutable, 1년 cache)
GET /api/approvals      ──> SQLite 조회
```

계좌 난독화 salt가 요청마다 바뀌므로 응답을 여러 번 받아 비교해도 같은 blob이 나오지 않습니다.
static 구성보다 이 점이 낫습니다.

---

## 앞단에 reverse proxy를 둘 때

server는 `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host`,
`CF-Connecting-IP` 를 읽습니다. **이 header를 전달해 주시기 바랍니다.**
넘기지 않으면 모든 하객이 proxy의 IP 하나로 보입니다. 그러면 첫 사람이 축하한 뒤
50초 동안 다른 사람이 축하하지 못합니다.

nginx 예시입니다.

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host  $host;
}
```

Caddy는 `reverse_proxy 127.0.0.1:8080` 만 쓰면 위 header를 알아서 붙입니다.

`SITE_ORIGIN` 을 `invitation.conf` 에 적어 두면 header 추측 없이 그 값을 씁니다.
카카오 공유 card가 정확해지므로 실제 배포에서는 적어 두는 편이 좋습니다.

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
   - 경로(`/main`)는 적지 않습니다. origin까지만 적습니다.
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

key를 고친 뒤에는 `docker compose restart` 를 합니다.

---

## Troubleshooting

| 증상 | 원인과 해결 |
|---|---|
| `conf 파일이 없습니다` 오류로 종료됩니다 | `cp invitation.conf.example invitation.conf` 를 먼저 실행해 주시기 바랍니다 |
| 축하가 한 번만 등록되고 계속 429가 돌아옵니다 | proxy가 IP header를 전달하지 않습니다. 위 nginx 설정을 확인해 주시기 바랍니다 |
| 재시작하니 축하가 사라졌습니다 | `docker compose down -v` 를 실행했습니다. `-v` 는 volume을 지웁니다 |
| `node:sqlite` 를 찾을 수 없습니다 | Node 24 미만입니다. `node -v` 로 확인해 주시기 바랍니다 |
| 수정한 내용이 반영되지 않습니다 | `invitation.conf` 는 restart가 필요합니다. `src/` 는 새로고침만 하면 됩니다 |
| 지도가 표시되지 않습니다 | key 또는 domain 등록 문제입니다. 이 문서의 지도와 카카오 key 절을 확인해 주시기 바랍니다 |
| port가 이미 사용 중입니다 | `INVITATION_PORT=3000 docker compose up -d` 로 바꿔 주시기 바랍니다 |
