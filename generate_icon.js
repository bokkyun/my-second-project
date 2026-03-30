const { Jimp } = require('jimp');
const path = require('path');

async function generateIcon() {
  const size = 1024;

  // 파란 배경
  const img = new Jimp({ width: size, height: size, color: 0x1565C0FF });

  function setPixel(x, y, color) {
    if (x >= 0 && x < size && y >= 0 && y < size) {
      img.setPixelColor(color, x, y);
    }
  }

  function fillRect(x1, y1, x2, y2, color) {
    for (let x = Math.floor(x1); x <= Math.ceil(x2); x++) {
      for (let y = Math.floor(y1); y <= Math.ceil(y2); y++) {
        setPixel(x, y, color);
      }
    }
  }

  function fillCircle(cx, cy, r, color) {
    for (let x = Math.floor(cx - r); x <= Math.ceil(cx + r); x++) {
      for (let y = Math.floor(cy - r); y <= Math.ceil(cy + r); y++) {
        if (Math.sqrt((x - cx) ** 2 + (y - cy) ** 2) <= r) {
          setPixel(x, y, color);
        }
      }
    }
  }

  function fillRoundRect(x1, y1, x2, y2, r, color) {
    // 중앙 가로 막대
    fillRect(x1 + r, y1, x2 - r, y2, color);
    // 중앙 세로 막대
    fillRect(x1, y1 + r, x2, y2 - r, color);
    // 4 모서리 원
    fillCircle(x1 + r, y1 + r, r, color);
    fillCircle(x2 - r, y1 + r, r, color);
    fillCircle(x1 + r, y2 - r, r, color);
    fillCircle(x2 - r, y2 - r, r, color);
  }

  // 배경 둥근 사각형 (아이콘 모양)
  fillRoundRect(0, 0, size - 1, size - 1, size * 0.22, 0x1565C0FF);

  // 배경 바깥 투명 처리
  const bgR = size * 0.22;
  for (let x = 0; x < size; x++) {
    for (let y = 0; y < size; y++) {
      const inTL = x < bgR && y < bgR && Math.sqrt((x - bgR) ** 2 + (y - bgR) ** 2) > bgR;
      const inTR = x > size - bgR && y < bgR && Math.sqrt((x - (size - bgR)) ** 2 + (y - bgR) ** 2) > bgR;
      const inBL = x < bgR && y > size - bgR && Math.sqrt((x - bgR) ** 2 + (y - (size - bgR)) ** 2) > bgR;
      const inBR = x > size - bgR && y > size - bgR && Math.sqrt((x - (size - bgR)) ** 2 + (y - (size - bgR)) ** 2) > bgR;
      if (inTL || inTR || inBL || inBR) {
        setPixel(x, y, 0x00000000);
      }
    }
  }

  // 흰색 캘린더 몸체
  const cL = size * 0.18, cT = size * 0.24, cR = size * 0.82, cB = size * 0.84;
  const cRad = size * 0.055;
  fillRoundRect(cL, cT, cR, cB, cRad, 0xFFFFFFFF);

  // 파란 헤더 영역
  const hB = cT + size * 0.16;
  fillRect(cL + cRad, cT, cR - cRad, hB, 0x1976D2FF);
  fillRect(cL, cT + cRad, cR, hB, 0x1976D2FF);
  fillCircle(cL + cRad, cT + cRad, cRad, 0x1976D2FF);
  fillCircle(cR - cRad, cT + cRad, cRad, 0x1976D2FF);

  // 캘린더 고리 2개 (흰색)
  const ringR = size * 0.038;
  const ringY = cT - size * 0.01;
  fillCircle(size * 0.33, ringY, ringR, 0xFFFFFFFF);
  fillCircle(size * 0.67, ringY, ringR, 0xFFFFFFFF);

  // 날짜 점들 (4열 × 3행)
  const dotR = size * 0.038;
  const gX = size * 0.265;
  const gY = cT + size * 0.245;
  const gGX = size * 0.155;
  const gGY = size * 0.135;

  for (let col = 0; col < 4; col++) {
    for (let row = 0; row < 3; row++) {
      if (col === 0 && row === 0) continue;
      const cx = gX + col * gGX;
      const cy = gY + row * gGY;
      if (col === 2 && row === 0) {
        fillCircle(cx, cy, dotR * 1.15, 0xE53935FF); // 빨간 특별 날
      } else {
        fillCircle(cx, cy, dotR, 0x1565C0FF);
      }
    }
  }

  await img.write(path.join(__dirname, 'icon_1024.png'));
  console.log('icon_1024.png 생성 완료!');
}

generateIcon().catch(console.error);
