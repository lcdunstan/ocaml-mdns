#!/usr/bin/env python3
#
# FIXME: need a much simpler way to canonicalise and diff the packet capture

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


# Example: 00:00:00.750896 IP (tos 0x0, ttl 38, id 41334, offset 0, flags [none], proto UDP (17), length 473)
IP_HEADER = re.compile(r'^(\d\d):(\d\d):(\d\d\.\d{6}) IP \(tos 0x[0-9a-fA-F]+, ttl (\d+), id \d+, offset \d+, flags \[[^\]]+\], proto (\w+) \(\d+\), length \d+\)$')
# Example: 00:00:01.954885 IP6 (hlim 255, next-header UDP (17) payload length: 126) 
IP6_HEADER = re.compile(r'^(\d\d):(\d\d):(\d\d\.\d{6}) IP6 \(hlim (\d+), next-header (\w+) \(\d+\) payload length: \d+\)(.*)$')

# Example: 192.168.3.3.mdns > 224.0.0.251.mdns: [udp sum ok] 
UDP = re.compile(r'^(\d+\.\d+.\d+.\d+|[0-9a-f:]+)\.(\w+) > (\d+\.\d+.\d+.\d+|[0-9a-f:]+)\.(\w+): \[([^\]]*)\] (.*) \((\d+)\)$')
# Example: 0 [1n]
MDNS_Q = re.compile(r'^\d+\+?%? (?:\[(\d+)q\] )?(?:\[(\d+)n\])?(.*)$')
# Example: ANY (QU)? mirage-mdns.local.
QSTART = re.compile(r'(\w+) \(Q([MU])\)\? ')
QUESTION = re.compile(r'(\w+) \(Q([MU])\)\? (.*)$')
# Example: _snake._tcp.local. [2m] PTR king brown._snake._tcp.local.
# Tough example: cubieboard2 [12:df:d4:08:83:ac]._workstation._tcp.local. [2m] SRV cubieboard2.local.:9 0 0
RR = re.compile(r'^((?:[-_ A-Za-z0-9:\[\]]+\.)+) (\(Cache flush\) )?\[(\d+h)?(\d+m)\] (.*)$')
# Example: 0*- [0q] 15/0/0 
MDNS_R = re.compile(r'^\d+\*?-?\|?\$? (?:\[(\d+)q\]) (\d+)/(\d+)/(\d+) (.*)$')


#f = open('tmp/test_mirage_start.txt', 'r')

def get_line():
    return input()


def get_packet():
    header = get_line()
    m = IP_HEADER.match(header)
    if m:
        hh, mm, ss, ttl, protocol = m.groups()
        t = float(ss) + 60 * (int(mm) + 60 * int(hh))
        body = get_line()
        return Object(t=t, v=4, ttl=ttl, protocol=protocol), body.strip()
    else:
        m = IP6_HEADER.match(header)
        hh, mm, ss, ttl, protocol, body = m.groups()
        t = float(ss) + 60 * (int(mm) + 60 * int(hh))
        return Object(t=t, v=6, ttl=ttl, protocol=protocol), body.strip()


def get_udp():
    packet, body = get_packet()
    if packet and packet.protocol == 'UDP':
        m = UDP.match(body)
        src_ip, src_port, dest_ip, dest_port, ok, payload, length = m.groups()
        # FIXME (offload?): assert ok == 'udp sum ok'
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

        return Object(udp=udp, qr='response', an=anlist, ns=nslist, ar=arlist)
    else:
        # Must be an mDNS query
        m = MDNS_Q.match(payload)
        if not m:
            raise ParseException('Error parsing DNS query {0}'.format(repr(payload)))
        numq, numn, rest = m.groups()
        if numq is None:
            numq = 1
        else:
            numq = int(numq)
        if numn is None:
            numn = 0
        else:
            numn = int(numn)
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
        q_part = q_part.strip()
        while q_part:
            m = QSTART.match(q_part)
            if not m:
                raise ParseException('Error parsing DNS question {0}'.format(repr(q)))
            n = QSTART.search(q_part, m.end())
            if n:
                q = q_part[:n.start()]
                q_part = q_part[n.start():]
            else:
                q = q_part
                q_part = ''
            m = QUESTION.match(q)
            if not m:
                raise ParseException('Error parsing DNS question {0}'.format(repr(q)))
            qlist.append(Object(type=m.group(1), unicast=m.group(2), name=m.group(3)))
        assert len(qlist) == numq, 'len({0}) != {1}'.format(qlist, numq)

        nslist = []
        for rr in ns_part.split(','):
            nslist.append(get_rr(rr))
        return Object(udp=udp, qr='query', q=qlist, ns=nslist)


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
