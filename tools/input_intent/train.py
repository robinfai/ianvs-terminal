#!/usr/bin/env python3
"""Reproduce Trail's local intent weights; Python stdlib only, no downloads.

All examples here are original project fixtures, not Warp training data/code.
The acceptance corpus lives in Dart tests and is never read by this trainer.
"""
import hashlib
import json
import math
from pathlib import Path
import random
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'packages/ianvs_terminal/lib/src/composer/input_intent_weights.dart'

AI = '''
hello
hi
thanks
explain
what happened
why is this failing
how do I exit vim
show me all files
find all large files
list the directories
please inspect this error
can you fix the build
could you summarize the output
help me understand the logs
what does git status mean
git failed why
git status 是什么意思
docker containers are failing to start
npm install failed can you help
ls 显示的是什么
find the cause of the error
run the tests and explain failures
remove the temporary files safely
delete the obsolete backups
create a new project
write a script for backups
check whether the server is running
look at the previous output
compare these two logs
show disk usage for this directory
list all active processes
search for the largest folder
the command stopped working
my connection keeps disconnecting
this process is stuck
there is no output
what should I try next
I want to understand this program
do we have enough disk space
is this configuration correct
make the failing tests pass
summarize the dependencies in this project
这个错误是什么意思
为什么没有输出
帮我检查网络连接
查看当前目录的文件
找出最大的文件夹
磁盘空间还有多少
这个进程卡住了
上面的命令执行失败了
分析一下这段日志
我想知道服务是否正常
端口被谁占用了
能不能把这些结果保存起来
比较这两个文件
生成一个备份脚本
删除临时文件之前先检查
解决依赖冲突
把当前的错误修复一下
解释一下 grep 的参数
如何查看磁盘剩余容量
请列出所有隐藏文件
在当前目录找配置文件
使用中文解释结果
这条命令安全吗
打开日志看看问题在哪
继续
好的
谢谢
你好
do it
go ahead
try again
continue with the previous plan
retry the failed step
保留原来的文件
只检查不要修改
先不要执行
stop and explain the output
use the other approach
that did not work
what about the other folder
find files modified today
list running services
show the current directory
explain ls -la
why does echo hello print hello
把 ls -la 的输出解释一下
find all files with .log extension
show me the contents of /tmp
help me run ./build.sh
how can I run docker ps
set up the environment for this project
这个 --help 参数有什么作用
为什么 A=1 没有生效
请执行 echo hello
告诉我 sudo 是什么意思
'''.strip().splitlines()

COMMANDS = '''
ls
ls -la
pwd
cd ..
cd /tmp
git status
git diff
git log --oneline
git add .
git commit -m "fix build"
git checkout main
git push origin main
docker ps
docker compose up -d
docker logs server
npm install
npm test
npm run build
pnpm dev
yarn start
flutter test
flutter analyze
dart analyze
python main.py
python3 -m http.server
node server.js
cargo test
cargo build
go test ./...
make
make clean
cmake --build build
ssh cloud
scp file cloud:/tmp
curl https://example.com
wget https://example.com/file
cat README.md
cat "中文文件"
head -n 10 file
tail -f server.log
grep error log.txt
rg TODO .
find . -name '*.log'
find /tmp -type f
sort file
uniq file
wc -l file
sed -n '1,10p' file
awk '{print $1}' file
ps aux
kill 1234
top
htop
vim file.txt
vi file.txt
nano README
less server.log
more README
clear
reset
exit
logout
history
env
printenv
which python
type ls
command -v node
date
whoami
hostname
uname -a
df -h
du -sh .
free -h
uptime
id
touch file
mkdir project
rm -rf tmp
cp file other
mv old new
chmod +x script.sh
chown user file
ln -s target link
tar -czf backup.tar.gz src
unzip archive.zip
zip -r archive.zip src
brew update
brew install jq
apt list
systemctl status nginx
journalctl -xe
kubectl get pods
k9s
terraform plan
ansible-playbook deploy.yml
dig example.com
ping localhost
netstat -an
lsof -i :8080
nc -vz host 443
openssl version
sqlite3 db.sqlite
mysql -u root
psql database
redis-cli ping
jq . file.json
true
false
test -f file
sleep 2
wait
jobs
fg
bg
read value
set -e
for f in *.txt; do cat "$f"; done
if test -f config; then cat config; fi
while true; do date; sleep 1; done
echo hello
printf '%s\\n' hello
sudo apt update
man ls
export PATH=/bin
source .env
./build.sh
FOO=1 make
'''.strip().splitlines()

# Varied shell arguments make prose inside quotes or Unicode filenames neutral.
for executable in ['cat', 'ls', 'rm', 'cp', 'mv', 'grep', 'rg', 'vim', 'less', 'touch']:
    for argument in ['README.md', 'src', 'config.json', '"为什么失败"', '"show all files"', '中文文件.txt']:
        COMMANDS.append(f'{executable} {argument}')
for verb in ['inspect', 'explain', 'summarize', 'check', 'fix', 'analyze']:
    for subject in ['the error', 'this output', 'the failing command', 'the server logs']:
        AI.append(f'{verb} {subject}')
for verb in ['检查', '分析', '解释', '修复', '查看']:
    for subject in ['这个报错', '服务状态', '网络问题', '命令输出', '构建失败的原因']:
        AI.append(verb + subject)


def features(text):
    text = re.sub(r'\s+', ' ', text.lower())
    chars = '^' + text + '$'
    return sorted({*('w:' + word for word in text.split(' ')),
                   *('c:' + chars[i:i+n] for n in range(2, 5)
                     for i in range(len(chars) - n + 1))})


def main():
    corpus = sorted(set((text, 1) for text in AI) | set((text, 0) for text in COMMANDS))
    rows = [(features(text), label) for text, label in corpus]
    weights, bias = {}, 0.0
    randomizer = random.Random(20261003)
    for epoch in range(180):
        randomizer.shuffle(rows)
        rate = 0.08 / (1 + epoch / 30)
        for keys, label in rows:
            score = bias + sum(weights.get(k, 0) for k in keys)
            error = label - 1 / (1 + math.exp(-max(-40, min(40, score))))
            bias += rate * error
            for key in keys:
                weights[key] = weights.get(key, 0) * (1 - rate * 0.001) + rate * error
    digest = hashlib.sha256(json.dumps(corpus, ensure_ascii=False).encode()).hexdigest()
    # JSON double-quoted literals are Dart-compatible after escaping dollars.
    lines = ['// GENERATED by tools/input_intent/train.py; original bilingual fixtures.',
             '// JSON-escaped feature names are kept verbatim for reproducibility.',
             '// ignore_for_file: prefer_single_quotes, avoid_escaping_inner_quotes, use_raw_strings',
             f'// Corpus: {len(corpus)} examples; SHA-256: {digest}',
             f'const double inputIntentBias = {bias:.8f};',
             'const Map<String, double> inputIntentWeights = {']
    for key, value in sorted(weights.items()):
        if abs(value) >= 0.005:
            literal = json.dumps(key, ensure_ascii=False).replace('$', r'\$')
            lines.append(f'  {literal}: {value:.8f},')
    lines.append('};\n')
    OUT.write_text('\n'.join(lines))
    print(f'Wrote {OUT.relative_to(ROOT)} from {len(corpus)} examples')


if __name__ == '__main__':
    main()
