# dist 를 local에서 미리 봅니다. 확인용이고 배포용이 아닙니다.
#
#   .\startup.ps1          http://localhost:8080
#   .\startup.ps1 3000     port를 바꿉니다
#
# 멈출 때는 Ctrl+C 입니다. dist 가 없으면 build.ps1 을 먼저 돌립니다.
#
# PowerShell 실행 정책 때문에 막히면 아래 명령으로 해당 session에서만 허용해 주시기 바랍니다.
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

[CmdletBinding()]
param([int]$Port = 8080)

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = [IO.Path]::Combine($here, 'dist')

if (-not (Test-Path -LiteralPath $dir)) {
  Write-Host 'dist 가 없어 먼저 build합니다.'
  Write-Host ''
  & ([IO.Path]::Combine($here, 'build.ps1'))
  Write-Host ''
}

Write-Host "  http://localhost:$Port  에서 확인하실 수 있습니다. 멈추려면 Ctrl+C 입니다."
Write-Host ''

# python 을 먼저 쓰고 없으면 node 로 fallback합니다.
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue

if ($py) {
  & $py.Source -m http.server $Port --bind 127.0.0.1 --directory $dir
} elseif ($nodeCmd) {
  $js = @'
const http=require("http"),fs=require("fs"),path=require("path");
const MIME={".html":"text/html; charset=utf-8",".css":"text/css; charset=utf-8",
  ".js":"text/javascript; charset=utf-8",".svg":"image/svg+xml",".png":"image/png",
  ".jpg":"image/jpeg",".jpeg":"image/jpeg",".webp":"image/webp",".gif":"image/gif"};
const root=path.resolve(process.argv[2]), port=Number(process.argv[1]);
http.createServer((req,res)=>{
  let p=decodeURIComponent(new URL(req.url,"http://x").pathname);
  if(p==="/")p="/index.html";
  const f=path.resolve(path.join(root,p));
  if(f!==root && !f.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
  fs.readFile(f,(e,d)=>{
    if(e){res.writeHead(404);return res.end("404");}
    res.writeHead(200,{"Content-Type":MIME[path.extname(f).toLowerCase()]||"application/octet-stream"});
    res.end(d);
  });
}).listen(port,"127.0.0.1");
'@
  & $nodeCmd.Source -e $js -- $Port $dir
} else {
  Write-Error 'startup.ps1: python 도 node 도 없습니다. dist 를 다른 정적 server로 열어 주시기 바랍니다.'
  exit 1
}
