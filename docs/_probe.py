# -*- coding: utf-8 -*-
"""headless 探针：复制 index.html 注入遍历脚本，检查渲染异常/横向溢出/JS 错误。"""
import io, os, re

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, 'index.html')
TMP = os.path.join(BASE, '_tmp')
os.makedirs(TMP, exist_ok=True)

raw = io.open(SRC, encoding='utf-8').read()

PROBE = r"""
<script>
(function(){
  var out = {};
  /* ---------- 探针 1：首页（必须在任何 go() 之前读） ---------- */
  try{
    var c1 = document.querySelector('#content');
    out.homeScrollW = c1.scrollWidth;
    out.homeClientW = c1.clientWidth;
    out.homeCards  = document.querySelectorAll('#content .cards .card, #content .card').length;
    out.homeChips  = document.querySelectorAll('#chips .chip').length;
    out.homeRecents= document.querySelectorAll('#content ul.recents li, #content .recents li').length;
    out.homeTree   = document.querySelectorAll('#tree a').length;
    out.docChip    = document.querySelectorAll('#chips .chip')[0] ? document.querySelectorAll('#chips .chip')[0].textContent : '';
  }catch(e){ out.homeErr = String(e); }

  /* ---------- 探针 2：全部文档页 ---------- */
  var errs = [], overs = [], noMd = [], thin = [];
  window.onerror = function(m){ errs.push(String(m)); };
  var ids = DOCS.map(function(d){ return d.id; });
  var tagTotal = 0;
  for (var i=0;i<ids.length;i++){
    go(ids[i]);
    var c = document.querySelector('#content');
    if(!c){ errs.push('no #content @'+ids[i]); break; }
    var md = c.querySelector('#md');
    if(!md){ noMd.push(ids[i]); }
    else{
      var n = md.querySelectorAll('h1,h2,h3,p,table,pre,ul,ol').length;
      tagTotal += n;
      if(n < 5) thin.push(ids[i]+':'+n);
    }
    if (c.scrollWidth > c.clientWidth + 1) overs.push('C:'+ids[i]+'='+c.scrollWidth+'/'+c.clientWidth);
    if (document.documentElement.scrollWidth > window.innerWidth + 1) overs.push('P:'+ids[i]);
  }
  out.docCount = ids.length;
  out.errCount = errs.length;
  out.errs     = errs.slice(0,4).join(' | ');
  out.overCount= overs.length;
  out.overs    = overs.slice(0,4).join(' | ');
  out.noMd     = noMd.length;
  out.noMdList = noMd.slice(0,4).join(',');
  out.thin     = thin.length;
  out.thinList = thin.slice(0,4).join(',');
  out.tagTotal = tagTotal;
  out.title    = document.title;

  var s = [];
  for (var k in out) s.push(k + '=' + String(out[k]));
  var d = document.createElement('div');
  d.setAttribute('probe-out', s.join(' || '));
  document.body.appendChild(d);
})();
</script>
</body>"""

assert '</body>' in raw, 'no </body>'
out_html = raw.replace('</body>', PROBE, 1)
dst = os.path.join(TMP, 'probe.html')
io.open(dst, 'w', encoding='utf-8').write(out_html)
print('written', dst, len(out_html))
