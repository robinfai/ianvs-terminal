"""Only for a disposable local test server/database; never run against production."""
import hashlib
import json
import os
import sqlite3
import urllib.request
import uuid

base = os.environ['WEBUI_REMOTE_URL']
assert base.startswith('http://127.0.0.1:'), 'Requires a loopback test server'
db = os.environ['WEBUI_SESSION_DB']

def post(path, data):
    request = urllib.request.Request(base + path, json.dumps(data).encode(),
                                     {'Content-Type': 'application/json'})
    with urllib.request.urlopen(request) as response:
        return json.load(response)

prepared = post('/v1/auth/register/begin', {
    'username': 'capacity-ui', 'password': 'session-ui-password'})
post('/v1/auth/register/complete', {'operation_id': prepared['operation_id']})
with sqlite3.connect(db) as connection:
    user = connection.execute('select id from users where username=?', ('capacity-ui',)).fetchone()[0]
    for _ in range(7):
        operation = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        token = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        connection.execute('insert into auth_operations values(?,?,?,?,?,?,?)',
                           (operation, 'login', 'issued', user, '2099-01-01 00:00:00+00:00',
                            '2020-01-01 00:00:00+00:00', '2020-01-01 00:00:00+00:00'))
        connection.execute('insert into auth_tokens values(?,?,?,?,?,?)',
                           (str(uuid.uuid4()), user, token, operation,
                            '2099-01-01 00:00:00+00:00', '2020-01-01 00:00:00+00:00'))
