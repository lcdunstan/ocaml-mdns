
all: rfc6762.txt.html rfc6762.txt.xml rfc6762_notes.html
.PHONY: all

%.txt.xml: %.txt parseietf.py
	./parseietf.py $< --xml $@

%.txt.html: %.txt parseietf.py
	./parseietf.py $< --html $@

%.html: %.xml notes_report.py
	./notes_report.py $< --html $@
