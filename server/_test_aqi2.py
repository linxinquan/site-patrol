import urllib.request, json
url = 'https://api.github.com/repos/qwd/qweather-ios-sdk/git/trees/main?recursive=1'
req = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0','Accept':'application/json'})
r = urllib.request.urlopen(req, timeout=8)
data = json.loads(r.read())
for item in data.get('tree', []):
    if 'air' in item['path'].lower():
        print(item['path'])
