# 개발자를 위한 모바일 청첩장

> 이런 걸 좋아해 주시는 분이 많을 줄 몰랐는데, 역시 세상은 넓네요. 😇

같은 청첩장을 **세 가지 version** 으로 보여 줍니다. 하객이 취향대로 골라 볼 수 있습니다.
화면 아래 전환 link로 서로 이동합니다.

| version | 설명 |
|---|---|
| **main** | 파스텔 톤. 신랑신부 프로필, gallery, 달력, countdown |
| **developer** | IDE와 CI/CD 콘셉트. dark와 light mode, git log 연출, branch graph |
| **terminal** | 녹색과 amber phosphor CRT. neofetch, LCD countdown, ASCII 달력과 ASCII art |
| **release** | 예식 시각이 지나면 열리는 감사 인사 page. RELEASE NOTES 형식 |

화면은 vanilla HTML, CSS, JS 입니다. React 같은 framework도, webpack 이나 vite 같은
bundler도 쓰지 않습니다. 아래 두 구성이 이 화면을 그대로 함께 씁니다.

---

## 데모

올려 둔 화면입니다. 휴대폰으로 여시면 하객이 보는 것과 같습니다.

| 구성 | main | developer | terminal |
|---|---|---|---|
| [static](static) | <a href="https://invitation-demo-type-a.nerd.kim/" target="_blank" rel="noopener noreferrer">열기</a> | <a href="https://invitation-demo-type-a.nerd.kim/developer.html" target="_blank" rel="noopener noreferrer">열기</a> | <a href="https://invitation-demo-type-a.nerd.kim/terminal.html" target="_blank" rel="noopener noreferrer">열기</a> |
| [with-guestbook](with-guestbook) | <a href="https://invitation-demo-type-b.nerd.kim/" target="_blank" rel="noopener noreferrer">열기</a> | <a href="https://invitation-demo-type-b.nerd.kim/developer" target="_blank" rel="noopener noreferrer">열기</a> | <a href="https://invitation-demo-type-b.nerd.kim/terminal" target="_blank" rel="noopener noreferrer">열기</a> |

두 구성을 나란히 열면 두 가지가 다릅니다.

- **축하 한마디 입력창이 `with-guestbook` 에만 있습니다.** `static` 은 저장할 곳이 없어
  입력창과 기록 목록을 감춥니다. demo에 남기신 축하는 모두에게 보입니다.
- **주소 모양이 다릅니다.** `with-guestbook` 은 server가 있어 `/developer` 로 서빙하고,
  `static` 은 정적 파일이라 `developer.html` 을 그대로 씁니다.

---

## 두 가지 구성

이 저장소를 쓰는 방식이 둘입니다. directory 하나가 구성 하나이고 필요한 쪽만 내려받으면 됩니다.
위에 적은 세 가지 화면 version은 두 구성 모두에 들어 있습니다.

### [static/](static) - HTML, CSS, JS 만

```bash
cd static
cp invitation.conf.example invitation.conf
./build.sh
./startup.sh                # http://localhost:8080
```

Windows 에서는 `.\build.ps1` 과 `.\startup.ps1` 을 씁니다. 같은 `invitation.conf` 를 읽습니다.

`bash`, `sed`, `awk` 만 있으면 됩니다. node도 npm도 docker도 필요 없습니다.
`dist/` 가 나오면 GitHub Pages나 Cloudflare Pages, S3 같은 정적 호스팅에 그대로 올립니다.
대개 무료입니다.

이 구성에는 축하 한마디를 저장할 곳이 없습니다. 그래서 **축하 한마디 입력창과 기록 목록이
아예 나오지 않습니다.** 남길 수 없는 것을 남길 수 있는 것처럼 보여 주지 않으려는 것입니다.
developer version과 terminal version의 AI agent 축하는 저장이 필요 없으므로 그대로 나옵니다.

축하 한마디를 받고 싶으시면 아래 `with-guestbook` 을 쓰시면 됩니다.
`GUESTBOOK_API_BASE` 에 API 주소를 넣으셔도 입력창이 다시 나옵니다.

### [with-guestbook/](with-guestbook) - 축하 한마디까지 받기

```bash
cd with-guestbook
cp invitation.conf.example invitation.conf
docker compose up -d        # http://localhost:8080
```

하객이 남긴 축하 한마디가 SQLite 파일에 쌓입니다.
docker를 쓰지 않고 직접 돌리려면 Node 24 이상이 필요합니다.

### 고르는 기준

| | static | with-guestbook |
|---|---|---|
| 축하 한마디를 모아야 한다 | 아니오 | **예** |
| 필요한 것 | bash, sed, awk (Windows는 PowerShell) | docker 또는 Node 24 |
| 올릴 곳 | 정적 호스팅 (대개 무료) | container 돌릴 server |
| 계좌 난독화 salt | build 시점에 한 번 | 요청마다 새로 |

**`invitation.conf` 형식이 같아서 두 구성 사이에 그대로 옮겨 쓸 수 있습니다.**
정적으로 시작했다가 나중에 축하 한마디가 필요해지면 conf 파일만 복사하면 됩니다.

정적 배포를 유지하면서 API만 따로 두는 방법도 있습니다.
`with-guestbook` 을 어딘가에 올리고 static 쪽 conf에 그 주소를 적습니다.

```ini
GUESTBOOK_API_BASE="https://guestbook.example.com/api"
```

---

## 구조

```
.
├── README.md                 이 파일
├── LICENSE                   MIT
├── static/                   구성 1. HTML, CSS, JS 만
│   ├── README.md
│   ├── build.sh              invitation.conf 를 읽어 src/ 를 dist/ 로 변환합니다
│   ├── startup.sh            dist/ 를 local에서 미리 봅니다
│   ├── build.ps1             build.sh 의 Windows 판
│   ├── startup.ps1           startup.sh 의 Windows 판
│   ├── invitation.conf.example
│   ├── src/                  원본. 실제 값이 없고 {{TOKEN}} 만 있습니다
│   │   ├── main.html  developer.html  terminal.html  release.html
│   │   ├── css/              main.css, developer.css, terminal.css
│   │   ├── js/               config.js, main.js, developer.js, terminal.js, private.js
│   │   ├── assets/           카카오 icon, AI brand icon
│   │   └── photos/           사진을 넣는 곳
│   └── dist/                 build 결과
│
└── with-guestbook/           구성 2. 축하 한마디까지
    ├── README.md
    ├── docker-compose.yml    service 하나, volume 하나
    ├── Dockerfile            node:24-alpine 한 단계
    ├── invitation.conf.example
    ├── server/
    │   └── server.mjs        정적 서빙 + SSR + 축하 API
    └── src/                  static/src 와 같은 내용의 독립 사본
```

두 구성이 `src/` 를 **각자 독립 사본으로** 가집니다. 중복이 있습니다.
그래도 원하는 directory만 내려받아 바로 쓸 수 있는 편이 공유용으로는 낫다고 보았습니다.

### 데이터가 흘러가는 길

두 구성이 같은 conf를 읽습니다. 치환하는 시점만 다릅니다.

```
static:
  invitation.conf ──[build.sh: sed 치환]──> dist/*.html   ──> 정적 호스팅
                  └─[난독화 + JSON 생성]──> dist/js/data.js
  치환 시점: build 할 때 한 번

with-guestbook:
  invitation.conf ──[server.mjs: 요청마다 치환]──> HTTP 응답
                  └─[난독화: salt가 매번 다름]
  축하 한마디      ──> SQLite (docker volume)
  치환 시점: 요청이 올 때마다
```

### 청첩장 JS의 계약

`src/js/` 를 고칠 때 알아 두어야 하는 것들입니다.

- **`window.__WEDDING__`** 이 이름과 예식 정보를 담습니다. `config.js` 가 이것을 읽어
  `CONFIG` 를 만들고, 세 version의 JS가 `CONFIG` 를 씁니다. 이 모양을 바꾸면 세 version이 함께 깨집니다.
- **`window.__GIFT__`** 가 난독화된 계좌 blob입니다. `private.js` 의 `deobfuscate` 가 풉니다.
  난독화 쪽(`build.sh` 의 `obfuscate`, `server.mjs` 의 `obfuscate`)과 **1:1로 대응** 하므로
  한쪽만 고치면 계좌가 안 보입니다.
- **축하 API 응답 계약** 은 `{count, recent: [{id, ts, msg}]}` 이고 **id 형식은 `<밀리초>-<순번>`** 입니다.
  client가 '더보기' cursor와 중복 판별 key로 씁니다. 바꾸면 세 version의 `config.js` 를 모두 고쳐야 합니다.
- **gallery는 3x3 pagination** 이라 9장이 한 page입니다. terminal version에는 gallery가 없습니다.
- **`config.js` 안에서는 `W` 를 쓰지 않습니다.** `main.js`, `developer.js`, `terminal.js` 가 각자
  최상위에 `const W = CONFIG.date` 를 선언하므로 전역에서 부딪쳐 그 파일들이 통째로 죽습니다.
  그래서 `config.js` 는 `WDATA` 를 씁니다.
- **`<pre>` 안의 ASCII art와 git log는 공백으로 정렬** 되어 있습니다. 압축이나 자동 formatting을
  하면 그림이 깨집니다.

---

## 내 청첩장으로 바꾸기

**손으로 고치는 파일은 `invitation.conf` 하나뿐입니다.** 다만 그 파일을 고친 것만으로
화면이 바뀌지는 않습니다. 아래 세 단계를 거칩니다.

1. **conf 작성** `invitation.conf` 에 이름과 예식 정보를 적습니다.
2. **반영** `static` 은 `./build.sh` 를 돌려 `dist/` 를 다시 만들고,
   `with-guestbook` 은 `docker compose restart` 를 합니다.
3. **배포** `static` 은 `dist/` 안의 내용을 정적 호스팅에 올리고,
   `with-guestbook` 은 container를 돌릴 server가 필요합니다.

`invitation.conf` 를 고칠 때마다 2번을 다시 해야 합니다. 잊으면 화면이 그대로입니다.

```bash
cd static                 # 또는 cd with-guestbook
cp invitation.conf.example invitation.conf
```

```ini
GROOM_NAME="김앙아"
BRIDE_NAME="최엥에"
WEDDING_AT="2026-11-14T11:00:00+09:00"
VENUE_NAME="별빛웨딩홀"
VENUE_ADDRESS="서울특별시 중구 세종대로 110"
INFO_PARKING="건물 지하 주차장 이용\n무료주차 2시간"
GROOM_ACCOUNTS="김앙아|달빛은행|000-0000-0000"
```

항목마다 무슨 뜻인지 `invitation.conf.example` 의 주석에 전부 달려 있습니다.
`DEFAULT_VERSION` 으로 처음 열었을 때 보여줄 version을 고릅니다.

사진은 `src/photos/` 에 넣고 파일 이름을 conf에 적습니다.
지도와 카카오 key는 각 directory README의 지도와 카카오 key 절을 참고해 주시기 바랍니다.
둘 다 없어도 동작합니다.

배포와 확인 절차는 [static/README.md](static/README.md) 와
[with-guestbook/README.md](with-guestbook/README.md) 에 각각 적어 두었습니다.

---

## Special Thanks to

- <a href="https://www.instagram.com/_multipotentialite__/" target="_blank" rel="noopener noreferrer">@\_multipotentialite\_\_</a> (Instagram)

## Maintainer

- <a href="https://nerd.kim/" target="_blank" rel="noopener noreferrer">NerdKim</a>
- <a href="https://github.com/SeeunChoi1" target="_blank" rel="noopener noreferrer">SeeunChoi1</a>

---

## 라이선스

MIT 입니다. 자세한 내용은 [LICENSE](LICENSE) 에 있습니다.

`src/assets/ai/` 의 brand icon(OpenAI, Claude, Gemini 등)은 **각 상표권자에게 권리가 있습니다.**
MIT 범위가 아니므로 개개인의 프로젝트에 사용할 때 확인해 주시기 바랍니다. developer version의 장식에만 쓰입니다.

본문에 쓰인 font(Gowun Batang, Gowun Dodum, JetBrains Mono)는 Google Fonts에서 불러오며
각자의 라이선스를 따릅니다.
