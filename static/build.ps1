# invitation.conf 를 읽어 src/ 를 dist/ 로 변환합니다.
#
# build.sh 의 Windows 판입니다. 같은 invitation.conf 를 읽고 같은 결과를 만듭니다.
#
# 하는 일
#   1) src/*.html 의 {{TOKEN}} 을 invitation.conf 값으로 치환합니다.
#   2) 예식 일시에서 파생값(요일, 한국어 날짜, D-day 기준)을 KST로 계산합니다.
#   3) 청첩장 JS가 읽는 window.__WEDDING__ 등을 dist/js/data.js 로 생성합니다.
#   4) 계좌를 난독화해 같은 파일에 넣습니다. 결과물에 평문 번호가 남지 않습니다.
#   5) css 와 js 참조에 ?v= 를 붙여 browser cache를 갱신합니다.
#
# Windows PowerShell 5.1 과 PowerShell 7 에서 동작합니다. 추가 module이 필요하지 않습니다.
#
#   .\build.ps1
#   .\build.ps1 -Conf other.conf
#   .\build.ps1 -Out C:\temp\out
#
# PowerShell 실행 정책 때문에 막히면 아래 명령으로 해당 session에서만 허용해 주시기 바랍니다.
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

[CmdletBinding()]
param(
  [string]$Conf,
  [string]$Out
)

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Conf) { $Conf = [IO.Path]::Combine($here, 'invitation.conf') }
if (-not $Out)  { $Out  = [IO.Path]::Combine($here, 'dist') }
$src = [IO.Path]::Combine($here, 'src')

# .NET API 는 PowerShell 의 현재 위치를 따르지 않습니다. 상대 경로를 절대 경로로 바꿉니다.
$Conf = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Conf))
$Out  = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Out))

# 출력 directory가 이 script의 산출물임을 표시하는 파일입니다.
# 지우기 전에 이 표식을 확인하므로 -Out 으로 다른 directory를 가리켜도 지우지 않습니다.
$stamp = '.invitation-build'

$utf8 = New-Object System.Text.UTF8Encoding($false)   # BOM 없는 UTF-8
function Read-Text([string]$p)  { [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }
function Write-Text([string]$p, [string]$t) { [IO.File]::WriteAllText($p, $t, $utf8) }
function Fail([string]$m) { Write-Error "build.ps1: $m"; exit 1 }

if (-not (Test-Path -LiteralPath $Conf)) {
  Fail "$Conf 이 없습니다. invitation.conf.example 을 복사해 만들어 주시기 바랍니다.`n  Copy-Item invitation.conf.example invitation.conf"
}
if (-not (Test-Path -LiteralPath $src)) { Fail "$src 이 없습니다." }


# --- invitation.conf 읽기 ---------------------------------------------------
# build.sh 와 server.mjs 와 같은 방식으로 해석합니다.
#   KEY=value 와 KEY="value" 를 다룹니다.
#   # 으로 시작하는 줄은 주석입니다.
#   값 안의 \n 은 그대로 두고 쓰는 곳에서 줄바꿈으로 바꿉니다.
$C = @{}
foreach ($line in [IO.File]::ReadAllLines($Conf, [Text.Encoding]::UTF8)) {
  $t = $line.Trim()
  if ($t -eq '' -or $t.StartsWith('#')) { continue }
  $eq = $t.IndexOf('=')
  if ($eq -lt 1) { continue }
  $key = $t.Substring(0, $eq).Trim()
  if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
  $val = $t.Substring($eq + 1).Trim()
  if ($val.Length -ge 2) {
    $q = $val[0]
    if (($q -eq '"' -or $q -eq "'") -and $val[$val.Length - 1] -eq $q) {
      $val = $val.Substring(1, $val.Length - 2)
    }
  }
  $C[$key] = $val
}

# conf 값 하나를 꺼냅니다. 없으면 기본값입니다.
function Cf([string]$k, [string]$d = '') {
  if ($C.ContainsKey($k) -and $C[$k] -ne '') { return $C[$k] }
  return $d
}

foreach ($v in @('GROOM_NAME', 'BRIDE_NAME', 'WEDDING_AT')) {
  if ((Cf $v) -eq '') { Write-Host "  경고: $v 이 비어 있습니다. 화면의 해당 자리가 빈 채로 나옵니다." }
}


# --- 예식 일시를 KST 구성요소로 분해 ----------------------------------------
$DAY_KO   = @('일','월','화','수','목','금','토')
$DAY_EN   = @('SUN','MON','TUE','WED','THU','FRI','SAT')
$MONTH_EN = @('JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST',
              'SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER')

function Kst([string]$iso) {
  $style = [Globalization.DateTimeStyles]::AssumeUniversal
  $dto = [DateTimeOffset]::MinValue
  $ok = [DateTimeOffset]::TryParse($iso, [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$dto)
  if (-not $ok) { return $null }
  return $dto.ToOffset([TimeSpan]::FromHours(9))
}

$w = Kst (Cf 'WEDDING_AT')
if ($null -eq $w) {
  Fail "WEDDING_AT 을 해석할 수 없습니다: '$(Cf 'WEDDING_AT')'`n  offset을 포함한 ISO 8601로 적어 주시기 바랍니다. 예: 2026-11-14T11:00:00+09:00"
}
$f = Kst (Cf 'FIRST_MET_AT' (Cf 'WEDDING_AT'))
if ($null -eq $f) {
  Write-Host "  경고: FIRST_MET_AT 을 해석할 수 없어 예식 일시로 대신합니다."
  $f = $w
}

$dow    = [int]$w.DayOfWeek        # Sunday = 0
$h24    = $w.Hour
$h12    = $h24 % 12
if ($h12 -eq 0) { $h12 = 12 }
if ($h24 -lt 12) { $ampm = 'AM'; $ampmKo = '오전' } else { $ampm = 'PM'; $ampmKo = '오후' }

$dateKo = "$($w.Year)년 $($w.Month)월 $($w.Day)일 $($DAY_KO[$dow])요일"
$timeKo = "$ampmKo $h12시"
if ($w.Minute -ne 0) { $timeKo = "$timeKo $($w.Minute)분" }

function P2([int]$n) { $n.ToString('00') }


# --- 문자열 도구 ------------------------------------------------------------
# 안내 문구의 \n 을 <br /> 로 바꿉니다. HTML에 그대로 들어가므로 태그 문자를 먼저 막습니다.
function Br([string]$s) {
  if (-not $s) { return '' }
  return ($s -replace '[<>]', '').Replace('\n', '<br />')
}

# JSON 문자열 하나를 만듭니다. ConvertTo-Json 은 PowerShell 판마다 빈 배열과
# 단일 요소 배열을 다르게 다룹니다. build.sh 와 같은 결과를 얻으려고 직접 만듭니다.
function JStr([string]$s) {
  if ($null -eq $s) { $s = '' }
  $s = $s -replace "`r", '' -replace "`n", ''
  $s = $s.Replace('\', '\\').Replace('"', '\"')
  return '"' + $s + '"'
}

function SplitList([string]$s) {
  if (-not $s) { return @() }
  return @($s.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function JList([string]$s) {
  $items = SplitList $s
  if ($items.Count -eq 0) { return '[]' }
  return '[' + (($items | ForEach-Object { JStr $_ }) -join ',') + ']'
}

function JNums([string]$s) {
  $items = @(SplitList $s | ForEach-Object { ($_ -replace '[^0-9]', '') } | Where-Object { $_ -ne '' })
  if ($items.Count -eq 0) { return '[]' }
  return '[' + ($items -join ',') + ']'
}

# 이름|은행|번호,... 를 JSON 객체 배열로 만듭니다.
function JAccounts([string]$s) {
  $recs = SplitList $s
  if ($recs.Count -eq 0) { return '[]' }
  $out = @()
  foreach ($r in $recs) {
    $p = $r.Split('|')
    $name = ''; $bank = ''; $num = ''
    if ($p.Count -ge 1) { $name = $p[0].Trim() }
    if ($p.Count -ge 2) { $bank = $p[1].Trim() }
    if ($p.Count -ge 3) { $num  = $p[2].Trim() }
    $out += '{"name":' + (JStr $name) + ',"bank":' + (JStr $bank) + ',"number":' + (JStr $num) + '}'
  }
  return '[' + ($out -join ',') + ']'
}

# 콤마 목록의 n번째(1부터) 항목입니다. 부모 이름을 하나씩 쓰는 token에 씁니다.
function Nth([string]$s, [int]$n) {
  $items = SplitList $s
  if ($items.Count -ge $n) { return $items[$n - 1] }
  return ''
}

function FirstName([string]$s) {
  if (-not $s) { return '' }
  $p = $s.Trim().Split(' ')
  return $p[0]
}
function Handle([string]$s) { return (FirstName $s).ToLower().Replace('-', '') }
function BranchName([string]$s) {
  if (-not $s) { return '' }
  return (($s.Trim().ToLower() -split '\s+') -join '-')
}

# 숫자인지 검사만 하고 원문을 그대로 냅니다. 좌표 자리수가 잘리면 지도 위치가 어긋납니다.
function NumOr([string]$s, [string]$d) {
  if ($s -match '^-?[0-9]+(\.[0-9]+)?$') { return $s }
  return $d
}

# 사진 파일 이름을 절대 URL로 바꿉니다. og:image 는 절대 URL이어야 카카오톡이 읽습니다.
$origin = (Cf 'SITE_ORIGIN').TrimEnd('/')
function PhotoUrl([string]$name) {
  if ($name -and $origin) { return "$origin/photos/$name" }
  return ''
}


# --- 계좌 난독화 ------------------------------------------------------------
# src/js/private.js 의 deobfuscate 와 1:1로 대응합니다.
# salt 1바이트를 앞에 붙이고 keystream으로 XOR한 뒤 base64로 인코딩합니다.
# 주의: 암호화가 아닙니다. 검색 노출과 자동수집을 막기 위한 것입니다.
function Obfuscate([string]$text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($text)
  $salt = Get-Random -Minimum 1 -Maximum 256
  $out = New-Object 'byte[]' ($bytes.Length + 1)
  $out[0] = [byte]$salt
  $k = $salt
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    $k = ($k * 31 + 17 + $i) -band 0xff
    $out[$i + 1] = [byte]($bytes[$i] -bxor $k)
  }
  return [Convert]::ToBase64String($out)
}


# --- token 표 --------------------------------------------------------------
# 여기 있는 이름이 src/*.html 의 {{TOKEN}} 과 1:1로 대응합니다.
# build.sh 의 add 목록과 같은 값을 만들어야 합니다.
$T = [ordered]@{}

$T['GROOM_NAME']       = Cf 'GROOM_NAME'
$T['GROOM_NAME_SHORT'] = Cf 'GROOM_NAME_SHORT'
$T['GROOM_NAME_EN']    = Cf 'GROOM_NAME_EN'
$T['GROOM_ROLE']       = Cf 'GROOM_ROLE'
$T['GROOM_PARENTS']    = (SplitList (Cf 'GROOM_PARENTS')) -join ' '
$T['GROOM_PARENTS_0']  = Nth (Cf 'GROOM_PARENTS') 1
$T['GROOM_PARENTS_1']  = Nth (Cf 'GROOM_PARENTS') 2
$T['GROOM_RANK_KO']    = Cf 'GROOM_RANK_KO'
$T['GROOM_RANK_EXPR']  = Cf 'GROOM_RANK_EXPR'
$T['GROOM_EN_FIRST']   = FirstName (Cf 'GROOM_NAME_EN')
$T['GROOM_HANDLE']     = Handle (Cf 'GROOM_NAME_EN')
$T['GROOM_BRANCH']     = BranchName (Cf 'GROOM_NAME_EN')

$T['BRIDE_NAME']       = Cf 'BRIDE_NAME'
$T['BRIDE_NAME_SHORT'] = Cf 'BRIDE_NAME_SHORT'
$T['BRIDE_NAME_EN']    = Cf 'BRIDE_NAME_EN'
$T['BRIDE_ROLE']       = Cf 'BRIDE_ROLE'
$T['BRIDE_PARENTS']    = (SplitList (Cf 'BRIDE_PARENTS')) -join ' '
$T['BRIDE_PARENTS_0']  = Nth (Cf 'BRIDE_PARENTS') 1
$T['BRIDE_PARENTS_1']  = Nth (Cf 'BRIDE_PARENTS') 2
$T['BRIDE_RANK_KO']    = Cf 'BRIDE_RANK_KO'
$T['BRIDE_RANK_EXPR']  = Cf 'BRIDE_RANK_EXPR'
$T['BRIDE_EN_FIRST']   = FirstName (Cf 'BRIDE_NAME_EN')
$T['BRIDE_HANDLE']     = Handle (Cf 'BRIDE_NAME_EN')
$T['BRIDE_BRANCH']     = BranchName (Cf 'BRIDE_NAME_EN')

$T['VENUE_NAME']         = Cf 'VENUE_NAME'
$T['VENUE_HALL']         = Cf 'VENUE_HALL'
$T['VENUE_ADDRESS']      = Cf 'VENUE_ADDRESS'
$T['VENUE_FLOOR']        = Cf 'VENUE_FLOOR'
$T['VENUE_ADDRESS_FULL'] = ((@((Cf 'VENUE_ADDRESS'), (Cf 'VENUE_FLOOR')) | Where-Object { $_ -ne '' }) -join ' ')
$T['VENUE_SUBWAY']       = Cf 'VENUE_SUBWAY'
$T['VENUE_SUBWAY_SHORT'] = Cf 'VENUE_SUBWAY_SHORT'

$T['MAP_NAVER_URL'] = Cf 'MAP_NAVER_URL'
$T['MAP_KAKAO_URL'] = Cf 'MAP_KAKAO_URL'

$T['WEDDING_DATE_KO']       = $dateKo
$T['WEDDING_TIME_KO']       = $timeKo
$T['WEDDING_DATETIME_KO']   = "$dateKo $timeKo"
$T['WEDDING_DATE_ISO']      = "$($w.Year)-$(P2 $w.Month)-$(P2 $w.Day)"
$T['WEDDING_DATE_DOT']      = "$($w.Year).$(P2 $w.Month).$(P2 $w.Day)"
$T['WEDDING_YEAR']          = "$($w.Year)"
$T['WEDDING_YEAR_MONTH_KO'] = "$($w.Year)년 $($w.Month)월"
$T['WEDDING_MONTH_EN']      = $MONTH_EN[$w.Month - 1]
$T['WEDDING_DAY_EN']        = $DAY_EN[$dow]
$T['WEDDING_DAY_KO_SHORT']  = $DAY_KO[$dow]
$T['WEDDING_TIME_EN']       = "$ampm ${h12}:$(P2 $w.Minute)"
$T['WEDDING_CLOCK_KST']     = "$($DAY_EN[$dow].Substring(0,1))$($DAY_EN[$dow].Substring(1).ToLower()) $($w.Year)-$(P2 $w.Month)-$(P2 $w.Day) $(P2 $h24):$(P2 $w.Minute):00 KST"
$T['FIRST_MET_ISO']         = "$($f.Year)-$(P2 $f.Month)-$(P2 $f.Day)"

$T['INFO_SUBWAY']  = Br (Cf 'INFO_SUBWAY')
$T['INFO_BUS']     = Br (Cf 'INFO_BUS')
$T['INFO_PARKING'] = Br (Cf 'INFO_PARKING')
$T['INFO_MEAL']    = Br (Cf 'INFO_MEAL')

# 공유 card image. 지정한 것이 없으면 각 version의 표지를 씁니다.
$ogMain = PhotoUrl (Cf 'PHOTO_OG_MAIN'     (Cf 'PHOTO_MAIN'))
$ogDev  = PhotoUrl (Cf 'PHOTO_OG_DEV'      (Cf 'PHOTO_MAIN_DEV' (Cf 'PHOTO_MAIN')))
$ogTerm = PhotoUrl (Cf 'PHOTO_OG_TERMINAL' (Cf 'PHOTO_MAIN_DEV' (Cf 'PHOTO_MAIN')))
$T['OG_IMAGE_MAIN']     = $ogMain
$T['OG_IMAGE_DEV']      = $ogDev
$T['OG_IMAGE_TERMINAL'] = $ogTerm

$T['HOST'] = $origin -replace '^https?://', ''


# --- dist 준비 -------------------------------------------------------------
# 이 script가 만든 directory임을 확인한 뒤에만 비웁니다.
if (Test-Path -LiteralPath $Out) {
  if (-not (Test-Path -LiteralPath ([IO.Path]::Combine($Out, $stamp)))) {
    Fail "$Out 은 이 script가 만든 곳이 아닙니다($stamp 표식이 없습니다).`n  실수로 지우지 않도록 멈췄습니다. 다른 경로를 -Out 으로 주거나, 그 directory를 직접 비워 주시기 바랍니다."
  }
  Get-ChildItem -LiteralPath $Out -Force | Remove-Item -Recurse -Force
} else {
  New-Item -ItemType Directory -Path $Out -Force | Out-Null
}
foreach ($d in @('js', 'css', 'assets', 'photos')) {
  New-Item -ItemType Directory -Path ([IO.Path]::Combine($Out, $d)) -Force | Out-Null
}
Write-Text ([IO.Path]::Combine($Out, $stamp)) "build.ps1 산출물입니다. 이 파일이 있어야 다음 build가 이 directory를 비웁니다.`n"

foreach ($d in @('css', 'js', 'assets')) {
  Copy-Item -Path ([IO.Path]::Combine($src, $d) + '\*') -Destination ([IO.Path]::Combine($Out, $d)) -Recurse -Force
}
# 사진은 있으면 함께 옮깁니다. README 만 있는 상태도 정상입니다.
$photoSrc = [IO.Path]::Combine($src, 'photos')
if (Test-Path -LiteralPath $photoSrc) {
  Get-ChildItem -LiteralPath $photoSrc -File | Where-Object { $_.Name -notlike 'README*' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination ([IO.Path]::Combine($Out, 'photos')) -Force }
}


# --- 청첩장 JS가 읽는 주입 값 (dist/js/data.js) -----------------------------
# 청첩장 세 version의 js/config.js 가 window.__WEDDING__ 를 읽습니다.
# 이 모양을 바꾸면 세 version이 함께 깨지므로 key 이름을 유지합니다.
function PersonJson([string]$px) {
  $zoom = NumOr (Cf "${px}_PHOTO_ZOOM" '1') '1'
  if ([double]$zoom -lt 1 -or [double]$zoom -gt 3) { $zoom = '1' }
  return '{"name":' + (JStr (Cf "${px}_NAME")) +
    ',"short":'      + (JStr (Cf "${px}_NAME_SHORT")) +
    ',"en":'         + (JStr (Cf "${px}_NAME_EN")) +
    ',"initial":'    + (JStr (Cf "${px}_INITIAL")) +
    ',"role":'       + (JStr (Cf "${px}_ROLE")) +
    ',"parents":'    + (JList (Cf "${px}_PARENTS")) +
    ',"rankKo":'     + (JStr (Cf "${px}_RANK_KO")) +
    ',"rank":'       + (JStr (Cf "${px}_RANK_EXPR")) +
    ',"mbti":'       + (JStr (Cf "${px}_MBTI")) +
    ',"hobby":'      + (JStr (Cf "${px}_HOBBY")) +
    ',"note":'       + (JStr (Cf "${px}_NOTE")) +
    ',"photo":'      + (JStr (Cf "${px}_PHOTO")) +
    ',"photoFocus":' + (JStr (Cf "${px}_PHOTO_FOCUS" '50% 30%')) +
    ',"photoZoom":'  + $zoom + '}'
}

$weddingJson = '{"at":' + (JStr (Cf 'WEDDING_AT')) +
  ',"firstMetAt":' + (JStr (Cf 'FIRST_MET_AT' (Cf 'WEDDING_AT'))) +
  ',"groom":' + (PersonJson 'GROOM') +
  ',"bride":' + (PersonJson 'BRIDE') +
  ',"venue":{"name":' + (JStr (Cf 'VENUE_NAME')) +
    ',"hall":' + (JStr (Cf 'VENUE_HALL')) +
    ',"address":' + (JStr (Cf 'VENUE_ADDRESS')) +
    ',"floor":' + (JStr (Cf 'VENUE_FLOOR')) +
    ',"addressCopy":' + (JStr (Cf 'VENUE_ADDRESS_COPY')) +
    ',"subway":' + (JStr (Cf 'VENUE_SUBWAY')) +
    ',"subwayShort":' + (JStr (Cf 'VENUE_SUBWAY_SHORT')) +
    ',"lat":' + (NumOr (Cf 'VENUE_LAT') '0') +
    ',"lng":' + (NumOr (Cf 'VENUE_LNG') '0') +
    ',"zoom":' + (NumOr (Cf 'VENUE_MAP_ZOOM') '17') + '}' +
  ',"map":{"naver":' + (JStr (Cf 'MAP_NAVER_URL')) +
    ',"kakao":' + (JStr (Cf 'MAP_KAKAO_URL')) + '}' +
  ',"photos":{"main":' + (JStr (Cf 'PHOTO_MAIN')) +
    ',"mainDev":' + (JStr (Cf 'PHOTO_MAIN_DEV')) +
    ',"bless":' + (JStr (Cf 'PHOTO_BLESS')) +
    ',"gallery":' + (JList (Cf 'PHOTO_GALLERY')) +
    ',"galleryPageOrder":{"main":' + (JNums (Cf 'GALLERY_ORDER_MAIN')) +
      ',"dev":' + (JNums (Cf 'GALLERY_ORDER_DEV')) + '}}}'

$giftJson = '{"accounts":{"groom":' + (JAccounts (Cf 'GROOM_ACCOUNTS')) +
  ',"bride":' + (JAccounts (Cf 'BRIDE_ACCOUNTS')) + '}}'
$giftBlob = Obfuscate $giftJson

$data = New-Object Text.StringBuilder
[void]$data.AppendLine('/* build.ps1 가 invitation.conf 에서 생성했습니다. 직접 고치지 않습니다. */')
[void]$data.AppendLine("window.__INV__='.';")
[void]$data.AppendLine("window.__PHOTOS__='photos/';")
if ($origin) { [void]$data.AppendLine("window.__ORIGIN__=$(JStr $origin);") }
# 축하 한마디 API. 주소가 있으면 그쪽으로 보냅니다. 없으면 이 build에 backend가 없다고
# 알려서 없는 주소로 5초마다 요청하지 않게 합니다. 그때는 localStorage demo mode입니다.
$api = (Cf 'GUESTBOOK_API_BASE').TrimEnd('/')
if ($api) { [void]$data.AppendLine("window.__API__=$(JStr $api);") }
else      { [void]$data.AppendLine('window.__NO_API__=true;') }
[void]$data.AppendLine("window.__WEDDING__=$weddingJson;")
[void]$data.AppendLine("window.__NAVER_MAP_KEY__=$(JStr (Cf 'NAVER_MAP_KEY_ID'));")
[void]$data.AppendLine("window.__KAKAO_KEY__=$(JStr (Cf 'KAKAO_JS_KEY'));")
[void]$data.AppendLine("window.__GA_ID__=$(JStr (Cf 'GA_MEASUREMENT_ID'));")
[void]$data.AppendLine("window.__GIFT__=$(JStr $giftBlob);")
Write-Text ([IO.Path]::Combine($Out, 'js', 'data.js')) $data.ToString()


# --- 자산 version (browser cache 갱신) --------------------------------------
# css 와 js 내용에서 뽑습니다. 내용이 바뀌면 값이 바뀝니다.
$acc = New-Object Text.StringBuilder
foreach ($p in (Get-ChildItem -LiteralPath ([IO.Path]::Combine($Out, 'css')) -File | Sort-Object Name)) {
  [void]$acc.Append((Read-Text $p.FullName))
}
foreach ($p in (Get-ChildItem -LiteralPath ([IO.Path]::Combine($Out, 'js')) -File | Sort-Object Name)) {
  [void]$acc.Append((Read-Text $p.FullName))
}
$sha = [Security.Cryptography.SHA1]::Create()
$hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($acc.ToString()))
$assetVer = -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })


# --- HTML 치환 --------------------------------------------------------------
$pages = 0
foreach ($file in (Get-ChildItem -LiteralPath $src -Filter '*.html' -File)) {
  $html = Read-Text $file.FullName

  # 주입 script를 config.js 앞에 넣습니다.
  $html = $html.Replace('<script src="js/config.js"', '<script src="js/data.js"></script><script src="js/config.js"')
  # 계좌는 data.js 로 옮겼으므로 예약 주석은 지웁니다.
  $html = $html.Replace('<!--#PRIVATE#-->', '')

  # css 와 js 참조에 ?v= 를 붙입니다.
  $html = $html -replace '(href|src)="((?:css|js)/[^"?]*\.(?:css|js))"', ('$1="$2?v=' + $assetVer + '"')

  # 이름과 예식 정보 token
  foreach ($k in $T.Keys) { $html = $html.Replace('{{' + $k + '}}', [string]$T[$k]) }
  $pageUrl = ''
  if ($origin) { $pageUrl = "$origin/$($file.Name)" }
  $html = $html.Replace('{{PAGE_URL}}', $pageUrl)

  # 사진이 없어 og:image 가 빈 값이면 그 meta를 지웁니다. 빈 URL을 남기면 카카오가
  # 미리보기를 못 읽고 깨진 card를 보여 줍니다.
  if (-not ($ogMain + $ogDev + $ogTerm)) {
    $html = ($html -split "`n" | Where-Object { $_ -notmatch '<meta property="og:image' }) -join "`n"
  }

  Write-Text ([IO.Path]::Combine($Out, $file.Name)) $html
  $pages++
}

# 처음 열었을 때 보여줄 version을 index.html 로 복사합니다.
$def = Cf 'DEFAULT_VERSION' 'main'
if (@('main', 'developer', 'terminal') -notcontains $def) {
  Write-Host "  경고: DEFAULT_VERSION='$def' 은 main, developer, terminal 중 하나여야 합니다. main으로 둡니다."
  $def = 'main'
}
Copy-Item -LiteralPath ([IO.Path]::Combine($Out, "$def.html")) -Destination ([IO.Path]::Combine($Out, 'index.html')) -Force


# --- 결과 확인 -------------------------------------------------------------
$left = @()
foreach ($p in (Get-ChildItem -LiteralPath $Out -Filter '*.html' -File)) {
  $m = [regex]::Matches((Read-Text $p.FullName), '\{\{[A-Z0-9_]+\}\}')
  foreach ($x in $m) { $left += $x.Value }
}
$left = @($left | Sort-Object -Unique)
if ($left.Count -gt 0) {
  Write-Host '  경고: 치환되지 않은 token이 남았습니다.'
  foreach ($x in $left) { Write-Host "    $x" }
}

# 평문 계좌번호가 결과물에 남지 않았는지 확인합니다. 사람이 확인하는 대신 script가 막습니다.
$leak = $false
foreach ($rec in (SplitList ((Cf 'GROOM_ACCOUNTS') + ',' + (Cf 'BRIDE_ACCOUNTS')))) {
  $p = $rec.Split('|')
  if ($p.Count -lt 3) { continue }
  $num = $p[2].Trim()
  if ($num.Length -lt 6) { continue }
  $hit = Get-ChildItem -LiteralPath $Out -Recurse -File |
    Where-Object { $_.Extension -notmatch '^\.(jpg|jpeg|png|webp|gif)$' } |
    Select-String -SimpleMatch -Pattern $num -List -ErrorAction SilentlyContinue
  if ($hit) {
    Write-Host "  위험: 계좌번호 '$num' 이 dist 에 평문으로 남아 있습니다."
    $leak = $true
  }
}
if ($leak) { Fail '난독화가 동작하지 않았습니다. 결과물을 배포하지 않는 편이 좋습니다.' }

Write-Host ''
Write-Host "완성했습니다.  pages=$pages+index  asset_ver=$assetVer"
Write-Host "  $(Cf 'GROOM_NAME' '?') <3 $(Cf 'BRIDE_NAME' '?')   $dateKo $timeKo"
Write-Host "  $(Cf 'VENUE_NAME' '?') $(Cf 'VENUE_HALL')"
Write-Host ''
Write-Host '미리 보기:  .\startup.ps1       그다음 http://localhost:8080'
Write-Host '올리기:     dist 안의 내용을 정적 호스팅에 그대로 올립니다.'
