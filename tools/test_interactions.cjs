// Dependency-free tests of production JS event handlers against a minimal DOM.
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const rootDir = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(rootDir,'assets/app.js'),'utf8');
const theme = fs.readFileSync(path.join(rootDir,'assets/theme.js'),'utf8');
class Element {
  constructor(dataset={}, text='') { this.dataset=dataset; this.textContent=text; this.value=''; this.attrs={}; this.events={}; this.children=[]; this.hidden=false; this.classes=new Set(); this.classList={add:(v)=>this.classes.add(v),remove:(v)=>this.classes.delete(v),toggle:(v,on)=>on?this.classes.add(v):this.classes.delete(v)}; }
  addEventListener(k,f){ (this.events[k] ||= []).push(f); }
  async emit(k,event={}){ for(const f of this.events[k]||[]) await f({target:this,...event}); }
  setAttribute(k,v){this.attrs[k]=v;}
  getAttribute(k){return this.attrs[k]??null;}
  append(v){this.children.push(v);}
  replaceChildren(){this.children=[];}
  focus(){this.focused=true;}
  closest(selector){return selector==='.site-header'?this:null;}
}
function harness(options={}){
  const els={theme:new Element(),menuToggle:new Element(),menu:new Element(),status:new Element(),output:new Element(),demoStatus:new Element(),search:new Element(),count:new Element(),empty:new Element(),clear:new Element(),code:new Element({},'make run')};
  els.menuToggle.setAttribute('aria-expanded','false');
  const demos=['local','ssh','replay'].map(v=>new Element({demo:v}));
  const filters=['all','xterm','kitty','iterm','other'].map(v=>new Element({filter:v}));
  const groups=['xterm','kitty','iterm','other'].map(v=>new Element({protocolGroup:v}));
  const html=fs.readFileSync(path.join(rootDir,'osc/index.html'),'utf8');
  const rows=[...html.matchAll(/<tr data-protocol-row data-family="([^"]+)">([\s\S]*?)<\/tr>/g)].map(m=>new Element({family:m[1]},m[2].replace(/<[^>]+>/g,'')));
  const copy=new Element({copy:'code'},'复制命令');
  const document=new Element(); document.documentElement=new Element();
  const singles={'[data-theme-select]':els.theme,'[data-menu-toggle]':els.menuToggle,'[data-status]':els.status,'[data-demo-output]':els.output,'[data-demo-status]':els.demoStatus,'[data-protocol-search]':els.search,'[data-result-count]':els.count,'[data-empty-state]':els.empty,'[data-clear-filters]':els.clear};
  const multi={'[data-demo]':demos,'[data-copy]':[copy],'[data-filter]':filters,'[data-protocol-row]':rows,'[data-protocol-group]':groups};
  document.querySelector=s=>singles[s]||null;
  document.querySelectorAll=s=>multi[s]||[];
  document.getElementById=id=>id==='main-nav'?els.menu:id==='code'?els.code:null;
  document.createElement=()=>new Element(); document.createTextNode=t=>({textContent:t});
  document.createRange=()=>({selectNodeContents:()=>{els.code.selected=true;}});
  const window=new Element(); window.location={href:options.url||'http://127.0.0.1:4312/osc/index.html'};
  window.matchMedia=()=>({matches:false,addEventListener:()=>{}}); window.setTimeout=()=>0;
  window.history={replaceState:(_,__,url)=>{window.location.href=String(url);}};
  window.getSelection=()=>({removeAllRanges:()=>{},addRange:()=>{}});
  const saved={value:options.saved||null};
  const localStorage={getItem:()=>{if(options.storageThrows)throw Error();return saved.value;},setItem:(_,value)=>{if(options.storageThrows)throw Error();saved.value=value;}};
  const clipboard={value:null,writeText:async(text)=>{if(options.clipboardThrows)throw Error();clipboard.value=text;}};
  const context=vm.createContext({document,window,localStorage,navigator:{clipboard},URL,console});
  vm.runInContext(theme,context); vm.runInContext(app,context);
  return {els,demos,filters,groups,rows,copy,document,window,saved,clipboard};
}
(async()=>{
  const h=harness();
  assert.equal(h.document.documentElement.dataset.theme,'system');
  h.els.theme.value='dark'; await h.els.theme.emit('change');
  assert.equal(h.saved.value,'dark'); assert.equal(h.document.documentElement.dataset.theme,'dark');
  assert.equal(harness({saved:'dark'}).els.theme.value,'dark');
  assert.equal(harness({saved:'garbage'}).els.theme.value,'system');
  const denied=harness({storageThrows:true}); denied.els.theme.value='light'; await denied.els.theme.emit('change'); assert.equal(denied.document.documentElement.dataset.theme,'light');
  await h.window.emit('storage',{key:'ianvs-astra-theme',newValue:'light'}); assert.equal(h.els.theme.value,'light');
  await h.els.menuToggle.emit('click'); assert.equal(h.els.menuToggle.getAttribute('aria-expanded'),'true'); assert.ok(h.els.menu.classes.has('is-open'));
  await h.document.emit('keydown',{key:'Escape'}); assert.equal(h.els.menuToggle.getAttribute('aria-expanded'),'false'); assert.ok(h.els.menuToggle.focused);
  await h.demos[2].emit('click'); assert.equal(h.demos[2].getAttribute('aria-pressed'),'true'); assert.equal(h.demos[0].getAttribute('aria-pressed'),'false'); assert.match(h.els.demoStatus.textContent,/录制回放/); assert.ok(h.els.output.children.length>0);
  await h.copy.emit('click'); assert.equal(h.clipboard.value,'make run'); assert.match(h.copy.textContent,/已复制/);
  const noClipboard=harness({clipboardThrows:true}); await noClipboard.copy.emit('click'); assert.ok(noClipboard.els.code.selected); assert.equal(noClipboard.copy.textContent,'请手动复制');
  assert.equal(h.rows.length,29); assert.equal(h.rows.filter(r=>!r.hidden).length,29);
  await h.filters[2].emit('click'); assert.equal(h.rows.filter(r=>!r.hidden).length,6); assert.ok(h.groups.find(g=>g.dataset.protocolGroup==='xterm').hidden); assert.match(h.window.location.href,/family=kitty/);
  h.els.search.value='does not exist'; await h.els.search.emit('input'); assert.equal(h.rows.filter(r=>!r.hidden).length,0); assert.equal(h.els.empty.hidden,false);
  await h.els.clear.emit('click'); assert.equal(h.rows.filter(r=>!r.hidden).length,29); assert.equal(h.els.search.value,''); assert.ok(h.els.search.focused); assert.equal(new URL(h.window.location.href).search,'');
  h.els.search.value='OSC 52'; await h.els.search.emit('input'); assert.equal(h.rows.filter(r=>!r.hidden).length,1);
  const restored=harness({url:'http://127.0.0.1:4312/osc/index.html?family=kitty&q=OSC%2022'}); assert.equal(restored.rows.filter(r=>!r.hidden).length,1); assert.equal(restored.els.search.value,'OSC 22');
  console.log('PASS: theme default/persistence/storage denial/cross-tab; menu/Escape; demo; copy/fallback; 29 protocol records/filter/search/empty/reset/URL restore.');
})().catch(error=>{console.error(error);process.exit(1);});
