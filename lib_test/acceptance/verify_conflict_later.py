#!/usr/bin/env python3

from dump_canon import *


def main():
    conflicting_probe = get_mdns()
    response = get_mdns()
    verify_delay(conflicting_probe.udp.packet, response.udp.packet, 0.0, 0.1)
    conflicting_probe.udp.packet.t = 't1'
    response.udp.packet.t = 't1+~0ms'
    print(format_obj(conflicting_probe))
    print(format_obj(response))

    renamed_probe1 = get_mdns()
    renamed_probe2 = get_mdns()
    renamed_probe3 = get_mdns()
    verify_delay(renamed_probe1.udp.packet, renamed_probe2.udp.packet, 0.2, 0.3)
    verify_delay(renamed_probe2.udp.packet, renamed_probe3.udp.packet, 0.2, 0.3)
    renamed_probe1.udp.packet.t = 't2'
    renamed_probe2.udp.packet.t = 't2+~250ms'
    renamed_probe3.udp.packet.t = 't2+~500ms'
    print(format_obj(renamed_probe1))
    print(format_obj(renamed_probe2))
    print(format_obj(renamed_probe3))

    ann1 = get_mdns()
    ann2 = get_mdns()
    ann3 = get_mdns()
    verify_delay(ann1.udp.packet, ann2.udp.packet, 0.9, 1.1)
    verify_delay(ann2.udp.packet, ann3.udp.packet, 1.9, 2.1)
    ann1.udp.packet.t = 't3'
    ann2.udp.packet.t = 't3+~1s'
    ann3.udp.packet.t = 't3+~2s'
    print(format_obj(ann1))
    print(format_obj(ann2))
    print(format_obj(ann3))

if __name__ == '__main__':
    main()
