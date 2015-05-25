TOOL_REPO=../reqtrace
TOOL_DIR=$(TOOL_REPO)/python
RFC_NOTES=$(TOOL_DIR)/rfc_notes.py

MAIN_REPO=../ocaml-mdns
DOC_DIR=$(MAIN_REPO)/doc

all: rfc6762_notes.html rfc_notes.js rfc_notes.css
.PHONY: all

%.html: $(DOC_DIR)/%.xml $(RFC_NOTES)
	$(RFC_NOTES) $< --html $@
	git add $@

%.js: $(TOOL_DIR)/%.js
	cp $< $@
	git add $@

%.css: $(TOOL_DIR)/%.css
	cp $< $@
	git add $@

