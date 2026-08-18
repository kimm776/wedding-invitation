#!/usr/bin/env bash
# dist/ 를 local에서 미리 봅니다. 확인용이고 배포용이 아닙니다.
#
#   ./startup.sh          http://localhost:8080
#   ./startup.sh 3000     port를 바꿉니다
#
# 멈출 때는 Ctrl+C 입니다. dist/ 가 없으면 build.sh 를 먼저 돌립니다.
#
# 파일을 두 번 눌러 file:// 로 열어도 대부분 보입니다. 다만 카카오 공유 SDK와 지도는
# http 로 열어야 동작합니다. 그래서 확인은 이 script로 하는 편이 좋습니다.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-8080}"
DIR="$HERE/dist"

if [ ! -d "$DIR" ]; then
  printf 'dist/ 가 없어 먼저 build합니다.\n\n'
  "$HERE/build.sh"
  printf '\n'
fi

printf '  http://localhost:%s  에서 확인하실 수 있습니다. 멈추려면 Ctrl+C 입니다.\n\n' "$PORT"

# python3 를 먼저 쓰고 없으면 node 로 fallback합니다.
if command -v python3 >/dev/null 2>&1; then
  exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR"
elif command -v node >/dev/null 2>&1; then
  exec node -e '
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
  ' -- "$PORT" "$DIR"
else
  printf 'startup.sh: python3 도 node 도 없습니다. dist/ 를 다른 정적 server로 열어 주시기 바랍니다.\n' >&2
  exit 1
fi
