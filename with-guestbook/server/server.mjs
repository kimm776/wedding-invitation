/*
   청첩장을 서빙하고 축하 한마디를 받는 단일 server다.

   Node 24 이상이 필요하다. 축하 한마디를 node:sqlite 에 담는데 20과 22에는 그 module이 없다.

   하는 일
     GET  /                         DEFAULT_VERSION 의 page
     GET  /main, /developer 등      각 version. 확장자가 없다. 요청마다 SSR한다.
     GET  /main.html 등             확장자 없는 같은 주소로 301 보낸다.
     GET  /api/approvals            { count, recent: [{ id, ts, msg }] }
     GET  /api/approvals?before=id  그보다 오래된 20건
     POST /api/approvals { message } { count }
     GET  /healthz                  liveness

   HTML은 요청마다 생성한다. token을 치환하고 계좌를 난독화해 주입한다.
   난독화 salt가 요청마다 달라지므로 응답 byte가 매번 다르다.

   환경변수
     PORT           기본 8080
     CONF_FILE      기본 ../invitation.conf
     SRC_DIR        기본 ../src
     DB_FILE        기본 ../data/guestbook.db
     SITE_ORIGIN    og:url 과 og:image 에 쓸 절대 domain. 비우면 요청 Host에서 유추한다.
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');

const PORT = Number(process.env.PORT) || 8080;
const CONF_FILE = process.env.CONF_FILE || path.join(ROOT, 'invitation.conf');
const SRC_DIR = path.resolve(process.env.SRC_DIR || path.join(ROOT, 'src'));
const DB_FILE = process.env.DB_FILE || path.join(ROOT, 'data', 'guestbook.db');

/** 축하 한마디 최대 글자수. 화면의 counter와 같은 값이다. */
const MAX_MSG = 50;
/** 한 page 건수. 첫 응답 건수이자 '더보기' 1회분이다. */
const PAGE = 20;
/** 요청 본문 상한 */
const MAX_BODY = 4 * 1024;
/** 같은 IP의 연타를 막는 창. 화면은 60초 cooldown을 보여주고 server는 조금 짧은 50초로
    최종 차단한다. 60초 직후 요청이 경계 race로 거절되는 일을 막으려고 일부러 더 짧다. */
const RATE_LIMIT_SECONDS = 50;

const INJECT_TOKEN = '<!--#PRIVATE#-->';


/* invitation.conf 읽기
   static/build.sh 와 같은 파일을 읽는다. 두 구성 사이에서 conf를 그대로 옮길 수 있다.
   KEY=value 와 KEY="value" 를 다루고 값 안의 \n 은 실제 줄바꿈으로 바꾼다.
   같은 이름의 환경변수가 있으면 그쪽이 이긴다. docker의 environment 주입을 지원하려는 것이다. */
function readConf(file) {
  let text = '';
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    console.error(`conf 파일이 없습니다: ${file}`);
    console.error('  invitation.conf.example 을 invitation.conf 로 복사해 주시기 바랍니다.');
    process.exit(1);
  }
  const env = {};
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    const q = val.charAt(0);
    if (val.length >= 2 && (q === '"' || q === "'") && val.endsWith(q)) val = val.slice(1, -1);
    env[key] = val.replace(/\\n/g, '\n');
  }
  return new Proxy(env, {
    get: (t, k) => (process.env[k] != null && process.env[k] !== '' ? process.env[k] : t[k]),
  });
}

const CONF = readConf(CONF_FILE);
const s = (k, dflt = '') => String(CONF[k] ?? dflt).trim();
const n = (k, dflt) => {
  const v = Number(String(CONF[k] ?? '').trim());
  return Number.isFinite(v) ? v : dflt;
};
const list = (k) =>
  s(k)
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);


/* 예식 일시를 KST 구성요소로 분해한다
   image에 ko-KR ICU가 없을 수 있어 Intl에 기대지 않고 offset을 직접 더한다. */
const DAY_KO = ['일', '월', '화', '수', '목', '금', '토'];
const DAY_EN = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const MONTH_EN = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
const pad2 = (v) => String(v).padStart(2, '0');

function kstParts(iso) {
  const t = Date.parse(iso);
  const d = new Date((Number.isNaN(t) ? 0 : t) + 9 * 3600 * 1000);
  const h24 = d.getUTCHours();
  return {
    y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(),
    dow: d.getUTCDay(), h24, mi: d.getUTCMinutes(),
    h12: h24 % 12 || 12, ampm: h24 < 12 ? 'AM' : 'PM', ampmKo: h24 < 12 ? '오전' : '오후',
  };
}

/** 안내 문구의 줄바꿈을 <br />로 바꾼다. HTML에 그대로 들어가므로 태그 문자를 먼저 막는다. */
function linesToHtml(v) {
  return String(v || '').replace(/[<>]/g, '').split('\n').join('<br />');
}

/** "이름|은행|번호,..." -> [{ name, bank, number }] */
function parseAccounts(str) {
  return String(str || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
    .map((rec) => {
      const [name, bank, number] = rec.split('|').map((x) => (x || '').trim());
      return { name: name || '', bank: bank || '', number: number || '' };
    });
}


/* 부팅 시 한 번 만드는 값
   요청과 무관하게 고정이다. conf를 고치면 container를 재시작한다. */
const CFG = (function build() {
  const weddingAt = s('WEDDING_AT', '2026-01-01T11:00:00+09:00');
  const firstMetAt = s('FIRST_MET_AT', weddingAt);
  const w = kstParts(weddingAt);
  const f = kstParts(firstMetAt);

  const person = (px) => ({
    name: s(`${px}_NAME`), short: s(`${px}_NAME_SHORT`), en: s(`${px}_NAME_EN`),
    initial: s(`${px}_INITIAL`), role: s(`${px}_ROLE`),
    parents: list(`${px}_PARENTS`),
    rankKo: s(`${px}_RANK_KO`), rank: s(`${px}_RANK_EXPR`),
    mbti: s(`${px}_MBTI`), hobby: s(`${px}_HOBBY`), note: s(`${px}_NOTE`),
    photo: s(`${px}_PHOTO`), photoFocus: s(`${px}_PHOTO_FOCUS`, '50% 30%'),
    photoZoom: Math.min(3, Math.max(1, n(`${px}_PHOTO_ZOOM`, 1))),
  });
  const groom = person('GROOM');
  const bride = person('BRIDE');

  const venue = {
    name: s('VENUE_NAME'), hall: s('VENUE_HALL'), address: s('VENUE_ADDRESS'),
    floor: s('VENUE_FLOOR'), addressCopy: s('VENUE_ADDRESS_COPY'),
    subway: s('VENUE_SUBWAY'), subwayShort: s('VENUE_SUBWAY_SHORT'),
    lat: n('VENUE_LAT', 0), lng: n('VENUE_LNG', 0), zoom: n('VENUE_MAP_ZOOM', 17),
  };

  const photos = {
    main: s('PHOTO_MAIN'), mainDev: s('PHOTO_MAIN_DEV'), bless: s('PHOTO_BLESS'),
    gallery: list('PHOTO_GALLERY'),
    galleryPageOrder: {
      main: list('GALLERY_ORDER_MAIN').map(Number).filter(Boolean),
      dev: list('GALLERY_ORDER_DEV').map(Number).filter(Boolean),
    },
  };

  const addressFull = [venue.address, venue.floor].filter(Boolean).join(' ');
  const dateKo = `${w.y}년 ${w.m}월 ${w.d}일 ${DAY_KO[w.dow]}요일`;
  const timeKo = `${w.ampmKo} ${w.h12}시${w.mi ? ` ${w.mi}분` : ''}`;
  const firstOf = (en) => en.split(' ')[0] ?? '';
  const lastOf = (en) => en.trim().split(/\s+/).filter(Boolean).at(-1) ?? '';
  const dayEn = DAY_EN[w.dow] ?? '';

  /* 청첩장 세 version의 js/config.js 가 읽는 모양. key 이름을 바꾸면 세 version이 함께 깨진다. */
  const wedding = {
    at: weddingAt, firstMetAt, groom, bride, venue,
    map: { naver: s('MAP_NAVER_URL'), kakao: s('MAP_KAKAO_URL') },
    photos,
  };

  /* HTML의 {{TOKEN}} 치환표. static/build.sh 의 표와 같은 값을 만든다. */
  const tokens = {
    GROOM_NAME: groom.name, GROOM_NAME_SHORT: groom.short, GROOM_NAME_EN: groom.en,
    GROOM_ROLE: groom.role, GROOM_PARENTS: groom.parents.join(' '),
    GROOM_PARENTS_0: groom.parents[0] ?? '', GROOM_PARENTS_1: groom.parents[1] ?? '',
    GROOM_RANK_KO: groom.rankKo, GROOM_RANK_EXPR: groom.rank,
    GROOM_EN_FIRST: firstOf(groom.en),
    GROOM_EN_LAST: lastOf(groom.en),
    GROOM_HANDLE: firstOf(groom.en).toLowerCase().replace(/-/g, ''),
    GROOM_BRANCH: groom.en.trim().toLowerCase().split(/\s+/).filter(Boolean).join('-'),

    BRIDE_NAME: bride.name, BRIDE_NAME_SHORT: bride.short, BRIDE_NAME_EN: bride.en,
    BRIDE_ROLE: bride.role, BRIDE_PARENTS: bride.parents.join(' '),
    BRIDE_PARENTS_0: bride.parents[0] ?? '', BRIDE_PARENTS_1: bride.parents[1] ?? '',
    BRIDE_RANK_KO: bride.rankKo, BRIDE_RANK_EXPR: bride.rank,
    BRIDE_EN_FIRST: firstOf(bride.en),
    BRIDE_EN_LAST: lastOf(bride.en),
    BRIDE_HANDLE: firstOf(bride.en).toLowerCase().replace(/-/g, ''),
    BRIDE_BRANCH: bride.en.trim().toLowerCase().split(/\s+/).filter(Boolean).join('-'),

    VENUE_NAME: venue.name, VENUE_HALL: venue.hall, VENUE_ADDRESS: venue.address,
    VENUE_FLOOR: venue.floor, VENUE_ADDRESS_FULL: addressFull,
    VENUE_SUBWAY: venue.subway, VENUE_SUBWAY_SHORT: venue.subwayShort,

    MAP_NAVER_URL: wedding.map.naver, MAP_KAKAO_URL: wedding.map.kakao,

    WEDDING_DATE_KO: dateKo, WEDDING_TIME_KO: timeKo,
    WEDDING_DATETIME_KO: `${dateKo} ${timeKo}`,
    WEDDING_DATE_ISO: `${w.y}-${pad2(w.m)}-${pad2(w.d)}`,
    WEDDING_DATE_DOT: `${w.y}.${pad2(w.m)}.${pad2(w.d)}`,
    WEDDING_YEAR: String(w.y), WEDDING_YEAR_MONTH_KO: `${w.y}년 ${w.m}월`,
    WEDDING_MONTH_EN: MONTH_EN[w.m - 1] ?? '', WEDDING_DAY_EN: dayEn,
    WEDDING_DAY_KO_SHORT: DAY_KO[w.dow] ?? '',
    WEDDING_TIME_EN: `${w.ampm} ${w.h12}:${pad2(w.mi)}`,
    WEDDING_CLOCK_KST: `${dayEn.charAt(0)}${dayEn.slice(1).toLowerCase()} ${w.y}-${pad2(w.m)}-${pad2(w.d)} ${pad2(w.h24)}:${pad2(w.mi)}:00 KST`,
    FIRST_MET_ISO: `${f.y}-${pad2(f.m)}-${pad2(f.d)}`,

    INFO_SUBWAY: linesToHtml(CONF.INFO_SUBWAY),
    INFO_BUS: linesToHtml(CONF.INFO_BUS),
    INFO_PARKING: linesToHtml(CONF.INFO_PARKING),
    INFO_MEAL: linesToHtml(CONF.INFO_MEAL),
  };

  return {
    wedding, tokens,
    /** 공유 card image의 파일 이름. 절대 URL은 요청 시점에 origin을 붙여 만든다. */
    og: {
      main: s('PHOTO_OG_MAIN') || photos.main,
      dev: s('PHOTO_OG_DEV') || photos.mainDev || photos.main,
      terminal: s('PHOTO_OG_TERMINAL') || photos.mainDev || photos.main,
    },
    accounts: { groom: parseAccounts(CONF.GROOM_ACCOUNTS), bride: parseAccounts(CONF.BRIDE_ACCOUNTS) },
    naverMapKey: s('NAVER_MAP_KEY_ID'),
    kakaoKey: s('KAKAO_JS_KEY'),
    gaId: s('GA_MEASUREMENT_ID'),
    siteOrigin: s('SITE_ORIGIN').replace(/\/+$/, ''),
    defaultVersion: ['main', 'developer', 'terminal'].includes(s('DEFAULT_VERSION', 'main'))
      ? s('DEFAULT_VERSION', 'main')
      : 'main',
  };
})();


/* 계좌 난독화
   src/js/private.js 의 deobfuscate 와 1:1로 대응한다.
   salt 1바이트를 앞에 붙이고 keystream으로 XOR한 뒤 base64로 인코딩한다.
   요청마다 salt가 달라지므로 blob도 매번 바뀐다.
   주의: 암호화가 아니라 검색 노출과 자동수집을 막기 위한 것이다. */
function obfuscate(text) {
  const bytes = Buffer.from(text, 'utf8');
  const salt = 1 + Math.floor(Math.random() * 255);
  const out = Buffer.alloc(bytes.length + 1);
  out[0] = salt;
  let k = salt;
  for (let i = 0; i < bytes.length; i++) {
    k = (k * 31 + 17 + i) & 0xff;
    out[i + 1] = (bytes[i] ?? 0) ^ k;
  }
  return out.toString('base64');
}


/* 축하를 담는 곳 (SQLite)
   seq 가 AUTOINCREMENT라 단조 증가한다. 같은 밀리초에 동시 요청이 와도 전순서가 보장된다.
   client에 주는 id 형식은 "<ms>-<seq>" 다. client가 '더보기' cursor와 중복 판별 key로 쓰므로
   형식을 바꾸면 청첩장 세 version의 js/config.js 를 모두 고쳐야 한다. */
fs.mkdirSync(path.dirname(DB_FILE), { recursive: true });
const db = new DatabaseSync(DB_FILE);
// WAL 이면 읽기와 쓰기가 서로를 막지 않고 재시작해도 남는다.
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA synchronous = NORMAL');
db.exec(`
  CREATE TABLE IF NOT EXISTS approvals (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    ms  INTEGER NOT NULL,
    ts  TEXT    NOT NULL,
    msg TEXT    NOT NULL DEFAULT '',
    ip  TEXT    NOT NULL DEFAULT ''
  );
  CREATE TABLE IF NOT EXISTS ratelimit (
    ip  TEXT    PRIMARY KEY,
    exp INTEGER NOT NULL
  );
`);

const Q = {
  count: db.prepare('SELECT COUNT(*) AS c FROM approvals'),
  recent: db.prepare('SELECT seq, ms, ts, msg FROM approvals ORDER BY seq DESC LIMIT ?'),
  older: db.prepare('SELECT seq, ms, ts, msg FROM approvals WHERE seq < ? ORDER BY seq DESC LIMIT ?'),
  insert: db.prepare('INSERT INTO approvals (ms, ts, msg, ip) VALUES (?, ?, ?, ?)'),
  rlGet: db.prepare('SELECT exp FROM ratelimit WHERE ip = ?'),
  rlSet: db.prepare(
    'INSERT INTO ratelimit (ip, exp) VALUES (?, ?) ON CONFLICT(ip) DO UPDATE SET exp = excluded.exp',
  ),
  rlSweep: db.prepare('DELETE FROM ratelimit WHERE exp < ?'),
};

const toItem = (r) => ({ id: `${r.ms}-${r.seq}`, ts: r.ts, msg: r.msg ?? '' });
const approvalCount = () => Number(Q.count.get().c ?? 0);

/** '더보기' cursor("<ms>-<seq>")에서 seq만 꺼낸다. 정렬 기준이 seq이기 때문이다. */
function cursorSeq(id) {
  const m = /^(\d+)-(\d+)$/.exec(String(id || ''));
  return m ? Number(m[2]) : null;
}

/** 같은 IP의 연타를 막는다. 창이 비어 있으면 통과시키고 창을 새로 만든다.
    DB 오류에는 통과시키고(fail-open) 뒤이은 쓰기가 오류를 처리하게 둔다. */
function rateLimited(ip) {
  if (!ip) return false;
  const now = Math.floor(Date.now() / 1000);
  try {
    Q.rlSweep.run(now);
    const row = Q.rlGet.get(ip);
    if (row && Number(row.exp) > now) return true;
    Q.rlSet.run(ip, now + RATE_LIMIT_SECONDS);
    return false;
  } catch {
    return false;
  }
}


/* 메시지 정제
   한 줄로 만들고, 태그 문자를 막고(XSS), 길이를 자른다.
   결합문자(Zalgo)와 제어문자, zero-width, 방향제어(BIDI)를 없앤다.
   client의 cleanMessage와 같은 규칙이며, client를 신뢰하지 않고 server에서 다시 적용한다. */
function sanitize(input) {
  const stripped = String(input ?? '').replace(/\p{M}+/gu, '');
  let out = '';
  for (const ch of stripped) {
    const c = ch.codePointAt(0) ?? 0;
    if (c === 9 || c === 10 || c === 13) { out += ' '; continue; }
    if (c < 0x20 || (c >= 0x7f && c <= 0x9f)) continue;
    if (c === 0x200b || c === 0x200c || c === 0x200e || c === 0x200f ||
        (c >= 0x202a && c <= 0x202e) || c === 0x2060 || c === 0xfeff) continue;
    out += ch;
  }
  return out.replace(/[<>]/g, '').trim().slice(0, MAX_MSG);
}


/* 응답 도구 */
function sendJson(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > MAX_BODY) req.destroy();
    });
    req.on('end', () => {
      try { resolve(JSON.parse(data || '{}')); } catch { resolve({}); }
    });
    req.on('error', () => resolve({}));
  });
}

/** 실제 방문자 IP를 복원한다. 앞단에 reverse proxy나 CDN이 있으면 header로 온다. */
function clientIp(req) {
  const h = req.headers;
  const xff = String(h['x-forwarded-for'] || '').split(',')[0].trim();
  return String(h['cf-connecting-ip'] || h['x-real-ip'] || xff || req.socket.remoteAddress || '').trim();
}


/* 축하 API
   응답 계약과 id 형식은 청첩장 세 version의 js/config.js 가 기대하는 그대로다. */
async function handleApi(req, res) {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS' });
    return res.end();
  }

  if (req.method === 'GET') {
    const before = new URL(req.url, 'http://x').searchParams.get('before');
    try {
      if (before) {
        const seq = cursorSeq(before);
        if (seq === null) return sendJson(res, 400, { count: approvalCount(), error: 'bad cursor' });
        return sendJson(res, 200, {
          count: approvalCount(),
          recent: Q.older.all(seq, PAGE).map(toItem),
        });
      }
      return sendJson(res, 200, { count: approvalCount(), recent: Q.recent.all(PAGE).map(toItem) });
    } catch (e) {
      console.error('approvals read failed:', e.message);
      return sendJson(res, 503, { count: 0, error: 'store unavailable' });
    }
  }

  if (req.method === 'POST') {
    const ip = clientIp(req);
    if (rateLimited(ip)) return sendJson(res, 429, { count: approvalCount(), error: 'rate limited' });

    const body = await readBody(req);
    const msg = sanitize(body.message);
    try {
      Q.insert.run(Date.now(), new Date().toISOString(), msg, ip);
      return sendJson(res, 200, { count: approvalCount() });
    } catch (e) {
      console.error('approval write failed:', e.message);
      return sendJson(res, 503, { error: 'store unavailable' });
    }
  }

  return sendJson(res, 405, { error: 'method not allowed' });
}


/* 정적 서빙과 SSR */
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.webp': 'image/webp', '.gif': 'image/gif', '.ico': 'image/x-icon',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/plain; charset=utf-8',
};

/* 자산 cache busting. 기동할 때마다 바뀌는 4자리 16진수다. HTML은 no-store로 내려가므로
   재시작 직후 하객이 최신 css와 js를 받는다. */
const ASSET_VER = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');

/** og:url 과 og:image 에 쓸 절대 origin. conf에 없으면 요청 Host에서 유추한다. */
function originFor(req) {
  if (CFG.siteOrigin) return CFG.siteOrigin;
  const host = String(req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
  if (!host) return '';
  const proto = String(req.headers['x-forwarded-proto'] || (host.startsWith('localhost') || host.startsWith('127.') ? 'http' : 'https'))
    .split(',')[0].trim();
  return `${proto}://${host}`;
}

function serveHtml(file, req, res) {
  let html;
  try {
    html = fs.readFileSync(file, 'utf8');
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('404 Not Found');
  }

  const origin = originFor(req);
  const photoBase = origin ? `${origin}/photos/` : '';
  const ogUrl = (name) => (name && photoBase ? photoBase + name : '');

  // 1) 계좌 난독화 주입. 예약 주석 자리에 넣는다.
  const gift = `<script>window.__GIFT__=${JSON.stringify(obfuscate(JSON.stringify({ accounts: CFG.accounts })))}</script>`;
  html = html.includes(INJECT_TOKEN) ? html.replace(INJECT_TOKEN, gift) : html;

  // 2) 청첩장 JS가 읽는 주입 값을 config.js 앞에 넣는다.
  //    자산 경로를 바꾸기 전에 해야 아래 정규식이 맞는다.
  const boot = [
    `window.__INV__='.'`,
    `window.__PHOTOS__='photos/'`,
    origin ? `window.__ORIGIN__=${JSON.stringify(origin)}` : '',
    `window.__WEDDING__=${JSON.stringify(CFG.wedding)}`,
    `window.__NAVER_MAP_KEY__=${JSON.stringify(CFG.naverMapKey)}`,
    `window.__KAKAO_KEY__=${JSON.stringify(CFG.kakaoKey)}`,
    `window.__GA_ID__=${JSON.stringify(CFG.gaId)}`,
  ].filter(Boolean).join(';');
  html = html.replace(
    '<script src="js/config.js',
    `<script>${boot}</script><script src="js/config.js`,
  );

  // 3) css 와 js 참조에 ?v= 를 붙인다.
  html = html.replace(
    /(href|src)="((?:css|js)\/[^"?]+\.(?:css|js))"/g,
    `$1="$2?v=${ASSET_VER}"`,
  );

  // 4) page 사이 link에서 .html 을 뗀다. 주소창이 /developer 로 유지되고,
  //    하객이 version을 오갈 때 redirect를 한 번 더 타지 않는다.
  html = html.replace(/(href=")([\w-]+)\.html(?=["#?])/g, '$1$2');

  // 5) 이름과 예식 정보 token. 추적되는 HTML에는 실제 값이 없고 여기서만 채워진다.
  const tokens = {
    ...CFG.tokens,
    OG_IMAGE_MAIN: ogUrl(CFG.og.main),
    OG_IMAGE_DEV: ogUrl(CFG.og.dev),
    OG_IMAGE_TERMINAL: ogUrl(CFG.og.terminal),
    HOST: origin.replace(/^https?:\/\//, ''),
    PAGE_URL: origin ? origin + new URL(req.url, 'http://x').pathname : '',
  };
  for (const [k, v] of Object.entries(tokens)) html = html.split(`{{${k}}}`).join(v);

  // 6) 사진이 없어 og:image 가 빈 값이면 그 meta를 지운다. 빈 URL을 남기면 카카오가
  //    미리보기를 못 읽고 깨진 card를 보여 준다.
  if (!tokens.OG_IMAGE_MAIN && !tokens.OG_IMAGE_DEV && !tokens.OG_IMAGE_TERMINAL) {
    html = html.replace(/<meta property="og:image[^>]*>/g, '');
  }

  res.writeHead(200, { 'Content-Type': MIME['.html'], 'Cache-Control': 'no-store' });
  res.end(html);
}

/** 확장자 없는 주소를 HTML 파일로 바꾼다. /developer 가 src/developer.html 이다.
    확장자가 이미 있으면 그대로 두고, 짝이 되는 파일이 없으면 빈 문자열을 준다. */
function htmlFileFor(file) {
  if (file.toLowerCase().endsWith('.html')) return file;
  if (path.extname(file)) return '';
  return fs.existsSync(`${file}.html`) ? `${file}.html` : '';
}

function serveStatic(req, res) {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/' || p === '') p = `/${CFG.defaultVersion}.html`;
  if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1);

  const file = path.resolve(path.join(SRC_DIR, p));
  // path traversal 차단. SRC_DIR 밖으로 나가는 경로를 거부한다.
  if (file !== SRC_DIR && !file.startsWith(SRC_DIR + path.sep)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('forbidden');
  }

  const htmlFile = htmlFileFor(file);
  if (htmlFile) return serveHtml(htmlFile, req, res);

  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('404 Not Found');
    }
    const ext = path.extname(file).toLowerCase();
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      // css 와 js 는 ?v= 로 갱신하므로 길게 cache해도 안전하다.
      'Cache-Control': ext === '.js' || ext === '.css'
        ? 'public, max-age=31536000, immutable'
        : 'public, max-age=3600',
    });
    res.end(data);
  });
}


/* 라우팅 */
const server = http.createServer((req, res) => {
  const { pathname } = new URL(req.url, 'http://x');

  if (pathname === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    return res.end('ok');
  }
  if (pathname === '/api/approvals') return void handleApi(req, res);
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('method not allowed');
  }

  // 확장자를 뗀 주소 하나로 모은다. 밖에서 들어온 .html link와 이전 북마크도 여기로 온다.
  // no-store 라서 browser가 이 redirect를 오래 기억하지 않는다. 되돌리기 쉽다.
  if (/\.html$/i.test(pathname)) {
    const { search } = new URL(req.url, 'http://x');
    res.writeHead(301, { Location: pathname.slice(0, -5) + search, 'Cache-Control': 'no-store' });
    return res.end();
  }

  return serveStatic(req, res);
});

server.listen(PORT, () => {
  console.log(`청첩장 server를 띄웠습니다.  port=${PORT}  asset_ver=${ASSET_VER}`);
  console.log(`  ${CFG.tokens.GROOM_NAME || '?'} ♥ ${CFG.tokens.BRIDE_NAME || '?'}   ${CFG.tokens.WEDDING_DATETIME_KO}`);
  console.log(`  ${CFG.tokens.VENUE_NAME || '?'} ${CFG.tokens.VENUE_HALL || ''}`);
  console.log(`  기본 version=${CFG.defaultVersion}  축하 ${approvalCount()}건  db=${DB_FILE}`);
});

/* container가 멈출 때 DB를 정리해 WAL을 반영한다. */
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`${sig} 을 받아 종료합니다.`);
    server.close(() => {
      try { db.close(); } catch { /* 이미 닫혔으면 넘어간다 */ }
      process.exit(0);
    });
  });
}
