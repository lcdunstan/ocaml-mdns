#!/usr/bin/env python3

import re
import xml.etree.ElementTree as etree


STYLES = '''
.label {
    display: inline-block;
    background-color: #75df67;
    border: solid 1px black;
    border-radius: 5px;
    margin: 1px 3px;
    padding: 3px 5px;
}

.must {
    background-color: #dddd33;
}

.should {
    background-color: #eecc33;
}
'''

class ParseException(Exception):
    pass


def line_as_element(line):
    elem = etree.Element('span')
    elem.set('id', line.get('id'))
    elem.set('class', 'line')
    elem.text = line.text
    elem.tail = '\n'
    return elem


def clause_as_element(clause):
    elem = etree.Element('span')
    elem.set('id', clause.get('id'))
    css_class = 'clause'
    importance = clause.get('importance')
    if importance:
        css_class += ' ' + importance
    elem.set('class', css_class)
    label = etree.Element('span')
    label.set('class', 'label')
    label.text = clause.get('id')
    elem.append(label)
    label.tail = ' '.join(sub.text for sub in clause.findall('linesub'))
    elem.tail = '\n'
    return elem


def paragraph_as_element(paragraph, section):
    elem = etree.Element('p')
    elem.set('class', 'paragraph')
    elem.text = '\n'
    id = paragraph.get('id')
    if id:
        elem.set('id', id)
    for clause in paragraph.findall('clause'):
        elem.append(clause_as_element(clause))
    if section.get('name') == 'Table of Contents':
        pre = etree.Element('pre')
        pre.text = '\n'.join(line.text for line in paragraph.findall('line'))
        elem.append(pre)
    else:
        for line in paragraph.findall('line'):
            elem.append(line_as_element(line))
    elem.tail = '\n\n'
    return elem


def section_as_elements(section):
    h = etree.Element('h2')
    name = section.get('name')
    num = section.get('num')
    id = section.get('id')
    if id:
        h.set('id', id)
    if num and name:
        h.text = num + ' ' + name
    elif name:
        h.text = name
    h.tail = '\n\n'
    return [h] + [paragraph_as_element(paragraph, section) for paragraph in section.findall('paragraph')]


def root_as_html(xml):
    root = etree.Element('html',
            xmlns='http://www.w3.org/1999/xhtml')

    head = etree.Element('head')
    head.text = '\n'
    title = 'RFC {0}: {1}'.format(xml.attrib['number'], xml.attrib['title'])
    title_elem = etree.Element('title')
    title_elem.text = title
    title_elem.tail = '\n'
    style = etree.Element('style')
    style.text = STYLES
    style.tail = '\n'
    head.append(style)
    head.append(title_elem)
    head.tail = '\n'
    root.append(head)

    body = etree.Element('body')
    body.text = '\n'
    
    h = etree.Element('h1')
    h.text = title
    body.append(h)

    sections = xml.find('sections')
    for section in sections.findall('section'):
        body.extend(section_as_elements(section))
    body.tail = '\n'
    root.append(body)

    return b'<!DOCTYPE html>\n' + etree.tostring(root)


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Convert an IETF RFC from annotated XML to XHTML')
    parser.add_argument('input', metavar='rfcNNNN_notes.xml', nargs=1, type=str,
            help='The path to the input XML document (.xml)')
    parser.add_argument('--html', dest='output_html', nargs=1, type=str,
            help='The path to an HTML output file')
    args = parser.parse_args()

    doc = etree.parse(args.input[0])
    if args.output_html:
        html = root_as_html(doc.getroot())
        with open(args.output_html[0], 'wb') as f:
            f.write(html)

if __name__ == '__main__':
    main()
