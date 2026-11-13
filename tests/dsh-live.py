"""Probe the wire contract against a disposable real `dsh web` instance."""

import asyncio
import http.client
import json
import pathlib
import re
import sys
import urllib.parse
import uuid

from websockets.asyncio.client import connect


def receive_http(address, method, path, headers=None, body=None):
    cls = http.client.HTTPSConnection if address.scheme == 'https' else http.client.HTTPConnection
    conn = cls(address.hostname, address.port, timeout=10)
    try:
        conn.request(method, path, body, headers or {})
        response = conn.getresponse()
        return response.status, response.getheaders(), response.read()
    finally:
        conn.close()


async def verify(launch_log):
    match = re.search(r'dsh web: (https?://[^\s]+)', launch_log.read_text())
    assert match, 'No DSH startup URL in log'
    address = urllib.parse.urlsplit(match.group(1))
    assert address.hostname in ('localhost', '127.0.0.1', '::1'), 'Use an isolated loopback DSH server'
    mount = address.path.rstrip('/')
    status, response_headers, _ = receive_http(address, 'GET', f'{mount}/?{address.query}')
    assert status in (302, 303), f'Expected DSH login redirect, received HTTP {status}'
    cookies = [value.split(';', 1)[0] for name, value in response_headers
               if name.lower() == 'set-cookie' and value.startswith('dsh-auth-')]
    assert cookies, 'No DSH authorization cookie'
    headers = {'Cookie': cookies[0], 'Content-Type': 'application/json'}

    def rpc(method, args):
        rpc_id = str(uuid.uuid4())
        request = {'type': 'client-request', 'rpcId': rpc_id, 'method': method, 'payload': {'args': args}}
        status, _, body = receive_http(address, 'POST', f'{mount}/api/{method}', headers, json.dumps(request))
        assert status == 200, f'{method} returned HTTP {status}'
        response = json.loads(body)
        assert response['type'] == 'server-response' and response['rpcId'] == rpc_id, method
        assert response['result']['ok'], f'{method} returned an RPC error'
        return response['result'].get('value')

    websocket = f'{address.scheme.replace("http", "ws")}://{address.netloc}{mount}/api/remote.mux'
    async with connect(websocket, additional_headers={'Cookie': cookies[0]}, open_timeout=10) as mux:
        async def open_stream(endpoint, args):
            stream_id = str(uuid.uuid4())
            await mux.send(json.dumps({'type': 'open', 'streamId': stream_id, 'endpoint': endpoint,
                                       'payload': {'args': args}}))
            return stream_id

        async def item(stream_id):
            while True:
                frame = json.loads(await mux.recv())
                if frame.get('streamId') == stream_id:
                    assert frame['type'] == 'item', f'Unexpected DSH mux frame {frame["type"]}'
                    return frame['value']

        events = await open_stream('$events', {})
        ready = await item(events)
        assert ready['type'] == 'ready' and ready['clientId'], 'Host event stream was not ready'
        workspaces = await open_stream('workspace/follow', {})
        assert (await item(workspaces))['type'] == 'baseline'
        assert isinstance(rpc('session/list', {'_request': {}})['items'], list)
        session = rpc('session/create', {'request': {}})['sessionId']
        assert any(row['sessionId'] == session for row in rpc('session/list', {'_request': {}})['items'])
        follow = await open_stream('session/follow', {'request': {
            'address': {'kind': 'session', 'sessionId': session}, 'assistantStream': True, 'maxMessages': 100
        }})
        snapshot = await item(follow)
        assert snapshot['type'] == 'snapshot' and snapshot['header']['id'] == session
        assert rpc('session/cancel', {'request': {'sessionId': session}})['accepted']
        await mux.send(json.dumps({'type': 'cancel', 'streamId': follow}))


if __name__ == '__main__':
    asyncio.run(asyncio.wait_for(verify(pathlib.Path(sys.argv[1])), timeout=25))
    print('Real DSH host verified: login cookie, event stream, workspace baseline, list, create, follow, cancel')
