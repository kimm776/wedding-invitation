# 사진 넣는 곳

`demo-*.jpg` 14장이 함께 들어 있습니다. 사진이 없어도 화면이 완성돼 보이게 하려고
그려 넣은 자리 표시입니다. 사진이 아니라 단순한 도형 구성이니 두 분의 사진으로 바꿔 주시기 바랍니다.

이 directory에 사진 파일을 넣고 `invitation.conf` 의 `PHOTO_*` 값에 파일 이름을 적습니다.

```ini
PHOTO_MAIN="cover.jpg"
PHOTO_MAIN_DEV="cover-dev.jpg"
PHOTO_BLESS="bless.jpg"
PHOTO_GALLERY="g01.jpg,g02.jpg,g03.jpg,g04.jpg,g05.jpg,g06.jpg,g07.jpg,g08.jpg,g09.jpg"
```

`build.sh` 가 이 directory의 파일을 `dist/photos/` 로 옮깁니다.

## 알아 두실 것

- **gallery는 3x3 pagination이라 9장이 한 page입니다.** 9의 배수로 넣으면 마지막 page가 비지 않습니다.
  terminal version에는 gallery가 없습니다.
- **표지 사진은 세로 4:5 를 기준으로 crop됩니다.** 얼굴 위치가 어긋나면 `invitation.conf` 의
  `GROOM_PHOTO_FOCUS` 와 `BRIDE_PHOTO_FOCUS` 로 초점을 옮깁니다. CSS `object-position` 값입니다.
- **비워 두어도 화면은 깨지지 않습니다.** 사진 자리에 이니셜 box와 자리 표시가 나옵니다.
- **긴 변 1600px 정도로 줄여서 넣는 편이 좋습니다.** 원본 그대로 올리면 모바일에서 느립니다.

```bash
# ImageMagick 이 있으면 한 번에 줄일 수 있습니다.
mogrify -resize 1600x1600\> -quality 82 *.jpg
```

- **본인의 사진은 추적되지 않습니다.** `.gitignore` 가 이 directory의 image를 빼 두었고
  `demo-*.jpg` 만 예외로 두었습니다. 그래서 fork해도 남의 사진이 따라오지 않습니다.
  본인의 사진이 실수로 올라가지도 않습니다. demo 사진은 지워도 됩니다.
