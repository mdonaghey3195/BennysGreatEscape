#!/usr/bin/env python3
"""Build report.html in the results folder: before vs after, side by side."""
import json, os, sys, html

root = sys.argv[1] if len(sys.argv) > 1 else '.'


def load(build):
    out = {}
    p = os.path.join(root, build, 'results.jsonl')
    if os.path.exists(p):
        for line in open(p):
            r = json.loads(line)
            out[r['id']] = r
    return out


B, A = load('before'), load('after')
W = json.load(open(os.path.join(root, 'windows.json'))) if os.path.exists(os.path.join(root, 'windows.json')) else {}
ids = [i for i in B] + [i for i in A if i not in B]


def badge(o):
    colour = {'CLEAR': '#1a7f37', 'HIT': '#cf222e', 'FLAKY': '#9a6700', 'DONE': '#57606a', 'GAMEOVER': '#8250df'}.get(o, '#57606a')
    return f'<span class="badge" style="background:{colour}">{html.escape(o or "-")}</span>'


def facts(r):
    if not r:
        return '<div class="facts">not run</div>'
    bits = [f"d {r['d']:.2f}", f"runs {'/'.join(r['runs'])}"]
    if r.get('hitFrame') is not None:
        bits.append(f"hit f{r['hitFrame']} {r.get('hitPose')}")
    if r.get('minSep') is not None:
        bits.append(f"closest {r['minSep']:+.1f}pt ({r.get('minSepPose')})")
    if r.get('apexes'):
        bits.append('apex ' + ', '.join(f'{x:.0f}' for x in r['apexes'][:10]))
    if r.get('landingFrame') is not None:
        bits.append(f"touchdown f{r['landingFrame']}")
    ge = r.get('groundEvents') or []
    if ge:
        bits.append('ground ' + ' '.join(ge[:8]))
    for n in r.get('notes') or []:
        bits.append(html.escape(n))
    return '<div class="facts">' + ' · '.join(bits) + '</div>'


def shots(r, build):
    if not r:
        return ''
    return ''.join(f'<a href="{build}/{s}"><img loading="lazy" src="{build}/{s}" alt="{s}"></a>' for s in r.get('shots', []))


def changed(b, a):
    if not b or not a:
        return False
    return b['outcome'] != a['outcome'] or (b.get('hitFrame') != a.get('hitFrame'))


def trace_svg(cid):
    """Paw height per frame, both builds, for landing-type cases."""
    series = []
    for build, data, colour in (('before', B, '#8c959f'), ('after', A, '#0969da')):
        r = data.get(cid)
        if r and r.get('trace'):
            series.append((build, [(s['frame'], s['paw']) for s in r['trace']], colour, r.get('landingFrame')))
    if not series:
        return ''
    t = next((s[3] for s in series if s[3]), None)
    lo_f = max(0, (t or 50) - 8)
    hi_f = (t or 50) + 14
    ys = [y for _, pts, _, _ in series for f, y in pts if lo_f <= f <= hi_f]
    if not ys:
        return ''
    y0, y1 = min(min(ys), -2), max(ys)
    w, h, pad = 640, 220, 36
    sx = lambda f: pad + (f - lo_f) / (hi_f - lo_f) * (w - 2 * pad)
    sy = lambda y: h - pad - (y - y0) / (y1 - y0 or 1) * (h - 2 * pad)
    out = [f'<svg viewBox="0 0 {w} {h}" class="trace">',
           f'<line x1="{pad}" x2="{w-pad}" y1="{sy(0)}" y2="{sy(0)}" stroke="#d0d7de"/>',
           f'<text x="{pad}" y="{sy(0)-4}" class="lbl">paw line = turf</text>']
    for build, pts, colour, _ in series:
        p = ' '.join(f'{sx(f):.1f},{sy(y):.1f}' for f, y in pts if lo_f <= f <= hi_f)
        out.append(f'<polyline points="{p}" fill="none" stroke="{colour}" stroke-width="2"/>')
        for f, y in pts:
            if lo_f <= f <= hi_f:
                out.append(f'<circle cx="{sx(f):.1f}" cy="{sy(y):.1f}" r="2.5" fill="{colour}"><title>{build} f{f}: {y:.1f}pt</title></circle>')
    out.append(f'<text x="{w-pad}" y="20" text-anchor="end" class="lbl"><tspan fill="#8c959f">● before</tspan>  <tspan fill="#0969da">● after</tspan></text>')
    out.append(f'<text x="{pad}" y="{h-8}" class="lbl">frames {lo_f}–{hi_f} after the swipe (60 per second) · y: paw height, pt</text>')
    out.append('</svg>')
    return ''.join(out)


regressions = {t: r['regressions'] for t, r in W.items() if r['regressions']}
case_regressions = [i for i in ids if B.get(i, {}).get('outcome') == 'CLEAR' and A.get(i, {}).get('outcome') == 'HIT']
ok = not regressions and not case_regressions

rows = []
order = sorted(ids, key=lambda i: (not changed(B.get(i), A.get(i)), ids.index(i)))
for cid in order:
    b, a = B.get(cid), A.get(cid)
    flag = '<span class="changed">CHANGED</span>' if changed(b, a) else ''
    extra = trace_svg(cid) if cid.startswith('L-1') or cid.startswith('L-8-CLIFF-JUMP') else ''
    rows.append(f'''<section class="case" id="{cid}">
<h3>{html.escape(cid)} {flag}</h3>
<div class="pair">
 <div><h4>Before (master) {badge(b and b["outcome"])}</h4>{facts(b)}<div class="shots">{shots(b, "before")}</div></div>
 <div><h4>After (branch) {badge(a and a["outcome"])}</h4>{facts(a)}<div class="shots">{shots(a, "after")}</div></div>
</div>{extra}</section>''')

sweep_rows = []
for t, r in sorted(W.items()):
    def cell(w):
        if not w:
            return '—'
        return f"{w[0]:.2f} – {w[1]:.2f} <small>({(w[1]-w[0])/r['speed']*1000:.0f} ms)</small>"
    wb, wa = r['before']['window'], r['after']['window']
    gain = ''
    if wb and wa:
        gain = f"{((wa[1]-wa[0])-(wb[1]-wb[0]))/r['speed']*1000:+.1f} ms"
    elif wa and not wb:
        gain = 'opens'
    sweep_rows.append(f"<tr><td>{t}</td><td>{r['speed']:.0f}</td><td>{r['height']:.1f}</td><td>{cell(wb)}</td><td>{cell(wa)}</td><td>{gain}</td>"
                      f"<td>{len(r['improvements'])}</td><td class=\"{'bad' if r['regressions'] else ''}\">{len(r['regressions'])}</td>"
                      f"<td>{len(r['before']['flaky'])}/{len(r['after']['flaky'])}</td></tr>")

page = f'''<!doctype html><html><head><meta charset="utf-8"><title>Hitbox Lab report</title>
<style>
body{{font:14px -apple-system,system-ui,sans-serif;margin:24px;color:#1f2328;max-width:1500px}}
h1{{margin:0 0 4px}} .sub{{color:#57606a;margin-bottom:16px}}
.banner{{padding:12px 16px;border-radius:8px;font-weight:600;margin:12px 0}}
.ok{{background:#dafbe1;color:#1a7f37}} .fail{{background:#ffebe9;color:#cf222e}}
table{{border-collapse:collapse;margin:8px 0 24px}} td,th{{border-bottom:1px solid #d0d7de;padding:4px 10px;text-align:left}}
td.bad{{color:#cf222e;font-weight:700}}
.case{{border-top:1px solid #d0d7de;padding:12px 0}} .case h3{{margin:0 0 6px}}
.pair{{display:grid;grid-template-columns:1fr 1fr;gap:16px}} .pair h4{{margin:4px 0}}
.shots img{{width:100%;border:1px solid #d0d7de;border-radius:4px;margin-top:6px}}
.badge{{color:#fff;border-radius:10px;padding:1px 8px;font-size:12px}}
.changed{{background:#fff8c5;color:#9a6700;border-radius:10px;padding:1px 8px;font-size:12px}}
.facts{{color:#57606a;font-size:12px}} .trace{{width:640px;margin-top:8px}} .lbl{{font-size:11px;fill:#57606a}}
</style></head><body>
<h1>Hitbox Lab: master vs feature/hitbox-improvements</h1>
<div class="sub">Cyan box = Benny's physics box probed from the physics world · magenta = obstacle solid · dashed = obstacle top. Rows that changed are listed first.</div>
<div class="banner {'ok' if ok else 'fail'}">{'Invariant holds: nothing that clears on master hits on the branch.' if ok else 'INVARIANT BROKEN: ' + html.escape(json.dumps(regressions) + ' ' + ', '.join(case_regressions))}</div>
<h2>Sweep windows (lead distance d that clears, pt)</h2>
<table><tr><th>Target</th><th>Speed</th><th>Height</th><th>Before</th><th>After</th><th>Window change</th><th>d fixed</th><th>d broken</th><th>Flaky b/a</th></tr>
{''.join(sweep_rows)}</table>
<h2>Cases</h2>
{''.join(rows)}
</body></html>'''
open(os.path.join(root, 'report.html'), 'w').write(page)
print('wrote report.html;', len(ids), 'cases;', 'invariant ok' if ok else 'INVARIANT BROKEN')
