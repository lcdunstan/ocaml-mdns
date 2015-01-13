#!/usr/bin/env python3

import re


class ParseException(Exception):
    pass


class Object:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)

    def __repr__(self):
        keys = sorted(self.__dict__)
        return 'Object(' + ', '.join(['{0}={1}'.format(key, self.__dict__[key]) for key in keys]) + ')'


def format_obj(obj, indent=0):
    if isinstance(obj, Object):
        keys = sorted(obj.__dict__)
        return '{\n' + '\n'.join(['{0}{1}: {2},'.format(' ' * (indent+4), repr(key), format_obj(obj.__dict__[key], indent+4)) for key in keys]) + '\n' + ' ' * indent + '}'
    elif isinstance(obj, list):
        return '[\n' + '\n'.join(['{0}{1},'.format(' ' * (indent+4), format_obj(value, indent+4)) for value in obj]) + '\n' + ' ' * indent + ']'
    else:
        return repr(obj)


IP_HEADER = re.compile(r'^(\d\d):(\d\d):(\d\d\.\d{6}) IP \(tos 0x[0-9a-fA-F]+, ttl \d+, id \d+, offset \d+, flags \[[^\]]+\], proto (\w+) \(\d+\), length \d+\)$')
UDP = re.compile(r'^    (\d+\.\d+.\d+.\d+)\.(\w+) > (\d+\.\d+.\d+.\d+)\.(\w+): \[([^\]]*)\] (.*) \((\d+)\)$')
MDNS_Q = re.compile(r'^\d+\+?%? (?:\[(\d+)n\])?(.*)$')
QUESTION = re.compile(r'(\w+) \(Q([MU])\)\? (.*)$')
RR = re.compile(r'^((?:[-_ A-Za-z0-9]+\.)+) (\(Cache flush\) )?\[(\d+h)?(\d+m)\] (.*)$')
MDNS_R = re.compile(r'^\d+\*?-?\|?\$? (?:\[(\d+)q\]) (\d+)/(\d+)/(\d+) (.*)$')


#f = open('tmp/test_mirage_start.txt', 'r')

def get_line():
    return input()


def get_packet():
    header = get_line()
    m = IP_HEADER.match(header)
    if m:
        hh, mm, ss, protocol = m.groups()
        t = float(ss) + 60 * (int(mm) + 60 * int(hh))
        body = get_line()
        return Object(t=t, protocol=protocol), body


def get_udp():
    packet, body = get_packet()
    if packet and packet.protocol == 'UDP':
        m = UDP.match(body)
        src_ip, src_port, dest_ip, dest_port, ok, payload, length = m.groups()
        assert ok == 'udp sum ok'
        return Object(packet=packet, src_ip=src_ip, src_port=src_port, dest_ip=dest_ip, dest_port=dest_port, length=int(length)), payload


def get_dns():
    def get_rr(rr):
        m = RR.match(rr.strip())
        if not m:
            raise ParseException('Error parsing DNS RR {0}'.format(repr(rr)))
        name, flush, hh, mm, rdata = m.groups()
        if hh:
            hh = int(hh[:-1])
        else:
            hh = 0
        if mm:
            mm = int(mm[:-1])
        else:
            mm = 0
        return Object(name=name, flush=bool(flush), ttl=60*(mm+60*hh), rdata=rdata)

    udp, payload = get_udp()
    if not udp:
        raise ParseException('Expected UDP datagram')
    if udp.src_port not in ('dns', 'mdns'):
        udp.src_port = 'x'  # canonicalise
    if udp.dest_port not in ('dns', 'mdns'):
        udp.dest_port = 'x'  # canonicalise
    if udp.src_port == 'x' and udp.dest_port == 'x':
        raise ParseException('Expected DNS')
    mdns = udp.src_port == 'mdns' or udp.dest_port == 'mdns'
    if payload.find('[0q]') != -1 or (udp.src_port == 'mdns' and udp.dest_port == 'x'):
        # Probably an mDNS response
        m = MDNS_R.match(payload)
        if not m:
            raise ParseException('Error parsing DNS response {0}'.format(repr(payload)))
        numq, numa, numns, numar, rest = m.groups()
        numq = int(numq)
        numa = int(numa)
        numns = int(numns)
        numar = int(numar)
        i_end = len(rest)
        an_part = rest
        ns_part = ''
        ar_part = ''
        i_ns = rest.find(' ns:')
        i_ar = rest.find(' ar:', i_ns + 1)
        if i_ar != -1:
            an_part = rest[:i_ar]
            ar_part = rest[i_ar+4:]
        if i_ns != -1:
            ns_part = an_part[i_ns+4:]
            an_part = an_part[:i_ns]

        anlist = []
        for rr in an_part.split(','):
            anlist.append(get_rr(rr))
        nslist = []
        if ns_part:
            for rr in ns_part.split(','):
                nslist.append(get_rr(rr))
        arlist = []
        if ar_part:
            for rr in ar_part.split(','):
                arlist.append(get_rr(rr))

        return Object(udp=udp, an=anlist, ns=nslist, ar=arlist)
    else:
        # Must be an mDNS query
        m = MDNS_Q.match(payload)
        if not m:
            raise ParseException('Error parsing DNS query {0}'.format(repr(payload)))
        numq, rest = m.groups()
        numq = int(numq)
        i_end = len(rest)
        q_part = rest
        ns_part = ''
        ar_part = ''
        i_ns = rest.find(' ns:')
        i_ar = rest.find(' ar:', i_ns + 1)
        if i_ar != -1:
            q_part = rest[:i_ar]
            ar_part = rest[i_ar+4:]
        if i_ns != -1:
            ns_part = q_part[i_ns+4:]
            q_part = q_part[:i_ns]

        qlist = []
        for q in q_part.split(','):
            m = QUESTION.match(q.strip())
            if not m:
                raise ParseException('Error parsing DNS question {0}'.format(repr(q)))
            qlist.append(Object(type=m.group(1), unicast=m.group(2), name=m.group(3)))
        assert len(qlist) == numq, 'len({0}) != {1}'.format(qlist, numq)

        nslist = []
        for rr in ns_part.split(','):
            nslist.append(get_rr(rr))
        return Object(udp=udp, q=qlist, ns=nslist)


def get_mdns():
    dns = get_dns()
    assert dns.udp.length < 9000
    dns.udp.length = '<9000'
    assert dns.udp.src_port == 'mdns'
    assert dns.udp.dest_port == 'mdns'
    return dns


def verify_delay(p1, p2, min_delay, max_delay):
    delay = p2.t - p1.t
    assert delay >= min_delay and delay <= max_delay, \
        'delay {0} not in [{1}, {2}]'.format(delay, min_delay, max_delay)


def main():
    probe1 = get_mdns()
    probe2 = get_mdns()
    probe3 = get_mdns()
    verify_delay(probe1.udp.packet, probe2.udp.packet, 0.2, 0.3)
    verify_delay(probe2.udp.packet, probe3.udp.packet, 0.2, 0.3)
    probe1.udp.packet.t = 't'
    probe2.udp.packet.t = 't+~250ms'
    probe3.udp.packet.t = 't+~500ms'
    print(format_obj(probe1))
    print(format_obj(probe2))
    print(format_obj(probe3))

    ann1 = get_mdns()
    ann2 = get_mdns()
    ann3 = get_mdns()
    verify_delay(ann1.udp.packet, ann2.udp.packet, 0.9, 1.1)
    verify_delay(ann2.udp.packet, ann3.udp.packet, 1.9, 2.1)
    ann1.udp.packet.t = 't'
    ann2.udp.packet.t = 't+1s'
    ann3.udp.packet.t = 't+1s'
    print(format_obj(ann1))
    print(format_obj(ann2))
    print(format_obj(ann3))

if __name__ == '__main__':
    main()