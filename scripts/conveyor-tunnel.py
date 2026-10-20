"""Hold Conveyor's interactive CLI in a real Windows PTY, without a GUI window."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from winpty import PtyProcess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--executable', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    proc = None
    state = {'phase': 'starting', 'wrapper_pid': os.getpid()}

    def save():
        for attempt in range(5):
            try:
                temporary = args.state.with_suffix('.tmp')
                temporary.write_text(json.dumps(state), encoding='utf-8')
                temporary.replace(args.state)
                return
            except PermissionError:
                if attempt == 4:
                    raise
                time.sleep(.05)

    try:
        save()
        proc = PtyProcess.spawn(subprocess.list2cmdline([
            args.executable, '-p', f'{args.port}i']), dimensions=(35, 220))
        state['process_id'] = proc.pid
        save()
        buffer = ''
        while proc.isalive():
            try:
                chunk = proc.read(8192)
            except EOFError:
                break
            if not chunk:
                time.sleep(.1)
                continue
            buffer = (buffer + re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', chunk))[-64000:]
            args.log.write_text(buffer, encoding='utf-8')
            origins = re.findall(r'https://[a-zA-Z0-9-]+\.conveyor\.cloud', buffer)
            if origins and state.get('origin') != origins[-1]:
                state.update(phase='ready', origin=origins[-1])
                save()
        state['phase'] = 'exited'
    except Exception as error:
        state.update(phase='error', error=str(error))
    finally:
        if proc is not None and proc.isalive():
            proc.terminate(force=True)
        save()


if __name__ == '__main__':
    main()
