#!/usr/bin/env python3

from dump_canon import *


def main():
    probe1 = get_mdns()
    probe2 = get_mdns()
    probe3 = get_mdns()
    verify_delay(probe1.udp.packet, probe2.udp.packet, 0.2, 0.3)
    verify_delay(probe2.udp.packet, probe3.udp.packet, 0.2, 0.3)
    probe1.udp.packet.t = 't1'
    probe2.udp.packet.t = 't1+~250ms'
    probe3.udp.packet.t = 't1+~500ms'
    print(format_obj(probe1))
    print(format_obj(probe2))
    print(format_obj(probe3))

    ann1 = get_mdns()
    ann2 = get_mdns()
    ann3 = get_mdns()
    verify_delay(ann1.udp.packet, ann2.udp.packet, 0.9, 1.1)
    verify_delay(ann2.udp.packet, ann3.udp.packet, 1.9, 2.1)
    ann1.udp.packet.t = 't2'
    ann2.udp.packet.t = 't2+~1s'
    ann3.udp.packet.t = 't2+~2s'
    print(format_obj(ann1))
    print(format_obj(ann2))
    print(format_obj(ann3))

if __name__ == '__main__':
    main()
