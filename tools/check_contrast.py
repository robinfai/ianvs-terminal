#!/usr/bin/env python3
"""Check text/background pairs from the actual CSS theme tokens."""
from pathlib import Path
import re
css=(Path(__file__).resolve().parents[1]/'assets/styles.css').read_text()
blocks=[css.split(':root{',1)[1].split('}',1)[0],css.split(':root[data-theme=dark]{',1)[1].split('}',1)[0]]
def luminance(h):
    rgb=[int(h[i:i+2],16)/255 for i in (1,3,5)]
    rgb=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in rgb]
    return .2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2]
def contrast(a,b):
    x,y=sorted([luminance(a),luminance(b)])
    return (y+.05)/(x+.05)
for name,block in zip(['light','dark'],blocks):
    colors=dict(re.findall(r'--([a-z0-9-]+):(#[a-fA-F0-9]{6})(?=;|})',block))
    pairs=[(a,b) for a in ['text','muted','subtle'] for b in ['bg','surface','surface-2']]+[('accent-ink','accent'),('accent-text','bg'),('accent-text','surface'),('accent-text','surface-2'),('terminal-text','terminal'),('terminal-muted','terminal'),('terminal-muted','terminal-2')]
    results=[(f'{a}/{b}',contrast(colors[a],colors[b])) for a,b in pairs]
    bad=[(pair,round(value,2)) for pair,value in results if value<4.5]
    print(name,': minimum text contrast',round(min(v for _,v in results),2),'failures',bad)
    if bad:raise SystemExit(1)
