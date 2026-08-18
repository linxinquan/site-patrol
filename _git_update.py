import subprocess, os

os.chdir(r'f:\建筑验收工具\site-patrol')

cmds = [
    'git fetch origin',
    'git pull origin main',
    'git status --short',
    'git branch --show-current',
]

for c in cmds:
    print('==== ' + c + ' ====')
    r = subprocess.run(c, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = (r.stdout or '') + (r.stderr or '')
    print(out)
