#!/usr/bin/env python3

import sys
from dump_canon import *


def is_probe(mdns):
    return mdns.qr == 'query' and len(mdns.ns) >= 1


def main():
    lesser_ipaddr = sys.argv[1]
    greater_ipaddr = sys.argv[2]

    lesser_probes = []
    greater_probes = []
    # Wait for a simultaneous pair of probes
    while lesser_probes == [] or greater_probes == []:
        mdns = get_mdns()
        assert is_probe(mdns)
        if mdns.ns[0].rdata == 'A ' + lesser_ipaddr:
            lesser_probes.append(mdns)
        elif mdns.ns[0].rdata == 'A ' + greater_ipaddr:
            greater_probes.append(mdns)

    # The greater one should finish probing
    while len(greater_probes) < 3:
        mdns = get_mdns()
        assert is_probe(mdns)
        assert mdns.udp.src_ip == greater_ipaddr
        greater_probes.append(mdns)

    # Verify and print the probes
    verify_delay(greater_probes[0].udp.packet, greater_probes[1].udp.packet, 0.2, 0.3)
    verify_delay(greater_probes[1].udp.packet, greater_probes[2].udp.packet, 0.2, 0.3)
    greater_probes[0].udp.packet.t = 't2'
    greater_probes[1].udp.packet.t = 't2+~250ms'
    greater_probes[2].udp.packet.t = 't2+~500ms'
    print(format_obj(greater_probes[0]))
    print(format_obj(greater_probes[1]))
    print(format_obj(greater_probes[2]))

    # Look for the re-probe from the lesser host,
    # interleaved with the greater hosts's announcements.
    conflicting_probe = None
    greater_ann = []
    while conflicting_probe is None:
        mdns = get_mdns()
        if mdns.udp.src_ip == lesser_ipaddr:
            assert is_probe(mdns)
            conflicting_probe = mdns
        else:
            assert mdns.udp.src_ip == greater_ipaddr
            assert not is_probe(mdns)
            greater_ann.append(mdns)

    # Now look for the defending response to the re-probe.
    conflicting_response = None
    while conflicting_response is None:
        mdns = get_mdns()
        assert mdns.udp.src_ip == greater_ipaddr
        if mdns.udp.dest_ip == lesser_ipaddr:
            conflicting_response = mdns
        else:
            assert mdns.udp.dest_ip == '224.0.0.251'
            assert not is_probe(mdns)
            greater_ann.append(mdns)
    # The response should not have been delayed
    verify_delay(conflicting_probe.udp.packet, conflicting_response.udp.packet, 0.0, 0.1)
    conflicting_probe.udp.packet.t = 't3'
    conflicting_response.udp.packet.t = 't3+~0ms'
    print(format_obj(conflicting_probe))
    print(format_obj(conflicting_response))

    # Now the lesser host renames itself and re-probes again.
    renamed_probes = []
    while len(renamed_probes) < 3:
        mdns = get_mdns()
        if mdns.udp.src_ip == lesser_ipaddr:
            assert is_probe(mdns)
            renamed_probes.append(mdns)
        else:
            assert mdns.udp.src_ip == greater_ipaddr
            assert not is_probe(mdns)
            greater_ann.append(mdns)

    # Verify and print the probes
    verify_delay(renamed_probes[0].udp.packet, renamed_probes[1].udp.packet, 0.2, 0.3)
    verify_delay(renamed_probes[1].udp.packet, renamed_probes[2].udp.packet, 0.2, 0.3)
    renamed_probes[0].udp.packet.t = 't4'
    renamed_probes[1].udp.packet.t = 't4+~250ms'
    renamed_probes[2].udp.packet.t = 't4+~500ms'
    print(format_obj(renamed_probes[0]))
    print(format_obj(renamed_probes[1]))
    print(format_obj(renamed_probes[2]))

    # Collect remaining announcements
    lesser_ann = []
    while len(greater_ann) < 3 or len(lesser_ann) < 3:
        mdns = get_mdns()
        if mdns.udp.src_ip == lesser_ipaddr:
            assert not is_probe(mdns)
            lesser_ann.append(mdns)
        else:
            assert mdns.udp.src_ip == greater_ipaddr
            assert not is_probe(mdns)
            greater_ann.append(mdns)

    # Verify and print greater host announcements
    assert len(greater_ann) == 3
    verify_delay(greater_ann[0].udp.packet, greater_ann[1].udp.packet, 0.9, 1.1)
    verify_delay(greater_ann[1].udp.packet, greater_ann[2].udp.packet, 1.9, 2.1)
    greater_ann[0].udp.packet.t = 't5'
    greater_ann[1].udp.packet.t = 't5+~1s'
    greater_ann[2].udp.packet.t = 't5+~2s'
    print(format_obj(greater_ann[0]))
    print(format_obj(greater_ann[1]))
    print(format_obj(greater_ann[2]))

    assert len(lesser_ann) == 3
    verify_delay(lesser_ann[0].udp.packet, lesser_ann[1].udp.packet, 0.9, 1.1)
    verify_delay(lesser_ann[1].udp.packet, lesser_ann[2].udp.packet, 1.9, 2.1)
    lesser_ann[0].udp.packet.t = 't6'
    lesser_ann[1].udp.packet.t = 't6+~1s'
    lesser_ann[2].udp.packet.t = 't6+~2s'
    print(format_obj(lesser_ann[0]))
    print(format_obj(lesser_ann[1]))
    print(format_obj(lesser_ann[2]))

if __name__ == '__main__':
    main()
