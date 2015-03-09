#!/usr/bin/env python3

# Sources:
# - http://www.ietf.org/proceedings/62/slides/editor-0.pdf
# - https://tools.ietf.org/html/rfc2026

import re
import xml.etree.ElementTree as etree


class ParseException(Exception):
    pass


class Line:
    def __init__(self, doc, num, start, end, page):
        self.doc = doc
        self.num = num
        self.start = start
        self.end = end
        self.page = page

    @property
    def text(self):
        return self.doc.text[self.start : self.end]

    @property
    def is_blank(self):
        return self.text.strip() == ''

    @property
    def len(self):
        return self.end - self.start

    def as_xml(self):
        elem = etree.Element('line')
        elem.set('id', 'L{0}'.format(self.num))
        elem.set('start', str(self.start))
        elem.set('end', str(self.end))
        elem.text = self.text
        elem.tail = '\n'
        return elem


# Relative to a line
class LineSubstring:
    def __init__(self, line, relative_start, relative_end):
        self.line = line
        self.relative_start = relative_start
        self.relative_end = relative_end

    @property
    def len(self):
        return self.relative_end - self.relative_start

    @property
    def start(self):
        return self.line.start + self.relative_start

    @property
    def end(self):
        return self.line.end + self.relative_end

    @property
    def text(self):
        return self.line.text[self.relative_start : self.relative_end]

    def as_xml(self):
        elem = etree.Element('linesub')
        elem.set('start', str(self.start))
        elem.set('end', str(self.end))
        elem.text = self.text
        elem.tail = '\n'
        return elem

class Clause:
    def __init__(self, paragraph, num):
        self.paragraph = paragraph
        self.num = num
        self.substrings = []

    @property
    def text(self):
        return ' '.join(sub.text for sub in self.substrings)

    @property
    def id(self):
        return '{0}_c{1}'.format(self.paragraph.id, self.num)

    def as_xml(self):
        elem = etree.Element('clause')
        elem.set('id', self.id)
        elem.set('num', str(self.num))
        elem.text = '\n'
        for sub in self.substrings:
            elem.append(sub.as_xml())
        elem.tail = '\n'
        return elem


class Paragraph:
    def __init__(self, section, num):
        self.section = section
        self.num = num
        self.lines = []
        self.clauses = []

    @property
    def text(self):
        return ' '.join(line.text.strip() for line in self.lines)

    @property
    def has_ended(self):
        c = self.lines[-1].text[-1]
        return c in '.:)'

    @property
    def id(self):
        if self.section.id:
            return '{0}_p{1}'.format(self.section.id, self.num)
        else:
            return ''

    def parse(self):
        self.clauses = []
        # Split numbered sections into numbered clauses (sentences)
        if self.lines and self.section.num:
            text = ' '.join(line.text for line in self.lines)
            text_start = self.lines[0].start
            start = 0
            num = 1
            while start < len(text):
                find_from = start

                # Skip ellipsis
                ellipsis = text.find('...', find_from)
                while ellipsis != -1:
                    find_from = ellipsis + 3
                    ellipsis = text.find('...', find_from)

                #open_quote = text.find('"', find_from)
                #while open_quote != -1:
                #    close_quote = text.find('"', open_quote + 1)
                #    if close_quote == -1:
                #        break
                #    find_from = close_quote + 1
                #    open_quote = text.find('"', find_from)

                while True:
                    end1 = text.find('. ', find_from)
                    if end1 == -1:
                        end1 = len(text)
                    end2 = text.find('.) ', find_from)
                    if end2 == -1:
                        end2 = len(text)
                    #end3 = text.find(' * ', find_from)
                    #if end3 == -1:
                    #    end3 = len(text)
                    #elif text[start:end3].strip() == '':
                    #    end3 = len(text)
                    end = min(end1, end2)#, end3)
                    if end == len(text):
                        break
                    if end == end2:
                        end += 2
                        break
                    #if end == end3:
                    #    break
                    assert end == end1
                    # Some abbreviations can occur at the end of a clause.
                    app = text.rfind('Appendix', start, end1)
                    if app != -1 and text[app+8:end1-1].strip() == '':
                        end += 1
                        break
                    # Heuristic for skipping list numbering, e.g. "1. "
                    # and name abbreviations, e.g. "L. Dunstan"
                    space = text.rfind(' ', start, end1)
                    if space == -1:
                        space = start
                    #if space - start > 2:
                    #    break
                    if end1 - space > 2:
                        end += 1
                        break
                    find_from = end1 + 2
                # Map text[start:end] to one or more LineSubstring objects
                clause = Clause(self, num)
                para_i = 0
                #import pdb; pdb.set_trace()
                for line in self.lines:
                    sub_start = max(start, para_i)
                    sub_end = min(end, para_i + line.len)
                    # Skip indentation
                    while sub_start < sub_end and text[sub_start] == ' ':
                        sub_start += 1
                    if sub_start < sub_end:
                        clause.substrings.append(LineSubstring(line, sub_start - para_i, sub_end - para_i))
                    para_i += line.len + 1
                assert len(clause.text.strip()) > 4, repr((clause.text, clause.id))
                self.clauses.append(clause)
                start = end
                num += 1

    def as_xml(self):
        self.parse()
        elem = etree.Element('paragraph')
        elem.set('num', str(self.num))
        if self.id:
            elem.set('id', self.id)
        elem.text = '\n'
        if self.clauses:
            for clause in self.clauses:
                elem.append(clause.as_xml())
        else:
            for line in self.lines:
                elem.append(line.as_xml())
        elem.tail = '\n\n'
        return elem


class Section:
    def __init__(self, doc, heading):
        self.doc = doc
        self.heading = heading
        self.lines = []
        self.paragraphs = []
        sep = '. '
        i = heading.find(sep)
        if i == -1:
            sep = ' - '
            i = heading.find(sep)
        if i == -1:
            i = 0
            sep = ''
        self.num = heading[:i].replace('Appendix ', 'App')
        self.name = heading[i+len(sep):].strip()

    @property
    def id(self):
        if self.num:
            return 's{0}'.format(self.num)
        else:
            return ''

    def as_xml(self):
        elem = etree.Element('section')
        elem.text = '\n'
        if self.num:
            elem.set('num', self.num)
            elem.set('id', self.id)
        elem.set('name', self.name)
        for paragraph in self.paragraphs:
            elem.append(paragraph.as_xml())
        elem.tail = '\n\n'
        return elem


class Document:
    def __init__(self, text):
        self.text = text
        self.lines = []
        self.header = {}
        self.rfc_number = None
        self.title = ''
        self.sections = []

    def as_xml(self):
        root = etree.Element('rfc',
                number=str(self.rfc_number),
                title=self.title,
                )

        root.text = '\n'
        header_elem = etree.Element('header')
        header_elem.text = '\n'
        for key in sorted(self.header.keys()):
            elem = etree.Element('value', name=key)
            elem.text = self.header[key]
            elem.tail = '\n'
            header_elem.append(elem)
        header_elem.tail = '\n\n'
        root.append(header_elem)

        sections_elem = etree.Element('sections')
        sections_elem.text = '\n\n'
        for section in self.sections:
            sections_elem.append(section.as_xml())
        sections_elem.tail = '\n'
        root.append(sections_elem)

        return etree.ElementTree(root)


def split_lines(doc, text):
    text_len = len(text)
    # Split into lines
    line_num = 1
    line_start = 0
    page_num = 1
    while line_start < text_len:
        line_end = text.find('\n', line_start)
        if line_end == -1:
            line_end = text_len
        line = Line(doc, line_num, line_start, line_end, page_num)
        yield line
        if line.text.find('\x0c') != -1:
            page_num += 1
        # Next line
        line_start = line_end + 1
        line_num += 1


def parse(text):
    doc = Document(text)
    lines = list(split_lines(doc, text))
    doc.lines = lines
    num_lines = len(lines)

    # Skip blank lines before header
    i = 0
    while lines[i].is_blank:
        i += 1

    # Parse header until next blank line
    while True:
        if lines[i].is_blank:
            break
        line = lines[i].text
        colon = line.find(':')
        if colon != -1:
            key = line[:colon]
            after_value = line.find('  ')
            if after_value == -1:
                after_value = len(line)
            value = line[colon+1:after_value].strip()
            doc.header[key] = value
            if key == 'Request for Comments':
                doc.rfc_number = int(value)
            elif key == 'Category':
                doc.category = value
        i += 1

    # Skip blank lines before title
    while lines[i].is_blank:
        i += 1

    # Extract title
    doc.title = lines[i].text.strip()
    i += 1

    # Extract sections
    header_start = 'RFC {0}'.format(doc.rfc_number)
    section = None
    paragraph = None
    while True:
        # Skip blank lines
        while i < num_lines and lines[i].is_blank:
            i += 1
            if paragraph and paragraph.has_ended:
                paragraph.parse()
                paragraph = None
        if i == num_lines:
            break
        line = lines[i].text
        if line.startswith(' '):
            # Section body
            if section is None:
                raise ParseException(lines[i].num, 'Expected section heading')
            else:
                if paragraph is None:
                    paragraph = Paragraph(section, len(section.paragraphs) + 1)
                    section.paragraphs.append(paragraph)
                paragraph.lines.append(lines[i])
        elif len(line) == 72 and line.startswith(header_start):
            # This is a page header
            assert line.find(doc.title) != -1
        elif len(line) == 72 and line.endswith(']'):
            # This is a page footer
            assert line.find(doc.category) != -1, line
            assert line.find('[Page ') != -1, line
        else:
            # Section heading
            section = Section(doc, line)
            doc.sections.append(section)
            paragraph = None
        i += 1

    return doc


def parse_path(path):
    with open(path, 'rb') as f:
        doc = parse(f.read().decode('us-ascii'))
    return doc


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Split an IETF RFC into clauses')
    parser.add_argument('input', metavar='rfcNNNN.txt', nargs=1, type=str,
            help='The path to the input RFC document in plain text format (.txt)')
    parser.add_argument('--xml', dest='output_xml', nargs=1, type=str,
            help='The path to an XML output file')
    parser.add_argument('--html', dest='output_html', nargs=1, type=str,
            help='The path to an HTML output file')
    args = parser.parse_args()

    doc = parse_path(args.input[0])
    if args.output_xml:
        xml = doc.as_xml()
        xml.write(args.output_xml[0])
    if args.output_html:
        assert False

if __name__ == '__main__':
    main()
