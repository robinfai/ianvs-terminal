#!/usr/bin/env python3
"""Dependency-free structural, link, theme and content-scope checks."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json

ROOT=Path(__file__).resolve().parents[1]
class Page(HTMLParser):
    def __init__(self,path):
        super().__init__(); self.path=path; self.ids=set(); self.refs=[]; self.errors=[]; self.main=0; self.h1=0; self.themes=0; self.options=[]; self.buttons=[]; self.tables=0; self.captions=0; self.in_theme=False
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:
            if a['id'] in self.ids:self.errors.append('duplicate id '+a['id'])
            self.ids.add(a['id'])
        self.main+=tag=='main'; self.h1+=tag=='h1'; self.tables+=tag=='table'; self.captions+=tag=='caption'
        if tag=='html' and not a.get('lang'):self.errors.append('missing lang')
        if tag=='img' and ('alt' not in a or 'width' not in a or 'height' not in a):self.errors.append('image missing alt/dimensions')
        if tag=='button' and a.get('type')!='button':self.errors.append('button lacks explicit type')
        if tag=='select' and 'data-theme-select' in a:self.themes+=1; self.in_theme=True
        if tag=='option' and self.in_theme:self.options.append(a.get('value'))
        for k in ('href','src'):
            if a.get(k):self.refs.append(a[k])
    def handle_endtag(self,tag):
        if tag=='select':self.in_theme=False
pages={}
for path in ROOT.rglob('*.html'):
    p=Page(path); p.feed(path.read_text()); pages[path.resolve()]=p
errors=[]
for path,p in pages.items():
    label=str(path.relative_to(ROOT)); raw=path.read_text()
    if p.main!=1 or p.h1!=1:p.errors.append(f'main={p.main}, h1={p.h1}')
    if p.themes!=1 or p.options!=['system','light','dark']:p.errors.append('missing consistent theme choices')
    if p.tables!=p.captions:p.errors.append('table lacks caption')
    for required in ['assets/styles.css','assets/app.js','assets/theme.js','data-menu-toggle','aria-controls="main-nav"','class="skip-link"','name="viewport"','name="color-scheme"']:
        if required not in raw:p.errors.append('missing '+required)
    for wrong in ['立即下载','全平台已经可用','完全兼容','Toolbelt']:
        if wrong in raw:p.errors.append('unverified product claim '+wrong)
    for ref in p.refs:
        u=urlsplit(ref)
        if u.scheme or u.netloc:continue
        dest=(ROOT/unquote(u.path.lstrip('/')) if u.path.startswith('/') else path.parent/unquote(u.path)).resolve() if u.path else path
        if dest.is_dir():dest=dest/'index.html'
        if not dest.is_relative_to(ROOT):p.errors.append('reference outside site '+ref)
        elif not dest.exists():p.errors.append('missing '+ref)
        elif u.fragment and dest in pages and unquote(u.fragment) not in pages[dest].ids:p.errors.append('missing fragment '+ref)
    errors += [label+': '+e for e in p.errors]
css=(ROOT/'assets/styles.css').read_text()
for requirement in ['prefers-reduced-motion','prefers-color-scheme:dark','data-theme=dark','data-theme=light','focus-visible','forced-colors:active','--accent-ink']:
    if requirement not in css:errors.append('CSS missing '+requirement)
if len(pages)!=6:errors.append('Expected six routes')
print(json.dumps({'pages':len(pages),'references':sum(len(p.refs) for p in pages.values()),'errors':errors},ensure_ascii=False,indent=2))
raise SystemExit(bool(errors))
