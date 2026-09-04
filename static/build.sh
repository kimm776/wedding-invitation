#!/usr/bin/env bash
# invitation.conf 를 읽어 src/ 를 dist/ 로 변환합니다.
#
# 하는 일
#   1) src/*.html 의 {{TOKEN}} 을 invitation.conf 값으로 sed 치환합니다.
#   2) 예식 일시에서 파생값(요일, 한국어 날짜, D-day 기준)을 KST로 계산합니다.
#   3) 청첩장 JS가 읽는 window.__WEDDING__ 등을 dist/js/data.js 로 생성합니다.
#   4) 계좌를 난독화해 같은 파일에 넣습니다. 결과물에 평문 번호가 남지 않습니다.
#   5) css 와 js 참조에 ?v= 를 붙여 browser cache를 갱신합니다.
#
# 필요한 명령: bash, sed, awk, od, base64
#
#   ./build.sh                      invitation.conf 를 읽습니다
#   ./build.sh -c other.conf        다른 conf 파일을 읽습니다
#   ./build.sh -o /tmp/out          다른 곳에 출력합니다
#
# macOS와 Linux에서 같이 동작합니다. GNU 전용 정규식과 옵션을 쓰지 않습니다.
# Windows에서는 build.ps1 을 씁니다.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="$HERE/invitation.conf"
OUT="$HERE/dist"
SRC="$HERE/src"

# 출력 directory가 이 script의 산출물임을 표시하는 파일입니다.
# 지우기 전에 이 표식을 확인하므로 -o 로 다른 directory를 가리켜도 지우지 않습니다.
STAMP=".invitation-build"

while getopts 'c:o:h' opt; do
  case "$opt" in
    c) CONF="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    h) sed -n '2,20p' "$0"; exit 0 ;;
    *) exit 2 ;;
  esac
done

log() { printf '%s\n' "$*"; }
die() { printf 'build.sh: %s\n' "$*" >&2; exit 1; }

[ -f "$CONF" ] || die "$CONF 이 없습니다. invitation.conf.example 을 복사해 만들어 주시기 바랍니다.
  cp invitation.conf.example invitation.conf"
[ -d "$SRC" ] || die "$SRC 이 없습니다."

# conf 를 shell로 source하지 않고 직접 해석합니다.
# with-guestbook 의 server.mjs 와 build.ps1 이 같은 방식으로 읽으므로 세 곳의 동작이
# 어긋나지 않습니다. conf 안의 문장이 shell 명령으로 실행될 일도 없습니다.
#   KEY=value 와 KEY="value" 를 다룹니다. 값에 공백이 있어도 따옴표가 필수가 아닙니다.
#   # 으로 시작하는 줄은 주석입니다.
#   값 안의 \n 은 그대로 두고 쓰는 곳에서 줄바꿈으로 바꿉니다.
conf_load() {
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    case "$line" in *=*) ;; *) continue ;; esac

    key="${line%%=*}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    # 변수 이름으로 쓸 수 있는 것만 받습니다. eval에 넘기기 전 확인입니다.
    printf '%s' "$key" | grep -q '^[A-Za-z_][A-Za-z0-9_]*$' || continue

    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    # 감싼 따옴표 한 겹을 없앱니다.
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    # 값 안의 홑따옴표를 escape해서 안전하게 대입합니다.
    eval "$key='$(printf '%s' "$val" | sed "s/'/'\\\\''/g")'"
  done < "$1"
}
conf_load "$CONF"

# 값이 비어 있어도 build는 됩니다. 다만 이름과 일시가 없으면 화면이 비므로 알려 줍니다.
for v in GROOM_NAME BRIDE_NAME WEDDING_AT; do
  eval "vv=\${$v:-}"
  [ -n "$vv" ] || log "  경고: $v 이 비어 있습니다. 화면의 해당 자리가 빈 채로 나옵니다."
done


# --- 예식 일시를 KST 구성요소로 분해 ---------------------------------------
# Intl이나 date 명령의 GNU와 BSD 차이에 기대지 않고 awk로 직접 계산합니다.
# offset을 KST(+09:00)로 옮긴 뒤 y, m, d, 요일, 시, 분을 뽑습니다.
kst_parts() {
  awk -v iso="$1" '
    function c2d(y, m, d,   yy, era, yoe, doy, doe) {
      yy = y - (m <= 2 ? 1 : 0)
      era = int((yy >= 0 ? yy : yy - 399) / 400)
      yoe = yy - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    function d2c(z,   era, doe, yoe, y, doy, mp, d, m) {
      z += 719468
      era = int((z >= 0 ? z : z - 146096) / 146097)
      doe = z - era * 146097
      yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
      y = yoe + era * 400
      doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
      mp = int((5 * doy + 2) / 153)
      d = doy - int((153 * mp + 2) / 5) + 1
      m = mp + (mp < 10 ? 3 : -9)
      y += (m <= 2 ? 1 : 0)
      CY = y; CM = m; CD = d
    }
    BEGIN {
      # YYYY-MM-DDThh:mm[:ss] 뒤에 Z 또는 +hh:mm 이 붙습니다.
      if (iso !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]/) {
        print "ERR"; exit 0
      }
      y  = substr(iso, 1, 4)  + 0
      mo = substr(iso, 6, 2)  + 0
      da = substr(iso, 9, 2)  + 0
      hh = substr(iso, 12, 2) + 0
      mi = substr(iso, 15, 2) + 0
      if (mo < 1 || mo > 12 || da < 1 || da > 31 || hh > 23 || mi > 59) { print "ERR"; exit 0 }

      # offset을 초로 바꿉니다. Z 이거나 표기가 없으면 0입니다.
      off = 0
      tail = substr(iso, 17)
      if (match(tail, /[+-][0-9][0-9]:[0-9][0-9]$/)) {
        s = substr(tail, RSTART, RLENGTH)
        sign = (substr(s, 1, 1) == "-") ? -1 : 1
        off = sign * (substr(s, 2, 2) * 3600 + substr(s, 5, 2) * 60)
      }

      # UTC로 옮긴 뒤 KST(+9h)를 더합니다.
      secs = c2d(y, mo, da) * 86400 + hh * 3600 + mi * 60 - off + 9 * 3600
      days = int(secs / 86400)
      rem  = secs - days * 86400
      if (rem < 0) { rem += 86400; days -= 1 }
      d2c(days)

      h24 = int(rem / 3600)
      m60 = int((rem - h24 * 3600) / 60)
      dow = ((days % 7) + 7 + 4) % 7        # 1970-01-01 은 목요일(4)입니다

      printf "Y=%d M=%d D=%d DOW=%d H24=%d MI=%d\n", CY, CM, CD, dow, h24, m60
    }
  '
}

DAY_KO=(일 월 화 수 목 금 토)
DAY_EN=(SUN MON TUE WED THU FRI SAT)
MONTH_EN=(JANUARY FEBRUARY MARCH APRIL MAY JUNE JULY AUGUST SEPTEMBER OCTOBER NOVEMBER DECEMBER)
pad2() { printf '%02d' "$1"; }

parts="$(kst_parts "${WEDDING_AT:-}")"
[ "$parts" != "ERR" ] || die "WEDDING_AT 을 해석할 수 없습니다: '${WEDDING_AT:-}'
  offset을 포함한 ISO 8601로 적어 주시기 바랍니다. 예: 2026-10-24T13:00:00+09:00"
eval "$parts"                                  # Y M D DOW H24 MI

fparts="$(kst_parts "${FIRST_MET_AT:-${WEDDING_AT:-}}")"
[ "$fparts" != "ERR" ] || { log "  경고: FIRST_MET_AT 을 해석할 수 없어 예식 일시로 대신합니다."; fparts="$parts"; }
eval "$(printf '%s' "$fparts" | sed 's/\([A-Z0-9]*\)=/F\1=/g')"   # FY FM FD FDOW FH24 FMI

H12=$(( H24 % 12 )); [ "$H12" -ne 0 ] || H12=12
if [ "$H24" -lt 12 ]; then AMPM=AM; AMPM_KO=오전; else AMPM=PM; AMPM_KO=오후; fi

DATE_KO="${Y}년 ${M}월 ${D}일 ${DAY_KO[$DOW]}요일"
TIME_KO="${AMPM_KO} ${H12}시"
[ "$MI" -eq 0 ] || TIME_KO="${TIME_KO} ${MI}분"


# --- 문자열 도구 ------------------------------------------------------------
# 안내 문구의 \n 을 <br /> 로 바꿉니다. HTML에 그대로 들어가므로 태그 문자를 먼저 막습니다.
br() { printf '%s' "${1:-}" | sed -e 's/[<>]//g' -e 's/\\n/<br \/>/g'; }

# JSON 문자열 하나를 만듭니다. 역슬래시와 따옴표, 제어문자를 막습니다.
json_str() {
  printf '"%s"' "$(printf '%s' "${1:-}" \
    | tr -d '\r\n' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# 콤마로 구분된 목록을 JSON 문자열 배열로 만듭니다.
json_list() {
  local IFS=',' item out=''
  for item in ${1:-}; do
    item="$(printf '%s' "$item" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$item" ] || continue
    out="${out}${out:+,}$(json_str "$item")"
  done
  printf '[%s]' "$out"
}

# 콤마로 구분된 숫자 목록을 JSON 숫자 배열로 만듭니다.
json_nums() {
  local IFS=',' item out=''
  for item in ${1:-}; do
    item="$(printf '%s' "$item" | tr -cd '0-9')"
    [ -n "$item" ] || continue
    out="${out}${out:+,}${item}"
  done
  printf '[%s]' "$out"
}

# 이름|은행|번호,... 를 JSON 객체 배열로 만듭니다.
json_accounts() {
  local IFS=',' rec out='' rest name bank num
  for rec in ${1:-}; do
    [ -n "$rec" ] || continue
    name="${rec%%|*}"
    rest="${rec#*|}"
    if [ "$rest" = "$rec" ]; then bank=''; num=''; else bank="${rest%%|*}"; num="${rest#*|}"; fi
    [ "$num" != "$bank" ] || num=''
    out="${out}${out:+,}{\"name\":$(json_str "$name"),\"bank\":$(json_str "$bank"),\"number\":$(json_str "$num")}"
  done
  printf '[%s]' "$out"
}

# 콤마 목록의 n번째(1부터) 항목입니다. 부모 이름을 하나씩 쓰는 token에 씁니다.
nth() { printf '%s' "${1:-}" | awk -F',' -v n="$2" '{gsub(/^[ \t]+|[ \t]+$/, "", $n); print $n}'; }

# 영문 이름에서 파생하는 장식 값입니다.
first_name() { printf '%s' "${1:-}" | awk '{print $1}'; }
last_name()  { printf '%s' "${1:-}" | awk '{print $NF}'; }
handle()     { first_name "${1:-}" | tr 'A-Z' 'a-z' | tr -d '-'; }
branch()     { printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | awk '{$1=$1; gsub(/ +/, "-"); print}'; }

# 사진 파일 이름을 절대 URL로 바꿉니다. og:image 는 절대 URL이어야 카카오톡이 읽습니다.
ORIGIN="$(printf '%s' "${SITE_ORIGIN:-}" | sed 's:/*$::')"
photo_url() {
  if [ -n "${1:-}" ] && [ -n "$ORIGIN" ]; then printf '%s/photos/%s' "$ORIGIN" "$1"; else printf ''; fi
}


# --- 계좌 난독화 ------------------------------------------------------------
# src/js/private.js 의 deobfuscate 와 1:1로 대응합니다.
# salt 1바이트를 앞에 붙이고 keystream으로 XOR한 뒤 base64로 인코딩합니다.
# 주의: 암호화가 아닙니다. 검색 노출과 자동수집을 막기 위한 것입니다.
b64() { if command -v base64 >/dev/null 2>&1; then base64 | tr -d '\n'; else openssl base64 | tr -d '\n'; fi; }

obfuscate() {
  local salt esc
  salt=$(( $(od -An -N1 -tu1 < /dev/urandom | tr -d ' \n') % 255 + 1 ))
  esc="$(printf '%s' "$1" \
    | od -An -v -tu1 \
    | tr -s ' \n' '\n\n' \
    | awk -v salt="$salt" '
        function xor8(a, b,   r, p, i, x, y) {
          r = 0; p = 1
          for (i = 0; i < 8; i++) {
            x = a % 2; y = b % 2
            if (x != y) r += p
            a = int(a / 2); b = int(b / 2); p *= 2
          }
          return r
        }
        BEGIN { k = salt; n = 0; printf "\\0%03o", salt }
        /^[0-9]+$/ { k = (k * 31 + 17 + n) % 256; printf "\\0%03o", xor8($1, k); n++ }
      ')"
  printf '%b' "$esc" | b64
}


# --- token 표 --------------------------------------------------------------
# 여기 있는 이름이 src/*.html 의 {{TOKEN}} 과 1:1로 대응합니다.
TOK=()
add() { TOK+=("$1=$2"); }

add GROOM_NAME        "${GROOM_NAME:-}"
add GROOM_NAME_SHORT  "${GROOM_NAME_SHORT:-}"
add GROOM_NAME_EN     "${GROOM_NAME_EN:-}"
add GROOM_ROLE        "${GROOM_ROLE:-}"
add GROOM_PARENTS     "$(printf '%s' "${GROOM_PARENTS:-}" | sed 's/ *, */ /g')"
add GROOM_PARENTS_0   "$(nth "${GROOM_PARENTS:-}" 1)"
add GROOM_PARENTS_1   "$(nth "${GROOM_PARENTS:-}" 2)"
add GROOM_RANK_KO     "${GROOM_RANK_KO:-}"
add GROOM_RANK_EXPR   "${GROOM_RANK_EXPR:-}"
add GROOM_EN_FIRST    "$(first_name "${GROOM_NAME_EN:-}")"
add GROOM_EN_LAST     "$(last_name "${GROOM_NAME_EN:-}")"
add GROOM_HANDLE      "$(handle "${GROOM_NAME_EN:-}")"
add GROOM_BRANCH      "$(branch "${GROOM_NAME_EN:-}")"

add BRIDE_NAME        "${BRIDE_NAME:-}"
add BRIDE_NAME_SHORT  "${BRIDE_NAME_SHORT:-}"
add BRIDE_NAME_EN     "${BRIDE_NAME_EN:-}"
add BRIDE_ROLE        "${BRIDE_ROLE:-}"
add BRIDE_PARENTS     "$(printf '%s' "${BRIDE_PARENTS:-}" | sed 's/ *, */ /g')"
add BRIDE_PARENTS_0   "$(nth "${BRIDE_PARENTS:-}" 1)"
add BRIDE_PARENTS_1   "$(nth "${BRIDE_PARENTS:-}" 2)"
add BRIDE_RANK_KO     "${BRIDE_RANK_KO:-}"
add BRIDE_RANK_EXPR   "${BRIDE_RANK_EXPR:-}"
add BRIDE_EN_FIRST    "$(first_name "${BRIDE_NAME_EN:-}")"
add BRIDE_EN_LAST     "$(last_name "${BRIDE_NAME_EN:-}")"
add BRIDE_HANDLE      "$(handle "${BRIDE_NAME_EN:-}")"
add BRIDE_BRANCH      "$(branch "${BRIDE_NAME_EN:-}")"

add VENUE_NAME          "${VENUE_NAME:-}"
add VENUE_HALL          "${VENUE_HALL:-}"
add VENUE_ADDRESS       "${VENUE_ADDRESS:-}"
add VENUE_FLOOR         "${VENUE_FLOOR:-}"
add VENUE_ADDRESS_FULL  "$(printf '%s %s' "${VENUE_ADDRESS:-}" "${VENUE_FLOOR:-}" | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
add VENUE_SUBWAY        "${VENUE_SUBWAY:-}"
add VENUE_SUBWAY_SHORT  "${VENUE_SUBWAY_SHORT:-}"

add MAP_NAVER_URL "${MAP_NAVER_URL:-}"
add MAP_KAKAO_URL "${MAP_KAKAO_URL:-}"

add WEDDING_DATE_KO       "$DATE_KO"
add WEDDING_TIME_KO       "$TIME_KO"
add WEDDING_DATETIME_KO   "$DATE_KO $TIME_KO"
add WEDDING_DATE_ISO      "${Y}-$(pad2 "$M")-$(pad2 "$D")"
add WEDDING_DATE_DOT      "${Y}.$(pad2 "$M").$(pad2 "$D")"
add WEDDING_YEAR          "${Y}"
add WEDDING_YEAR_MONTH_KO "${Y}년 ${M}월"
add WEDDING_MONTH_EN      "${MONTH_EN[$((M - 1))]}"
add WEDDING_DAY_EN        "${DAY_EN[$DOW]}"
add WEDDING_DAY_KO_SHORT  "${DAY_KO[$DOW]}"
add WEDDING_TIME_EN       "${AMPM} ${H12}:$(pad2 "$MI")"
add WEDDING_CLOCK_KST     "${DAY_EN[$DOW]:0:1}$(printf '%s' "${DAY_EN[$DOW]:1}" | tr 'A-Z' 'a-z') ${Y}-$(pad2 "$M")-$(pad2 "$D") $(pad2 "$H24"):$(pad2 "$MI"):00 KST"
add FIRST_MET_ISO         "${FY}-$(pad2 "$FM")-$(pad2 "$FD")"

add INFO_SUBWAY  "$(br "${INFO_SUBWAY:-}")"
add INFO_BUS     "$(br "${INFO_BUS:-}")"
add INFO_PARKING "$(br "${INFO_PARKING:-}")"
add INFO_MEAL    "$(br "${INFO_MEAL:-}")"

# 공유 card image. 지정한 것이 없으면 각 version의 표지를 씁니다.
OG_MAIN="$(photo_url "${PHOTO_OG_MAIN:-${PHOTO_MAIN:-}}")"
OG_DEV="$(photo_url "${PHOTO_OG_DEV:-${PHOTO_MAIN_DEV:-${PHOTO_MAIN:-}}}")"
OG_TERM="$(photo_url "${PHOTO_OG_TERMINAL:-${PHOTO_MAIN_DEV:-${PHOTO_MAIN:-}}}")"
add OG_IMAGE_MAIN     "$OG_MAIN"
add OG_IMAGE_DEV      "$OG_DEV"
add OG_IMAGE_TERMINAL "$OG_TERM"

# scheme 을 없앤 host. GNU 전용 \? 대신 * 를 써서 macOS sed 에서도 동작합니다.
add HOST "$(printf '%s' "$ORIGIN" | sed -e 's#^https*://##')"


# --- dist 준비 -------------------------------------------------------------
# 이 script가 만든 directory임을 확인한 뒤에만 비웁니다.
if [ -e "$OUT" ]; then
  [ -d "$OUT" ] || die "$OUT 이 directory가 아닙니다."
  if [ ! -f "$OUT/$STAMP" ]; then
    die "$OUT 은 이 script가 만든 곳이 아닙니다($STAMP 표식이 없습니다).
  실수로 지우지 않도록 멈췄습니다. 다른 경로를 -o 로 주시거나 그 directory를 직접 비워 주시기 바랍니다."
  fi
  find "$OUT" -mindepth 1 -delete
fi
mkdir -p "$OUT/js" "$OUT/css" "$OUT/assets" "$OUT/photos"
printf 'build.sh 산출물입니다. 이 파일이 있어야 다음 build가 이 directory를 비웁니다.\n' > "$OUT/$STAMP"
cp -R "$SRC/css/." "$OUT/css/"
cp -R "$SRC/js/."  "$OUT/js/"
cp -R "$SRC/assets/." "$OUT/assets/"
# 사진은 있으면 함께 옮깁니다. README 만 있는 상태도 정상입니다.
find "$SRC/photos" -type f ! -name 'README*' -exec cp {} "$OUT/photos/" \; 2>/dev/null || true


# --- 청첩장 JS가 읽는 주입 값 (dist/js/data.js) -----------------------------
# 청첩장 세 version의 js/config.js 가 window.__WEDDING__ 를 읽습니다.
# 이 모양을 바꾸면 세 version이 함께 깨지므로 key 이름을 유지합니다.
person_json() {
  local p="$1" v
  v() { eval "printf '%s' \"\${${p}_$1:-$2}\""; }
  printf '{"name":%s,"short":%s,"en":%s,"initial":%s,"role":%s,"parents":%s,"rankKo":%s,"rank":%s,"mbti":%s,"hobby":%s,"note":%s,"photo":%s,"photoFocus":%s,"photoZoom":%s}' \
    "$(json_str "$(v NAME '')")" \
    "$(json_str "$(v NAME_SHORT '')")" \
    "$(json_str "$(v NAME_EN '')")" \
    "$(json_str "$(v INITIAL '')")" \
    "$(json_str "$(v ROLE '')")" \
    "$(json_list "$(v PARENTS '')")" \
    "$(json_str "$(v RANK_KO '')")" \
    "$(json_str "$(v RANK_EXPR '')")" \
    "$(json_str "$(v MBTI '')")" \
    "$(json_str "$(v HOBBY '')")" \
    "$(json_str "$(v NOTE '')")" \
    "$(json_str "$(v PHOTO '')")" \
    "$(json_str "$(v PHOTO_FOCUS '50% 30%')")" \
    "$(printf '%s' "$(v PHOTO_ZOOM 1)" | awk '{v=$0+0; print (v>=1 && v<=3) ? v : 1}')"
}

# 숫자인지 검사만 하고 원문을 그대로 냅니다. $0+0 으로 내면 awk의 기본 출력 형식(%.6g)이
# 좌표 자리수를 잘라 지도 위치가 어긋납니다.
num_or() { printf '%s' "${1:-}" | awk -v d="$2" '{ if ($0 ~ /^-?[0-9]+(\.[0-9]+)?$/) printf "%s", $0; else printf "%s", d }'; }

WEDDING_JSON="$(printf '%s' \
"{\"at\":$(json_str "${WEDDING_AT:-}"),\"firstMetAt\":$(json_str "${FIRST_MET_AT:-${WEDDING_AT:-}}"),\
\"groom\":$(person_json GROOM),\"bride\":$(person_json BRIDE),\
\"venue\":{\"name\":$(json_str "${VENUE_NAME:-}"),\"hall\":$(json_str "${VENUE_HALL:-}"),\
\"address\":$(json_str "${VENUE_ADDRESS:-}"),\"floor\":$(json_str "${VENUE_FLOOR:-}"),\
\"addressCopy\":$(json_str "${VENUE_ADDRESS_COPY:-}"),\"subway\":$(json_str "${VENUE_SUBWAY:-}"),\
\"subwayShort\":$(json_str "${VENUE_SUBWAY_SHORT:-}"),\"lat\":$(num_or "${VENUE_LAT:-}" 0),\
\"lng\":$(num_or "${VENUE_LNG:-}" 0),\"zoom\":$(num_or "${VENUE_MAP_ZOOM:-}" 17)},\
\"map\":{\"naver\":$(json_str "${MAP_NAVER_URL:-}"),\"kakao\":$(json_str "${MAP_KAKAO_URL:-}")},\
\"photos\":{\"main\":$(json_str "${PHOTO_MAIN:-}"),\"mainDev\":$(json_str "${PHOTO_MAIN_DEV:-}"),\
\"bless\":$(json_str "${PHOTO_BLESS:-}"),\"gallery\":$(json_list "${PHOTO_GALLERY:-}"),\
\"galleryPageOrder\":{\"main\":$(json_nums "${GALLERY_ORDER_MAIN:-}"),\"dev\":$(json_nums "${GALLERY_ORDER_DEV:-}")}}}")"

GIFT_JSON="{\"accounts\":{\"groom\":$(json_accounts "${GROOM_ACCOUNTS:-}"),\"bride\":$(json_accounts "${BRIDE_ACCOUNTS:-}")}}"
GIFT_BLOB="$(obfuscate "$GIFT_JSON")"

{
  echo "/* build.sh 가 invitation.conf 에서 생성했습니다. 직접 고치지 않습니다. */"
  echo "window.__INV__='.';"
  echo "window.__PHOTOS__='photos/';"
  [ -z "$ORIGIN" ] || echo "window.__ORIGIN__=$(json_str "$ORIGIN");"
  # 축하 한마디 API. 주소가 있으면 그쪽으로 보냅니다. 없으면 이 build에 backend가 없다고
  # 알려서 없는 주소로 5초마다 요청하지 않게 합니다. 그때는 localStorage demo mode입니다.
  if [ -n "${GUESTBOOK_API_BASE:-}" ]; then
    echo "window.__API__=$(json_str "$(printf '%s' "$GUESTBOOK_API_BASE" | sed 's:/*$::')");"
  else
    echo "window.__NO_API__=true;"
  fi
  echo "window.__WEDDING__=${WEDDING_JSON};"
  echo "window.__NAVER_MAP_KEY__=$(json_str "${NAVER_MAP_KEY_ID:-}");"
  echo "window.__KAKAO_KEY__=$(json_str "${KAKAO_JS_KEY:-}");"
  echo "window.__GA_ID__=$(json_str "${GA_MEASUREMENT_ID:-}");"
  echo "window.__GIFT__=$(json_str "$GIFT_BLOB");"
} > "$OUT/js/data.js"

# 만든 JSON이 유효한지 확인합니다. node가 있으면 씁니다. 없으면 건너뜁니다.
if command -v node >/dev/null 2>&1; then
  node -e 'JSON.parse(process.argv[1])' "$WEDDING_JSON" 2>/dev/null \
    || die "생성한 window.__WEDDING__ JSON이 유효하지 않습니다.
  conf 값에 따옴표나 역슬래시가 섞였는지 확인해 주시기 바랍니다."
  node -e 'JSON.parse(process.argv[1])' "$GIFT_JSON" 2>/dev/null \
    || die "계좌 JSON이 유효하지 않습니다. GROOM_ACCOUNTS 와 BRIDE_ACCOUNTS 형식을 확인해 주시기 바랍니다."
fi


# --- 자산 version (browser cache 갱신) --------------------------------------
ASSET_VER="$(cat "$OUT"/css/*.css "$OUT"/js/*.js | cksum | awk '{printf "%x", $1}')"


# --- sed script를 만들어 HTML을 치환 ----------------------------------------
# mktemp 에 template 을 줍니다. 인자 없는 mktemp 는 macOS 에서 실패합니다.
SEDF="$(mktemp "${TMPDIR:-/tmp}/invitation-sed.XXXXXX")"
trap 'rm -f "$SEDF"' EXIT

# sed 치환문에서 뜻을 갖는 문자를 막습니다. & 는 일치한 전체를 뜻하므로 반드시 escape합니다.
sed_esc() { printf '%s' "${1:-}" | tr -d '\n' | sed 's/[\\&|]/\\&/g'; }

for entry in "${TOK[@]}"; do
  printf 's|{{%s}}|%s|g\n' "${entry%%=*}" "$(sed_esc "${entry#*=}")" >> "$SEDF"
done

# 주입 script를 config.js 앞에 넣습니다. 자산 경로에 ?v= 를 붙이기 전에 해야 함께 붙습니다.
printf '%s\n' 's|<script src="js/config.js"|<script src="js/data.js"></script><script src="js/config.js"|g' >> "$SEDF"
# 계좌는 data.js 로 옮겼으므로 예약 주석은 지웁니다.
printf '%s\n' 's|<!--#PRIVATE#-->||g' >> "$SEDF"
# css 와 js 참조의 ?v= 는 아래 page loop 에서 sed -E 로 따로 붙입니다.
# href 와 src 두 갈래를 한 정규식으로 쓰려면 ERE 가 필요합니다.
# BRE 의 \| 는 GNU 전용이라 macOS sed 에서 통하지 않습니다.

pages=0
for f in "$SRC"/*.html; do
  name="$(basename "$f")"
  page_url=''
  [ -z "$ORIGIN" ] || page_url="$ORIGIN/$name"
  sed -f "$SEDF" -e "s|{{PAGE_URL}}|$(sed_esc "$page_url")|g" "$f" \
    | sed -E "s#(href|src)=\"((css|js)/[^\"?]*\.(css|js))\"#\\1=\"\\2?v=${ASSET_VER}\"#g" \
    > "$OUT/$name"
  pages=$((pages + 1))
done

# 사진이 없어 og:image 가 빈 값이면 그 meta를 지웁니다. 빈 URL을 남기면 카카오가
# 미리보기를 못 읽고 깨진 card를 보여 줍니다.
if [ -z "${OG_MAIN}${OG_DEV}${OG_TERM}" ]; then
  for f in "$OUT"/*.html; do
    sed '/<meta property="og:image/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
fi

# 처음 열었을 때 보여줄 version을 index.html 로 복사합니다.
case "${DEFAULT_VERSION:-main}" in
  main|developer|terminal) DEF="${DEFAULT_VERSION:-main}" ;;
  *) log "  경고: DEFAULT_VERSION='${DEFAULT_VERSION:-}' 은 main, developer, terminal 중 하나여야 합니다. main으로 둡니다."
     DEF=main ;;
esac
cp "$OUT/${DEF}.html" "$OUT/index.html"


# --- 결과 확인 -------------------------------------------------------------
left="$(grep -ho '{{[A-Z0-9_]*}}' "$OUT"/*.html 2>/dev/null | sort -u || true)"
if [ -n "$left" ]; then
  log "  경고: 치환되지 않은 token이 남았습니다."
  printf '    %s\n' $left
fi

# 평문 계좌번호가 결과물에 남지 않았는지 확인합니다. 사람이 확인하는 대신 script가 막습니다.
leak=0
old_ifs="$IFS"; IFS=','
for acc in ${GROOM_ACCOUNTS:-} ${BRIDE_ACCOUNTS:-}; do
  num="${acc##*|}"
  [ ${#num} -ge 6 ] || continue
  if grep -rqF -- "$num" "$OUT" 2>/dev/null; then
    log "  위험: 계좌번호 '$num' 이 dist/ 에 평문으로 남아 있습니다."
    leak=1
  fi
done
IFS="$old_ifs"
[ "$leak" -eq 0 ] || die "난독화가 동작하지 않았습니다. 결과물을 배포하지 않는 편이 좋습니다."

log ""
log "완성했습니다.  pages=${pages}+index  asset_ver=${ASSET_VER}"
log "  ${GROOM_NAME:-?} ♥ ${BRIDE_NAME:-?}   ${DATE_KO} ${TIME_KO}"
log "  ${VENUE_NAME:-?} ${VENUE_HALL:-}"
log ""
log "미리 보기:  ./startup.sh        그다음 http://localhost:8080"
log "올리기:     dist/ 안의 내용을 정적 호스팅에 그대로 올립니다."
