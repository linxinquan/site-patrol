import urllib.request, gzip, json
paths = [
    '/v/air-current?location=113.98,22.59',
    '/air-quality/v1/current?location=113.98,22.59',
    '/v7/air/current?location=113.98,22.59',
]
for path in paths:
    url = 'https://m46aq24n8x.re.qweatherapi.com' + path + '&key=03ff76a3810343cf9bdb11dd7bfb5089'
    print('===', path)
    req = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0','Accept-Encoding':'gzip','Accept':'application/json'})
    try:
        r = urllib.request.urlopen(req, timeout=6)
        raw = r.read()
        if r.headers.get('Content-Encoding') == 'gzip':
            raw = gzip.decompress(raw)
        print('OK', r.status, json.loads(raw) if len(raw) < 300 else raw[:200])
    except urllib.error.HTTPError as e:
        raw = e.read()
        if e.headers.get('Content-Encoding') == 'gzip':
            raw = gzip.decompress(raw)
        print('ERR', e.code, raw.decode('utf-8', errors='replace')[:120])
