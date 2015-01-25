#!/usr/bin/env python3

import sys
import subprocess


def main():
    if len(sys.argv) != 3:
        print('Usage: logcon.py <domain> <logfile>')
        sys.exit(1)

    domain = sys.argv[1]
    log_path = sys.argv[2]
    with open(log_path, 'w') as log:
        # By using a valid pipe for stdin, xenconsole will keep running
        # until this Python script is killed.
        # TODO: is there any advantage to runnin xenconsole directly?
        proc = subprocess.Popen(['xl', 'console', domain], stdin=subprocess.PIPE, stdout=log)
        proc.wait()


if __name__ == '__main__':
    main()
