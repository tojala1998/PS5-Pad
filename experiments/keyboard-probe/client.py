"""Command-line client for the isolated uhnmeyker PS5 keyboard experiment."""
import argparse
import json
import socket

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('host')
    p.add_argument('action', choices=('status','type','key','open-test','stop'))
    p.add_argument('--text', help='At most 128 printable US-ASCII characters; not logged by this client')
    p.add_argument('--key', choices=('BACKSPACE','ENTER','ESCAPE'))
    p.add_argument('--port', type=int, default=9306)
    a=p.parse_args()
    if a.action=='type':
        if not a.text or len(a.text)>128 or any(ord(c)<32 or ord(c)>126 for c in a.text):
            p.error('--text requires 1 to 128 printable ASCII characters')
    if a.action=='key' and not a.key:
        p.error('--key is required')
    with socket.create_connection((a.host,a.port),timeout=3) as s:
        s.settimeout(15)
        with s.makefile('rb') as reader:
            def receive():
                raw=reader.readline(2048)
                if not raw or len(raw)>=2048:
                    raise RuntimeError('Probe did not return a bounded response')
                return json.loads(raw)
            hello=receive()
            if hello.get('service')!='uhnmeyker-keyboard-probe':
                raise RuntimeError('This is not the keyboard test service')
            print(json.dumps(hello,indent=2))
            def command(text):
                s.sendall(text.encode('ascii')+b'\n')
                result=receive()
                print(json.dumps(result))
                if result.get('ok') is False:
                    raise RuntimeError('Probe rejected the command (details above)')
                return result
            if a.action=='status':
                return
            if a.action=='stop':
                command('STOP'); return
            command('OPEN')
            try:
                if a.action=='type':
                    command('TYPE '+a.text.encode('ascii').hex())
                elif a.action=='key':
                    command('KEY '+a.key)
            finally:
                command('CLOSE')
            command('QUIT')

if __name__=='__main__':
    main()
