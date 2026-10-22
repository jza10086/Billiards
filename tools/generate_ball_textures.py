#!/usr/bin/env python3
"""Regenerate original ball textures. Requires Python3 + Pillow.
Run: python tools/generate_ball_textures.py --font /path/to/DejaVuSans-Bold.ttf
DejaVu Sans is used only to rasterize numerals; no font binary is copied.
"""
import argparse
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--font', default='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
args = parser.parse_args()
out = Path(__file__).resolve().parents[1] / 'assets' / 'balls'
out.mkdir(parents=True, exist_ok=True)
colors=['#efeee6','#e7ba25','#2158a0','#b83b31','#693d88','#e67624','#286a4d','#7c292b','#161b20']
font=ImageFont.truetype(args.font,82)
for n in range(16):
 c=colors[n if n<9 else n-8]
 im=Image.new('RGB',(1024,512),c if n<9 else '#f2eddb');d=ImageDraw.Draw(im)
 if n>8:d.rectangle((0,174,1023,338),fill=c)
 if n:
  for x in (256,768):
   d.ellipse((x-66,190,x+66,322),fill='#f5f0dc')
   s=str(n);b=d.textbbox((0,0),s,font=font);d.text((x-(b[2]-b[0])/2,256-(b[3]-b[1])/2-b[1]),s,font=font,fill='#11171c')
 im.save(out/f'ball_{n:02d}.png',optimize=True)
